import SwiftUI
import UniformTypeIdentifiers

struct WindowAccessor: NSViewRepresentable {
    let proportion: CGFloat
    @Binding var isFullScreen: Bool
    let hideChrome: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain || $0.isVisible }),
                  let screen = window.screen ?? NSScreen.main else { return }
            
            configureWindow(window)

            self.isFullScreen = window.styleMask.contains(.fullScreen)
            
            if !self.isFullScreen {
                let visible = screen.visibleFrame
                let targetW = visible.width * proportion
                let targetH = visible.height * proportion
                let x = visible.origin.x + (visible.width - targetW) / 2
                let y = visible.origin.y + (visible.height - targetH) / 2
                window.setFrame(NSRect(x: x, y: y, width: targetW, height: targetH), display: true, animate: false)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configureWindow(window)

            let fs = window.styleMask.contains(.fullScreen)
            if self.isFullScreen != fs {
                self.isFullScreen = fs
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }

        let hideButtons = self.hideChrome
        window.standardWindowButton(.closeButton)?.isHidden = hideButtons
        window.standardWindowButton(.miniaturizeButton)?.isHidden = hideButtons
        window.standardWindowButton(.zoomButton)?.isHidden = hideButtons
    }
}

struct ContentView: View {
    @EnvironmentObject var docManager: DocumentManager
    @State private var markdownText: String = """
    # Bem-vindo ao LiteMD

    Edita o teu Markdown aqui e clica no botão **Ver** no topo para pré-visualizar formatado com diagramas!

    ## Exemplo de Diagrama Mermaid

    ```mermaid
    graph TD
        A[Editar .md] -->|Clica em Ver| B(Visualização Formatada)
        B -->|Clica em Editar| A
        B --> C[Diagramas Vetoriais]
        B --> D[Código com Syntax Highlighting]
    ```

    ## Código e Tabelas

    ```swift
    let app = "LiteMD"
    print("Superlite e rápido!")
    ```

    | Recurso | Suporte |
    | :--- | :--- |
    | Markdown GFM | Sim |
    | Mermaid | Sim |
    | Mac Nativo | Sim |
    """
    @StateObject private var notesManager = NotesManager()
    @State private var showSidebar: Bool = false
    @State private var autoSaveWorkItem: DispatchWorkItem? = nil
    @State private var autoSaveStatus: String = ""
    @State private var isViewing: Bool = false
    @State private var currentFileURL: URL? = nil
    @State private var isTargetedForDrop: Bool = false
    @State private var showNewConfirmDialog: Bool = false
    @State private var slideViewMode: SlideViewMode = .presentation
    @State private var isFullScreen: Bool = false

    private var hideChrome: Bool {
        isFullScreen && isMarp && isViewing
    }

    private var lineCount: Int {
        markdownText.components(separatedBy: .newlines).count
    }

    private var wordCount: Int {
        let words = markdownText.components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    private var charCount: Int {
        markdownText.count
    }

    private var isMarp: Bool {
        let trimmed = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return false }
        let parts = trimmed.components(separatedBy: "---")
        guard parts.count >= 2 else { return false }
        let frontmatter = parts[1].lowercased()
        return frontmatter.range(of: #"\bmarp\s*:\s*true\b"#, options: .regularExpression) != nil
    }

    private var marpSlideCount: Int {
        let trimmed = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: "\n---")
        return max(1, parts.count - 1)
    }

