# Find & Replace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-pane Find & Replace bar that works in both view mode (browser text search via `window.find()`) and edit mode (CodeMirror's search extension), triggered by Cmd+F / Cmd+H, with next/previous match navigation and a match counter.

**Architecture:** The find bar is a SwiftUI overlay at the bottom of `MarkdownPaneView`, toggled via `NotificationCenter` (same pattern used by every other feature in this codebase). State lives in `MarkdownPaneView` (`@State`). The bar calls JS functions exposed in `markdown.html` — one set for view mode (`window.find()` loop with custom highlight span injection), a different set for edit mode (delegating to CodeMirror's `@codemirror/search` extension via the existing `EditorManager` API). Replace only operates in edit mode.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), WKWebView, vanilla JS in `markdown.html`, CodeMirror 6 (`@codemirror/search`) already bundled in `editor.js` (the bundle is minified; we add an exported API surface in `editor.js` that `markdown.html` can call as `editorManager.openSearch(query)` etc.).

---

## Codebase Orientation

Before starting: read these files to understand the patterns:

- `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/EzmdvApp.swift` — how menu commands + `Notification.Name` are declared
- `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Views/MarkdownPaneView.swift` — how `@State` and `.onReceive` are used
- `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Views/MarkdownWebView.swift` — how `evaluateJavaScript` is called and how `Coordinator` receives JS messages
- `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Resources/markdown.html` — how JS functions are exposed for Swift to call; how `window.webkit.messageHandlers.*` posts back to Swift
- `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Services/JSEscaping.swift` — always use `JSEscaping.escapeForStringLiteral()` when embedding user text in JS string literals

Build command (run from repo root): `swift build`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/EzmdvApp/Views/FindBar.swift` | **Create** | SwiftUI find/replace bar component. Pure UI: bindings for query, replace text, match count, replace-row-visible. Buttons post notifications; does not talk to JS directly. |
| `Sources/EzmdvApp/Views/MarkdownPaneView.swift` | **Modify** | Add `@State` for find bar visibility and query/replace strings. Add `.onReceive` for find/replace notifications. Wire `FindBar` overlay at bottom of VStack (above status bar divider). Pass `editorMode` down to `FindBar`. |
| `Sources/EzmdvApp/Views/MarkdownWebView.swift` | **Modify** | Add `findQuery`, `findTrigger`, `findDirection`, `replaceTrigger`, `replaceAllTrigger` props. In `updateNSView`, fire JS when these change. Add `findHandler` message handler in `Coordinator` to receive match count back from JS. |
| `Sources/EzmdvApp/EzmdvApp.swift` | **Modify** | Add `Notification.Name` declarations and menu items for Find, Find Next, Find Previous, Use Selection for Find, Find & Replace. |
| `Sources/EzmdvApp/Resources/markdown.html` | **Modify** | Add view-mode find JS functions: `findInView(query)`, `findNextInView()`, `findPrevInView()`. These use `window.find()` and custom `<mark class="find-highlight">` injection with scroll-into-view. Post match count back via `findHandler` message handler. |
| `Sources/EzmdvApp/Resources/editor.js` | **Modify** | Expose `editorManager.openSearch(query)`, `editorManager.findNext()`, `editorManager.findPrev()`, `editorManager.replaceCurrentMatch(replacement)`, `editorManager.replaceAllMatches(query, replacement)`, `editorManager.closeSearch()` using CodeMirror 6 `@codemirror/search` commands. |

---

## Task 1: Notification Names + Menu Items

**Goal:** Register all notification names and wire Cmd+F / Cmd+G / Cmd+Shift+G / Cmd+H in the app menu. No UI yet — just the plumbing that other tasks will react to.

**Files:**
- Modify: `Sources/EzmdvApp/EzmdvApp.swift`

**Context:** Every feature uses the `NotificationCenter` + `Notification.Name` pattern. New names go in the same `extension Notification.Name` block at the bottom of `EzmdvApp.swift`. Menu items go inside `.commands { }`.

- [ ] **Step 1: Read the existing `EzmdvApp.swift`**

  Read `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/EzmdvApp.swift` so you have the current source in context before editing.

- [ ] **Step 2: Add notification name declarations**

  In the `extension Notification.Name` block at the bottom of `EzmdvApp.swift`, add:

  ```swift
  static let openFind        = Notification.Name("openFind")
  static let openFindReplace = Notification.Name("openFindReplace")
  static let findNext        = Notification.Name("findNext")
  static let findPrevious    = Notification.Name("findPrevious")
  static let closeFind       = Notification.Name("closeFind")
  ```

- [ ] **Step 3: Add Find menu items in `.commands { }`**

  Insert a new `CommandMenu("Find")` after the existing `CommandMenu("Navigate")` block inside the `.commands { }` closure:

  ```swift
  CommandMenu("Find") {
      Button("Find...") {
          NotificationCenter.default.post(name: .openFind, object: nil)
      }
      .keyboardShortcut("f", modifiers: .command)

      Button("Find & Replace...") {
          NotificationCenter.default.post(name: .openFindReplace, object: nil)
      }
      .keyboardShortcut("h", modifiers: .command)

      Divider()

      Button("Find Next") {
          NotificationCenter.default.post(name: .findNext, object: nil)
      }
      .keyboardShortcut("g", modifiers: .command)

      Button("Find Previous") {
          NotificationCenter.default.post(name: .findPrevious, object: nil)
      }
      .keyboardShortcut("g", modifiers: [.command, .shift])
  }
  ```

  > **Note on Cmd+H conflict:** macOS reserves Cmd+H for "Hide Application" at the system level. In practice the SwiftUI `CommandMenu` item overrides it within the app window when a text field is not focused, but the system shortcut takes priority when the window loses focus. This is acceptable for a first implementation — a future iteration can remap to Cmd+Opt+F. Do not fight the system shortcut; just register it and move on.

- [ ] **Step 4: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  Expected: `Build complete!` with no errors. Run the app and confirm a "Find" menu appears with the three items.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/EzmdvApp.swift
  git commit -m "feat(find-replace): add notification names and Find menu items"
  ```

---

## Task 2: `FindBar` SwiftUI Component

**Goal:** Create the visual find bar — a two-row control strip that matches the app's toolbar aesthetic. Row 1 is always shown when the bar is visible (query field + navigation buttons + match label + close button). Row 2 (replace field + Replace/Replace All buttons) is shown when `showReplace` is `true`.

**Files:**
- Create: `Sources/EzmdvApp/Views/FindBar.swift`

**Context:** Look at `AutoScrollButton.swift` and `PaneToolbar.swift` for styling conventions (`.background(.bar)`, `Divider()` overlays, `.font(.system(size: 10))`). The find bar sits at the bottom of the pane, above the status bar — it does not use a sheet or popover.

- [ ] **Step 1: Create `FindBar.swift`**

  Create `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Views/FindBar.swift` with the following content:

  ```swift
  import SwiftUI

  struct FindBar: View {
      @Binding var query: String
      @Binding var replaceText: String
      @Binding var showReplace: Bool
      let editorMode: String        // "view" | "edit" | "preview"
      let matchCurrent: Int         // 1-based index of current match, 0 = none
      let matchTotal: Int           // total match count, -1 = not yet known
      let onFindNext: () -> Void
      let onFindPrev: () -> Void
      let onReplace: () -> Void
      let onReplaceAll: () -> Void
      let onClose: () -> Void

      @FocusState private var queryFocused: Bool

      var body: some View {
          VStack(spacing: 0) {
              Divider()
              // Row 1: Find
              HStack(spacing: 6) {
                  Image(systemName: "magnifyingglass")
                      .font(.system(size: 11))
                      .foregroundStyle(.secondary)

                  TextField("Find", text: $query)
                      .textFieldStyle(.plain)
                      .font(.system(size: 12))
                      .focused($queryFocused)
                      .onSubmit { onFindNext() }

                  matchLabel

                  Divider().frame(height: 14)

                  Button(action: onFindPrev) {
                      Image(systemName: "chevron.up")
                          .font(.system(size: 11))
                  }
                  .buttonStyle(.plain)
                  .help("Previous Match (⌘⇧G)")
                  .disabled(query.isEmpty)

                  Button(action: onFindNext) {
                      Image(systemName: "chevron.down")
                          .font(.system(size: 11))
                  }
                  .buttonStyle(.plain)
                  .help("Next Match (⌘G)")
                  .disabled(query.isEmpty)

                  Divider().frame(height: 14)

                  Button(action: onClose) {
                      Image(systemName: "xmark")
                          .font(.system(size: 10))
                  }
                  .buttonStyle(.plain)
                  .help("Close (Esc)")
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 5)

              // Row 2: Replace (only when showReplace && in edit mode)
              if showReplace && editorMode == "edit" {
                  Divider()
                  HStack(spacing: 6) {
                      Image(systemName: "pencil")
                          .font(.system(size: 11))
                          .foregroundStyle(.secondary)

                      TextField("Replace", text: $replaceText)
                          .textFieldStyle(.plain)
                          .font(.system(size: 12))
                          .onSubmit { onReplace() }

                      Divider().frame(height: 14)

                      Button("Replace", action: onReplace)
                          .buttonStyle(.plain)
                          .font(.system(size: 11))
                          .disabled(query.isEmpty)

                      Button("Replace All", action: onReplaceAll)
                          .buttonStyle(.plain)
                          .font(.system(size: 11))
                          .disabled(query.isEmpty)
                  }
                  .padding(.horizontal, 12)
                  .padding(.vertical, 5)
              }
          }
          .background(.bar)
          .onAppear { queryFocused = true }
      }

      @ViewBuilder
      private var matchLabel: some View {
          if !query.isEmpty {
              if matchTotal == 0 {
                  Text("No matches")
                      .font(.system(size: 10))
                      .foregroundStyle(.red)
              } else if matchTotal > 0 {
                  Text("\(matchCurrent) of \(matchTotal)")
                      .font(.system(size: 10))
                      .foregroundStyle(.secondary)
              }
              // matchTotal == -1: search pending, show nothing
          }
      }
  }
  ```

- [ ] **Step 2: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  Expected: `Build complete!` — `FindBar` is not yet wired up so no visual change yet.

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/FindBar.swift
  git commit -m "feat(find-replace): add FindBar SwiftUI component"
  ```

---

## Task 3: Wire `FindBar` into `MarkdownPaneView`

**Goal:** Show/hide `FindBar` in the correct position (bottom of pane, above status bar divider), react to all find notifications, and pass state down to `MarkdownWebView` (next task). The find bar must only react to notifications when **this pane is the focused pane**.

**Files:**
- Modify: `Sources/EzmdvApp/Views/MarkdownPaneView.swift`

**Context:** The existing pane uses `@State` for local UI state (`zoom`, `tocOpen`, `editorMode`, etc.) and `.onReceive` on the `MarkdownWebView` to handle notifications. The pattern here is the same: add `@State`, add `.onReceive`, add an overlay/view in the `VStack`.

The find bar sits **inside** `MarkdownPaneView`'s `VStack`, between the main content area and the bottom. It is **not** a global overlay — each pane has its own independent find bar.

- [ ] **Step 1: Read `MarkdownPaneView.swift`**

  Read `/Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Views/MarkdownPaneView.swift` to have it in context.

- [ ] **Step 2: Add `@State` variables**

  Add these new `@State` declarations immediately after `@State private var printTrigger: Int = 0` and `@State private var presentationTrigger: Int = 0`:

  ```swift
  @State private var findBarVisible: Bool = false
  @State private var showReplace: Bool = false
  @State private var findQuery: String = ""
  @State private var replaceText: String = ""
  @State private var findMatchCurrent: Int = 0
  @State private var findMatchTotal: Int = -1
  @State private var findTrigger: Int = 0        // bumped to fire a new search
  @State private var findDirection: Int = 1      // 1 = next, -1 = prev
  @State private var replaceTrigger: Int = 0     // bumped to fire replace-current
  @State private var replaceAllTrigger: Int = 0  // bumped to fire replace-all
  ```

- [ ] **Step 3: Add the `FindBar` view and close-on-Escape handling**

  Replace the closing `}` of the `VStack(spacing: 0)` in `body` (the one that wraps `PaneToolbar`, `BreadcrumbView`, `HStack`) with this expanded version. Specifically, **after** the `HStack(spacing: 0) { ... }` block (which contains `MarkdownWebView` and side panels) and **before** the closing `}` of `VStack`, insert:

  ```swift
  if findBarVisible {
      FindBar(
          query: $findQuery,
          replaceText: $replaceText,
          showReplace: $showReplace,
          editorMode: editorMode,
          matchCurrent: findMatchCurrent,
          matchTotal: findMatchTotal,
          onFindNext: {
              findDirection = 1
              findTrigger += 1
          },
          onFindPrev: {
              findDirection = -1
              findTrigger += 1
          },
          onReplace: { replaceTrigger += 1 },
          onReplaceAll: { replaceAllTrigger += 1 },
          onClose: { closeFindBar() }
      )
      .transition(.move(edge: .bottom).combined(with: .opacity))
  }
  ```

- [ ] **Step 4: Add notification receivers**

  On the `MarkdownWebView` (alongside the existing `.onReceive` chain), add these handlers. They must all guard `appState.focusedPane == pane`:

  ```swift
  .onReceive(NotificationCenter.default.publisher(for: .openFind)) { _ in
      guard appState.focusedPane == pane else { return }
      showReplace = false
      openFindBar()
  }
  .onReceive(NotificationCenter.default.publisher(for: .openFindReplace)) { _ in
      guard appState.focusedPane == pane else { return }
      showReplace = true
      openFindBar()
  }
  .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
      guard appState.focusedPane == pane else { return }
      guard findBarVisible else { openFindBar(); return }
      findDirection = 1
      findTrigger += 1
  }
  .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
      guard appState.focusedPane == pane else { return }
      guard findBarVisible else { openFindBar(); return }
      findDirection = -1
      findTrigger += 1
  }
  .onReceive(NotificationCenter.default.publisher(for: .closeFind)) { _ in
      guard appState.focusedPane == pane else { return }
      closeFindBar()
  }
  ```

- [ ] **Step 5: Add helper methods**

  Add a private extension or private methods on the view struct. Because SwiftUI views are structs, use computed closures captured by the view's local scope. The cleanest approach is to declare them as private funcs in a `private` extension on `MarkdownPaneView`. Add at the bottom of the file (or inside the struct after `body`):

  ```swift
  private func openFindBar() {
      findBarVisible = true
      // Reset match counter when reopening
      findMatchCurrent = 0
      findMatchTotal = -1
      // Fire initial search if there's an existing query
      if !findQuery.isEmpty { findTrigger += 1 }
  }

  private func closeFindBar() {
      withAnimation(.easeOut(duration: 0.15)) {
          findBarVisible = false
      }
      findQuery = ""
      replaceText = ""
      findMatchCurrent = 0
      findMatchTotal = -1
  }
  ```

- [ ] **Step 6: Add keyboard Escape handling**

  SwiftUI on macOS doesn't expose a native `.onKeyPress(.escape)` without targeting macOS 14 `onKeyPress`. Use a background `NSEvent` monitor approach — but that is complex. The simpler approach for this codebase: add `.onExitCommand` on the `FindBar` (which fires on Escape in SwiftUI):

  In the `FindBar` view created in Task 2, add `.onExitCommand { onClose() }` on the outermost `VStack` in `FindBar.body`:

  ```swift
  // At the end of body's outermost VStack, add:
  .onExitCommand { onClose() }
  ```

  Edit `FindBar.swift` to add this modifier.

- [ ] **Step 7: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  Expected: `Build complete!`. Run the app, press Cmd+F — the bar should appear at the bottom of the pane. Press Escape — it should close. The text field gets focus automatically. No search actually fires yet (that's Task 4 and 5).

  **Manual check:**
  - Cmd+F opens bar, Escape closes it
  - Cmd+H opens bar with replace row visible (only in edit mode)
  - Second Cmd+F while bar is open does not crash

- [ ] **Step 8: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/MarkdownPaneView.swift \
          Sources/EzmdvApp/Views/FindBar.swift
  git commit -m "feat(find-replace): wire FindBar into MarkdownPaneView with open/close/notifications"
  ```

