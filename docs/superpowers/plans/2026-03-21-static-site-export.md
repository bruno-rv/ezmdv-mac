# Static Site Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export an entire project vault as a self-contained static HTML website, with per-file HTML pages, relative navigation, an index page with sidebar, and wiki-link rewriting — all rendered via JavaScriptCore (no additional WKWebViews).

**Architecture:** A new `StaticSiteExporter` service owns the full export pipeline: it loads `marked.js` from the app bundle into a `JSContext`, evaluates each markdown file's content in that shared context (reusing the same JS engine across all files for performance), rewrites `[[wiki-links]]` to relative `.html` hrefs, copies referenced images, and writes out a complete folder of HTML files plus a generated `index.html`. A small `SiteExportProgressView` SwiftUI sheet shows live progress. The menu item and `Notification.Name` extension live in `EzmdvApp.swift`, keeping the existing notification-dispatch pattern.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, JavaScriptCore (`JSContext`/`JSValue`), AppKit (`NSOpenPanel`), Foundation file I/O, existing `WikiLinkResolver`, `JSEscaping`, `MarkdownFile.flatten`, `ExportService` (read-only reference for CSS extraction)

---

## Codebase Orientation

Before starting, read these files to understand conventions:

- `Sources/EzmdvApp/Services/ExportService.swift` — existing single-file HTML export; the CSS block in `generateStandaloneHTML` is the source of truth for site styles
- `Sources/EzmdvApp/Services/WikiLinkResolver.swift` — `resolve(target:in:)` and `findLinks(in:)` are reused as-is
- `Sources/EzmdvApp/Services/JSEscaping.swift` — `escapeForTemplateLiteral` is needed to safely embed markdown into JS
- `Sources/EzmdvApp/Models/Project.swift` — `Project`, `MarkdownFile`, `MarkdownFile.flatten`
- `Sources/EzmdvApp/EzmdvApp.swift` — the `CommandGroup(after: .saveItem)` block is where the new menu item is added; `Notification.Name` extensions are at the bottom
- `Sources/EzmdvApp/Resources/markdown.html` — look at the full `<style>` block (lines 20–214); this CSS is embedded verbatim into generated pages

---

## File Map

| Action   | Path | Responsibility |
|----------|------|----------------|
| Create   | `Sources/EzmdvApp/Services/StaticSiteExporter.swift` | Core export engine: JSContext setup, per-file HTML generation, wiki-link rewriting, image copying, index.html |
| Create   | `Sources/EzmdvApp/Views/SiteExportProgressView.swift` | SwiftUI progress sheet shown during export |
| Modify   | `Sources/EzmdvApp/EzmdvApp.swift` | Add `Button("Export Vault as Site…")` in the export `CommandGroup`; add `.exportVaultSite` to `Notification.Name` extension |
| Modify   | `Sources/EzmdvApp/Views/ContentView.swift` | Add `.onReceive(.exportVaultSite)` handler that triggers the export sheet |

---

## Task 1: Add the Notification Name and Menu Item

**Files:**
- Modify: `Sources/EzmdvApp/EzmdvApp.swift`

- [ ] **Step 1: Add `.exportVaultSite` to the `Notification.Name` extension**

  Open `Sources/EzmdvApp/EzmdvApp.swift`. At the bottom, in the `extension Notification.Name` block, add one line after `.exportHTML`:

  ```swift
  static let exportVaultSite = Notification.Name("exportVaultSite")
  ```

- [ ] **Step 2: Add the menu item**

  In the same file, find the `CommandGroup(after: .saveItem)` block. After the existing `Button("Export as HTML…")` button, add:

  ```swift
  Button("Export Vault as Site…") {
      NotificationCenter.default.post(name: .exportVaultSite, object: nil)
  }
  ```

  No keyboard shortcut is needed (this is a power-user operation).

- [ ] **Step 3: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/EzmdvApp.swift
  git commit -m "feat: add Export Vault as Site menu item and notification name"
  ```

---

## Task 2: Create the Progress Sheet View

**Files:**
- Create: `Sources/EzmdvApp/Views/SiteExportProgressView.swift`

This is a simple modal sheet shown during export. It shows a file counter and an indeterminate progress spinner.

- [ ] **Step 1: Create the file**

  ```swift
  // Sources/EzmdvApp/Views/SiteExportProgressView.swift
  import SwiftUI

  struct SiteExportProgressView: View {
      let totalFiles: Int
      @Binding var completedFiles: Int
      @Binding var currentFileName: String
      let onCancel: () -> Void

      var body: some View {
          VStack(spacing: 16) {
              Text("Exporting Vault…")
                  .font(.headline)

              ProgressView(value: totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0)
                  .progressViewStyle(.linear)
                  .frame(width: 320)

              Text("\(completedFiles) / \(totalFiles) files")
                  .font(.caption)
                  .foregroundColor(.secondary)

              if !currentFileName.isEmpty {
                  Text(currentFileName)
                      .font(.caption2)
                      .foregroundColor(.secondary)
                      .lineLimit(1)
                      .truncationMode(.middle)
                      .frame(width: 320)
              }

              Button("Cancel", role: .cancel, action: onCancel)
                  .keyboardShortcut(.cancelAction)
          }
          .padding(24)
          .frame(minWidth: 380)
      }
  }
  ```

- [ ] **Step 2: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/SiteExportProgressView.swift
  git commit -m "feat: add SiteExportProgressView sheet for site export progress"
  ```

