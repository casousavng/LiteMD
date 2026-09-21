# LiteMD ⚡

> **PT**: Visualizador e editor de Markdown nativo para macOS, ultraleve, com suporte a diagramas Mermaid, apresentações Marp (16:9) e exportação PDF profissional.  
> **EN**: Lightweight, native macOS Markdown viewer & editor with Mermaid diagrams, Marp presentations (16:9), and professional PDF export.

---

## Índice / Table of Contents
- [Português](#-português)
  - [Funcionalidades](#funcionalidades)
  - [Atalhos de Teclado](#atalhos-de-teclado)
  - [Como Compilar e Instalar](#como-compilar-e-instalar)
  - [Como Editar e Personalizar o Código](#como-editar-e-personalizar-o-código)
  - [Utilização via Terminal (CLI)](#utilização-via-terminal-cli)
- [English](#-english)
  - [Features](#features)
  - [Keyboard Shortcuts](#keyboard-shortcuts)
  - [How to Build & Install](#how-to-build--install)
  - [How to Edit & Customize](#how-to-edit--customize)
  - [CLI Usage](#cli-usage)

---

# 🇵🇹 Português

O **LiteMD** foi concebido como uma alternativa nativa, rápida e elegante aos visualizadores pesados em Electron. Utiliza SwiftUI moderno e WebKit otimizado para proporcionar uma experiência fluida no macOS.

### Funcionalidades

- 📝 **Editor e Visualizador Markdown**: Alternância instantânea entre escrita em texto puro e visualização rica (`⌘E`).
- 📊 **Diagramas Mermaid Integrados**: Renderização de diagramas de fluxo, sequência, classes e arquitetura sem plugins externos.
- 🎨 **Coloração de Sintaxe**: Suporte para blocos de código com destaque automático via Highlight.js.
- 🚀 **Apresentações Marp (16:9)**:
  - Deteção automática do cabeçalho YAML (`marp: true`).
  - **Modo Apresentação**: 1 slide por ecrã, navegação fluida por teclado e HUD flutuante inteligente.
  - **Modo Lista**: Visualização contínua de todos os slides para revisão rápida.
  - Ecrã Inteiro nativo (`F`) com transições suaves e adaptação automática de cor de fundo.
- 📄 **Exportação PDF de Alta Qualidade (`⌘⇧P`)**:
  - **Documentos Normais**: Paginação A4 com margens elegantes (20mm topo/base, 18mm laterais), preservação de linhas de tabela e tipografia limpa.
  - **Apresentações**: Exportação vetorizada 16:9 sem quebras aleatórias (1 página por slide).
- 📂 **Gestor de Notas e Barra Lateral (`⌘\`)**:
  - Organização por pastas locais.
  - Pesquisa rápida em tempo real e criação de novos documentos.
- 🖱️ **Integração macOS**: Drag & Drop de ficheiros `.md` diretamente na janela, suporte nativo a Modo Claro e Escuro.

---

### Atalhos de Teclado

| Atalho | Ação |
| :--- | :--- |
| `⌘E` | Alternar entre **Editar** e **Ver** (ou Apresentar se for Marp) |
| `⌘N` | Novo documento |
| `⌘O` | Abrir ficheiro do disco |
| `⌘S` | Guardar ficheiro atual |
| `⌘⇧P` | Exportar como PDF |
| `⌘\` | Alternar visibilidade da barra lateral de notas |
| `F` | Alternar modo Ecrã Inteiro (durante apresentação Marp) |
| `←` / `→` ou `Espaço` | Mudar de slide (no modo apresentação) |
| `Home` / `End` | Ir para o primeiro / último slide |

---

### Como Compilar e Instalar

#### Requisitos
- macOS 12.0 (Monterey) ou superior.
- Xcode Command Line Tools (`xcode-select --install`) ou Xcode com suporte a Swift 5.9+.

#### Instalação Rápida
Executa o script de compilação na raiz do projeto:

```bash
chmod +x build_app.sh
./build_app.sh
```

O script:
1. Compila o binário Swift em modo Release (`swift build -c release`).
2. Empacota o bundle `LiteMD.app` com os ícones e scripts auxiliares.
3. Instala a app diretamente em `/Applications/LiteMD.app`.
4. Regista o comando CLI global `litemd` em `~/.local/bin/litemd`.

---

### Como Editar e Personalizar o Código

#### Estrutura do Projeto
```
LiteMD/
├── Package.swift               # Manifesto do Swift Package Manager
├── build_app.sh                # Script de empacotamento e instalação
├── Resources/
│   ├── AppIcon.icns            # Ícone macOS
│   └── marp-viewer.min.js      # Motor Marp Core compilado
└── Sources/
    └── LiteMD/
        ├── App.swift           # Ponto de entrada @main e menus do sistema
        ├── ContentView.swift   # Vista principal SwiftUI, barra de topo e estado
        ├── MarkdownWebView.swift # Motor WKWebView, CSS, Marp, Mermaid e PDF
        ├── NotesManager.swift  # Gestão de pastas, ficheiros e persistência
        └── NotesSidebarView.swift # Interface da barra lateral de navegação
```

#### Onde Fazer Alterações:
- **Estilos de Documento e Impressão**: Edita o CSS em `Sources/LiteMD/MarkdownWebView.swift` dentro do bloco `@media print` e `#content.normal-doc`.
- **Motor Marp e Templates**: As regras de dimensionamento e navegação de slides encontram-se no JavaScript embutido em `MarkdownWebView.swift`.
- **Atalhos ou Menus de Sistema**: Edita os comandos e botões em `App.swift` e a barra de ferramentas em `ContentView.swift`.

Para testar alterações rapidamente durante o desenvolvimento:
```bash
swift run
```

---

### Utilização via Terminal (CLI)

Após a instalação com `./build_app.sh`, podes abrir qualquer documento ou apresentação diretamente do terminal:

```bash
# Abrir ficheiro existente
litemd ./minha_apresentacao.md

# Abrir pasta ou aplicação vazia
litemd
```

*(Nota: Certifica-te de que `~/.local/bin` está no teu `$PATH`)*.

---

# 🇬🇧 English

**LiteMD** is designed as a fast, native, and lightweight macOS alternative to resource-heavy Electron markdown viewers. Built using modern SwiftUI and an optimized WebKit rendering pipeline.

### Features

- 📝 **Markdown Editor & Live Viewer**: Switch effortlessly between raw Markdown editing and formatted reading mode (`⌘E`).
- 📊 **Built-in Mermaid Diagrams**: Native rendering for flowcharts, sequence diagrams, class diagrams, and state charts.
- 🎨 **Syntax Highlighting**: Pre-configured code block formatting powered by Highlight.js.
- 🚀 **Marp Presentations (16:9)**:
  - Automatic detection via YAML frontmatter (`marp: true`).
  - **Presentation Mode**: 1 slide per screen, keyboard navigation, and smart auto-hiding HUD.
  - **List Mode**: Continuous scrollable deck view for overview and quick scanning.
  - Native Fullscreen (`F`) with dynamic background color blending to match slide themes.
- 📄 **Professional PDF Export (`⌘⇧P`)**:
  - **Standard Documents**: Paginated A4 output with 20mm/18mm margins, table row break guards, and crisp typography.
  - **Slide Decks**: Vectorized 16:9 PDF export with exactly 1 slide per page.
- 📂 **Notes Manager & Sidebar (`⌘\`)**:
  - Local folder workspace navigation.
  - Real-time search and instant note creation.
- 🖱️ **macOS Integration**: Drag & Drop `.md` files onto the window, system Dark & Light mode integration.

---

### Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘E` | Toggle **Edit** and **View** (or Present in Marp) |
| `⌘N` | New document |
| `⌘O` | Open file from disk |
| `⌘S` | Save current file |
| `⌘⇧P` | Export to PDF |
| `⌘\` | Toggle notes sidebar |
| `F` | Toggle Fullscreen (during Marp presentation) |
| `←` / `→` or `Space` | Next / Previous slide |
| `Home` / `End` | Jump to first / last slide |

---

### How to Build & Install

#### Prerequisites
- macOS 12.0 (Monterey) or later.
- Xcode Command Line Tools (`xcode-select --install`) or Xcode with Swift 5.9+.

#### Installation
Run the build script from the repository root:

```bash
chmod +x build_app.sh
./build_app.sh
```

This will:
1. Build the production binary (`swift build -c release`).
2. Package `LiteMD.app` with icons and bundled resources.
3. Install to `/Applications/LiteMD.app`.
4. Install the global terminal command `litemd` into `~/.local/bin/litemd`.

---

### How to Edit & Customize

#### Code Architecture
```
LiteMD/
├── Package.swift               # Swift Package Manager manifest
├── build_app.sh                # App bundle packaging and installer
├── Resources/
│   ├── AppIcon.icns            # macOS app icon
│   └── marp-viewer.min.js      # Bundled Marp Core engine
└── Sources/
    └── LiteMD/
        ├── App.swift           # @main entry point and system menu bar
        ├── ContentView.swift   # Main SwiftUI layout, top navigation bar, view state
        ├── MarkdownWebView.swift # WebKit engine, CSS, Marp, Mermaid & PDF rendering
        ├── NotesManager.swift  # Workspace file operations and note storage
        └── NotesSidebarView.swift # Folder browser & sidebar UI
```

#### Key Customization Points:
- **Print / PDF Layout & Margins**: Check `@media print` and `#litemd-print-page-style` in `Sources/LiteMD/MarkdownWebView.swift`.
- **Slide Presentation Logic**: Slide scaling, keyboard handling, and HUD logic are located in the embedded JavaScript inside `MarkdownWebView.swift`.
- **UI / Shortcuts**: Add or modify shortcuts in `Sources/LiteMD/App.swift` and `Sources/LiteMD/ContentView.swift`.

Run locally for fast iteration:
```bash
swift run
```

---

### CLI Usage

Once built, open files directly from your terminal:

```bash
# Open an existing document or presentation
litemd ./my_notes.md

# Launch application
litemd
```

*(Ensure `~/.local/bin` is exported in your shell's `$PATH`)*.

---

## Licença / License

MIT License © 2026 André Sousa.