---

## Task 4: View-Mode Search in JavaScript (`markdown.html`)

**Goal:** Implement `findInView(query, direction)` in `markdown.html` that:
1. Strips previous highlights
2. Walks the `#content` DOM text nodes to find all case-insensitive matches
3. Wraps each match in `<mark class="find-highlight">` (yellow background)
4. Scrolls the current match into view
5. Posts the match count + current index back to Swift via `window.webkit.messageHandlers.findHandler`

Also implement `clearFindHighlights()` (called when the bar closes).

**Files:**
- Modify: `Sources/EzmdvApp/Resources/markdown.html`

**Context:** The HTML file already has JS functions called from Swift (`renderMarkdown`, `setMode`, `scrollToHeading`, etc.). The pattern is: expose a global JS function; Swift calls it via `webView.evaluateJavaScript(...)`. Add new functions in the same `<script>` block.

The `window.webkit.messageHandlers.findHandler` message handler does not exist yet — it will be registered in Swift in Task 5. Add it here anyway; the JS is defensive about missing handlers.

- [ ] **Step 1: Add CSS for highlights**

  Inside the `<style>` block in `markdown.html`, add after the existing `/* === Print === */` section:

  ```css
  /* === Find highlights === */
  mark.find-highlight {
    background: #ffe066;
    color: inherit;
    border-radius: 2px;
    padding: 0 1px;
  }
  mark.find-highlight.find-current {
    background: #ff8c00;
    outline: 2px solid #ff8c00;
    border-radius: 2px;
  }
  @media (prefers-color-scheme: dark) {
    mark.find-highlight { background: #7a6000; color: #ffe066; }
    mark.find-highlight.find-current { background: #b87800; outline-color: #ffb300; color: #fff; }
  }
  ```

