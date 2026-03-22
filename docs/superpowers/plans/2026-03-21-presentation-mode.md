# Presentation Mode Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Swift side to receive presentation state changes, enter macOS fullscreen on presentation start, and add a smooth fade transition between slides.

**Architecture:** MarkdownWebView gets an onPresentationChanged callback (mirrors onAutoScrollStopped pattern); MarkdownPaneView handles fullscreen toggling; markdown.html gets a CSS fade transition on the slide body element.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, WKWebView, JavaScript/CSS.

---

## Task 1: Wire `presentationHandler` in MarkdownWebView

**File:** `Sources/EzmdvApp/Views/MarkdownWebView.swift`

The `"presentationHandler"` message handler is already registered (line 34) but messages are silently dropped — `userContentController(_:didReceive:)` has no branch for it. This task adds the callback plumbing end-to-end.

### Steps

- [ ] **1.1** Add `onPresentationChanged` to the `MarkdownWebView` struct.

  After line 22 (`var onAutoScrollStopped: (() -> Void)? = nil`), insert:

  ```swift
  var onPresentationChanged: ((Bool) -> Void)? = nil
  ```

- [ ] **1.2** In `makeNSView` (around line 64, after `context.coordinator.onAutoScrollStopped = onAutoScrollStopped`), add:

  ```swift
  context.coordinator.onPresentationChanged = onPresentationChanged
  ```

- [ ] **1.3** In `updateNSView` (around line 90, after `context.coordinator.onAutoScrollStopped = onAutoScrollStopped`), add:

  ```swift
  context.coordinator.onPresentationChanged = onPresentationChanged
  ```

- [ ] **1.4** Add `onPresentationChanged` to the `Coordinator` class.

  After line 257 (`var onAutoScrollStopped: (() -> Void)?`), insert:

  ```swift
  var onPresentationChanged: ((Bool) -> Void)?
  ```

- [ ] **1.5** In `userContentController(_:didReceive:)`, add the handler after the `autoScrollHandler` block (after line 384, `DispatchQueue.main.async { self.onAutoScrollStopped?() }`):

  ```swift
  if message.name == "presentationHandler",
     let info = message.body as? [String: Any],
     let active = info["active"] as? Bool {
      DispatchQueue.main.async { self.onPresentationChanged?(active) }
  }
  ```

### Build verification

```
swift build 2>&1 | tail -5
```

Expected: clean build, no errors or warnings.

### Manual verification

1. Build and run the app.
2. Open any markdown file.
3. Open the browser console for the WKWebView (Safari → Develop → [app] → Web Inspector).
4. Run `enterPresentation()` in the console.
5. Confirm no crash. The `presentationHandler` message fires — at this point `onPresentationChanged` is `nil` in the view, so the callback is a no-op. Fullscreen will be wired in Task 2.
6. Press Escape. No crash.

---

## Task 2: macOS Fullscreen Integration in MarkdownPaneView

**File:** `Sources/EzmdvApp/Views/MarkdownPaneView.swift`

The file currently imports only `SwiftUI` (line 1). `NSApp` is available via `AppKit`; on macOS, SwiftUI files can access AppKit types directly without an explicit import because SwiftUI re-exports it, but adding `import AppKit` is explicit and safe. Check first: the file has only `import SwiftUI` at line 1, so add `import AppKit`.

### Steps

- [ ] **2.1** Add `import AppKit` after the existing `import SwiftUI` at line 1:

  ```swift
  import SwiftUI
  import AppKit
  ```

- [ ] **2.2** Add the new state variable. After line 29 (`@State private var presentationTrigger: Int = 0`), insert:

  ```swift
  @State private var enteredFullscreenForPresentation: Bool = false
  ```

- [ ] **2.3** In the `MarkdownWebView(...)` call (lines 76–109), add `onPresentationChanged` after the `onAutoScrollStopped` closure (after line 101, `}`):

  ```swift
  onPresentationChanged: { active in
      handlePresentationChange(active)
  },
  ```

  The full argument list in context (for placement clarity):

  ```swift
  onAutoScrollStopped: {
      autoScrollActive = false
  },
  onPresentationChanged: { active in
      handlePresentationChange(active)
  },
  onFindResult: { current, total in
  ```

- [ ] **2.4** Add the private helper function inside `MarkdownPaneView`. Place it after `closeFindBar()` (after line 249, the closing `}` of `closeFindBar`), before the closing `}` of the struct:

  ```swift
  private func handlePresentationChange(_ active: Bool) {
      guard let window = NSApp.keyWindow else { return }
      if active {
          let isAlreadyFullscreen = window.styleMask.contains(.fullScreen)
          enteredFullscreenForPresentation = !isAlreadyFullscreen
          if !isAlreadyFullscreen {
              window.toggleFullScreen(nil)
          }
      } else {
          if enteredFullscreenForPresentation {
              enteredFullscreenForPresentation = false
              if window.styleMask.contains(.fullScreen) {
                  window.toggleFullScreen(nil)
              }
          }
      }
  }
  ```

