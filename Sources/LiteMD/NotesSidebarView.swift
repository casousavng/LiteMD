import SwiftUI
import AppKit

struct NotesSidebarView: View {
    @ObservedObject var notesManager: NotesManager
    let activeFileURL: URL?
    let onSelectNote: (URL) -> Void
    let onNewNote: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Cabeçalho da Sidebar
            HStack(spacing: 8) {
                Button(action: { notesManager.changeFolder() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(notesManager.folderURL.lastPathComponent)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Pasta atual: \(notesManager.folderURL.path). Clique para mudar de pasta.")

                Spacer()

                Button(action: onNewNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Criar nova nota nesta pasta")

                Button(action: { notesManager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Atualizar lista de notas")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Campo de Pesquisa
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))

                TextField("Pesquisar notas...", text: $notesManager.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !notesManager.searchText.isEmpty {
                    Button(action: { notesManager.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // Lista de Notas
            if notesManager.filteredNotes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: notesManager.searchText.isEmpty ? "note.text" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(notesManager.searchText.isEmpty ? "Nenhuma nota encontrada" : "Sem resultados")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    if notesManager.searchText.isEmpty {
                        Button("Criar Nota") {
                            onNewNote()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(notesManager.filteredNotes) { note in
                            let isSelected = activeFileURL == note.url
                            Button(action: { onSelectNote(note.url) }) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(note.name)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .white : .primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(formatDate(note.modifiedDate))
                                            .font(.system(size: 10))
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    }

                                    if !note.preview.isEmpty {
                                        Text(note.preview)
                                            .font(.system(size: 11))
                                            .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isSelected ? Color.accentColor : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .contextMenu {
                                Button("Mostrar no Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([note.url])
                                }
                                Divider()
                                Button("Apagar Nota", role: .destructive) {
                                    notesManager.deleteNote(at: note.url)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Barra inferior da sidebar com contagem de notas
            HStack {
                Text("\(notesManager.filteredNotes.count) \(notesManager.filteredNotes.count == 1 ? "nota" : "notas")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Ontem"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM"
            return formatter.string(from: date)
        }
    }
}
