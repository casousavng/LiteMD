import SwiftUI
import AppKit

class DocumentManager: ObservableObject {
    static let shared = DocumentManager()
    @Published var fileToOpen: URL? = nil

    init() {
        // Verificar se foi passado argumento via terminal (ex: LiteMD file.md)
        let args = CommandLine.arguments
        if args.count > 1 {
            let path = args[1]
            if !path.hasPrefix("-") {
                let url = URL(fileURLWithPath: path)
                self.fileToOpen = url
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: iconUrl) {
            NSApplication.shared.applicationIconImage = img
        } else if let localIcon = NSImage(contentsOfFile: "Resources/AppIcon.png") {
            NSApplication.shared.applicationIconImage = localIcon
        }

        // Redimensionar janela para 85% do ecrã logo no arranque
        DispatchQueue.main.async {
            self.resizeInitialWindowToScreenProportion(0.85)
        }
    }

    private func resizeInitialWindowToScreenProportion(_ proportion: CGFloat) {
        guard let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain || $0.isVisible }),
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let targetW = visible.width * proportion
        let targetH = visible.height * proportion
        let x = visible.origin.x + (visible.width - targetW) / 2
        let y = visible.origin.y + (visible.height - targetH) / 2
        window.setFrame(NSRect(x: x, y: y, width: targetW, height: targetH), display: true, animate: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        return false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
                return true
            }
        }
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        DispatchQueue.main.async {
            DocumentManager.shared.fileToOpen = url
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first {
            _ = application(sender, openFile: first)
        }
    }
}

@main
struct LiteMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var docManager = DocumentManager.shared

    var body: some Scene {
        Window("LiteMD", id: "main") {
            ContentView()
                .environmentObject(docManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Novo Documento") {
                    NotificationCenter.default.post(name: Notification.Name("LiteMDTriggerNewDocument"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Abrir...") {
                    NotificationCenter.default.post(name: Notification.Name("LiteMDTriggerOpenFile"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Guardar") {
                    NotificationCenter.default.post(name: Notification.Name("LiteMDTriggerSaveFile"), object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Exportar como PDF...") {
                    NotificationCenter.default.post(name: Notification.Name("LiteMDTriggerExportPDFDialog"), object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appInfo) {
                Button("Sobre o LiteMD") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 André Sousa",
                        NSApplication.AboutPanelOptionKey(rawValue: "ApplicationName"): "LiteMD",
                        NSApplication.AboutPanelOptionKey.version: "1.0.0",
                        NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.0",
                        NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                            string: "Desenvolvido por André Sousa\nVisualizador e Editor Markdown Ultraleve",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 11),
                                .foregroundColor: NSColor.secondaryLabelColor
                            ]
                        )
                    ])
                }
            }
        }
    }
}
