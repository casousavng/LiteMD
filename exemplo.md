# Exemplo LiteMD

Este é um documento de teste para o **LiteMD**.

## Diagrama de Fluxo (Mermaid)

```mermaid
graph TD
    Start([Abrir Ficheiro .md]) --> Edit[Editar Texto / Diagramas]
    Edit --> ClickVer{Clicar em 'Ver'}
    ClickVer --> Formatted[Renderizar Markdown Formatado]
    Formatted --> MermaidGraph[Renderizar Diagrama SVG]
    Formatted --> SyntaxCode[Colorir Sintaxe de Código]
    Formatted --> ClickEdit[Clicar em 'Editar']
    ClickEdit --> Edit
```

## Diagrama de Sequência

```mermaid
sequenceDiagram
    autonumber
    actor Utilizador
    participant App as LiteMD
    participant WebKit as WKWebView (Mermaid)

    Utilizador->>App: Clica no botão "Ver" (⌘E)
    App->>WebKit: Envia Markdown
    WebKit->>WebKit: Renderiza Markdown + SVG
    WebKit-->>Utilizador: Exibe visualização formatada
```

## Bloco de Código

```swift
import SwiftUI

struct LiteMDView: View {
    var body: some View {
        Text("Superlite e Rápido!")
    }
}
```

## Tabela de Atalhos

| Atalho | Ação |
| :--- | :--- |
| `⌘E` | Alternar entre **Ver** e **Editar** |
| `⌘O` | Abrir ficheiro `.md` |
| `⌘S` | Guardar ficheiro atual |
| Drag & Drop | Arrastar qualquer `.md` para a janela |