    private var frontmatterTitle: String? {
        let trimmed = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }
        let parts = trimmed.components(separatedBy: "---")
        guard parts.count >= 2 else { return nil }
        let frontmatter = parts[1]
        let pattern = #"(?m)^\s*title\s*:\s*["']?([^"'\n\r]+)["']?\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: frontmatter, range: NSRange(frontmatter.startIndex..., in: frontmatter)),
           let range = Range(match.range(at: 1), in: frontmatter) {
            let title = String(frontmatter[range]).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    private var defaultWidth: CGFloat {
        (NSScreen.main?.visibleFrame.width ?? 1440) * 0.88
    }

    private var defaultHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.88
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hideChrome {
                // Toolbar superior minimalista e desobstruída
                HStack(spacing: 10) {
                    // Botão para alternar a Barra Lateral de Notas
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showSidebar ? .accentColor : .primary)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("\\", modifiers: .command)
                    .help(showSidebar ? "Ocultar lista de notas (⌘\\)" : "Mostrar lista de notas (⌘\\)")

                    // Ações de ficheiro à esquerda
                    Button(action: newDocument) {
                        Label("Novo", systemImage: "doc.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Criar novo documento Markdown (⌘N)")

                    Button(action: openFile) {
                        Label("Abrir", systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Abrir ficheiro Markdown (⌘O)")

                    Button(action: { _ = saveFile() }) {
                        Label("Guardar", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Guardar ficheiro atual (⌘S)")

                    Button(action: exportPDF) {
                        Label("PDF", systemImage: "arrow.down.doc")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .help("Exportar como PDF (⌘⇧P)")

                    // Centro livre e desobstruído
                    Spacer()

                    // À direita: Seletor de Modo de Slides (quando em visualização Marp)
                    if isViewing && isMarp {
                        Picker("", selection: $slideViewMode) {
                            Label("Apresentação", systemImage: "play.rectangle.fill").tag(SlideViewMode.presentation)
                            Label("Lista", systemImage: "rectangle.grid.1x2").tag(SlideViewMode.list)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.large)
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    // O BOTÃO PRINCIPAL: Ver / Editar / Apresentar Marp
                    Button(action: toggleView) {
                        HStack(spacing: 6) {
                            Image(systemName: isViewing ? "pencil" : (isMarp ? "play.rectangle.fill" : "eye.fill"))
                            Text(isViewing ? "Editar" : (isMarp ? "Apresentar" : "Ver"))
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(isViewing ? .indigo : (isMarp ? .orange : .accentColor))
                    .keyboardShortcut("e", modifiers: .command)
                    .help(isViewing ? "Voltar à edição (⌘E)" : (isMarp ? "Apresentar slides Marp (⌘E)" : "Visualizar formatado com diagramas (⌘E)"))
                }                .padding(.leading, isFullScreen ? 16 : 78)
                .padding(.trailing, 16)
                .padding(.top, isFullScreen ? 10 : 12)
                .padding(.bottom, 10)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.move(edge: .top).combined(with: .opacity))

                Divider()
            }

            // Área principal: Barra lateral de notas + Editor ou Visualizador
            HStack(spacing: 0) {
                if showSidebar && !hideChrome {
                    NotesSidebarView(
                        notesManager: notesManager,
                        activeFileURL: currentFileURL,
                        onSelectNote: { url in
                            loadFile(from: url)
                        },
                        onNewNote: {
                            if let url = notesManager.createNewNote() {
                                loadFile(from: url)
                                if isViewing {
                                    isViewing = false
                                }
                            }
                        }
                    )
                    .transition(.move(edge: .leading))

                    Divider()
                }

                ZStack {
                    if isViewing {
                        MarkdownWebView(
                            markdown: markdownText,
                            fileURL: currentFileURL,
                            slideViewMode: slideViewMode,
                            isFullScreen: isFullScreen
                        )
                        .transition(.opacity)
                    } else {
                        TextEditor(text: $markdownText)
                            .font(.system(.body, design: .monospaced))
                            .padding(14)
                            .background(Color(NSColor.textBackgroundColor))
                            .transition(.opacity)
                            .onChange(of: markdownText) { _ in
                                triggerAutoSave()
                            }
                    }

                    // Overlay visual quando arrasta ficheiro para a janela
                    if isTargetedForDrop {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .background(Color.accentColor.opacity(0.1))
                            .overlay(
                                Text("Largar ficheiro .md para abrir")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            )
                    }
                }
            }

            if !hideChrome {
                Divider()

                // Barra de estado inferior (Rodapé): Informação do ficheiro à esquerda, estatísticas à direita
                HStack(spacing: 12) {
                    // Nome e Título do Ficheiro à esquerda
                    HStack(spacing: 8) {
                        Image(systemName: isMarp ? "play.tv.fill" : "doc.text")
                            .foregroundColor(isMarp ? .orange : .secondary)

                        Text(currentFileURL?.lastPathComponent ?? "Sem título.md")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)

                        if let title = frontmatterTitle, title != currentFileURL?.lastPathComponent {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.4))
                            Text(title)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if isMarp {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("Marp (\(marpSlideCount) slides)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                        }

                        if !autoSaveStatus.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.4))
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                                Text(autoSaveStatus)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .transition(.opacity)
                        }
                    }
                    .help(currentFileURL?.path ?? "Documento sem título")

                    Spacer()

                    // Estatísticas de texto à direita
                    HStack(spacing: 8) {
                        Text("\(lineCount) linhas")
                        Text("•").foregroundColor(.secondary.opacity(0.4))
                        Text("\(wordCount) palavras")
                        Text("•").foregroundColor(.secondary.opacity(0.4))
                        Text("\(charCount) carateres")
                    }
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.all)
        .animation(.easeInOut(duration: 0.2), value: hideChrome)
        .frame(minWidth: 900, idealWidth: defaultWidth, minHeight: 600, idealHeight: defaultHeight)
        .background(WindowAccessor(proportion: 0.88, isFullScreen: $isFullScreen, hideChrome: hideChrome))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullScreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isFullScreen = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LiteMDTriggerExportPDFDialog"))) { _ in
            exportPDF()
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, isMarkdown(url: url) {
                    DispatchQueue.main.async {
                        loadFile(from: url)
                    }
                }
            }
            return true
        }
        .onOpenURL { url in
            loadFile(from: url)
        }
        .onReceive(docManager.$fileToOpen) { url in
            if let url = url {
                loadFile(from: url)
            }
        }
        .confirmationDialog(
            "Criar novo documento?",
            isPresented: $showNewConfirmDialog,
            titleVisibility: .visible
        ) {
            Button("Descartar e Criar Novo", role: .destructive) {
                createNewDocument()
            }
            Button("Guardar antes de criar") {
                if saveFile() {
                    createNewDocument()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O documento atual tem alterações. Deseja guardar antes de continuar?")
        }
    }

    private func newDocument() {
        let trimmed = markdownText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            showNewConfirmDialog = true
        } else {
            createNewDocument()
        }
    }

    private func createNewDocument() {
        self.markdownText = "# Sem título\n\n"
        self.currentFileURL = nil
        self.autoSaveStatus = ""
        if isViewing {
            isViewing = false
        }
    }

    private func isMarkdown(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown" || ext == "mkd" || ext == "txt"
    }

    private func toggleView() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isViewing.toggle()
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(from: url)
        }
    }

    private func loadFile(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            self.markdownText = content
            self.currentFileURL = url
            self.autoSaveStatus = ""
        } catch {
            print("Erro ao ler ficheiro: \(error)")
        }
    }

    private func triggerAutoSave() {
        guard let url = currentFileURL else { return }
        autoSaveWorkItem?.cancel()

        let textToSave = markdownText
        let item = DispatchWorkItem {
            do {
                try textToSave.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.autoSaveStatus = "Guardado"
                    }
                    self.notesManager.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if self.autoSaveStatus == "Guardado" {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.autoSaveStatus = ""
                            }
                        }
                    }
                }
            } catch {
                print("Erro no auto-save: \(error)")
            }
        }
        autoSaveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    @discardableResult
    private func saveFile() -> Bool {
        if let currentURL = currentFileURL {
            do {
                try markdownText.write(to: currentURL, atomically: true, encoding: .utf8)
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.autoSaveStatus = "Guardado"
                }
                notesManager.refresh()
                return true
            } catch {
                print("Erro ao guardar: \(error)")
                return false
            }
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "documento.md"

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try markdownText.write(to: url, atomically: true, encoding: .utf8)
                    self.currentFileURL = url
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.autoSaveStatus = "Guardado"
                    }
                    notesManager.refresh()
                    return true
                } catch {
                    print("Erro ao guardar: \(error)")
                    return false
                }
            }
            return false
        }
    }

    private func exportPDF() {
        if !isViewing {
            isViewing = true
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? (isMarp ? "Apresentação" : "Documento")
        panel.nameFieldStringValue = "\(baseName).pdf"
        panel.prompt = "Exportar PDF"
        panel.message = isMarp ? "Exportar todos os slides como PDF (16:9)" : "Exportar documento formatado como PDF (A4)"

        if panel.runModal() == .OK, let targetURL = panel.url {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(
                    name: Notification.Name("LiteMDExportPDF"),
                    object: targetURL,
                    userInfo: ["isMarp": self.isMarp]
                )
            }
        }
    }
}