- [ ] **Step 2: Add view-mode find JavaScript**

  In the `<script>` block, before the closing `</script>` tag (i.e., after the auto-scroll section), add:

  ```js
  // --- Find in View mode ---
  let _findMatches = [];   // Array of <mark> DOM elements
  let _findIndex = -1;     // Current match index (0-based)

  function clearFindHighlights() {
    document.querySelectorAll('mark.find-highlight').forEach(mark => {
      const parent = mark.parentNode;
      parent.replaceChild(document.createTextNode(mark.textContent), mark);
      parent.normalize();
    });
    _findMatches = [];
    _findIndex = -1;
  }

  function _postFindCount(current, total) {
    if (window.webkit?.messageHandlers?.findHandler) {
      window.webkit.messageHandlers.findHandler.postMessage({ current: current, total: total });
    }
  }

  // Collect all text nodes under el that are not inside a <script> or <style>
  function _textNodes(el) {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const tag = node.parentElement?.tagName?.toUpperCase();
        if (tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = [];
    let n;
    while ((n = walker.nextNode())) nodes.push(n);
    return nodes;
  }

  function findInView(query, direction) {
    // direction: 1 = next, -1 = prev
    clearFindHighlights();
    if (!query) { _postFindCount(0, 0); return; }

    const container = document.getElementById('content');
    if (!container) return;

    const textNodes = _textNodes(container);
    const lowerQuery = query.toLowerCase();

    textNodes.forEach(node => {
      const text = node.textContent;
      const lower = text.toLowerCase();
      let idx = 0;
      const parts = [];
      let match;
      while ((match = lower.indexOf(lowerQuery, idx)) !== -1) {
        if (match > idx) parts.push(document.createTextNode(text.slice(idx, match)));
        const mark = document.createElement('mark');
        mark.className = 'find-highlight';
        mark.textContent = text.slice(match, match + query.length);
        parts.push(mark);
        _findMatches.push(mark);
        idx = match + query.length;
      }
      if (parts.length > 0) {
        if (idx < text.length) parts.push(document.createTextNode(text.slice(idx)));
        const frag = document.createDocumentFragment();
        parts.forEach(p => frag.appendChild(p));
        node.parentNode.replaceChild(frag, node);
      }
    });

    const total = _findMatches.length;
    if (total === 0) { _postFindCount(0, 0); return; }

    // Pick starting index based on direction
    if (direction >= 0) {
      _findIndex = 0;
    } else {
      _findIndex = total - 1;
    }

    _activateFindMatch();
    _postFindCount(_findIndex + 1, total);
  }

  function findNextInView() {
    if (_findMatches.length === 0) return;
    _findIndex = (_findIndex + 1) % _findMatches.length;
    _activateFindMatch();
    _postFindCount(_findIndex + 1, _findMatches.length);
  }

  function findPrevInView() {
    if (_findMatches.length === 0) return;
    _findIndex = (_findIndex - 1 + _findMatches.length) % _findMatches.length;
    _activateFindMatch();
    _postFindCount(_findIndex + 1, _findMatches.length);
  }

  function _activateFindMatch() {
    _findMatches.forEach((m, i) => {
      m.classList.toggle('find-current', i === _findIndex);
    });
    const current = _findMatches[_findIndex];
    if (current) current.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
  ```