### Build verification

```
swift build 2>&1 | tail -5
```

Expected: clean build, no errors or warnings.

### Manual verification

1. Build and run the app.
2. Open any markdown file that contains one or more `---` slide separators (e.g., `# Slide 1\n\n---\n\n# Slide 2`).
3. Click the presentation toolbar button (or trigger via menu → Show Presentation).
4. Confirm the app enters macOS fullscreen mode automatically.
5. Press Escape to exit the presentation overlay.
6. Confirm the app exits fullscreen automatically (returns to its previous windowed state).
7. If the window was already fullscreen before entering presentation, confirm it stays fullscreen after Escape (the `enteredFullscreenForPresentation` guard prevents toggling).

---

## Task 3: Slide Transition Fade Animation in markdown.html

**File:** `Sources/EzmdvApp/Resources/markdown.html`

Currently `_render()` (lines 738–747) replaces `this.container.innerHTML` wholesale on every slide change, causing an instant hard cut. This task adds a CSS opacity transition so slides fade out then back in.

### Steps

- [ ] **3.1** Add fade CSS inside the `<style>` block. After line 188 (`.slide-content.markdown-body code, .slide-content.markdown-body pre { font-size: 0.75em; }`), insert before line 190 (`/* === Find highlights === */`):

  ```css
  #slide-body {
      opacity: 1;
      transition: opacity 0.15s ease;
  }
  #slide-body.slide-fading {
      opacity: 0;
  }
  ```

- [ ] **3.2** Replace the `_render()` method (lines 738–747). Change:

  ```js
  async _render() {
      if (!this.container) return;
      const total = this.slides.length;
      const md = this.slides[this.currentSlide] || '';
      this.container.innerHTML =
        `<article id="slide-body" class="slide-content markdown-body"></article>` +
        `<div style="position:absolute;bottom:18px;right:24px;font-size:12px;opacity:0.35">${this.currentSlide + 1} / ${total}</div>` +
        `<div style="position:absolute;bottom:18px;left:24px;font-size:11px;opacity:0.25">← → navigate · Esc exit</div>`;
      await renderMarkdownToEl(md, document.getElementById('slide-body'));
    },
  ```

  To:

  ```js
  async _render(firstRender = false) {
      if (!this.container) return;
      const total = this.slides.length;
      const md = this.slides[this.currentSlide] || '';

      if (firstRender || !document.getElementById('slide-body')) {
        // First render: build the container skeleton
        this.container.innerHTML =
          `<article id="slide-body" class="slide-content markdown-body"></article>` +
          `<div id="slide-counter" style="position:absolute;bottom:18px;right:24px;font-size:12px;opacity:0.45">${this.currentSlide + 1} / ${total}</div>` +
          `<div style="position:absolute;bottom:18px;left:24px;font-size:11px;opacity:0.3">← → navigate &nbsp;·&nbsp; Esc exit</div>`;
        await renderMarkdownToEl(md, document.getElementById('slide-body'));
      } else {
        // Subsequent renders: fade out → update → fade in
        const body = document.getElementById('slide-body');
        const counter = document.getElementById('slide-counter');
        body.classList.add('slide-fading');
        await new Promise(r => setTimeout(r, 120));
        await renderMarkdownToEl(md, body);
        if (counter) counter.textContent = `${this.currentSlide + 1} / ${total}`;
        body.classList.remove('slide-fading');
      }
    },
  ```

- [ ] **3.3** Update the `enter` method to pass `true` for `firstRender`. On line 720, change:

  ```js
  await this._render();
  ```

  To:

  ```js
  await this._render(true);
  ```

  `next()` and `prev()` (line 749–750) call `this._render()` with no arguments, which correctly defaults to `firstRender = false` — no changes needed there.

### Build verification

```
swift build 2>&1 | tail -5
```

Expected: clean build (HTML/JS changes don't affect Swift compilation, but this confirms no Swift regressions).

### Manual verification

1. Build and run the app.
2. Open a markdown file with multiple slides separated by `---`.
3. Enter presentation mode (toolbar button or menu).
4. Confirm the first slide renders immediately with no flicker.
5. Press the right arrow key (or space) to advance to the next slide.
6. Confirm a smooth 120ms fade-out → content swap → fade-in transition is visible.
7. Press the left arrow to go back. Same fade transition.
8. Confirm the slide counter (`2 / 3` etc.) updates correctly after each transition.
9. Press Escape. Confirm presentation exits cleanly and the window returns to its previous state.