---

## Task 3: Create StaticSiteExporter — JSContext Setup and Single-File Rendering

**Files:**
- Create: `Sources/EzmdvApp/Services/StaticSiteExporter.swift`

This task creates the file and implements the JSContext-based markdown-to-HTML renderer. We do not yet wire it to the full export loop — just the core rendering primitive.

### Background: how JavaScriptCore works here

`JSContext` is Apple's JS engine (the same engine used by Safari/WKWebView). We load `marked.min.js` from the app bundle into a `JSContext` once, then call `marked.parse(mdString)` for every file. This is ~10-100x faster than spawning one WKWebView per file and avoids all async complexity.

**Important:** `marked.min.js` is already in the app bundle (it is loaded by `markdown.html` from a CDN at runtime). For the JSContext approach, we need a **local copy** of `marked.min.js` bundled with the app. Task 3 includes adding the file to the bundle.

### Step-by-step

- [ ] **Step 1: Download marked.min.js and register it in Package.swift**

  ```bash
  curl -L "https://cdnjs.cloudflare.com/ajax/libs/marked/15.0.7/marked.min.js" \
    -o /Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Resources/marked.min.js
  ```

  **Important:** `Package.swift` in this project lists resources explicitly (not as a whole-directory glob). Open `Package.swift` and add the new file to the `resources` array:

  ```swift
  // Package.swift — inside the .executableTarget resources array
  resources: [
      .copy("Resources/markdown.html"),
      .copy("Resources/markdown.css"),
      .copy("Resources/editor.js"),
      .copy("Resources/marked.min.js"),   // <-- add this line
  ]
  ```

  Verify the file is included in the build:

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -5
  ```

  Expected: `Build complete!` (no error about missing resource)

- [ ] **Step 2: Create the exporter file with JSContext setup and single-file renderer**

  ```swift
  // Sources/EzmdvApp/Services/StaticSiteExporter.swift
  import Foundation
  import JavaScriptCore

  /// Exports a project vault as a self-contained static HTML website.
  final class StaticSiteExporter {

      // MARK: - Cancellation

      private var cancelled = false

      func cancel() { cancelled = true }

      // MARK: - JS Engine (shared across all files in one export run)

      private var jsContext: JSContext?

      /// Load marked.min.js from the app bundle into a fresh JSContext.
      /// Returns the context, or nil if the bundle resource is missing.
      private func makeJSContext() -> JSContext? {
          guard let url = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
                let source = try? String(contentsOf: url, encoding: .utf8) else {
              return nil
          }
          let ctx = JSContext()!
          ctx.exceptionHandler = { _, exception in
              print("[StaticSiteExporter] JS exception: \(exception?.toString() ?? "unknown")")
          }
          ctx.evaluateScript(source)
          // Configure marked: GFM on, no line breaks
          ctx.evaluateScript("marked.setOptions({ gfm: true, breaks: false });")
          return ctx
      }

      /// Convert a markdown string to an HTML fragment using marked.js via JSContext.
      /// Returns nil if the JSContext is unavailable or JS throws.
      func renderMarkdown(_ markdown: String, context: JSContext) -> String? {
          let escaped = JSEscaping.escapeForTemplateLiteral(markdown)
          let result = context.evaluateScript("marked.parse(`\(escaped)`)")
          return result?.toString()
      }

      // MARK: - Slug / path utilities

      /// Converts a relative markdown path ("Notes/My File.md") to a relative HTML path ("Notes/My File.html").
      static func htmlRelativePath(from mdRelativePath: String) -> String {
          let withoutExt = (mdRelativePath as NSString).deletingPathExtension
          return withoutExt + ".html"
      }

      /// Converts a display name or target string to a URL-safe slug.
      /// E.g. "My Note" -> "my-note", "Sub/Dir Note" -> "sub/dir-note"
      static func slugify(_ name: String) -> String {
          name
              .lowercased()
              .replacingOccurrences(of: " ", with: "-")
              .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_./")).inverted)
              .joined()
      }
  }
  ```

- [ ] **Step 3: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Resources/marked.min.js \
          Sources/EzmdvApp/Services/StaticSiteExporter.swift
  git commit -m "feat: add StaticSiteExporter with JSContext markdown renderer"
  ```

