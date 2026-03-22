# Tags System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tag system that parses `#hashtags` from markdown files, indexes them per-project, and surfaces a collapsible tag filter panel in the sidebar that lets users filter the file tree by tag.

**Architecture:** A pure static-enum `TagService` handles regex-based tag extraction and index building (tag → [filePaths]). `AppState` grows two `@Published` properties — `tagIndex` and `activeTagFilter` — updated on project load and on every file save. The sidebar gains a `TagFilterPanelView` section below the file tree, plus a tag-filter pill chip below the search bar; when a tag is active, the file tree is replaced by a flat `TagFilteredFilesView`.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, Foundation (NSRegularExpression), no external dependencies.

---

## File Structure

| Status | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/EzmdvApp/Services/TagService.swift` | Tag extraction regex + index builder |
| Modify | `Sources/EzmdvApp/Models/AppState.swift` | Add `tagIndex`, `activeTagFilter` published vars |
| Modify | `Sources/EzmdvApp/Models/AppState+Projects.swift` | Call `rebuildTagIndex` after `loadProjectFiles` |
| Modify | `Sources/EzmdvApp/Models/AppState+FileContent.swift` | Call `rebuildTagIndex` inside `saveFile` |
| Create | `Sources/EzmdvApp/Views/TagFilterPanelView.swift` | Collapsible tag list + tag chip UI |
| Modify | `Sources/EzmdvApp/Views/SidebarView.swift` | Integrate tag chip below search bar; conditionally show `TagFilteredFilesView` or `ProjectListView` |

---

## Task 1: TagService — tag extraction and index building

**Files:**
- Create: `Sources/EzmdvApp/Services/TagService.swift`

### Context

`TagService` is a pure static enum (no state, no dependencies) following the same pattern as `SearchService`. It exposes two functions:

1. `findTags(in:)` — extracts every `#tag` from a string using a regex. A tag is `#` followed by one or more alphanumeric, hyphen, or underscore characters. Tags inside code fences or inline code are intentionally still matched (YAGNI — filtering them out is not in the spec).
2. `buildIndex(for:)` — walks all flat non-directory files of a project, reads them from disk, returns `[String: [String]]` mapping lowercase tag → [absolute file paths].

### Why a static enum?

The codebase uses `enum SearchService` for the same pattern: pure functions, no stored state, not instantiated. Match it.

- [ ] **Step 1: Create `TagService.swift`**

```swift
import Foundation

enum TagService {
    // Matches #word where word is [a-zA-Z0-9_-]+
    // Compiled once as a static constant — NSRegularExpression is thread-safe after init.
    private static let tagRegex: NSRegularExpression = {
        // The pattern uses a word boundary equivalent: require the # is NOT preceded by a word char.
        // Simplest approach: match literal # then one-or-more [A-Za-z0-9_-].
        // We require at least one alpha char so pure numeric #123 doesn't match.
        try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])#([A-Za-z][A-Za-z0-9_-]*)"#)
    }()

    /// Returns all unique lowercase tags found in `content`, e.g. ["todo", "project-x"].
    static func findTags(in content: String) -> [String] {
        let range = NSRange(content.startIndex..., in: content)
        let matches = tagRegex.matches(in: content, range: range)
        var seen = Set<String>()
        for match in matches {
            if let captureRange = Range(match.range(at: 1), in: content) {
                let tag = String(content[captureRange]).lowercased()
                seen.insert(tag)
            }
        }
        return Array(seen).sorted()
    }

    /// Builds a tag index for a project: tag → [absolute file paths].
    /// Reads files from disk; skips unreadable files silently.
    static func buildIndex(for project: Project) -> [String: [String]] {
        let flatFiles = MarkdownFile.flatten(project.files)
        var index: [String: [String]] = [:]
        for file in flatFiles {
            guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
            let tags = findTags(in: content)
            for tag in tags {
                index[tag, default: []].append(file.path)
            }
        }
        return index
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
```

