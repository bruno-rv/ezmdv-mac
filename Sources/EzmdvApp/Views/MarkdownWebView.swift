import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let filePath: String
    var zoom: Double = 1.0
    var editorMode: String = "view"  // "view" | "edit" | "preview"
    var autoScrollActive: Bool = false
    var autoScrollInterval: Double = 5
    var autoScrollPercent: Double = 10
    var onHeadingsExtracted: (([TOCHeading]) -> Void)? = nil
    var onContentChanged: ((String) -> Void)? = nil
    var onAutoScrollStopped: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState

    func makeNSView(context: Context) -> WKWebView {
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "tocHandler")
        userController.add(context.coordinator, name: "editHandler")
        userController.add(context.coordinator, name: "editorHandler")
        userController.add(context.coordinator, name: "readyHandler")
        userController.add(context.coordinator, name: "autoScrollHandler")

        // Inject editor.js via WKUserScript (avoids </script> breakage from inlining)
        if let editorURL = Bundle.module.url(forResource: "editor", withExtension: "js"),
           let editorJS = try? String(contentsOf: editorURL, encoding: .utf8) {
            let script = WKUserScript(source: editorJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            userController.addUserScript(script)
        }

        let config = WKWebViewConfiguration()
        config.userContentController = userController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        if let htmlURL = Bundle.module.url(forResource: "markdown", withExtension: "html"),
           let html = try? String(contentsOf: htmlURL, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: htmlURL.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        context.coordinator.appState = appState
        context.coordinator.pendingContent = loadMarkdown()
        context.coordinator.pendingZoom = zoom
        context.coordinator.pendingMode = editorMode
        context.coordinator.onHeadingsExtracted = onHeadingsExtracted
        context.coordinator.onContentChanged = onContentChanged
        context.coordinator.onAutoScrollStopped = onAutoScrollStopped

        // Find the project for this file to pass file list for wiki-link resolution
        if let tab = appState.tabs.first(where: { $0.filePath == filePath }),
           let project = appState.projects.first(where: { $0.id == tab.projectId }) {
            context.coordinator.projectId = project.id
            context.coordinator.pendingProjectFiles = flattenFiles(project.files)
        }

        // Listen for scroll-to-heading notifications
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollToHeading(_:)),
            name: .scrollToHeading,
            object: nil
        )

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let content = loadMarkdown()
        context.coordinator.onHeadingsExtracted = onHeadingsExtracted
        context.coordinator.onContentChanged = onContentChanged
        context.coordinator.onAutoScrollStopped = onAutoScrollStopped
        context.coordinator.filePath = filePath

        if context.coordinator.jsReady {
            // Apply zoom
            webView.evaluateJavaScript("document.body.style.zoom = '\(zoom)'", completionHandler: nil)

            // Apply mode change
            if context.coordinator.lastMode != editorMode {
                context.coordinator.lastMode = editorMode
                // Stop auto-scroll when switching to edit mode
                if editorMode == "edit" {
                    webView.evaluateJavaScript("stopAutoScroll()", completionHandler: nil)
                }
                webView.evaluateJavaScript("setMode('\(editorMode)')", completionHandler: nil)
            }

            // Apply auto-scroll config and state
            webView.evaluateJavaScript(
                "setAutoScrollConfig(\(autoScrollInterval), \(autoScrollPercent))",
                completionHandler: nil
            )
            if context.coordinator.lastAutoScrollActive != autoScrollActive {
                context.coordinator.lastAutoScrollActive = autoScrollActive
                if autoScrollActive {
                    webView.evaluateJavaScript("toggleAutoScroll()", completionHandler: nil)
                } else {
                    webView.evaluateJavaScript("stopAutoScroll()", completionHandler: nil)
                }
            }

            // Inject content (only in view mode — in edit/preview, editor owns content)
            if editorMode == "view" {
                context.coordinator.injectMarkdown(content)
            }
        } else {
            context.coordinator.pendingContent = content
            context.coordinator.pendingZoom = zoom
            context.coordinator.pendingMode = editorMode
        }
    }

    private func flattenFiles(_ files: [MarkdownFile]?) -> [[String: String]] {
        guard let files = files else { return [] }
        var result: [[String: String]] = []
        for file in files {
            if file.isDirectory {
                result.append(contentsOf: flattenFiles(file.children))
            } else {
                result.append([
                    "name": file.name,
                    "path": file.path,
                    "relativePath": file.relativePath
                ])
            }
        }
        return result
    }

    private func loadMarkdown() -> String {
        if let cached = appState.contentCache[filePath] { return cached }
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            DispatchQueue.main.async { appState.contentCache[filePath] = content }
            return content
        }
        return "# Error\nCould not read file."
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        weak var appState: AppState?
        var filePath: String = ""
        var projectId: UUID?
        var pendingContent: String?
        var pendingZoom: Double?
        var pendingMode: String?
        var pendingProjectFiles: [[String: String]]?
        var lastInjected: String?
        var lastMode: String = "view"
        var lastAutoScrollActive: Bool = false
        var jsReady = false
        var onHeadingsExtracted: (([TOCHeading]) -> Void)?
        var onContentChanged: ((String) -> Void)?
        var onAutoScrollStopped: (() -> Void)?

        private func onJSReady() {
            jsReady = true
            guard let webView = webView else { return }

            // Apply buffered zoom
            if let zoom = pendingZoom {
                webView.evaluateJavaScript("document.body.style.zoom = '\(zoom)'", completionHandler: nil)
                pendingZoom = nil
            }

            // Apply buffered content
            if let content = pendingContent {
                pendingContent = nil
                injectMarkdown(content)
            }

            // Apply buffered project files (for wiki-link resolution)
            if let files = pendingProjectFiles {
                injectProjectFiles(files)
                pendingProjectFiles = nil
            }

            // Apply buffered mode
            if let mode = pendingMode {
                lastMode = mode
                webView.evaluateJavaScript("setMode('\(mode)')", completionHandler: nil)
                pendingMode = nil
            }
        }

        func injectProjectFiles(_ files: [[String: String]]) {
            guard jsReady, let webView = webView else {
                pendingProjectFiles = files
                return
            }
            if let data = try? JSONSerialization.data(withJSONObject: files),
               let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("setProjectFiles(\(json))", completionHandler: nil)
            }
        }

        func injectMarkdown(_ content: String) {
            guard jsReady, let webView = webView else {
                pendingContent = content
                return
            }
            if content == lastInjected { return }
            lastInjected = content

            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")

            webView.evaluateJavaScript("renderMarkdown(`\(escaped)`);") { _, error in
                if let error = error { print("JS render error: \(error)") }
            }
        }

        // Handle messages from JS
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "readyHandler" {
                DispatchQueue.main.async { self.onJSReady() }
                return
            }

            if message.name == "tocHandler",
               let items = message.body as? [[String: Any]] {
                let headings = items.compactMap { item -> TOCHeading? in
                    guard let level = item["level"] as? Int,
                          let text = item["text"] as? String,
                          let anchor = item["anchor"] as? String
                    else { return nil }
                    return TOCHeading(level: level, text: text, anchor: anchor)
                }
                DispatchQueue.main.async { self.onHeadingsExtracted?(headings) }
            }

            // Auto-scroll stopped (reached bottom)
            if message.name == "autoScrollHandler",
               let info = message.body as? [String: Any],
               let active = info["active"] as? Bool, !active {
                DispatchQueue.main.async { self.onAutoScrollStopped?() }
            }

            // Content from editor (both legacy editHandler and new editorHandler)
            if message.name == "editHandler" || message.name == "editorHandler",
               let content = message.body as? String {
                DispatchQueue.main.async {
                    self.lastInjected = content  // prevent re-injection loop
                    self.onContentChanged?(content)
                }
            }
        }

        @objc func handleScrollToHeading(_ notification: Notification) {
            guard let anchor = notification.userInfo?["anchor"] as? String,
                  let targetFile = notification.userInfo?["filePath"] as? String,
                  targetFile == filePath
            else { return }
            webView?.evaluateJavaScript("scrollToHeading('\(anchor)')", completionHandler: nil)
        }

        // Handle link clicks: wiki-links navigate in-app, external links open in browser
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "wiki" {
                // Wiki-link: resolve target and open file
                let target = url.host.flatMap { $0.removingPercentEncoding } ?? ""
                resolveAndOpenWikiLink(target: target)
                decisionHandler(.cancel)
            } else if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        private func resolveAndOpenWikiLink(target: String) {
            guard let appState = appState, let projectId = projectId else { return }
            guard let project = appState.projects.first(where: { $0.id == projectId }),
                  let files = project.files else { return }

            // Split target#heading
            let parts = target.split(separator: "#", maxSplits: 1)
            let fileTarget = String(parts[0])
            let headingAnchor = parts.count > 1 ? String(parts[1]) : nil

            // Flatten and search
            let flat = flattenAllFiles(files)
            let targetLower = fileTarget.lowercased()
            let withExt = targetLower.hasSuffix(".md") ? targetLower : targetLower + ".md"

            // 1. Exact relative path match
            var match = flat.first { $0.relativePath.lowercased() == withExt }

            // 2. Basename match
            if match == nil {
                let basename = (withExt as NSString).lastPathComponent
                let candidates = flat.filter { $0.name.lowercased() == basename }
                if candidates.count == 1 { match = candidates[0] }
            }

            // 3. Basename without extension
            if match == nil {
                let candidates = flat.filter {
                    let nameNoExt = ($0.name as NSString).deletingPathExtension.lowercased()
                    return nameNoExt == targetLower
                }
                if candidates.count == 1 { match = candidates[0] }
            }

            if let match = match {
                DispatchQueue.main.async {
                    appState.openFile(projectId: projectId, filePath: match.path)
                    // If heading anchor, scroll after a short delay
                    if let anchor = headingAnchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(
                                name: .scrollToHeading,
                                object: nil,
                                userInfo: ["anchor": anchor, "filePath": match.path]
                            )
                        }
                    }
                }
            }
        }

        private func flattenAllFiles(_ files: [MarkdownFile]) -> [MarkdownFile] {
            var result: [MarkdownFile] = []
            for file in files {
                if file.isDirectory {
                    if let children = file.children {
                        result.append(contentsOf: flattenAllFiles(children))
                    }
                } else {
                    result.append(file)
                }
            }
            return result
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