---

## Task 4: Implement Wiki-Link Rewriting for Static HTML

**Files:**
- Modify: `Sources/EzmdvApp/Services/StaticSiteExporter.swift`

Wiki-links in the source markdown (`[[Other Note]]`) must become relative HTML links (`<a href="../Other Note.html">Other Note</a>`) in the output. We rewrite them in the markdown string **before** calling `marked.parse`, so marked treats them as normal HTML anchor tags.

- [ ] **Step 1: Add `rewriteWikiLinks` method to `StaticSiteExporter`**

  Add the following method inside `StaticSiteExporter` (after `slugify`):

  ```swift
  /// Rewrites [[wiki-links]] in markdown to relative HTML anchor tags.
  ///
  /// - Parameters:
  ///   - markdown: raw markdown content
  ///   - sourceRelativePath: the relativePath of the file being processed (e.g. "Notes/My Note.md")
  ///   - allFiles: flat list of all MarkdownFile entries in the project
  /// - Returns: markdown with [[...]] replaced by <a href="..."> tags
  func rewriteWikiLinks(
      in markdown: String,
      sourceRelativePath: String,
      allFiles: [MarkdownFile]
  ) -> String {
      let links = WikiLinkResolver.findLinks(in: markdown)
      guard !links.isEmpty else { return markdown }

      let nsMarkdown = markdown as NSString
      var result = ""
      var lastEnd = 0

      for link in links {
          // Append text before this match
          let beforeRange = NSRange(location: lastEnd, length: link.fullMatch.location - lastEnd)
          result += nsMarkdown.substring(with: beforeRange)

          // Parse inner: "Target|Display" or "Target#heading"
          let inner = link.inner
          let pipeParts = inner.split(separator: "|", maxSplits: 1)
          let targetAndAnchor = String(pipeParts[0]).trimmingCharacters(in: .whitespaces)
          let displayText = pipeParts.count > 1
              ? String(pipeParts[1]).trimmingCharacters(in: .whitespaces)
              : targetAndAnchor

          // Resolve to a file
          let resolved = WikiLinkResolver.resolve(target: targetAndAnchor, in: allFiles)
          let anchor = WikiLinkResolver.headingAnchor(from: targetAndAnchor)

          if let resolved = resolved {
              // Compute relative path from sourceRelativePath's directory to the target's HTML file
              let sourceDir = (sourceRelativePath as NSString).deletingLastPathComponent
              let targetHTML = Self.htmlRelativePath(from: resolved.relativePath)
              let relativeHref = Self.relativePath(from: sourceDir, to: targetHTML)
              let hrefWithAnchor = anchor.map { relativeHref + "#\($0)" } ?? relativeHref
              result += "<a href=\"\(hrefWithAnchor)\">\(displayText)</a>"
          } else {
              // Unresolved: render as plain span so the text is preserved
              result += "<span class=\"wiki-link unresolved\">\(displayText)</span>"
          }

          lastEnd = link.fullMatch.location + link.fullMatch.length
      }

      // Append remaining text
      result += nsMarkdown.substring(from: lastEnd)
      return result
  }

  /// Compute a relative filesystem path from a source directory to a target file path.
  /// Both paths are relative to the same root (the project directory).
  ///
  /// Example: relativePath(from: "Notes/Sub", to: "Archive/Other.html") -> "../../Archive/Other.html"
  static func relativePath(from sourceDir: String, to targetPath: String) -> String {
      // Split on "/" — empty sourceDir means we're at root
      let fromParts = sourceDir.isEmpty ? [] : sourceDir.split(separator: "/").map(String.init)
      let toParts = targetPath.split(separator: "/").map(String.init)

      // Find common prefix length
      var commonLen = 0
      while commonLen < fromParts.count && commonLen < toParts.count
            && fromParts[commonLen] == toParts[commonLen] {
          commonLen += 1
      }

      // Go up from source to common ancestor, then down to target
      let ups = Array(repeating: "..", count: fromParts.count - commonLen)
      let downs = Array(toParts[commonLen...])
      let components = ups + downs
      return components.isEmpty ? "." : components.joined(separator: "/")
  }
  ```

