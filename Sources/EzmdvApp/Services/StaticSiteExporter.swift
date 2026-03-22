import Foundation
import JavaScriptCore

/// Exports a project vault as a self-contained static HTML website.
final class StaticSiteExporter {

    // MARK: - Cancellation

    private var cancelled = false

    func cancel() { cancelled = true }

    // MARK: - JS Engine

    /// Load marked.min.js into a fresh JSContext. Reuse across all files in one run.
    private func makeJSContext() -> JSContext? {
        guard let url = Bundle.module.url(forResource: "marked.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, exception in
            print("[StaticSiteExporter] JS exception: \(exception?.toString() ?? "unknown")")
        }
        ctx.evaluateScript(source)
        ctx.evaluateScript("marked.setOptions({ gfm: true, breaks: false });")
        return ctx
    }

    /// Convert markdown to an HTML fragment via JSContext.
    func renderMarkdown(_ markdown: String, context: JSContext) -> String? {
        let escaped = JSEscaping.escapeForTemplateLiteral(markdown)
        let result = context.evaluateScript("marked.parse(`\(escaped)`)")
        return result?.toString()
    }

    // MARK: - Path utilities

    /// "Notes/My File.md" → "Notes/My File.html"
    static func htmlRelativePath(from mdRelativePath: String) -> String {
        (mdRelativePath as NSString).deletingPathExtension + ".html"
    }

    /// Compute a relative path from a source directory to a target file, both relative to project root.
    /// e.g. relativePath(from: "Notes/Sub", to: "Archive/Other.html") → "../../Archive/Other.html"
    static func relativePath(from sourceDir: String, to targetPath: String) -> String {
        let fromParts = sourceDir.isEmpty ? [] : sourceDir.split(separator: "/").map(String.init)
        let toParts = targetPath.split(separator: "/").map(String.init)

        var commonLen = 0
        while commonLen < fromParts.count && commonLen < toParts.count
              && fromParts[commonLen] == toParts[commonLen] {
            commonLen += 1
        }

        let ups = Array(repeating: "..", count: fromParts.count - commonLen)
        let downs = Array(toParts[commonLen...])
        let components = ups + downs
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    // MARK: - Wiki-link rewriting

    /// Rewrites [[wiki-links]] to relative <a href> tags before markdown parsing.
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
            let beforeRange = NSRange(location: lastEnd, length: link.fullMatch.location - lastEnd)
            result += nsMarkdown.substring(with: beforeRange)

            let inner = link.inner
            let pipeParts = inner.split(separator: "|", maxSplits: 1)
            let targetAndAnchor = String(pipeParts[0]).trimmingCharacters(in: .whitespaces)
            let displayText = pipeParts.count > 1
                ? String(pipeParts[1]).trimmingCharacters(in: .whitespaces)
                : targetAndAnchor

            let resolved = WikiLinkResolver.resolve(target: targetAndAnchor, in: allFiles)
            let anchor = WikiLinkResolver.headingAnchor(from: targetAndAnchor)

            if let resolved = resolved {
                let sourceDir = (sourceRelativePath as NSString).deletingLastPathComponent
                let targetHTML = Self.htmlRelativePath(from: resolved.relativePath)
                let relativeHref = Self.relativePath(from: sourceDir, to: targetHTML)
                let hrefWithAnchor = anchor.map { relativeHref + "#\($0)" } ?? relativeHref
                result += "<a href=\"\(hrefWithAnchor)\">\(displayText)</a>"
            } else {
                result += "<span class=\"wiki-link unresolved\">\(displayText)</span>"
            }

            lastEnd = link.fullMatch.location + link.fullMatch.length
        }