Expected: `Build complete!` — no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/bruno/Claude/ezmdv-native
git add Sources/EzmdvApp/Services/TagService.swift
git commit -m "feat(tags): add TagService with regex extraction and index builder"
```

---

## Task 2: Add tag state to AppState

**Files:**
- Modify: `Sources/EzmdvApp/Models/AppState.swift`

### Context

`AppState` is an `ObservableObject`. All state that drives UI updates lives as `@Published` vars here. Add two properties:

- `tagIndex: [String: [String]]` — the merged index across all open projects (tag → [filePaths]). Not persisted (derived data, recomputed on load).
- `activeTagFilter: String?` — the currently selected tag, or `nil` when no filter is active. Drives what the sidebar shows.

Also add a `rebuildTagIndex()` method — it merges `TagService.buildIndex(for:)` across all projects. This is called from the extension files (Tasks 3 & 4), so it must be `internal` (default access, so no keyword needed).

- [ ] **Step 1: Add `@Published` properties to `AppState.swift`**

Open `Sources/EzmdvApp/Models/AppState.swift`. Add after the `// MARK: - Sort orders per project` block (after line 44):

```swift
    // MARK: - Tags
    @Published var tagIndex: [String: [String]] = [:]
    @Published var activeTagFilter: String? = nil
```

So the section looks like:
```swift
    // MARK: - Sort orders per project
    @Published var projectSortOrders: [UUID: FileSortOrder] = [:]

    // MARK: - Tags
    @Published var tagIndex: [String: [String]] = [:]
    @Published var activeTagFilter: String? = nil
```

- [ ] **Step 2: Add `rebuildTagIndex()` to `AppState.swift`**

Add the method inside the class body, before the closing `}` of the class:

```swift
    func rebuildTagIndex() {
        var merged: [String: [String]] = [:]
        for project in projects {
            let projectIndex = TagService.buildIndex(for: project)
            for (tag, paths) in projectIndex {
                merged[tag, default: []].append(contentsOf: paths)
            }
        }
        tagIndex = merged
    }
```

- [ ] **Step 3: Verify it builds**

```bash
cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd /Users/bruno/Claude/ezmdv-native
git add Sources/EzmdvApp/Models/AppState.swift
git commit -m "feat(tags): add tagIndex and activeTagFilter to AppState"
```

---

## Task 3: Rebuild tag index on project load

**Files:**
- Modify: `Sources/EzmdvApp/Models/AppState+Projects.swift`

### Context

`loadProjectFiles(_:)` is already called in two places:
1. `addProject(at:)` — when user opens a new folder.
2. `loadState()` (in `AppState+Persistence.swift`) — on app launch for each restored project.

After `loadProjectFiles` sets `projects[idx].files`, call `rebuildTagIndex()`. This ensures the index is always fresh after any structural change (load, create, rename, delete).

`loadProjectFiles` is already used for file-change events too, so this covers file watcher refreshes.

- [ ] **Step 1: Call `rebuildTagIndex()` at end of `loadProjectFiles(_:)`**

In `Sources/EzmdvApp/Models/AppState+Projects.swift`, the current `loadProjectFiles` is:

```swift
    func loadProjectFiles(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let files = FileScanner.scan(directory: project.path)
        projects[idx].files = files
    }
```

Replace it with:

```swift
    func loadProjectFiles(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let files = FileScanner.scan(directory: project.path)
        projects[idx].files = files
        rebuildTagIndex()
    }
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd /Users/bruno/Claude/ezmdv-native
git add Sources/EzmdvApp/Models/AppState+Projects.swift
git commit -m "feat(tags): rebuild tag index after project file load"
```

---

## Task 4: Rebuild tag index on file save

**Files:**
- Modify: `Sources/EzmdvApp/Models/AppState+FileContent.swift`

### Context

When the user edits a file and it auto-saves (or manual saves), the content changes. Tags in that file may have changed too. Call `rebuildTagIndex()` after a successful `saveFile` so the sidebar tag list stays accurate.

`saveFile(_:)` currently is:
```swift
    func saveFile(_ filePath: String) {
        guard let content = contentCache[filePath] else { return }
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            dirtyFiles.remove(filePath)
            autoSaveTimers[filePath]?.invalidate()
            autoSaveTimers.removeValue(forKey: filePath)
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 1: Add `rebuildTagIndex()` call after successful write in `saveFile`**

Replace `saveFile(_:)` in `Sources/EzmdvApp/Models/AppState+FileContent.swift`:

```swift
    func saveFile(_ filePath: String) {
        guard let content = contentCache[filePath] else { return }
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            dirtyFiles.remove(filePath)
            autoSaveTimers[filePath]?.invalidate()
            autoSaveTimers.removeValue(forKey: filePath)
            rebuildTagIndex()
        } catch {
            lastError = "Failed to save: \(error.localizedDescription)"
        }
    }
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd /Users/bruno/Claude/ezmdv-native
git add Sources/EzmdvApp/Models/AppState+FileContent.swift
git commit -m "feat(tags): rebuild tag index on file save"
```

---

## Task 5: TagFilterPanelView — tag list and filtered files view

**Files:**
- Create: `Sources/EzmdvApp/Views/TagFilterPanelView.swift`

### Context

This file contains two views:

**`TagFilterPanelView`** — a collapsible `DisclosureGroup` with header "Tags". Lists all tags from `appState.tagIndex` sorted alphabetically, each shown as a button: `#tagname (N)`. Tapping a tag sets `appState.activeTagFilter = tag`. The active tag gets `.accentColor` foreground. If there are no tags, the section is hidden entirely (no empty state needed in the panel itself).