- [ ] **Step 3: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  Expected: `Build complete!` — the JS changes don't affect the Swift compilation but we catch any Package.swift or asset issues.

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Resources/markdown.html
  git commit -m "feat(find-replace): add view-mode find JS (highlight + scroll + match count)"
  ```

---

## Task 5: Swift Bridge — Fire Find from `MarkdownWebView`

**Goal:** When `findTrigger`, `replaceTrigger`, or `replaceAllTrigger` changes in `MarkdownWebView`, call the correct JS function. Register the `findHandler` message handler in the Coordinator so match count flows back to Swift and then to `MarkdownPaneView`.

**Files:**
- Modify: `Sources/EzmdvApp/Views/MarkdownWebView.swift`
- Modify: `Sources/EzmdvApp/Views/MarkdownPaneView.swift`

**Context:** Study how `printTrigger` and `presentationTrigger` are handled in `MarkdownWebView.updateNSView` — it's a simple `if coordinator.lastXTrigger != xTrigger { ... }` pattern. Follow the same approach. The `findHandler` message handler is added in `makeNSView` alongside `tocHandler`, `editHandler`, etc.

- [ ] **Step 1: Read `MarkdownWebView.swift`**

  Read the file to have it in context before editing.

- [ ] **Step 2: Add props to `MarkdownWebView`**

  Add these stored properties to the `MarkdownWebView` struct (alongside `printTrigger`, `presentationTrigger`, etc.):

  ```swift
  var findQuery: String = ""
  var findTrigger: Int = 0
  var findDirection: Int = 1      // 1 = next, -1 = prev
  var replaceTrigger: Int = 0
  var replaceAllTrigger: Int = 0
  var replaceText: String = ""
  var onFindResult: ((Int, Int) -> Void)? = nil   // (current, total)
  var onFindClose: (() -> Void)? = nil
  ```

- [ ] **Step 3: Register `findHandler` in `makeNSView`**

  In `makeNSView`, alongside the other `userController.add(...)` calls, add:

  ```swift
  userController.add(context.coordinator, name: "findHandler")
  ```

  Also assign the new callbacks in the coordinator setup section:

  ```swift
  context.coordinator.onFindResult = onFindResult
  context.coordinator.onFindClose = onFindClose
  ```

- [ ] **Step 4: Update coordinator callbacks in `updateNSView`**

  In `updateNSView`, after updating other callbacks, add:

  ```swift
  context.coordinator.onFindResult = onFindResult
  context.coordinator.onFindClose = onFindClose
  ```

- [ ] **Step 5: Add tracking vars to `Coordinator`**

  In `class Coordinator`, add:

  ```swift
  var lastFindTrigger: Int = 0
  var lastFindQuery: String = ""
  var lastReplaceTrigger: Int = 0
  var lastReplaceAllTrigger: Int = 0
  var onFindResult: ((Int, Int) -> Void)?
  var onFindClose: (() -> Void)?
  ```

- [ ] **Step 6: Fire JS in `updateNSView` when triggers change**

  In `updateNSView`, after the existing trigger handling (print, presentation), add:

  ```swift
  // Find trigger
  if context.coordinator.lastFindTrigger != findTrigger {
      context.coordinator.lastFindTrigger = findTrigger
      context.coordinator.lastFindQuery = findQuery
      let escapedQuery = JSEscaping.escapeForStringLiteral(findQuery)
      if editorMode == "view" {
          let dir = findDirection >= 0 ? 1 : -1
          if findTrigger == 1 || context.coordinator.lastFindQuery != findQuery {
              // New search
              webView.evaluateJavaScript(
                  "findInView(\"\(escapedQuery)\", \(dir))",
                  completionHandler: nil
              )
          } else {
              // Navigate existing results
              if findDirection >= 0 {
                  webView.evaluateJavaScript("findNextInView()", completionHandler: nil)
              } else {
                  webView.evaluateJavaScript("findPrevInView()", completionHandler: nil)
              }
          }
      } else if editorMode == "edit" {
          // CodeMirror search — delegate to editorManager
          webView.evaluateJavaScript(
              "editorManager && editorManager.openSearch(\"\(escapedQuery)\", \(findDirection))",
              completionHandler: nil
          )
      }
  }

  // Replace trigger (edit mode only)
  if context.coordinator.lastReplaceTrigger != replaceTrigger {
      context.coordinator.lastReplaceTrigger = replaceTrigger
      let escapedReplacement = JSEscaping.escapeForStringLiteral(replaceText)
      webView.evaluateJavaScript(
          "editorManager && editorManager.replaceCurrentMatch(\"\(escapedReplacement)\")",
          completionHandler: nil
      )
  }

  // Replace All trigger (edit mode only)
  if context.coordinator.lastReplaceAllTrigger != replaceAllTrigger {
      context.coordinator.lastReplaceAllTrigger = replaceAllTrigger
      let escapedQuery = JSEscaping.escapeForStringLiteral(findQuery)
      let escapedReplacement = JSEscaping.escapeForStringLiteral(replaceText)
      webView.evaluateJavaScript(
          "editorManager && editorManager.replaceAllMatches(\"\(escapedQuery)\", \"\(escapedReplacement)\")",
          completionHandler: nil
      )
  }
  ```

  > **Implementation note for findTrigger logic:** The trigger approach above has a subtle issue — distinguishing "new search" from "navigate existing" by trigger count is fragile. A cleaner approach: always call `findInView` on each trigger (it re-highlights everything), passing direction. `findInView(query, direction)` already handles this: it clears and rebuilds highlights, then navigates to first (direction=1) or last (direction=-1) match. For subsequent "next/prev" calls where the query hasn't changed, the trigger bump should call `findNextInView()` / `findPrevInView()` instead.
  >
  > Simplest correct implementation: store `lastFindQuery` in coordinator. If `findQuery != lastFindQuery` → call `findInView` (new search). If `findQuery == lastFindQuery` → call `findNextInView` or `findPrevInView`.

  Revise the find trigger block to:

  ```swift
  if context.coordinator.lastFindTrigger != findTrigger {
      context.coordinator.lastFindTrigger = findTrigger
      let escapedQuery = JSEscaping.escapeForStringLiteral(findQuery)
      let isNewQuery = context.coordinator.lastFindQuery != findQuery
      context.coordinator.lastFindQuery = findQuery

      if editorMode == "view" {
          if isNewQuery || findTrigger == 1 {
              let dir = findDirection >= 0 ? 1 : -1
              webView.evaluateJavaScript(
                  "findInView(\"\(escapedQuery)\", \(dir))",
                  completionHandler: nil
              )
          } else {
              if findDirection >= 0 {
                  webView.evaluateJavaScript("findNextInView()", completionHandler: nil)
              } else {
                  webView.evaluateJavaScript("findPrevInView()", completionHandler: nil)
              }
          }
      } else if editorMode == "edit" || editorMode == "preview" {
          if isNewQuery || findTrigger == 1 {
              let dir = findDirection >= 0 ? 1 : -1
              webView.evaluateJavaScript(
                  "editorManager && editorManager.openSearch(\"\(escapedQuery)\", \(dir))",
                  completionHandler: nil
              )
          } else {
              if findDirection >= 0 {
                  webView.evaluateJavaScript(
                      "editorManager && editorManager.findNext()", completionHandler: nil)
              } else {
                  webView.evaluateJavaScript(
                      "editorManager && editorManager.findPrev()", completionHandler: nil)
              }
          }
      }
  }
  ```

- [ ] **Step 7: Handle `findHandler` messages in `Coordinator.userContentController`**

  In the `userContentController` method, add a new case after the existing handlers:

  ```swift
  if message.name == "findHandler",
     let info = message.body as? [String: Any],
     let current = info["current"] as? Int,
     let total = info["total"] as? Int {
      DispatchQueue.main.async { self.onFindResult?(current, total) }
  }
  ```

- [ ] **Step 8: Wire `MarkdownPaneView` to pass new props to `MarkdownWebView`**

  In `MarkdownPaneView.body`, the `MarkdownWebView(...)` initializer call needs the new props. Add these arguments to the `MarkdownWebView(...)` call (alongside `filePath:`, `zoom:`, etc.):

  ```swift
  findQuery: findQuery,
  findTrigger: findTrigger,
  findDirection: findDirection,
  replaceTrigger: replaceTrigger,
  replaceAllTrigger: replaceAllTrigger,
  replaceText: replaceText,
  onFindResult: { current, total in
      findMatchCurrent = current
      findMatchTotal = total
  },
  onFindClose: {
      closeFindBar()
  }
  ```

  Also add a `clearFindHighlights` call when the mode changes to view (so stale highlights from a previous session don't persist). Add this inside the `.onReceive(NotificationCenter.default.publisher(for: .toggleEditMode))` handler, after switching `editorMode`:

  ```swift
  // Clear find state when switching modes
  if findBarVisible {
      findMatchCurrent = 0
      findMatchTotal = -1
      findTrigger += 1  // re-run search in new mode
  }
  ```

- [ ] **Step 9: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  Expected: `Build complete!`.

  **Manual verification:**
  1. Open a file with repeated words (e.g. "the")
  2. Press Cmd+F
  3. Type "the" — yellow highlights should appear on all matches; the current match is orange; "1 of N" label updates
  4. Press Cmd+G — next match highlighted and scrolled into view, counter updates
  5. Press Cmd+Shift+G — previous match
  6. Press Escape — bar closes, all highlights removed (verify by looking at the view)
  7. Clearing the query field should reset the highlights

- [ ] **Step 10: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/MarkdownWebView.swift \
          Sources/EzmdvApp/Views/MarkdownPaneView.swift
  git commit -m "feat(find-replace): Swift bridge for find triggers and match count callback"
  ```

