import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let filePath: String
    var zoom: Double = 1.0
    var editorMode: String = "view"  // "view" | "edit" | "preview"
    var autoScrollActive: Bool = false
    var autoScrollInterval: Double = 5
    var autoScrollPercent: Double = 10
    var printTrigger: Int = 0
    var presentationTrigger: Int = 0
    var findQuery: String = ""
    var findTrigger: Int = 0
    var findDirection: Int = 1
    var replaceTrigger: Int = 0
    var replaceAllTrigger: Int = 0
    var replaceText: String = ""
    var findBarVisible: Bool = false
    var onHeadingsExtracted: (([TOCHeading]) -> Void)? = nil
    var onContentChanged: ((String) -> Void)? = nil
    var onAutoScrollStopped: (() -> Void)? = nil
    var onPresentationChanged: ((Bool) -> Void)? = nil
    var onFindResult: ((Int, Int) -> Void)? = nil
    var onFindClose: (() -> Void)? = nil
    @EnvironmentObject var appState: AppState

    func makeNSView(context: Context) -> WKWebView {
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "tocHandler")
        userController.add(context.coordinator, name: "editHandler")
        userController.add(context.coordinator, name: "editorHandler")
        userController.add(context.coordinator, name: "readyHandler")
        userController.add(context.coordinator, name: "autoScrollHandler")
        userController.add(context.coordinator, name: "presentationHandler")
        userController.add(context.coordinator, name: "findHandler")

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
        context.coordinator.onPresentationChanged = onPresentationChanged
        context.coordinator.onFindResult = onFindResult
        context.coordinator.onFindClose = onFindClose

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
        context.coordinator.onPresentationChanged = onPresentationChanged
        context.coordinator.onFindResult = onFindResult
        context.coordinator.onFindClose = onFindClose
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

            // Print trigger
            if context.coordinator.lastPrintTrigger != printTrigger {
                context.coordinator.lastPrintTrigger = printTrigger
                let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
                printInfo.topMargin = 36; printInfo.bottomMargin = 36
                printInfo.leftMargin = 36; printInfo.rightMargin = 36
                let op = webView.printOperation(with: printInfo)
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                op.run()
            }

            // Presentation trigger
            if context.coordinator.lastPresentationTrigger != presentationTrigger {
                context.coordinator.lastPresentationTrigger = presentationTrigger
                webView.evaluateJavaScript("enterPresentation()", completionHandler: nil)
            }

            // Find trigger
            if context.coordinator.lastFindTrigger != findTrigger {
                context.coordinator.lastFindTrigger = findTrigger
                let escapedQuery = JSEscaping.escapeForStringLiteral(findQuery)
                let isNewQuery = context.coordinator.lastFindQuery != findQuery
                context.coordinator.lastFindQuery = findQuery

                if editorMode == "view" {
                    if isNewQuery || findTrigger == 1 {
                        let dir = findDirection >= 0 ? 1 : -1
                        webView.evaluateJavaScript(
                            "findInView(\"\(escapedQuery)\", \(dir))", completionHandler: nil)
                    } else {
                        if findDirection >= 0 {
                            webView.evaluateJavaScript("findNextInView()", completionHandler: nil)
                        } else {
                            webView.evaluateJavaScript("findPrevInView()", completionHandler: nil)
                        }
                    }
                } else {
                    if isNewQuery || findTrigger == 1 {
                        let dir = findDirection >= 0 ? 1 : -1
                        webView.evaluateJavaScript(
                            "editorFindOpen(\"\(escapedQuery)\", \(dir))",
                            completionHandler: nil)
                    } else {
                        if findDirection >= 0 {
                            webView.evaluateJavaScript("editorFindNext()", completionHandler: nil)
                        } else {
                            webView.evaluateJavaScript("editorFindPrev()", completionHandler: nil)
                        }
                    }
                }
            }

            // Replace trigger (edit mode only)
            if context.coordinator.lastReplaceTrigger != replaceTrigger {
                context.coordinator.lastReplaceTrigger = replaceTrigger
                let escapedReplacement = JSEscaping.escapeForStringLiteral(replaceText)
                webView.evaluateJavaScript(
                    "editorReplaceCurrentMatch(\"\(escapedReplacement)\")",
                    completionHandler: nil)
            }

            // Replace All trigger (edit mode only)
            if context.coordinator.lastReplaceAllTrigger != replaceAllTrigger {
                context.coordinator.lastReplaceAllTrigger = replaceAllTrigger
                let escapedQuery = JSEscaping.escapeForStringLiteral(findQuery)
                let escapedReplacement = JSEscaping.escapeForStringLiteral(replaceText)
                webView.evaluateJavaScript(
                    "editorReplaceAllMatches(\"\(escapedQuery)\", \"\(escapedReplacement)\")",
                    completionHandler: nil)
            }

            // Clear find when bar closes
            if context.coordinator.lastFindBarVisible != findBarVisible {
                context.coordinator.lastFindBarVisible = findBarVisible
                if !findBarVisible {
                    if editorMode == "view" {
                        webView.evaluateJavaScript("clearFindHighlights()", completionHandler: nil)
                    } else {
                        webView.evaluateJavaScript("editorCloseSearch()", completionHandler: nil)
                    }
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
        MarkdownFile.flattenForJS(files)
    }

    private func loadMarkdown() -> String {
        if let cached = appState.contentCache.get(filePath) { return cached }
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            DispatchQueue.main.async { appState.contentCache.set(filePath, content) }
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
        var lastPrintTrigger: Int = 0
        var lastPresentationTrigger: Int = 0
        var lastFindTrigger: Int = 0
        var lastFindQuery: String = ""
        var lastReplaceTrigger: Int = 0
        var lastReplaceAllTrigger: Int = 0
        var lastFindBarVisible: Bool = false
        var jsReady = false
        private var transclusionDebounceTimer: Timer?
        var onHeadingsExtracted: (([TOCHeading]) -> Void)?
        var onContentChanged: ((String) -> Void)?
        var onAutoScrollStopped: (() -> Void)?
        var onPresentationChanged: ((Bool) -> Void)?
        var onFindResult: ((Int, Int) -> Void)?
        var onFindClose: (() -> Void)?

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
            guard jsReady, webView != nil else {
                pendingContent = content
                return
            }
            if content == lastInjected { return }
            lastInjected = content

            transclusionDebounceTimer?.invalidate()
            let escaped = JSEscaping.escapeForTemplateLiteral(content)

            transclusionDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                guard let self, let webView = self.webView else { return }

                // Resolve transclusions: ![[filename]] → content map (disk reads happen here)
                let transclusions = self.resolveTransclusions(in: content, depth: 0)
                if !transclusions.isEmpty,
                   let data = try? JSONSerialization.data(withJSONObject: transclusions),
                   let json = String(data: data, encoding: .utf8) {
                    webView.evaluateJavaScript("setTransclusions(\(json))", completionHandler: nil)
                }

                webView.evaluateJavaScript("renderMarkdown(`\(escaped)`);") { _, error in
                    if let error = error { print("JS render error: \(error)") }
                }
            }
        }

        private func resolveTransclusions(in content: String, depth: Int) -> [String: String] {
            guard depth < 3, let appState = appState, let projectId = projectId else { return [:] }
            guard let project = appState.projects.first(where: { $0.id == projectId }),
                  let files = project.files else { return [:] }

            let pattern = "!\\[\\[([^\\[\\]]+)\\]\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
            let ns = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))

            var result: [String: String] = [:]
            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let inner = ns.substring(with: match.range(at: 1))
                let target = inner.split(separator: "|").first.map(String.init) ?? inner
                let key = target.split(separator: "#").first
                    .map { String($0).trimmingCharacters(in: .whitespaces).lowercased()
                        .replacingOccurrences(of: ".md", with: "") } ?? ""
                if result[key] != nil { continue }
                if let resolved = WikiLinkResolver.resolve(target: target, in: files),
                   let fileContent = try? String(contentsOfFile: resolved.path, encoding: .utf8) {
                    result[key] = fileContent
                    // Recurse for nested transclusions
                    let nested = resolveTransclusions(in: fileContent, depth: depth + 1)
                    nested.forEach { result[$0] = $1 }
                }
            }
            return result
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

            if message.name == "presentationHandler",
               let info = message.body as? [String: Any],
               let active = info["active"] as? Bool {
                DispatchQueue.main.async { self.onPresentationChanged?(active) }
            }

            if message.name == "findHandler",
               let info = message.body as? [String: Any],
               let current = info["current"] as? Int,
               let total = info["total"] as? Int {
                DispatchQueue.main.async { self.onFindResult?(current, total) }
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

            guard let match = WikiLinkResolver.resolve(target: target, in: files) else { return }
            let headingAnchor = WikiLinkResolver.headingAnchor(from: target)

            DispatchQueue.main.async {
                appState.openFile(projectId: projectId, filePath: match.path)
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

        deinit {
            transclusionDebounceTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