        result += nsMarkdown.substring(from: lastEnd)
        return result
    }

    // MARK: - CSS extraction

    private func extractBundleCSS() -> String {
        guard let url = Bundle.module.url(forResource: "markdown", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            return "body { font-family: -apple-system, sans-serif; max-width: 820px; margin: 0 auto; padding: 2rem; }"
        }
        if let styleStart = html.range(of: "<style>"),
           let styleEnd = html.range(of: "</style>") {
            let css = String(html[styleStart.upperBound..<styleEnd.lowerBound])
            return stripEditorLayoutCSS(css)
        }
        return ""
    }

    private func stripEditorLayoutCSS(_ css: String) -> String {
        let editorSelectors = [
            "#view-container", "#edit-container", "#preview-container",
            "#editor-pane", "#render-pane", ".slide-content",
        ]
        let lines = css.components(separatedBy: "\n")
        var output: [String] = []
        var skipDepth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if editorSelectors.contains(where: { trimmed.hasPrefix($0) }) && trimmed.hasSuffix("{") {
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

    // MARK: - Per-file HTML generation

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

    // MARK: - Index page

    func generateIndexHTML(projectName: String, allFiles: [MarkdownFile], css: String) -> String {
        var groupMap: [String: [MarkdownFile]] = [:]
        for file in allFiles.filter({ !$0.isDirectory }).sorted(by: { $0.relativePath < $1.relativePath }) {
            let parts = file.relativePath.split(separator: "/")
            let folder = parts.count > 1 ? String(parts[0]) : ""
            groupMap[folder, default: []].append(file)
        }
        let sortedKeys = groupMap.keys.sorted { a, b in
            if a.isEmpty { return true }
            if b.isEmpty { return false }
            return a < b
        }

        var listHTML = ""
        for key in sortedKeys {
            if !key.isEmpty { listHTML += "<h2>\(key)</h2>\n" }
            listHTML += "<ul>\n"
            for file in groupMap[key]! {
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

    // MARK: - Image copying

    func copyReferencedImages(
        from markdown: String,
        sourceRelativePath: String,
        projectPath: String,
        outputURL: URL
    ) {
        let pattern = #"!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        let sourceDir = (sourceRelativePath as NSString).deletingLastPathComponent

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let pathStr = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !pathStr.hasPrefix("http://"), !pathStr.hasPrefix("https://"),
                  !pathStr.hasPrefix("data:") else { continue }

            let imageAbsPath: String
            if pathStr.hasPrefix("/") {
                imageAbsPath = (projectPath as NSString).appendingPathComponent(pathStr)
            } else {
                let sourceDirAbs = (projectPath as NSString).appendingPathComponent(sourceDir)
                imageAbsPath = (sourceDirAbs as NSString).appendingPathComponent(pathStr)
            }

            guard FileManager.default.fileExists(atPath: imageAbsPath) else { continue }
            let destRelative = sourceDir.isEmpty ? pathStr : (sourceDir as NSString).appendingPathComponent(pathStr)
            let destURL = outputURL.appendingPathComponent(destRelative)

            do {
                try FileManager.default.createDirectory(
                    at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.copyItem(
                        at: URL(fileURLWithPath: imageAbsPath), to: destURL)
                }
            } catch {
                print("[StaticSiteExporter] Image copy failed: \(error)")
            }
        }
    }

    // MARK: - Main export loop

    func export(
        project: Project,
        outputURL: URL,
        onProgress: @escaping (Int, String) -> Void,
        onComplete: @escaping (String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let error = self.runExport(project: project, outputURL: outputURL, onProgress: onProgress)
            DispatchQueue.main.async { onComplete(error) }
        }
    }

    private func runExport(
        project: Project,
        outputURL: URL,
        onProgress: @escaping (Int, String) -> Void
    ) -> String? {
        let allFiles = MarkdownFile.flatten(project.files)
        let mdFiles = allFiles.filter { !$0.isDirectory && $0.name.hasSuffix(".md") }
        guard !mdFiles.isEmpty else { return "No markdown files found in project." }

        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            return "Could not create output directory: \(error.localizedDescription)"
        }

        guard let ctx = makeJSContext() else {
            return "Could not load marked.min.js from app bundle."
        }

        let css = extractBundleCSS()

        for (index, file) in mdFiles.enumerated() {
            if cancelled { return "Export cancelled." }
            DispatchQueue.main.async { onProgress(index, file.name) }

            guard let markdown = try? String(contentsOfFile: file.path, encoding: .utf8) else {
                print("[StaticSiteExporter] Could not read \(file.path), skipping.")
                continue
            }

            let rewritten = rewriteWikiLinks(in: markdown, sourceRelativePath: file.relativePath, allFiles: allFiles)
            guard let htmlBody = renderMarkdown(rewritten, context: ctx) else {
                print("[StaticSiteExporter] JS render failed for \(file.name), skipping.")
                continue
            }

            let title = (file.name as NSString).deletingPathExtension
            let pageHTML = generatePageHTML(
                title: title, htmlBody: htmlBody,
                allFiles: mdFiles, sourceRelativePath: file.relativePath, css: css
            )

            let outputRelative = Self.htmlRelativePath(from: file.relativePath)
            let outputFile = outputURL.appendingPathComponent(outputRelative)
            do {
                try FileManager.default.createDirectory(
                    at: outputFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pageHTML.write(to: outputFile, atomically: true, encoding: .utf8)
            } catch {
                print("[StaticSiteExporter] Write failed for \(outputRelative): \(error)")
            }

            copyReferencedImages(
                from: markdown, sourceRelativePath: file.relativePath,
                projectPath: project.path, outputURL: outputURL)
        }

        if !cancelled {
            let indexHTML = generateIndexHTML(projectName: project.name, allFiles: mdFiles, css: css)
            let indexFile = outputURL.appendingPathComponent("index.html")
            try? indexHTML.write(to: indexFile, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { onProgress(mdFiles.count, "index.html") }
        }

        return nil
    }
}