---

## Task 6: Clear Highlights When Bar Closes

**Goal:** When `findBarVisible` becomes false, call `clearFindHighlights()` in JS (view mode) or `editorManager.closeSearch()` (edit mode) so the document is restored to a clean state.

**Files:**
- Modify: `Sources/EzmdvApp/Views/MarkdownWebView.swift`
- Modify: `Sources/EzmdvApp/Views/MarkdownPaneView.swift`

**Context:** The existing pattern for "do something when a bool changes" is to add a tracking var to Coordinator and compare in `updateNSView`. Follow the same pattern.

- [ ] **Step 1: Add `findBarVisible` prop to `MarkdownWebView`**

  Add to the struct:

  ```swift
  var findBarVisible: Bool = false
  ```

  Add to Coordinator:

  ```swift
  var lastFindBarVisible: Bool = false
  ```

- [ ] **Step 2: React to `findBarVisible` changes in `updateNSView`**

  In `updateNSView`, after the find/replace trigger block, add:

  ```swift
  // Clear find when bar closes
  if context.coordinator.lastFindBarVisible != findBarVisible {
      context.coordinator.lastFindBarVisible = findBarVisible
      if !findBarVisible {
          if editorMode == "view" {
              webView.evaluateJavaScript("clearFindHighlights()", completionHandler: nil)
          } else {
              webView.evaluateJavaScript(
                  "editorManager && editorManager.closeSearch()", completionHandler: nil)
          }
      }
  }
  ```

- [ ] **Step 3: Pass `findBarVisible` from `MarkdownPaneView`**

  In `MarkdownPaneView.body`, add `findBarVisible: findBarVisible` to the `MarkdownWebView(...)` initializer.