- [ ] **Step 2: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Services/StaticSiteExporter.swift
  git commit -m "feat: add wiki-link rewriter for static HTML output"
  ```

---

## Task 5: Implement Per-File HTML Page Generation

**Files:**
- Modify: `Sources/EzmdvApp/Services/StaticSiteExporter.swift`

Each markdown file gets its own `.html` file at the same relative path. The HTML embeds all CSS inline (no external network dependencies) and uses a minimal two-column layout: a left sidebar (nav links) and a right content area. The CSS comes verbatim from `markdown.html` in the bundle.

- [ ] **Step 1: Add `extractBundleCSS` and `generatePageHTML` methods**

  Add the following methods inside `StaticSiteExporter`:

  ```swift
  /// Reads the full <style>…</style> block from the bundled markdown.html.
  /// Falls back to a minimal reset if the file is missing.
  private func extractBundleCSS() -> String {
      guard let url = Bundle.main.url(forResource: "markdown", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8) else {
          return "body { font-family: -apple-system, sans-serif; max-width: 820px; margin: 0 auto; padding: 2rem; }"
      }
      // Extract everything between <style> and </style>
      if let styleStart = html.range(of: "<style>"),
         let styleEnd = html.range(of: "</style>") {
          let css = String(html[styleStart.upperBound..<styleEnd.lowerBound])
          // Remove layout containers that are editor-specific (#view-container, #edit-container, etc.)
          return stripEditorLayoutCSS(css)
      }
      return ""
  }

  /// Removes CSS rules that are specific to the in-app editor and irrelevant in a static site.
  private func stripEditorLayoutCSS(_ css: String) -> String {
      // These selectors are safe to strip from exported pages
      let editorSelectors = [
          "#view-container", "#edit-container", "#preview-container",
          "#editor-pane", "#render-pane", ".slide-content",
      ]
      let lines = css.components(separatedBy: "\n")
      var output: [String] = []
      var skipDepth = 0

      for line in lines {
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          let startsEditorBlock = editorSelectors.contains(where: { trimmed.hasPrefix($0) })
          if startsEditorBlock && trimmed.hasSuffix("{") {
              skipDepth += 1
              continue
          }
          if skipDepth > 0 {
              if trimmed == "}" { skipDepth -= 1 }
              continue
          }
          output.append(line)
      }
      return output.joined(separator: "\n")
  }

  /// Generates a complete standalone HTML page for a single markdown file.
  ///
  /// - Parameters:
  ///   - title: page title (file name without extension)
  ///   - htmlBody: rendered HTML fragment (output of marked.parse)
  ///   - allFiles: full flat file list, used to generate the sidebar nav
  ///   - sourceRelativePath: relative path of the source .md file (for computing nav hrefs)
  ///   - css: the inlined CSS string from extractBundleCSS()
  func generatePageHTML(
      title: String,
      htmlBody: String,
      allFiles: [MarkdownFile],
      sourceRelativePath: String,
      css: String
  ) -> String {
      let sourceDir = (sourceRelativePath as NSString).deletingLastPathComponent
      let indexHref = Self.relativePath(from: sourceDir, to: "index.html")
      let navItems = allFiles
          .filter { !$0.isDirectory }
          .sorted { $0.relativePath < $1.relativePath }
          .map { file -> String in
              let htmlPath = Self.htmlRelativePath(from: file.relativePath)
              let href = Self.relativePath(from: sourceDir, to: htmlPath)
              let displayName = (file.name as NSString).deletingPathExtension
              let isCurrentPage = file.relativePath == sourceRelativePath
              let activeAttr = isCurrentPage ? " class=\"nav-active\"" : ""
              return "<li><a href=\"\(href)\"\(activeAttr)>\(displayName)</a></li>"
          }
          .joined(separator: "\n")

      return """
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>\(title)</title>
      <style>
      \(css)

      /* === Static site layout === */
      html, body { overflow: visible; height: auto; }
      .site-layout { display: flex; min-height: 100vh; }
      .site-nav {
        width: 220px; min-width: 180px; max-width: 260px;
        border-right: 1px solid var(--border);
        padding: 24px 0;
        position: sticky; top: 0; height: 100vh; overflow-y: auto;
        background: var(--bg); flex-shrink: 0;
      }
      .site-nav .nav-title {
        font-size: 11px; font-weight: 600; letter-spacing: 0.05em;
        text-transform: uppercase; color: var(--fg-secondary);
        padding: 0 16px 8px; margin-bottom: 4px;
        border-bottom: 1px solid var(--border);
      }
      .site-nav ul { list-style: none; margin: 8px 0 0; padding: 0; }
      .site-nav li { margin: 0; }
      .site-nav a {
        display: block; padding: 4px 16px;
        color: var(--fg); text-decoration: none; font-size: 13px;
        border-radius: 4px; margin: 1px 6px;
      }
      .site-nav a:hover { background: var(--code-bg); }
      .site-nav a.nav-active { color: var(--link); font-weight: 600; background: var(--code-bg); }
      .site-main { flex: 1; overflow: auto; }
      .site-main .markdown-body { max-width: 820px; padding: 32px 40px 80px; }
      @media (max-width: 640px) {
        .site-layout { flex-direction: column; }
        .site-nav { width: 100%; height: auto; position: static; border-right: none; border-bottom: 1px solid var(--border); }
      }
      </style>
      </head>
      <body>
      <div class="site-layout">
        <nav class="site-nav">
          <div class="nav-title"><a href="\(indexHref)" style="color:inherit;text-decoration:none;">Index</a></div>
          <ul>
      \(navItems)
          </ul>
        </nav>
        <main class="site-main">
          <article class="markdown-body">
      \(htmlBody)
          </article>
        </main>
      </div>
      </body>
      </html>
      """
  }
  ```

- [ ] **Step 2: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Services/StaticSiteExporter.swift
  git commit -m "feat: add per-file HTML page generator with inline CSS and sidebar nav"
  ```

