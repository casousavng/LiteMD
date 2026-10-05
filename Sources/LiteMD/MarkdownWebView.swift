import SwiftUI
import WebKit
import PDFKit

enum SlideViewMode: String, CaseIterable {
    case presentation = "presentation"
    case list = "list"
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fileURL: URL?
    let slideViewMode: SlideViewMode
    let isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "toggleFullscreen")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let tempDir = FileManager.default.temporaryDirectory
        let htmlFile = tempDir.appendingPathComponent("litemd_stage.html")
        try? Coordinator.htmlTemplate.write(to: htmlFile, atomically: true, encoding: .utf8)

        webView.loadFileURL(htmlFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.isLoaded {
            context.coordinator.sendPayload()
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        weak var webView: WKWebView?
        var isLoaded = false

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleExportPDFNotification(_:)),
                name: Notification.Name("LiteMDExportPDF"),
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleExportPDFNotification(_ notification: Notification) {
            guard let targetURL = notification.object as? URL else { return }
            let isMarp = (notification.userInfo?["isMarp"] as? Bool) ?? false

            DispatchQueue.main.async {
                self.exportPDF(to: targetURL, isMarp: isMarp)
            }
        }

        private func exportPDF(to targetURL: URL, isMarp: Bool) {
            guard self.webView != nil else { return }

            if isMarp {
                exportMarpPDF(to: targetURL)
            } else {
                exportNormalPDF(to: targetURL)
            }
        }

        private func exportMarpPDF(to targetURL: URL) {
            guard let webView = self.webView else { return }

            webView.evaluateJavaScript("prepareForPDFExport()") { [weak self, weak webView] result, error in
                guard let _ = self, let webView = webView else { return }
                let totalSlides = (result as? Int) ?? 0

                guard totalSlides > 0 else {
                    webView.evaluateJavaScript("finishPDFExport()", completionHandler: nil)
                    return
                }

                let finalPDFDoc = PDFDocument()
                var capturedCount = 0

                func captureSlide(at index: Int) {
                    guard index < totalSlides else {
                        finalPDFDoc.write(to: targetURL)
                        webView.evaluateJavaScript("finishPDFExport()", completionHandler: nil)
                        return
                    }

                    let config = WKPDFConfiguration()
                    config.rect = CGRect(x: 0, y: CGFloat(index * 720), width: 1280, height: 720)

                    webView.createPDF(configuration: config) { result in
                        switch result {
                        case .success(let data):
                            if let singlePageDoc = PDFDocument(data: data),
                               let page = singlePageDoc.page(at: 0) {
                                finalPDFDoc.insert(page, at: capturedCount)
                                capturedCount += 1
                            }
                        case .failure(let err):
                            print("Error capturing slide \(index): \(err)")
                        }
                        captureSlide(at: index + 1)
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    captureSlide(at: 0)
                }
            }
        }

        private func exportNormalPDF(to targetURL: URL) {
            guard let webView = self.webView else { return }

            let printInfo = NSPrintInfo(dictionary: [
                NSPrintInfo.AttributeKey.jobDisposition: NSPrintInfo.JobDisposition.save,
                NSPrintInfo.AttributeKey.jobSavingURL: targetURL
            ])
            printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
            printInfo.topMargin = 56.69
            printInfo.bottomMargin = 56.69
            printInfo.leftMargin = 51.02
            printInfo.rightMargin = 51.02
            printInfo.orientation = .portrait
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = false

            let printOp = webView.printOperation(with: printInfo)
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = false

            if let window = webView.window ?? NSApplication.shared.keyWindow {
                printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                printOp.run()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            sendPayload()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "toggleFullscreen" {
                DispatchQueue.main.async {
                    NSApplication.shared.keyWindow?.toggleFullScreen(nil)
                }
            }
        }

        func sendPayload() {
            guard let webView = webView else { return }
            
            let customTheme = findCustomThemeCSS(for: parent.markdown, fileURL: parent.fileURL) ?? ""
            let baseDir = parent.fileURL?.deletingLastPathComponent().path ?? ""

            let payload: [String: Any] = [
                "text": parent.markdown,
                "mode": parent.slideViewMode.rawValue,
                "customTheme": customTheme,
                "baseDir": baseDir,
                "isFullScreen": parent.isFullScreen
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }

            let js = "window.renderPayload(\(jsonString));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func findCustomThemeCSS(for markdown: String, fileURL: URL?) -> String? {
            let pattern = #"(?m)^\s*theme\s*:\s*([a-zA-Z0-9_\-]+)\s*$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
                  let range = Range(match.range(at: 1), in: markdown) else {
                return nil
            }
            let themeName = String(markdown[range])
            if themeName == "default" || themeName == "gaia" || themeName == "uncover" {
                return nil
            }

            guard let fileURL = fileURL else { return nil }
            var dir = fileURL.deletingLastPathComponent()
            for _ in 0..<6 {
                let candidates = [
                    dir.appendingPathComponent("\(themeName).css"),
                    dir.appendingPathComponent("templates").appendingPathComponent("\(themeName).css"),
                    dir.appendingPathComponent("themes").appendingPathComponent("\(themeName).css"),
                    dir.appendingPathComponent("css").appendingPathComponent("\(themeName).css")
                ]
                for candidate in candidates {
                    if FileManager.default.fileExists(atPath: candidate.path),
                       let css = try? String(contentsOf: candidate, encoding: .utf8) {
                        return css
                    }
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
            return nil
        }

        static let marpScript: String = {
            if let url = Bundle.main.url(forResource: "marp-viewer", withExtension: "min.js"),
               let str = try? String(contentsOf: url, encoding: .utf8) {
                return str
            }
            if let str = try? String(contentsOfFile: "Resources/marp-viewer.min.js", encoding: .utf8) {
                return str
            }
            return ""
        }()

        static var htmlTemplate: String {
            """
            <!DOCTYPE html>
            <html lang="pt">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
              <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
              <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/highlight.js@11.9.0/styles/github.min.css" id="hl-light">
              <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/highlight.js@11.9.0/styles/github-dark.min.css" id="hl-dark" media="(prefers-color-scheme: dark)">
              <script src="https://cdn.jsdelivr.net/npm/highlight.js@11.9.0/lib/highlight.min.js"></script>
              <script>
              \(marpScript)
              </script>
              <style>
                :root {
                  color-scheme: light dark;
                  --bg-color: #ffffff;
                  --text-color: #1f2328;
                  --border-color: #d1d9e0;
                  --code-bg: #f6f8fa;
                  --quote-color: #59636e;
                  --link-color: #0969da;
                }
                @media (prefers-color-scheme: dark) {
                  :root {
                    --bg-color: #0d1117;
                    --text-color: #e6edf3;
                    --border-color: #30363d;
                    --code-bg: #161b22;
                    --quote-color: #8b949e;
                    --link-color: #4493f8;
                  }
                }
                * {
                  box-sizing: border-box;
                }
                html, body {
                  margin: 0;
                  padding: 0;
                  width: 100%;
                  height: 100%;
                }
                body {
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
                  font-size: 15px;
                  line-height: 1.6;
                  word-wrap: break-word;
                  background-color: var(--bg-color);
                  color: var(--text-color);
                  transition: background-color 0.2s ease;
                }

                /* --- ESTILOS EXCLUSIVOS DO MODO MARKDOWN NORMAL (NÃO AFETAM O MARP) --- */
                #content.normal-doc {
                  padding: 24px 32px;
                  max-width: 960px;
                  margin: 0 auto;
                }
                #content.normal-doc h1,
                #content.normal-doc h2,
                #content.normal-doc h3,
                #content.normal-doc h4,
                #content.normal-doc h5,
                #content.normal-doc h6 {
                  margin-top: 24px;
                  margin-bottom: 16px;
                  font-weight: 600;
                  line-height: 1.25;
                  color: var(--text-color);
                }
                #content.normal-doc h1 { font-size: 2em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
                #content.normal-doc h2 { font-size: 1.5em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
                #content.normal-doc h3 { font-size: 1.25em; }
                #content.normal-doc p,
                #content.normal-doc ul,
                #content.normal-doc ol,
                #content.normal-doc dl,
                #content.normal-doc table,
                #content.normal-doc pre,
                #content.normal-doc details {
                  margin-top: 0;
                  margin-bottom: 16px;
                }
                #content.normal-doc a {
                  color: var(--link-color);
                  text-decoration: none;
                }
                #content.normal-doc a:hover {
                  text-decoration: underline;
                }
                #content.normal-doc code {
                  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
                  font-size: 85%;
                  background-color: var(--code-bg);
                  padding: 0.2em 0.4em;
                  border-radius: 6px;
                }
                #content.normal-doc pre {
                  background-color: var(--code-bg);
                  padding: 16px;
                  border-radius: 8px;
                  overflow: auto;
                  border: 1px solid var(--border-color);
                }
                #content.normal-doc pre code {
                  background-color: transparent;
                  padding: 0;
                  font-size: 13px;
                }
                #content.normal-doc blockquote {
                  margin: 0 0 16px;
                  padding: 0 1em;
                  color: var(--quote-color);
                  border-left: 0.25em solid var(--border-color);
                }
                #content.normal-doc table {
                  border-spacing: 0;
                  border-collapse: collapse;
                  margin-bottom: 16px;
                  width: 100%;
                  overflow: auto;
                }
                #content.normal-doc table th,
                #content.normal-doc table td {
                  padding: 8px 13px;
                  border: 1px solid var(--border-color);
                }
                #content.normal-doc table tr:nth-child(2n) {
                  background-color: var(--code-bg);
                }
                #content.normal-doc img {
                  max-width: 100%;
                  box-sizing: content-box;
                }
                #content.normal-doc hr {
                  height: 0.25em;
                  padding: 0;
                  margin: 24px 0;
                  background-color: var(--border-color);
                  border: 0;
                }
                .mermaid-container {
                  display: flex;
                  justify-content: center;
                  background: var(--code-bg);
                  border: 1px solid var(--border-color);
                  border-radius: 8px;
                  padding: 16px;
                  margin: 16px 0;
                  overflow-x: auto;
                }
                .mermaid {
                  text-align: center;
                }

                /* --- ESTILO DE EXPORTAÇÃO DIRETA DE SLIDES MARP --- */
                body.marp-export-pdf {
                  margin: 0 !important;
                  padding: 0 !important;
                  background: transparent !important;
                  width: 1280px !important;
                }
                #marp-export-container {
                  margin: 0 !important;
                  padding: 0 !important;
                  display: block !important;
                  width: 1280px !important;
                }
                body.marp-export-pdf section {
                  display: flex !important;
                  flex-direction: column !important;
                  width: 1280px !important;
                  height: 720px !important;
                  min-width: 1280px !important;
                  max-width: 1280px !important;
                  min-height: 720px !important;
                  max-height: 720px !important;
                  box-sizing: border-box !important;
                  box-shadow: none !important;
                  border-radius: 0 !important;
                  border: none !important;
                  margin: 0 !important;
                  overflow: hidden !important;
                }

                /* --- MODO MARP: COMUM A AMBAS AS VISTAS --- */
                body.marp-active section {
                  box-sizing: border-box;
                  position: relative;
                }

                /* --- VISTA 1: LISTA VERTICAL DE SLIDES --- */
                body.marp-mode-list {
                  background-color: #16181d !important;
                  overflow-y: auto !important;
                  padding: 30px 16px 60px !important;
                  display: block !important;
                }
                @media (prefers-color-scheme: light) {
                  body.marp-mode-list {
                    background-color: #eaedf1 !important;
                  }
                }
                .marp-list-deck {
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  gap: 32px;
                  width: 100%;
                }
                .marp-list-item {
                  position: relative;
                  border-radius: 10px;
                  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.38);
                  overflow: hidden;
                  transition: transform 0.15s ease, box-shadow 0.15s ease;
                }
                .marp-list-item:hover {
                  box-shadow: 0 16px 44px rgba(0, 0, 0, 0.48);
                }
                .marp-list-scaler {
                  width: 1280px;
                  height: 720px;
                  transform-origin: top left;
                }
                .marp-list-badge {
                  position: absolute;
                  bottom: 8px;
                  right: 12px;
                  font-size: 11px;
                  font-family: -apple-system, sans-serif;
                  font-weight: 600;
                  color: rgba(255, 255, 255, 0.9);
                  background: rgba(0, 0, 0, 0.6);
                  padding: 2px 8px;
                  border-radius: 10px;
                  backdrop-filter: blur(4px);
                  pointer-events: none;
                  opacity: 0.5;
                  transition: opacity 0.2s ease;
                }
                .marp-list-item:hover .marp-list-badge {
                  opacity: 1;
                }

                /* --- VISTA 2: APRESENTAÇÃO DE SLIDES (SLIDESHOW) --- */
                body.marp-mode-presentation {
                  overflow: hidden !important;
                  width: 100vw !important;
                  height: 100vh !important;
                  margin: 0 !important;
                  display: flex !important;
                  align-items: center !important;
                  justify-content: center !important;
                  transition: background-color 0.2s ease;
                }

                /* Modo Janela: Fundo neutro de estúdio (Keynote/PowerPoint) e slide como cartão 16:9 destacado */
                body.marp-mode-presentation.is-windowed {
                  background-color: #1a1c22 !important;
                  padding: 16px !important;
                }
                @media (prefers-color-scheme: light) {
                  body.marp-mode-presentation.is-windowed {
                    background-color: #e5e8ed !important;
                  }
                }
                body.marp-mode-presentation.is-windowed .presentation-stage {
                  position: relative;
                  border-radius: 8px !important;
                  box-shadow: 0 14px 44px rgba(0, 0, 0, 0.4) !important;
                  overflow: hidden;
                  cursor: pointer;
                }

                /* Modo Ecrã Inteiro / Projetor: 100% imersivo sem cortes */
                body.marp-mode-presentation.is-fullscreen {
                  padding: 0 !important;
                }
                body.marp-mode-presentation.is-fullscreen .presentation-stage {
                  position: relative;
                  border-radius: 0 !important;
                  box-shadow: none !important;
                  overflow: hidden;
                  cursor: pointer;
                }
                .presentation-scaler {
                  width: 1280px;
                  height: 720px;
                  transform-origin: top left;
                }
                .presentation-slide-view {
                  display: none;
                  width: 100%;
                  height: 100%;
                }
                .presentation-slide-view.active {
                  display: block;
                }

                /* Controlos flutuantes na base da apresentação - OCULTO POR PREDEFINIÇÃO */
                .presentation-hud {
                  position: fixed;
                  bottom: 24px;
                  left: 50%;
                  transform: translateX(-50%) translateY(24px);
                  display: flex;
                  align-items: center;
                  gap: 10px;
                  background: rgba(22, 26, 34, 0.92);
                  backdrop-filter: blur(16px);
                  -webkit-backdrop-filter: blur(16px);
                  padding: 6px 14px;
                  border-radius: 26px;
                  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.6);
                  border: 1px solid rgba(255, 255, 255, 0.15);
                  z-index: 10000;
                  opacity: 0;
                  pointer-events: none;
                  transition: opacity 0.28s ease, transform 0.28s cubic-bezier(0.16, 1, 0.3, 1);
                }
                .presentation-hud.visible,
                .presentation-hud:hover {
                  opacity: 1 !important;
                  pointer-events: auto !important;
                  transform: translateX(-50%) translateY(0) !important;
                }
                .hud-btn {
                  background: transparent;
                  border: none;
                  color: #ffffff;
                  font-size: 14px;
                  cursor: pointer;
                  padding: 4px 10px;
                  border-radius: 6px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  font-weight: 500;
                  transition: background 0.15s;
                }
                .hud-btn:hover {
                  background: rgba(255, 255, 255, 0.18);
                }
                .hud-btn:disabled {
                  opacity: 0.35;
                  cursor: default;
                }
                .hud-counter {
                  color: #e0e0e0;
                  font-size: 13px;
                  font-weight: 600;
                  font-family: -apple-system, sans-serif;
                  min-width: 68px;
                  text-align: center;
                }

                /* --- ESTILOS DE IMPRESSÃO E EXPORTAÇÃO PARA PDF --- */
                @media print {
                  html, body {
                    width: 100% !important;
                    height: auto !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    background: transparent !important;
                    -webkit-print-color-adjust: exact !important;
                    print-color-adjust: exact !important;
                  }

                  /* 1. Modo Documento Normal */
                  #content.normal-doc {
                    padding: 0 !important;
                    max-width: 100% !important;
                    margin: 0 !important;
                    font-size: 11pt !important;
                  }
                  #content.normal-doc > *:first-child {
                    margin-top: 0 !important;
                  }
                  #content.normal-doc h1,
                  #content.normal-doc h2,
                  #content.normal-doc h3 {
                    page-break-after: avoid;
                    break-after: avoid;
                  }
                  #content.normal-doc pre,
                  #content.normal-doc .mermaid-container,
                  #content.normal-doc blockquote,
                  #content.normal-doc tr {
                    page-break-inside: avoid;
                    break-inside: avoid;
                  }

                  /* 2. Modo Apresentação Marp (16:9 - 1 slide por página) */
                  body.marp-export-print,
                  body.marp-active {
                    background: transparent !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    display: block !important;
                    width: 1280px !important;
                    height: auto !important;
                  }
                  #marp-print-container {
                    margin: 0 !important;
                    padding: 0 !important;
                    display: block !important;
                    width: 1280px !important;
                  }
                  body.marp-export-print section,
                  body.marp-active section {
                    display: flex !important;
                    flex-direction: column !important;
                    width: 1280px !important;
                    height: 720px !important;
                    min-width: 1280px !important;
                    max-width: 1280px !important;
                    min-height: 720px !important;
                    max-height: 720px !important;
                    box-sizing: border-box !important;
                    box-shadow: none !important;
                    border-radius: 0 !important;
                    border: none !important;
                    margin: 0 !important;
                    overflow: hidden !important;
                    page-break-inside: avoid !important;
                    break-inside: avoid !important;
                    page-break-before: always !important;
                    break-before: page !important;
                    page-break-after: avoid !important;
                    break-after: avoid !important;
                    -webkit-print-color-adjust: exact !important;
                    print-color-adjust: exact !important;
                  }
                  body.marp-export-print section:first-child,
                  body.marp-active section:first-child {
                    page-break-before: auto !important;
                    break-before: auto !important;
                  }
                }
              </style>
              <style id="litemd-print-page-style">
                @page {
                  size: A4 portrait;
                  margin: 20mm 18mm;
                }
              </style>
            </head>
            <body>
              <div id="content"></div>
              <script>
                let currentPayload = null;
                let exportRestoreState = null;

                function prepareForPDFExport() {
                  const sections = document.querySelectorAll('section');
                  if (!sections || sections.length === 0) return 0;
                  
                  exportRestoreState = {
                    bodyClass: document.body.className,
                    bodyHtml: document.body.innerHTML,
                    bodyBg: document.body.style.backgroundColor,
                    activeSlide: activeSlideIndex
                  };

                  let cleanSectionsHtml = '';
                  sections.forEach(sec => {
                    cleanSectionsHtml += sec.outerHTML;
                  });

                  document.body.className = 'marp-export-pdf';
                  document.body.style.backgroundColor = 'transparent';
                  document.body.innerHTML = '<div id="marp-export-container">' + cleanSectionsHtml + '</div>';
                  return sections.length;
                }

                function finishPDFExport() {
                  if (!exportRestoreState) return;
                  document.body.className = exportRestoreState.bodyClass;
                  document.body.innerHTML = exportRestoreState.bodyHtml;
                  document.body.style.backgroundColor = exportRestoreState.bodyBg;
                  const targetIndex = exportRestoreState.activeSlide;
                  exportRestoreState = null;
                  
                  adjustLayout();
                  if (document.body.classList.contains('marp-mode-presentation')) {
                    showSlide(targetIndex);
                  }
                }

                let activeSlideIndex = 0;
                let totalSlides = 0;

                const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                if (window.mermaid) mermaid.initialize({
                  startOnLoad: false,
                  theme: isDark ? 'dark' : 'default',
                  securityLevel: 'loose'
                });

                function isMarpDocument(text) {
                  if (!text) return false;
                  const trimmed = text.trim();
                  const match = /^---\\s*\\n([\\s\\S]*?)\\n---\\s*(\\n|$)/.exec(trimmed);
                  if (match) {
                    return /^\\s*marp\\s*:\\s*true\\b/im.test(match[1]);
                  }
                  return false;
                }

                function fixRelativeImages(container, baseDir) {
                  if (!baseDir) return;
                  const images = container.querySelectorAll('img');
                  images.forEach(img => {
                    const src = img.getAttribute('src');
                    if (src && !src.startsWith('http://') && !src.startsWith('https://') && !src.startsWith('data:') && !src.startsWith('file://')) {
                      let baseParts = baseDir.split('/').filter(Boolean);
                      for (const p of src.split('/')) {
                        if (p === '..') {
                          baseParts.pop();
                        } else if (p !== '.' && p !== '') {
                          baseParts.push(p);
                        }
                      }
                      img.src = 'file:///' + baseParts.join('/');
                    }
                  });
                }

                function adjustLayout() {
                  if (!document.body.classList.contains('marp-active')) return;
                  const mode = currentPayload ? currentPayload.mode : 'presentation';

                  if (mode === 'presentation') {
                    const stage = document.querySelector('.presentation-stage');
                    const scaler = document.querySelector('.presentation-scaler');
                    if (!stage || !scaler) return;

                    const isFS = currentPayload ? !!currentPayload.isFullScreen : false;
                    const padW = isFS ? 0 : 28;
                    const padH = isFS ? 0 : 28;
                    const availW = Math.max(100, window.innerWidth - padW);
                    const availH = Math.max(100, window.innerHeight - padH);
                    const baseW = 1280;
                    const baseH = 720;
                    const scale = Math.min(availW / baseW, availH / baseH);

                    stage.style.width = Math.round(baseW * scale) + 'px';
                    stage.style.height = Math.round(baseH * scale) + 'px';
                    scaler.style.transform = `scale(${scale})`;
                  } else {
                    const items = document.querySelectorAll('.marp-list-item');
                    if (items.length === 0) return;

                    const availW = window.innerWidth - 64;
                    const baseW = 1280;
                    const baseH = 720;
                    const scale = Math.min(1.0, Math.max(0.2, availW / baseW));
                    const scaledW = Math.round(baseW * scale);
                    const scaledH = Math.round(baseH * scale);

                    items.forEach(item => {
                      item.style.width = scaledW + 'px';
                      item.style.height = scaledH + 'px';
                      const scaler = item.querySelector('.marp-list-scaler');
                      if (scaler) scaler.style.transform = `scale(${scale})`;
                    });
                  }
                }

                window.addEventListener('resize', adjustLayout);

                function showSlide(index) {
                  if (index < 0) index = 0;
                  if (index >= totalSlides) index = totalSlides - 1;
                  activeSlideIndex = index;

                  const slides = document.querySelectorAll('.presentation-slide-view');
                  slides.forEach((sl, idx) => {
                    sl.classList.toggle('active', idx === activeSlideIndex);
                  });

                  // Sincronizar cor de fundo com o slide ativo para fundir com as margens
                  syncSlideBackground();

                  const counter = document.getElementById('hud-counter');
                  if (counter) counter.textContent = `${activeSlideIndex + 1} / ${totalSlides}`;

                  const prevBtn = document.getElementById('hud-prev');
                  if (prevBtn) prevBtn.disabled = (activeSlideIndex === 0);

                  const nextBtn = document.getElementById('hud-next');
                  if (nextBtn) nextBtn.disabled = (activeSlideIndex === totalSlides - 1);
                }

                function syncSlideBackground() {
                  const isFS = currentPayload ? !!currentPayload.isFullScreen : false;
                  if (!isFS) {
                    // Em modo janela, limpa a cor direta para usar o fundo neutro do CSS (.is-windowed)
                    document.body.style.backgroundColor = '';
                    return;
                  }
                  const slides = document.querySelectorAll('.presentation-slide-view');
                  if (slides && slides[activeSlideIndex]) {
                    const activeSection = slides[activeSlideIndex].querySelector('section');
                    if (activeSection) {
                      const compStyle = window.getComputedStyle(activeSection);
                      const compBg = compStyle.backgroundColor;
                      if (compBg && compBg !== 'transparent' && compBg !== 'rgba(0, 0, 0, 0)') {
                        document.body.style.backgroundColor = compBg;
                      }
                    }
                  }
                }

                function toggleNativeFullscreen() {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.toggleFullscreen) {
                    window.webkit.messageHandlers.toggleFullscreen.postMessage({});
                  }
                }

                let hudTimer = null;
                let cursorTimer = null;

                window.addEventListener('mousemove', (e) => {
                  if (!document.body.classList.contains('marp-mode-presentation')) return;
                  const hud = document.querySelector('.presentation-hud');

                  // Restaurar cursor se estava oculto
                  document.body.style.cursor = 'default';
                  clearTimeout(cursorTimer);
                  cursorTimer = setTimeout(() => {
                    if (document.body.classList.contains('marp-mode-presentation') && (!hud || !hud.matches(':hover'))) {
                      document.body.style.cursor = 'none';
                    }
                  }, 2500);

                  if (!hud) return;

                  // O navegador de slides só aparece se o rato estiver no fundo da página (≤ 85px)
                  const distFromBottom = window.innerHeight - e.clientY;
                  if (distFromBottom <= 85) {
                    hud.classList.add('visible');
                    clearTimeout(hudTimer);
                    hudTimer = setTimeout(() => {
                      if (!hud.matches(':hover')) {
                        hud.classList.remove('visible');
                      }
                    }, 3000);
                  } else {
                    if (!hud.matches(':hover')) {
                      clearTimeout(hudTimer);
                      hud.classList.remove('visible');
                    }
                  }
                });

                window.addEventListener('keydown', (e) => {
                  if (!document.body.classList.contains('marp-active')) return;
                  const mode = currentPayload ? currentPayload.mode : 'presentation';

                  if (mode === 'presentation') {
                    if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === ' ' || e.key === 'PageDown') {
                      e.preventDefault();
                      showSlide(activeSlideIndex + 1);
                    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp' || e.key === 'PageUp') {
                      e.preventDefault();
                      showSlide(activeSlideIndex - 1);
                    } else if (e.key === 'Home') {
                      e.preventDefault();
                      showSlide(0);
                    } else if (e.key === 'End') {
                      e.preventDefault();
                      showSlide(totalSlides - 1);
                    } else if (e.key === 'f' || e.key === 'F') {
                      e.preventDefault();
                      toggleNativeFullscreen();
                    }
                  } else {
                    const items = document.querySelectorAll('.marp-list-item');
                    if (items.length === 0) return;

                    let currentIdx = 0;
                    const scrollPos = window.scrollY + 120;
                    items.forEach((item, i) => {
                      if (item.offsetTop <= scrollPos) currentIdx = i;
                    });

                    if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === ' ' || e.key === 'PageDown') {
                      if (currentIdx < items.length - 1) {
                        e.preventDefault();
                        items[currentIdx + 1].scrollIntoView({ behavior: 'smooth', block: 'center' });
                      }
                    } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp' || e.key === 'PageUp') {
                      if (currentIdx > 0) {
                        e.preventDefault();
                        items[currentIdx - 1].scrollIntoView({ behavior: 'smooth', block: 'center' });
                      }
                    }
                  }
                });

                window.renderPayload = async function(payload) {
                  currentPayload = payload;
                  const text = payload.text;
                  const mode = payload.mode || 'presentation';
                  const customTheme = payload.customTheme || '';
                  const baseDir = payload.baseDir || '';
                  const contentDiv = document.getElementById('content');

                  if (!text || text.trim() === '') {
                    document.body.className = '';
                    contentDiv.className = 'normal-doc';
                    contentDiv.innerHTML = '<p style="color: var(--quote-color); font-style: italic;">Documento vazio.</p>';
                    return;
                  }

                  // 1. MODO MARP SLIDES
                  if (isMarpDocument(text) && typeof window.renderMarp === 'function') {
                    const printPageStyle = document.getElementById('litemd-print-page-style');
                    if (printPageStyle) printPageStyle.textContent = '@page { size: 1280px 720px; margin: 0; }';
                    const isFS = !!payload.isFullScreen;
                    document.body.className = `marp-active marp-mode-${mode} ${isFS ? 'is-fullscreen' : 'is-windowed'}`;
                    contentDiv.className = '';

                    try {
                      const result = window.renderMarp(text, customTheme);
                      let styleEl = document.getElementById('marp-injected-style');
                      if (!styleEl) {
                        styleEl = document.createElement('style');
                        styleEl.id = 'marp-injected-style';
                        document.head.appendChild(styleEl);
                      }
                      styleEl.textContent = result.css || '';

                      const temp = document.createElement('div');
                      temp.innerHTML = result.html;
                      const sections = temp.querySelectorAll('section');
                      totalSlides = sections.length;

                      if (mode === 'presentation') {
                        // VISTA DE APRESENTAÇÃO (1 slide por ecrã)
                        let html = '<div class="presentation-stage" onclick="handleClickStage(event)" ondblclick="handleDblClickStage(event)">';
                        html += '<div class="presentation-scaler">';
                        sections.forEach((sec, idx) => {
                          html += `<div class="presentation-slide-view ${idx === activeSlideIndex ? 'active' : ''}">${sec.outerHTML}</div>`;
                        });
                        html += '</div></div>';

                        // HUD Flutuante com navegação e botão Fullscreen
                        html += `
                          <div class="presentation-hud">
                            <button class="hud-btn" id="hud-prev" onclick="showSlide(activeSlideIndex - 1)">◀</button>
                            <span class="hud-counter" id="hud-counter">${activeSlideIndex + 1} / ${totalSlides}</span>
                            <button class="hud-btn" id="hud-next" onclick="showSlide(activeSlideIndex + 1)">▶</button>
                            <button class="hud-btn" id="hud-fs" onclick="toggleNativeFullscreen()" title="Alternar Ecrã Inteiro (F)">⛶</button>
                          </div>
                        `;
                        contentDiv.innerHTML = html;
                        showSlide(activeSlideIndex);
                      } else {
                        // VISTA EM LISTA (todos os slides em fila vertical)
                        let html = '<div class="marp-list-deck">';
                        sections.forEach((sec, idx) => {
                          html += `
                            <div class="marp-list-item">
                              <div class="marp-list-scaler">
                                ${sec.outerHTML}
                              </div>
                              <div class="marp-list-badge">Slide ${idx + 1} / ${totalSlides}</div>
                            </div>
                          `;
                        });
                        html += '</div>';
                        contentDiv.innerHTML = html;
                      }

                      // Corrigir caminhos de imagens locais relativas
                      fixRelativeImages(contentDiv, baseDir);
                      adjustLayout();

                      // Code highlighting
                      document.querySelectorAll('section pre code').forEach(el => {
                        if (!el.classList.contains('language-mermaid') && window.hljs) {
                          hljs.highlightElement(el);
                        }
                      });

                      // Mermaid
                      try {
                        const mermaidNodes = [];
                        document.querySelectorAll('section pre code.language-mermaid').forEach(el => {
                          const container = document.createElement('div');
                          container.className = 'mermaid';
                          container.textContent = el.textContent;
                          el.parentElement.replaceWith(container);
                          mermaidNodes.push(container);
                        });
                        if (mermaidNodes.length > 0 && window.mermaid) {
                          await mermaid.run({ nodes: mermaidNodes });
                        }
                      } catch (err) {
                        console.error('Mermaid error:', err);
                      }
                      return;
                    } catch (err) {
                      console.error('Marp error:', err);
                    }
                  }

                  // 2. MODO NORMAL (NÃO-MARP)
                  const printPageStyle = document.getElementById('litemd-print-page-style');
                  if (printPageStyle) printPageStyle.textContent = '@page { size: A4 portrait; margin: 20mm 18mm; }';
                  document.body.className = '';
                  contentDiv.className = 'normal-doc';
                  const styleEl = document.getElementById('marp-injected-style');
                  if (styleEl) styleEl.textContent = '';

                  const renderer = new marked.Renderer();
                  const originalCode = renderer.code.bind(renderer);
                  renderer.code = function({ text, lang }) {
                    if (lang === 'mermaid') {
                      return '<div class="mermaid-container"><pre class="mermaid">' + text + '</pre></div>';
                    }
                    return originalCode({ text, lang });
                  };

                  marked.setOptions({
                    renderer: renderer,
                    gfm: true,
                    breaks: true
                  });

                  contentDiv.innerHTML = marked.parse(text);
                  fixRelativeImages(contentDiv, baseDir);

                  document.querySelectorAll('pre code:not(.language-mermaid)').forEach((el) => {
                    if (window.hljs) hljs.highlightElement(el);
                  });

                  try {
                    const mermaidNodes = document.querySelectorAll('.mermaid');
                    if (mermaidNodes.length > 0) {
                      await mermaid.run({ nodes: mermaidNodes });
                    }
                  } catch (err) {
                    console.error('Mermaid render error:', err);
                  }
                };

                window.handleClickStage = function(e) {
                  const rect = e.currentTarget.getBoundingClientRect();
                  const clickX = e.clientX - rect.left;
                  if (clickX < rect.width * 0.3) {
                    showSlide(activeSlideIndex - 1);
                  } else {
                    showSlide(activeSlideIndex + 1);
                  }
                };

                window.handleDblClickStage = function(e) {
                  e.preventDefault();
                  e.stopPropagation();
                  toggleNativeFullscreen();
                };
              </script>
            </body>
            </html>
            """
        }
    }
}