- [ ] **Step 4: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  **Manual check:** Open bar, search, see highlights. Close with Escape. Confirm all yellow marks are gone.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/MarkdownWebView.swift \
          Sources/EzmdvApp/Views/MarkdownPaneView.swift
  git commit -m "feat(find-replace): clear highlights when find bar closes"
  ```

---

## Task 7: Edit-Mode Search via CodeMirror (`editor.js`)

**Goal:** Expose `openSearch`, `findNext`, `findPrev`, `closeSearch`, `replaceCurrentMatch`, `replaceAllMatches` methods on `EditorManager` (the class built in `editor.js`) using CodeMirror 6's `@codemirror/search` extension. Also post match count back to Swift via `findHandler` when CodeMirror reports matches.

**Files:**
- Modify: `Sources/EzmdvApp/Resources/editor.js`

**Context:** `editor.js` is a minified bundle. The `EditorManager` class is exposed as `window.EditorManager`. You need to find the class definition in the source (before bundling) or — since the source is bundled — add the methods by patching the prototype or extending the class definition. Since we cannot unbundle, we will **add methods to `window.EditorManager.prototype` in `markdown.html`** (a post-bundle patch), calling CodeMirror commands that are already in the bundle.

This is the right approach because:
1. We cannot easily re-bundle `editor.js` without the build toolchain
2. CodeMirror 6 exposes commands on the `view` object that can be called programmatically
3. `EditorManager` already exposes its `view` (CodeMirror `EditorView`) through the class; we need to check if it's accessible

**Investigation step first:**

- [ ] **Step 1: Verify `EditorManager` API surface**

  Search the `editor.js` bundle for the string `EditorManager` and `this.view` to understand how the class exposes the CodeMirror `EditorView`:

  ```bash
  grep -o 'EditorManager[^;]*' \
    /Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Resources/editor.js \
    | head -20
  ```

  Also check `markdown.html` for how `editorManager.init(...)`, `editorManager.getContent()`, `editorManager.setContent(...)` are called — these are the existing public methods. We need to find the property name the class uses internally for the `EditorView` instance.

  ```bash
  grep -o 'this\.[a-zA-Z_]*[Vv]iew[^;]*' \
    /Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Resources/editor.js \
    | head -20
  ```

  > **If `EditorView` is not exposed on `this`:** We will need to patch `EditorManager` to store `this.view = editorView` in its `init` method. Since the bundle is minified and hard to edit, the cleanest approach is to **add a `findHandler` message handler registration in `makeNSView` (Task 5, already done) and implement the search API as free functions in `markdown.html` that directly access `editorManager._view` or the DOM**.

- [ ] **Step 2: Add CodeMirror search methods to `markdown.html`**

  Since `editor.js` is a minified bundle and patching it directly is risky, add the edit-mode search methods **in `markdown.html`** as a post-load patch on `window.EditorManager.prototype`. Add this block in the `<script>` section of `markdown.html`, after the find-in-view functions added in Task 4:

  ```js
  // --- Find in Edit mode (CodeMirror) ---
  // We patch EditorManager prototype after editor.js loads.
  // This runs after DOMContentLoaded so EditorManager is defined.

  // Called from Swift to open/restart a search in the CodeMirror editor
  function editorFindOpen(query, direction) {
    if (!editorManager || !editorManager._cmView) return;
    const view = editorManager._cmView;
    // Use CodeMirror's openSearchPanel command + setSearchQuery
    // These are bundled in editor.js under the codemirror/search package
    if (window._cmSearch) {
      window._cmSearch.openSearchPanel(view);
      window._cmSearch.setSearchQuery(view, {
        search: query,
        caseSensitive: false,
        regexp: false
      });
      if (direction >= 0) {
        window._cmSearch.findNext(view);
      } else {
        window._cmSearch.findPrevious(view);
      }
    }
  }

  function editorFindNext() {
    if (!editorManager || !editorManager._cmView || !window._cmSearch) return;
    window._cmSearch.findNext(editorManager._cmView);
  }

  function editorFindPrev() {
    if (!editorManager || !editorManager._cmView || !window._cmSearch) return;
    window._cmSearch.findPrevious(editorManager._cmView);
  }

  function editorCloseSearch() {
    if (!editorManager || !editorManager._cmView || !window._cmSearch) return;
    window._cmSearch.closeSearchPanel(editorManager._cmView);
  }

  function editorReplaceCurrentMatch(replacement) {
    if (!editorManager || !editorManager._cmView || !window._cmSearch) return;
    window._cmSearch.replaceNext(editorManager._cmView);
  }

  function editorReplaceAllMatches(query, replacement) {
    if (!editorManager || !editorManager._cmView || !window._cmSearch) return;
    window._cmSearch.replaceAll(editorManager._cmView);
  }
  ```

  > **Key concern:** CodeMirror 6's commands (`findNext`, `findPrevious`, `replaceNext`, `replaceAll`, `openSearchPanel`, `closeSearchPanel`, `setSearchQuery`) are tree-shakable. Whether they exist in the bundle depends on whether they were imported in the original source. If the bundle was built without `@codemirror/search`, these APIs won't be present.

- [ ] **Step 3: Check if `@codemirror/search` is in the bundle**

  ```bash
  grep -c 'findNext\|searchPanel\|SearchQuery\|openSearchPanel' \
    /Users/bruno/Claude/ezmdv-native/Sources/EzmdvApp/Resources/editor.js
  ```

  **If count > 0:** The search extension is bundled. Proceed to Step 4 to expose the API.

  **If count == 0:** The search extension was NOT included in the bundle. In that case use the **fallback approach** described in Step 3b.

- [ ] **Step 3b (fallback): Implement CodeMirror search without the extension**

  If `@codemirror/search` is not bundled, implement a simpler text-based search in the CodeMirror editor by using `EditorView.dispatch` with a selection change. This is less polished (no built-in highlight panel) but functional:

  ```js
  function editorFindOpen(query, direction) {
    if (!editorManager) return;
    const content = editorManager.getContent();
    if (!content || !query) { _postFindCount(0, 0); return; }
    const lowerContent = content.toLowerCase();
    const lowerQuery = query.toLowerCase();
    const matches = [];
    let idx = 0;
    while ((idx = lowerContent.indexOf(lowerQuery, idx)) !== -1) {
      matches.push(idx);
      idx += lowerQuery.length;
    }
    _editorFindMatches = matches;
    _editorFindQuery = query;
    if (matches.length === 0) { _postFindCount(0, 0); return; }
    _editorFindIndex = direction >= 0 ? 0 : matches.length - 1;
    _editorActivateMatch();
    _postFindCount(_editorFindIndex + 1, matches.length);
  }

  let _editorFindMatches = [];
  let _editorFindIndex = -1;
  let _editorFindQuery = '';

  function _editorActivateMatch() {
    if (!editorManager || !editorManager._cmView) return;
    const pos = _editorFindMatches[_editorFindIndex];
    if (pos === undefined) return;
    const view = editorManager._cmView;
    view.dispatch({
      selection: { anchor: pos, head: pos + _editorFindQuery.length },
      scrollIntoView: true
    });
    view.focus();
  }

  function editorFindNext() {
    if (_editorFindMatches.length === 0) return;
    _editorFindIndex = (_editorFindIndex + 1) % _editorFindMatches.length;
    _editorActivateMatch();
    _postFindCount(_editorFindIndex + 1, _editorFindMatches.length);
  }

  function editorFindPrev() {
    if (_editorFindMatches.length === 0) return;
    _editorFindIndex = (_editorFindIndex - 1 + _editorFindMatches.length) % _editorFindMatches.length;
    _editorActivateMatch();
    _postFindCount(_editorFindIndex + 1, _editorFindMatches.length);
  }

  function editorCloseSearch() {
    _editorFindMatches = [];
    _editorFindIndex = -1;
    _editorFindQuery = '';
  }

  function editorReplaceCurrentMatch(replacement) {
    if (!editorManager || !editorManager._cmView || _editorFindMatches.length === 0) return;
    const pos = _editorFindMatches[_editorFindIndex];
    const view = editorManager._cmView;
    view.dispatch({
      changes: { from: pos, to: pos + _editorFindQuery.length, insert: replacement }
    });
    // Re-run search to update match positions
    const newContent = editorManager.getContent();
    editorFindOpen(_editorFindQuery, 1);
  }

  function editorReplaceAllMatches(query, replacement) {
    if (!editorManager || !editorManager._cmView) return;
    const content = editorManager.getContent();
    const newContent = content.split(query).join(replacement);
    editorManager.setContent(newContent);
    _postFindCount(0, 0);
  }
  ```

  This fallback requires that `editorManager._cmView` is accessible. If it isn't, add `this._cmView = view` in the `EditorManager.init` method — but that requires editing the minified bundle. Instead, expose it by adding to `markdown.html`:

  ```js
  // Patch EditorManager to expose _cmView after init
  // Run after editor.js is injected (it's added as WKUserScript at document end)
  document.addEventListener('DOMContentLoaded', () => {
    if (!window.EditorManager) return;
    const origInit = window.EditorManager.prototype.init;
    window.EditorManager.prototype.init = function(container, content) {
      origInit.call(this, container, content);
      // After init, grab the EditorView from the container's DOM
      // CodeMirror 6 adds a .cm-editor element; the EditorView is accessible
      // via the container's first child if EditorManager stores it.
      // Best effort: store reference if the class exposes it.
      if (!this._cmView && this.view) { this._cmView = this.view; }
    };
  });
  ```

  > **Note:** The exact property name (`this.view`, `this._view`, `this.editorView`) depends on the original `EditorManager` source. The investigation in Step 1 will reveal this. If the bundle is too obfuscated to determine, add `console.log(Object.keys(editorManager))` in the browser console during development to inspect the instance.

- [ ] **Step 4: Update `MarkdownWebView` to use the correct JS function names**

  In Task 5's `updateNSView` find-trigger block, the JS calls were written as `editorManager.openSearch(...)`, `editorManager.findNext()`, etc. Update them to match the actual function names we defined in `markdown.html`:

  ```swift
  // In the edit mode branch of the find trigger handler:
  if isNewQuery || findTrigger == 1 {
      let dir = findDirection >= 0 ? 1 : -1
      webView.evaluateJavaScript(
          "editorFindOpen(\"\(escapedQuery)\", \(dir))",
          completionHandler: nil
      )
  } else {
      if findDirection >= 0 {
          webView.evaluateJavaScript("editorFindNext()", completionHandler: nil)
      } else {
          webView.evaluateJavaScript("editorFindPrev()", completionHandler: nil)
      }
  }

  // For replace trigger:
  webView.evaluateJavaScript(
      "editorReplaceCurrentMatch(\"\(escapedReplacement)\")",
      completionHandler: nil
  )

  // For replace all trigger:
  webView.evaluateJavaScript(
      "editorReplaceAllMatches(\"\(escapedQuery)\", \"\(escapedReplacement)\")",
      completionHandler: nil
  )

  // For close:
  webView.evaluateJavaScript("editorCloseSearch()", completionHandler: nil)
  ```

- [ ] **Step 5: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  Expected: `Build complete!`.

  **Manual verification (edit mode):**
  1. Open a file, switch to Edit mode (Cmd+E)
  2. Press Cmd+F
  3. Type a word that appears in the document
  4. Match count should update; CodeMirror should select/scroll to the first match
  5. Cmd+G navigates to next
  6. Cmd+Shift+G navigates to previous
  7. With replace bar open (Cmd+H), type replacement, click "Replace" — current selection is replaced
  8. "Replace All" replaces all occurrences

- [ ] **Step 6: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Resources/markdown.html \
          Sources/EzmdvApp/Views/MarkdownWebView.swift
  git commit -m "feat(find-replace): edit-mode search via CodeMirror EditorManager API"
  ```