---

## Task 6: Implement Index Page and Image Copying

**Files:**
- Modify: `Sources/EzmdvApp/Services/StaticSiteExporter.swift`

The `index.html` is a directory listing. Image copying handles relative `![alt](./images/foo.png)` references in the markdown.

- [ ] **Step 1: Add `generateIndexHTML` method**

  Add inside `StaticSiteExporter`:

  ```swift
  /// Generates an index.html that lists all files grouped by top-level directory.
  func generateIndexHTML(
      projectName: String,
      allFiles: [MarkdownFile],
      css: String
  ) -> String {
      // Group files by their top-level directory segment
      var groups: [(folder: String, files: [MarkdownFile])] = []
      var groupMap: [String: [MarkdownFile]] = [:]

      for file in allFiles.filter({ !$0.isDirectory }).sorted(by: { $0.relativePath < $1.relativePath }) {
          let parts = file.relativePath.split(separator: "/")
          let folder = parts.count > 1 ? String(parts[0]) : ""
          groupMap[folder, default: []].append(file)
      }

      // Sort: root files first, then named folders alphabetically
      let sortedKeys = groupMap.keys.sorted { a, b in
          if a.isEmpty { return true }
          if b.isEmpty { return false }
          return a < b
      }
      for key in sortedKeys {
          groups.append((folder: key, files: groupMap[key]!))
      }

      var listHTML = ""
      for group in groups {
          if !group.folder.isEmpty {
              listHTML += "<h2>\(group.folder)</h2>\n<ul>\n"
          } else {
              listHTML += "<ul>\n"
          }
          for file in group.files {
              let htmlPath = Self.htmlRelativePath(from: file.relativePath)
              let displayName = (file.name as NSString).deletingPathExtension
              listHTML += "  <li><a href=\"\(htmlPath)\">\(displayName)</a></li>\n"
          }
          listHTML += "</ul>\n"
      }

      return """
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>\(projectName)</title>
      <style>
      \(css)
      html, body { overflow: visible; height: auto; }
      .index-body { max-width: 820px; margin: 0 auto; padding: 40px; }
      .index-body h1 { font-size: 2em; margin-bottom: 0.25em; }
      .index-body h2 { font-size: 1.1em; color: var(--fg-secondary); margin-top: 1.5em; }
      .index-body ul { list-style: none; padding: 0; margin: 0.5em 0; }
      .index-body li { padding: 3px 0; }
      .index-body a { color: var(--link); text-decoration: none; font-size: 14px; }
      .index-body a:hover { text-decoration: underline; }
      </style>
      </head>
      <body>
      <div class="index-body">
      <h1>\(projectName)</h1>
      \(listHTML)
      </div>
      </body>
      </html>
      """
  }
  ```