**`TagFilteredFilesView`** — shown in the main sidebar content area when a tag is active. Flat list of all files that contain the active tag. Each row is a button that opens the file, identical in style to `SearchResultsView`. Shows project name as tertiary text so the user knows which project each file belongs to.

Both views use `@EnvironmentObject var appState: AppState`.

- [ ] **Step 1: Create `TagFilterPanelView.swift`**

```swift
import SwiftUI

// MARK: - Tag Filter Panel (collapsible, lives below the file tree)

struct TagFilterPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool = true

    /// Tags sorted alphabetically with their occurrence counts.
    private var sortedTags: [(tag: String, count: Int)] {
        appState.tagIndex
            .map { (tag: $0.key, count: $0.value.count) }
            .sorted { $0.tag < $1.tag }
    }

    var body: some View {
        // Only show the panel when there are tags to display.
        if !sortedTags.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(sortedTags, id: \.tag) { item in
                    Button(action: {
                        appState.activeTagFilter = item.tag
                    }) {
                        HStack(spacing: 4) {
                            Text("#\(item.tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    appState.activeTagFilter == item.tag
                                        ? Color.accentColor
                                        : Color.primary
                                )
                            Spacer()
                            Text("\(item.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            } label: {
                Text("Tags")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Tag Filtered Files View (replaces file tree when a tag is active)

struct TagFilteredFilesView: View {
    @EnvironmentObject var appState: AppState
    let tag: String

    private struct TaggedFile: Identifiable {
        let id = UUID()
        let filePath: String
        let fileName: String
        let projectName: String
        let projectId: UUID
    }

    private var matchingFiles: [TaggedFile] {
        guard let paths = appState.tagIndex[tag] else { return [] }
        // Deduplicate paths (multiple projects could theoretically share a path).
        let uniquePaths = Array(Set(paths)).sorted()
        return uniquePaths.compactMap { path in
            // Find which project owns this file.
            guard let project = appState.projects.first(where: { path.hasPrefix($0.path) })
            else { return nil }
            let fileName = (path as NSString).lastPathComponent
            return TaggedFile(
                filePath: path,
                fileName: fileName,
                projectName: project.name,
                projectId: project.id
            )
        }
    }

    var body: some View {
        List(matchingFiles) { file in
            Button(action: {
                appState.openFile(projectId: file.projectId, filePath: file.filePath)
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(file.fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(file.projectName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd /Users/bruno/Claude/ezmdv-native
git add Sources/EzmdvApp/Views/TagFilterPanelView.swift
git commit -m "feat(tags): add TagFilterPanelView and TagFilteredFilesView"
```

---

## Task 6: Wire tag UI into SidebarView

**Files:**
- Modify: `Sources/EzmdvApp/Views/SidebarView.swift`

### Context

`SidebarView.body` is a `VStack` with:
1. Search bar `HStack`
2. `Divider()`
3. Conditional: `SearchResultsView` (if searchText non-empty) else `ProjectListView`

We need to add:
- **Tag filter chip** — a pill row shown between the search bar and the divider when `appState.activeTagFilter != nil`. It shows `#tagname  ×` and tapping `×` clears the filter.
- **Content area switch** — when `activeTagFilter != nil` AND `searchText` is empty, show `TagFilteredFilesView` instead of `ProjectListView`. Search takes priority over tag filter so users can still search while a tag is active (though search clears tag filter implicitly via visual convention — see note below).
- **Tag panel** — `TagFilterPanelView` appended at the bottom of `ProjectListView` content, or shown below `TagFilteredFilesView`. The simplest approach: embed it at the bottom of the scroll area in the non-search branch.

**Note on search + tag filter interaction:** Per the spec, there's no explicit interaction rule. The plan keeps both independent: if `searchText` is non-empty, `SearchResultsView` always wins. Tag filter chip remains visible as context. This is the least surprising behaviour.