---

## Task 8: Live Search (Query Change Fires Search)

**Goal:** When the user types in the find field, the search fires automatically after a short debounce (rather than requiring Enter/Cmd+G). This is the standard Mac find bar UX.

**Files:**
- Modify: `Sources/EzmdvApp/Views/FindBar.swift`
- Modify: `Sources/EzmdvApp/Views/MarkdownPaneView.swift`

**Context:** SwiftUI `onChange(of:)` on the `query` binding allows reacting to text changes. Debounce using `DispatchWorkItem` stored in a class-based holder (structs can't hold mutable state across re-renders). The debounce delay should be 300ms — short enough to feel responsive, long enough to avoid firing on every keystroke for long documents.

- [ ] **Step 1: Add a debouncer to `FindBar`**

  `FindBar` is a struct so it can't hold a `DispatchWorkItem` directly. Pass an `onQueryChanged` closure from the parent and let the parent debounce:

  In `FindBar.swift`, add a parameter:

  ```swift
  let onQueryChanged: (String) -> Void
  ```

  Add `.onChange(of: query)` on the outermost VStack in `FindBar.body`:

  ```swift
  .onChange(of: query) { newValue in
      onQueryChanged(newValue)
  }
  ```

- [ ] **Step 2: Implement debounced search in `MarkdownPaneView`**

  `MarkdownPaneView` is also a struct. Use a `class` wrapper for the debounce work item. Add a private class at the top of `MarkdownPaneView.swift` (outside the struct, at file scope):

  ```swift
  private final class FindDebouncer {
      var workItem: DispatchWorkItem?
      func schedule(delay: Double = 0.3, action: @escaping () -> Void) {
          workItem?.cancel()
          let item = DispatchWorkItem(block: action)
          workItem = item
          DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
      }
  }
  ```

  Add to `MarkdownPaneView` struct:

  ```swift
  @StateObject private var findDebouncer = FindDebouncer()
  ```

  Wait — `@StateObject` requires an `ObservableObject`. Make `FindDebouncer` conform:

  ```swift
  private final class FindDebouncer: ObservableObject {
      var workItem: DispatchWorkItem?
      func schedule(delay: Double = 0.3, action: @escaping () -> Void) {
          workItem?.cancel()
          let item = DispatchWorkItem(block: action)
          workItem = item
          DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
      }
  }
  ```

  In the `FindBar(...)` call in `MarkdownPaneView`, pass:

  ```swift
  onQueryChanged: { newQuery in
      findQuery = newQuery
      findMatchCurrent = 0
      findMatchTotal = -1
      if newQuery.isEmpty {
          // Don't fire search for empty query; clear highlights
          findTrigger = 0
      } else {
          findDebouncer.schedule {
              findDirection = 1
              findTrigger += 1
          }
      }
  }
  ```

- [ ] **Step 3: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  **Manual check:** Open find bar, type a word character by character. Highlights should appear after ~300ms pause, not on every keystroke (observe the JS call frequency in Console if you have the WebView inspector open).

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/FindBar.swift \
          Sources/EzmdvApp/Views/MarkdownPaneView.swift
  git commit -m "feat(find-replace): debounced live search as user types"
  ```

---

## Task 9: Polish & Edge Cases

**Goal:** Handle edge cases that would otherwise feel broken: empty query, mode switch while bar is open, split-view (each pane has independent bar state), Cmd+F when bar is already open (re-focuses the text field).

**Files:**
- Modify: `Sources/EzmdvApp/Views/MarkdownPaneView.swift`
- Modify: `Sources/EzmdvApp/Views/FindBar.swift`

- [ ] **Step 1: Re-focus query field when Cmd+F fires while bar is already open**

  In `MarkdownPaneView`, `openFindBar()` currently just sets `findBarVisible = true`. Also need to re-focus the text field. Since `FindBar` uses `@FocusState` and `.onAppear { queryFocused = true }`, re-opening the bar will already do this if `FindBar` is removed and re-added. But since `findBarVisible` is already `true`, the `.onAppear` won't fire again.

  Solution: add an `id` to the `FindBar` that changes on each open. Add `@State private var findBarID: UUID = UUID()` and increment it in `openFindBar()`:

  In `openFindBar()`:
  ```swift
  private func openFindBar() {
      findBarID = UUID()   // forces re-creation, triggering .onAppear
      findBarVisible = true
      findMatchCurrent = 0
      findMatchTotal = -1
      if !findQuery.isEmpty { findTrigger += 1 }
  }
  ```

  In `MarkdownPaneView.body`, add `.id(findBarID)` to the `FindBar(...)` call:

  ```swift
  FindBar(...).id(findBarID).transition(...)
  ```

- [ ] **Step 2: Guard replace against view/preview mode**

  `FindBar` already hides the replace row when `editorMode != "edit"` (Task 2 Step 1). Verify this works when the user switches mode while the bar is open.

  In the `.onReceive(.toggleEditMode)` handler in `MarkdownPaneView`, add:

  ```swift
  // If switching away from edit mode and replace row was showing, hide it
  if editorMode != "edit" { showReplace = false }
  ```

  (This runs after the mode toggle.)

- [ ] **Step 3: Handle `findQuery.isEmpty` — post zero matches to reset UI**

  When user clears the query field, immediately reset the match count display. In `onQueryChanged`:

  ```swift
  if newQuery.isEmpty {
      findMatchCurrent = 0
      findMatchTotal = -1   // show nothing
      // Also clear highlights immediately (no debounce needed)
      // Trigger a "close" of find state in the webview
      // We achieve this by bumping findBarVisible off/on — too disruptive.
      // Instead: set findTrigger to 0 (no-op) and let the bar-close handler clear.
      // Actually, post a direct JS call via a new notification or by setting
      // findQuery = "" and bumping a dedicated clearTrigger.
  }
  ```

  Simplest approach: if `newQuery.isEmpty`, bump `findTrigger` with an empty string. In view mode, `findInView("", 1)` will call `clearFindHighlights()` because the early-exit in `findInView` handles empty query:

  ```js
  if (!query) { clearFindHighlights(); _postFindCount(0, -1); return; }
  ```

  Update the JS `findInView` to call `clearFindHighlights()` when query is empty (update `markdown.html`):

  ```js
  function findInView(query, direction) {
    clearFindHighlights();
    if (!query) { _postFindCount(0, -1); return; }
    // ... rest of function
  }
  ```

  And update `_postFindCount` to handle `total == -1` as "no active search" (the Swift side already handles `matchTotal == -1` as "show nothing").

- [ ] **Step 4: Animate the bar in/out**

  Wrap the `findBarVisible` toggle in `.animation`:

  In `MarkdownPaneView.body`, add `.animation(.easeOut(duration: 0.15), value: findBarVisible)` on the `VStack`:

  ```swift
  VStack(spacing: 0) {
      // ... all content
  }
  .animation(.easeOut(duration: 0.15), value: findBarVisible)
  ```

- [ ] **Step 5: Build and verify**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
  ```

  **Full manual checklist:**

  | Scenario | Expected |
  |----------|----------|
  | Cmd+F in view mode | Bar opens, focus in query field |
  | Type a present word | Highlights appear, counter shows "1 of N" |
  | Type a word not in doc | "No matches" in red |
  | Cmd+G | Next match, counter updates |
  | Cmd+Shift+G | Previous match, wraps around |
  | Escape | Bar closes, highlights gone |
  | Cmd+F while bar open | Bar stays open, query field refocused |
  | Cmd+H in view mode | Bar opens, replace row NOT shown (view mode) |
  | Switch to Edit mode, Cmd+H | Bar opens with replace row |
  | Replace in edit mode | Current match replaced, re-search fires |
  | Replace All | All occurrences replaced |
  | Switch mode while bar open | Match counter resets, new search fires in new mode |
  | Split view | Each pane has independent find bar; Cmd+F targets focused pane |
  | Clear query field | Highlights clear immediately |

- [ ] **Step 6: Commit**

  ```bash
  cd /Users/bruno/Claude/ezmdv-native
  git add Sources/EzmdvApp/Views/MarkdownPaneView.swift \
          Sources/EzmdvApp/Views/FindBar.swift \
          Sources/EzmdvApp/Resources/markdown.html
  git commit -m "feat(find-replace): polish edge cases, animations, empty query, mode-switch"
  ```

---

## Summary of All Modified/Created Files

| File | Change |
|------|--------|
| `Sources/EzmdvApp/EzmdvApp.swift` | +5 `Notification.Name` + `CommandMenu("Find")` with 4 items |
| `Sources/EzmdvApp/Views/FindBar.swift` | **New file** — SwiftUI find/replace bar component |
| `Sources/EzmdvApp/Views/MarkdownPaneView.swift` | +12 `@State` vars, `FindBar` overlay, 5 `.onReceive` handlers, `openFindBar`/`closeFindBar` helpers, new props passed to `MarkdownWebView` |
| `Sources/EzmdvApp/Views/MarkdownWebView.swift` | +8 props, `findHandler` registration, trigger-based JS calls in `updateNSView`, `findHandler` in `Coordinator` |
| `Sources/EzmdvApp/Resources/markdown.html` | CSS for highlights, ~80 lines JS: `findInView`, `findNextInView`, `findPrevInView`, `clearFindHighlights`, `_postFindCount`, `editorFindOpen`, `editorFindNext`, `editorFindPrev`, `editorCloseSearch`, `editorReplaceCurrentMatch`, `editorReplaceAllMatches` |

---

## Known Constraints and Tradeoffs

- **Cmd+H conflict:** macOS system reserves Cmd+H for Hide. The menu item is registered but the system shortcut takes priority when the app is not in the foreground. Consider remapping to Cmd+Opt+F in a future iteration.
- **CodeMirror bundled search API:** If `@codemirror/search` was not included in the bundle, edit-mode search falls back to selection-based navigation. The replace-row still works (via `EditorView.dispatch`), but there are no CodeMirror-native highlights. This is functional but lacks the polished match-highlight UI CodeMirror's search panel provides.
- **View-mode `window.find()`:** We chose DOM text-node traversal + `<mark>` injection over `window.find()` because `window.find()` doesn't provide match count. The tradeoff is we manipulate the DOM directly, which means switching modes while the bar is open could leave stale markup if `clearFindHighlights` isn't called. The mode-switch handler in Task 9 mitigates this.
- **No automated tests:** This codebase has no test target. All verification is manual as documented above.