- [ ] **Step 2: Add `copyReferencedImages` method**

  Add inside `StaticSiteExporter`:

  ```swift
  /// Scans markdown content for relative image references and copies those files
  /// from the project directory into the output directory, preserving relative paths.
  ///
  /// Only copies images with relative paths (not http:// or https:// URLs).
  func copyReferencedImages(
      from markdown: String,
      sourceRelativePath: String,
      projectPath: String,
      outputURL: URL
  ) {
      // Match ![alt](path) — capture the path group
      let pattern = #"!\[[^\]]*\]\(([^)]+)\)"#
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
      let ns = markdown as NSString
      let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))

      let sourceDir = (sourceRelativePath as NSString).deletingLastPathComponent

      for match in matches {
          guard match.numberOfRanges >= 2 else { continue }
          let pathStr = ns.substring(with: match.range(at: 1))
              .trimmingCharacters(in: .whitespaces)

          // Skip absolute URLs
          guard !pathStr.hasPrefix("http://"), !pathStr.hasPrefix("https://"),
                !pathStr.hasPrefix("data:") else { continue }

          // Resolve the image's absolute path in the source project
          let imageAbsPath: String
          if pathStr.hasPrefix("/") {
              imageAbsPath = (projectPath as NSString).appendingPathComponent(pathStr)
          } else {
              let sourceDirAbs = (projectPath as NSString).appendingPathComponent(sourceDir)
              imageAbsPath = (sourceDirAbs as NSString).appendingPathComponent(pathStr)
          }

          let imageSourceURL = URL(fileURLWithPath: imageAbsPath)
          guard FileManager.default.fileExists(atPath: imageAbsPath) else { continue }

          // Compute destination: output/<sourceDir>/<imagePath>
          let destRelative = sourceDir.isEmpty
              ? pathStr
              : (sourceDir as NSString).appendingPathComponent(pathStr)
          let destURL = outputURL.appendingPathComponent(destRelative)

          do {
              try FileManager.default.createDirectory(
                  at: destURL.deletingLastPathComponent(),
                  withIntermediateDirectories: true
              )
              if !FileManager.default.fileExists(atPath: destURL.path) {
                  try FileManager.default.copyItem(at: imageSourceURL, to: destURL)
              }
          } catch {
              print("[StaticSiteExporter] Image copy failed: \(error)")
          }
      }
  }
  ```

- [ ] **Step 3: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Services/StaticSiteExporter.swift
  git commit -m "feat: add index.html generator and referenced image copying"
  ```

---

## Task 7: Implement the Main Export Loop

**Files:**
- Modify: `Sources/EzmdvApp/Services/StaticSiteExporter.swift`

This is the orchestrating method. It runs on a background thread and calls a progress callback on the main thread.

- [ ] **Step 1: Add `export` method**

  Add inside `StaticSiteExporter`:

  ```swift
  /// Run the full export for a project.
  ///
  /// - Parameters:
  ///   - project: the Project to export
  ///   - outputURL: the chosen output directory URL (must already exist or be creatable)
  ///   - onProgress: called on the **main thread** with (completedCount, currentFileName)
  ///   - onComplete: called on the **main thread** with an optional error message
  func export(
      project: Project,
      outputURL: URL,
      onProgress: @escaping (Int, String) -> Void,
      onComplete: @escaping (String?) -> Void
  ) {
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
          guard let self else { return }
          let errorMessage = self.runExport(project: project, outputURL: outputURL, onProgress: onProgress)
          DispatchQueue.main.async { onComplete(errorMessage) }
      }
  }

  /// The synchronous export logic (runs on background thread).
  /// Returns nil on success, or an error string on failure.
  private func runExport(
      project: Project,
      outputURL: URL,
      onProgress: @escaping (Int, String) -> Void
  ) -> String? {
      // 1. Collect all markdown files
      let allFiles = MarkdownFile.flatten(project.files)
      let mdFiles = allFiles.filter { !$0.isDirectory && $0.name.hasSuffix(".md") }
      guard !mdFiles.isEmpty else { return "No markdown files found in project." }

      // 2. Create output directory
      do {
          try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
      } catch {
          return "Could not create output directory: \(error.localizedDescription)"
      }

      // 3. Set up JS engine
      guard let ctx = makeJSContext() else {
          return "Could not load marked.min.js from app bundle. Please report this bug."
      }

      // 4. Extract CSS once
      let css = extractBundleCSS()

      // 5. Process each file
      for (index, file) in mdFiles.enumerated() {
          if cancelled { return "Export cancelled." }

          DispatchQueue.main.async { onProgress(index, file.name) }

          // Read source markdown
          guard let markdown = try? String(contentsOfFile: file.path, encoding: .utf8) else {
              print("[StaticSiteExporter] Could not read \(file.path), skipping.")
              continue
          }

          // Rewrite wiki-links
          let rewritten = rewriteWikiLinks(
              in: markdown,
              sourceRelativePath: file.relativePath,
              allFiles: allFiles
          )

          // Render to HTML via JSContext
          guard let htmlBody = renderMarkdown(rewritten, context: ctx) else {
              print("[StaticSiteExporter] JS render failed for \(file.name), skipping.")
              continue
          }

          // Generate full page
          let title = (file.name as NSString).deletingPathExtension
          let pageHTML = generatePageHTML(
              title: title,
              htmlBody: htmlBody,
              allFiles: mdFiles,
              sourceRelativePath: file.relativePath,
              css: css
          )

          // Write output HTML file
          let outputRelative = Self.htmlRelativePath(from: file.relativePath)
          let outputFile = outputURL.appendingPathComponent(outputRelative)
          do {
              try FileManager.default.createDirectory(
                  at: outputFile.deletingLastPathComponent(),
                  withIntermediateDirectories: true
              )
              try pageHTML.write(to: outputFile, atomically: true, encoding: .utf8)
          } catch {
              print("[StaticSiteExporter] Write failed for \(outputRelative): \(error)")
          }

          // Copy referenced images
          copyReferencedImages(
              from: markdown,
              sourceRelativePath: file.relativePath,
              projectPath: project.path,
              outputURL: outputURL
          )
      }

      // 6. Generate index.html
      if !cancelled {
          let indexHTML = generateIndexHTML(
              projectName: project.name,
              allFiles: mdFiles,
              css: css
          )
          let indexFile = outputURL.appendingPathComponent("index.html")
          try? indexHTML.write(to: indexFile, atomically: true, encoding: .utf8)
          DispatchQueue.main.async { onProgress(mdFiles.count, "index.html") }
      }

      return nil  // success
  }
  ```

- [ ] **Step 2: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Services/StaticSiteExporter.swift
  git commit -m "feat: implement main export loop in StaticSiteExporter"
  ```