### Changes to `SidebarView`

The `SidebarView` struct itself needs no new `@State` vars — `activeTagFilter` lives on `appState`.

**Tag chip row** (insert between search bar HStack and the `Divider()`):

```swift
// Tag filter chip — shown when a tag is active
if let tag = appState.activeTagFilter {
    HStack(spacing: 4) {
        Text("#\(tag)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
        Button(action: { appState.activeTagFilter = nil }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        Spacer()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(.bar)
}
```

**Content area** (replace the existing `if !searchText.isEmpty` block):

```swift
if !searchText.isEmpty {
    SearchResultsView()
} else if let tag = appState.activeTagFilter {
    VStack(spacing: 0) {
        TagFilteredFilesView(tag: tag)
        Divider()
        TagFilterPanelView()
    }
} else {
    VStack(spacing: 0) {
        ProjectListView()
        TagFilterPanelView()
    }
}
```

- [ ] **Step 1: Add the tag chip below the search bar in `SidebarView.body`**

The current search bar block ends with its closing `}` followed by `Divider()`. Insert the chip between the search `HStack`'s closing brace and `Divider()`.

Find this in `Sources/EzmdvApp/Views/SidebarView.swift` (lines 28–33):
```swift
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()
```

Replace with:
```swift
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)

            // Tag filter chip
            if let tag = appState.activeTagFilter {
                HStack(spacing: 4) {
                    Text("#\(tag)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Button(action: { appState.activeTagFilter = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.bar)
            }

            Divider()
```

- [ ] **Step 2: Replace the content area switch to incorporate tag filter and tag panel**

Find this block (lines 36–40):
```swift
            // Search results or project tree
            if !searchText.isEmpty {
                SearchResultsView()
            } else {
                ProjectListView()
            }
```

Replace with:
```swift
            // Search results, tag-filtered files, or full project tree
            if !searchText.isEmpty {
                SearchResultsView()
            } else if let tag = appState.activeTagFilter {
                VStack(spacing: 0) {
                    TagFilteredFilesView(tag: tag)
                    Divider()
                    TagFilterPanelView()
                }
            } else {
                VStack(spacing: 0) {
                    ProjectListView()
                    Divider()
                    TagFilterPanelView()
                }
            }
```

- [ ] **Step 3: Verify it builds**

```bash
cd /Users/bruno/Claude/ezmdv-native && swift build 2>&1
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd /Users/bruno/Claude/ezmdv-native
git add Sources/EzmdvApp/Views/SidebarView.swift
git commit -m "feat(tags): wire tag chip and tag panel into sidebar"
```

---

## Manual Verification

Run the app with `swift run` or open the built product (no test target exists):

```bash
cd /Users/bruno/Claude/ezmdv-native && swift run 2>&1
```

**Checklist:**

- [ ] Open a project folder containing `.md` files that include `#hashtag` words.
- [ ] Expand a project in the sidebar — the Tags panel appears below the file tree if tags exist.
- [ ] Tags are listed alphabetically with occurrence counts, e.g. `#todo (3)`.
- [ ] Click a tag — the file tree is replaced by a flat list of files containing that tag. A `#tagname ×` chip appears below the search bar.
- [ ] Click the `×` on the chip — the tag filter clears; the full file tree returns.
- [ ] Click a file in the tag-filtered list — the file opens normally in the editor.
- [ ] Edit a file in the editor, add `#newtag`, wait 3 seconds (auto-save) — the new tag appears in the Tags panel.
- [ ] Delete all `#todo` tags from their files and save — `#todo` disappears from the Tags panel.
- [ ] Type in the search bar while a tag is active — search results are shown; the tag chip remains visible.
- [ ] Quit and relaunch — no tag filter persists (correct: it is derived, not saved).
- [ ] Open a project with no tags — the Tags panel does not appear (empty state hidden).

---

## Final Commit

After all tasks pass manual verification:

```bash
cd /Users/bruno/Claude/ezmdv-native
git log --oneline -6
```

Expected output (newest first):
```
<sha> feat(tags): wire tag chip and tag panel into sidebar
<sha> feat(tags): add TagFilterPanelView and TagFilteredFilesView
<sha> feat(tags): rebuild tag index on file save
<sha> feat(tags): rebuild tag index after project file load
<sha> feat(tags): add tagIndex and activeTagFilter to AppState
<sha> feat(tags): add TagService with regex extraction and index builder
```
