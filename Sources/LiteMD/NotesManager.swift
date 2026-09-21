import SwiftUI
import Foundation
import AppKit

struct NoteItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let modifiedDate: Date
    let preview: String
}

class NotesManager: ObservableObject {
    @Published var folderURL: URL
    @Published var notes: [NoteItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false

    private let folderKey = "litemd_notes_folder_path"

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let defaultFolder = appSupport.appendingPathComponent("LiteMD").appendingPathComponent("Notas")
        try? FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)

        if let savedPath = UserDefaults.standard.string(forKey: "litemd_notes_folder_path"),
           FileManager.default.fileExists(atPath: savedPath),
           !savedPath.contains("/Documents/Notas") {
            self.folderURL = URL(fileURLWithPath: savedPath)
        } else {
            self.folderURL = defaultFolder
            UserDefaults.standard.set(defaultFolder.path, forKey: "litemd_notes_folder_path")
        }
        refresh()
    }

    var filteredNotes: [NoteItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return notes
        }
        return notes.filter { note in
            note.name.lowercased().contains(query) || note.preview.lowercased().contains(query)
        }
    }

    func refresh() {
        let url = folderURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var items: [NoteItem] = []

            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "md" || ext == "markdown" || ext == "txt" {
                        let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                        let modDate = attrs?.contentModificationDate ?? Date()

                        // Ler pequenas primeiras linhas para excerto rápido (máx 1KB)
                        var preview = ""
                        if let handle = try? FileHandle(forReadingFrom: fileURL) {
                            let data = handle.readData(ofLength: 1024)
                            try? handle.close()
                            if let text = String(data: data, encoding: .utf8) {
                                let lines = text.components(separatedBy: .newlines)
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
                                preview = lines.prefix(2).joined(separator: " ")
                            }
                        }

                        let rawName = fileURL.deletingPathExtension().lastPathComponent
                        items.append(NoteItem(
                            url: fileURL,
                            name: rawName,
                            modifiedDate: modDate,
                            preview: preview
                        ))
                    }
                }
            }

            items.sort { $0.modifiedDate > $1.modifiedDate }

            DispatchQueue.main.async {
                self.notes = items
            }
        }
    }

    func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Selecionar Pasta de Notas"
        panel.directoryURL = folderURL

        if panel.runModal() == .OK, let selectedURL = panel.url {
            self.folderURL = selectedURL
            UserDefaults.standard.set(selectedURL.path, forKey: folderKey)
            refresh()
        }
    }

    func createNewNote() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Nota \(timestamp).md"
        let fileURL = folderURL.appendingPathComponent(filename)

        let initialContent = "# Nova Nota\n\n"
        do {
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            refresh()
            return fileURL
        } catch {
            print("Erro ao criar nova nota: \(error)")
            return nil
        }
    }

    func deleteNote(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            refresh()
        } catch {
            print("Erro ao apagar nota: \(error)")
        }
    }
}