---

## Task 8: Wire the Export Flow in ContentView

**Files:**
- Modify: `Sources/EzmdvApp/Views/ContentView.swift`

ContentView listens for the `.exportVaultSite` notification, shows an `NSOpenPanel` to pick the output folder, then presents `SiteExportProgressView` as a sheet while export runs.

- [ ] **Step 1: Read ContentView to understand its current structure**

  ```bash
  cat -n /Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Views/ContentView.swift
  ```

  Note where the existing `.onReceive` modifiers live (they receive `.exportHTML`, `.printCurrentFile`, etc.) so you can add the new one in the same style.

- [ ] **Step 2: Add export state properties and the notification handler**

  Add the following `@State` properties near the top of `ContentView` (with the other state properties):

  ```swift
  @State private var isExportingSite = false
  @State private var exportTotalFiles = 0
  @State private var exportCompletedFiles = 0
  @State private var exportCurrentFileName = ""
  @State private var exportError: String? = nil
  @State private var activeExporter: StaticSiteExporter? = nil
  ```

- [ ] **Step 3: Add the `.onReceive` handler and `.sheet` modifier**

  In `ContentView.body`, add after the existing `.onReceive` modifiers:

  ```swift
  .onReceive(NotificationCenter.default.publisher(for: .exportVaultSite)) { _ in
      handleExportVaultSite()
  }
  .sheet(isPresented: $isExportingSite) {
      SiteExportProgressView(
          totalFiles: exportTotalFiles,
          completedFiles: $exportCompletedFiles,
          currentFileName: $exportCurrentFileName,
          onCancel: {
              activeExporter?.cancel()
              isExportingSite = false
          }
      )
  }
  ```

- [ ] **Step 4: Add `handleExportVaultSite` as a private method on ContentView**

  ```swift
  private func handleExportVaultSite() {
      // Require at least one project
      guard let project = appState.projects.first else {
          let alert = NSAlert()
          alert.messageText = "No Project Open"
          alert.informativeText = "Open a folder first, then export it as a site."
          alert.runModal()
          return
      }

      // If multiple projects, pick the focused one — fall back to first
      let targetProject: Project
      if let focusedTab = appState.primaryTab,
         let p = appState.projects.first(where: { $0.id == focusedTab.projectId }) {
          targetProject = p
      } else {
          targetProject = project
      }

      // Folder picker
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = true
      panel.message = "Choose an output folder for the static site"
      panel.prompt = "Export Here"

      guard panel.runModal() == .OK, let outputURL = panel.url else { return }

      // Reload files if needed
      if targetProject.files == nil {
          appState.loadProjectFiles(targetProject)
      }

      // Set up progress state
      let total = MarkdownFile.flatten(targetProject.files).filter { !$0.isDirectory && $0.name.hasSuffix(".md") }.count
      exportTotalFiles = total
      exportCompletedFiles = 0
      exportCurrentFileName = ""
      exportError = nil

      // Start export
      let exporter = StaticSiteExporter()
      activeExporter = exporter
      isExportingSite = true

      exporter.export(
          project: targetProject,
          outputURL: outputURL,
          onProgress: { completed, fileName in
              exportCompletedFiles = completed
              exportCurrentFileName = fileName
          },
          onComplete: { errorMessage in
              isExportingSite = false
              activeExporter = nil
              if let errorMessage = errorMessage {
                  let alert = NSAlert()
                  alert.messageText = "Export Failed"
                  alert.informativeText = errorMessage
                  alert.runModal()
              } else {
                  NSWorkspace.shared.activateFileViewerSelecting([outputURL])
              }
          }
      )
  }
  ```

- [ ] **Step 5: Build to verify compilation**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -20
  ```

  Expected: `Build complete!`

- [ ] **Step 6: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/ContentView.swift
  git commit -m "feat: wire Export Vault as Site flow in ContentView"
  ```

---

## Task 9: Manual Verification

No test target exists in this project, so verification is done by running the app.

- [ ] **Step 1: Build and run**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -5
  ```

  Then open the built app or run from Xcode.

- [ ] **Step 2: Open a project with multiple `.md` files**

  Use File → Open Folder… to open any vault that has at least 5 files, some in subdirectories.

- [ ] **Step 3: Trigger the export**

  File menu → "Export Vault as Site…"

  Expected:
  - An `NSOpenPanel` appears prompting you to choose an output folder
  - After choosing, a progress sheet appears showing file count advancing
  - Sheet dismisses when done
  - Finder opens showing the output folder

- [ ] **Step 4: Inspect the output folder**

  Check that:
  - `index.html` exists at the root
  - Each `.md` file has a corresponding `.html` file at the same relative path
  - Opening `index.html` in Safari shows a two-column layout with a sidebar of all file links
  - Clicking a sidebar link opens the correct file page
  - The content page renders with correct markdown styling (headings, code blocks, tables)

- [ ] **Step 5: Test wiki-link resolution**

  If the vault has `[[wiki-links]]`:
  - Resolved links should be clickable `<a>` tags that navigate to the correct page
  - Unresolved links should appear as plain `<span class="wiki-link unresolved">` text (visible but not linked)

- [ ] **Step 6: Test image copying**

  If any note references a local image `![](./images/photo.png)`:
  - The image file should appear in the output at the same relative location
  - The image should display in the exported page

- [ ] **Step 7: Test cancellation**

  Trigger the export again on a large vault. Click "Cancel" during progress.
  - The sheet should dismiss
  - No Finder window should open
  - The partially-generated output folder will exist but may be incomplete (this is acceptable)

- [ ] **Step 8: Test with zero markdown files**

  Create a new empty folder, open it as a project, then try to export.
  - Expected: an alert "No markdown files found in project."

---

## Task 10: Final Integration Commit

- [ ] **Step 1: Verify clean build one last time**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1 | tail -5
  ```

  Expected: `Build complete!` with zero warnings or errors.

- [ ] **Step 2: Tag the feature complete**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git log --oneline -10
  ```

  Review that all task commits are present, then optionally create a summary commit if any loose files remain uncommitted:

  ```bash
  git status
  # If clean, nothing to do. If there are stray changes:
  git add -p
  git commit -m "chore: finalize static site export implementation"
  ```

---

## Troubleshooting Reference

### `marked.min.js` not found at runtime

Symptom: export fails with "Could not load marked.min.js from app bundle."

Fix: Verify that `Package.swift` includes the Resources directory. The target should have:

```swift
.executableTarget(
    name: "EzmdvApp",
    resources: [
        .copy("Resources")   // or .process("Resources")
    ]
)
```

Run `swift build` and check that `marked.min.js` appears under `.build/debug/EzmdvApp_EzmdvApp.bundle/Contents/Resources/` (the exact path varies by Swift build system version).

### JS exception in JSContext

Symptom: `[StaticSiteExporter] JS exception: ...` in console, pages have empty body.

Fix: The `marked.min.js` version and the `marked.setOptions` call must be compatible. Verify the downloaded file is valid:

```bash
node -e "const m = require('./Sources/EzmdvApp/Resources/marked.min.js'); console.log(typeof m.parse)"
```

Expected output: `function`

### Wiki-links produce wrong relative paths

Symptom: Links in sidebar or content point to 404 pages.

Fix: Add a debug print in `relativePath(from:to:)` to inspect `fromParts` and `toParts`. The most common issue is a trailing slash on `sourceDir` — the code uses `NSString.deletingLastPathComponent` which never produces a trailing slash, so this should be safe.

### Progress sheet freezes (spinning beach ball)

Symptom: The sheet appears but never updates.

Fix: Confirm that `onProgress` is called on the main thread. In `runExport`, the `DispatchQueue.main.async { onProgress(...) }` call must be inside the loop, not outside it. If JSContext evaluation takes longer than expected (e.g., for a 500-file vault), this is expected — the UI will update between files.
