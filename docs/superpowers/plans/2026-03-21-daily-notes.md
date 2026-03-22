# Daily Notes Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add yesterday/tomorrow navigation to the daily note toolbar and template support for new daily notes.

**Architecture:** Pure date logic goes into EzmdvCore (testable); DailyNoteService gains a date-aware openNote method; PaneToolbar shows ←/→ chevrons when the current file is a daily note.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, Swift Testing framework for tests.

---

## Task 1: Pure date logic in EzmdvCore

**Files to create/modify:**
- Create `Sources/EzmdvCore/DailyNoteLogic.swift`

### Steps

- [ ] Create `Sources/EzmdvCore/DailyNoteLogic.swift` with the following complete content:

```swift
import Foundation

public enum DailyNoteLogic {
    public static let folderName = "Daily Notes"

    public static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Returns true if the file is a daily note (YYYY-MM-DD.md inside a "Daily Notes" folder)
    public static func isDailyNote(filePath: String) -> Bool {
        let url = URL(fileURLWithPath: filePath)
        let name = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        guard parent == folderName else { return false }
        return dateFormatter.date(from: name) != nil
    }

    /// Extracts the date from a daily note file path. Returns nil if not a daily note.
    public static func date(fromDailyNotePath filePath: String) -> Date? {
        guard isDailyNote(filePath: filePath) else { return nil }
        let name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        return dateFormatter.date(from: name)
    }

    /// Returns the file path for a daily note on a given date within a project
    public static func filePath(for date: Date, projectPath: String) -> String {
        let dateStr = dateFormatter.string(from: date)
        let folder = (projectPath as NSString).appendingPathComponent(folderName)
        return (folder as NSString).appendingPathComponent("\(dateStr).md")
    }

    /// Returns a date offset by the given number of days
    public static func date(byAdding days: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
```

- [ ] Verify the build passes:

```
swift build
```

---

## Task 2: Tests for DailyNoteLogic

**Files to create/modify:**
- Create `Tests/EzmdvTests/DailyNoteLogicTests.swift`

### Steps

- [ ] Create `Tests/EzmdvTests/DailyNoteLogicTests.swift` with the following complete content:

```swift
import Testing
import Foundation
@testable import EzmdvCore

@Suite("DailyNoteLogic")
struct DailyNoteLogicTests {

    // MARK: - isDailyNote

    @Test func isDailyNote_trueForValidPath() {
        #expect(DailyNoteLogic.isDailyNote(filePath: "/path/Daily Notes/2026-03-21.md") == true)
    }

    @Test func isDailyNote_falseForWrongFolder() {
        #expect(DailyNoteLogic.isDailyNote(filePath: "/path/Other Folder/2026-03-21.md") == false)
    }

    @Test func isDailyNote_falseForNonDateFilename() {
        #expect(DailyNoteLogic.isDailyNote(filePath: "/path/Daily Notes/readme.md") == false)
    }

    @Test func isDailyNote_falseForMalformedDate() {
        #expect(DailyNoteLogic.isDailyNote(filePath: "/path/Daily Notes/not-a-date.md") == false)
    }

    // MARK: - date(fromDailyNotePath:)

    @Test func dateFromDailyNotePath_returnsCorrectDate() {
        let result = DailyNoteLogic.date(fromDailyNotePath: "/path/Daily Notes/2026-03-21.md")
        #expect(result != nil)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: result!)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 21)
    }

    @Test func dateFromDailyNotePath_returnsNilForNonDailyNote() {
        let result = DailyNoteLogic.date(fromDailyNotePath: "/path/Other Folder/readme.md")
        #expect(result == nil)
    }

    // MARK: - filePath(for:projectPath:)

    @Test func filePathForDate_returnsCorrectPath() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = formatter.date(from: "2026-03-21")!
        let result = DailyNoteLogic.filePath(for: date, projectPath: "/my/project")
        #expect(result == "/my/project/Daily Notes/2026-03-21.md")
    }

    // MARK: - date(byAdding:to:)

    @Test func dateByAdding_addOneDay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let base = formatter.date(from: "2026-03-21")!
        let next = DailyNoteLogic.date(byAdding: 1, to: base)
        #expect(formatter.string(from: next) == "2026-03-22")
    }

    @Test func dateByAdding_subtractOneDay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let base = formatter.date(from: "2026-03-21")!
        let prev = DailyNoteLogic.date(byAdding: -1, to: base)
        #expect(formatter.string(from: prev) == "2026-03-20")
    }
}
```

- [ ] Run the tests to confirm they pass:

```
DYLD_FRAMEWORK_PATH=/Library/Developer/CommandLineTools/Library/Developer/Frameworks swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

---

## Task 3: Update DailyNoteService to support arbitrary date navigation and templates

**Files to create/modify:**
- Modify `Sources/EzmdvApp/Services/DailyNoteService.swift`

### Steps

- [ ] Replace the entire content of `Sources/EzmdvApp/Services/DailyNoteService.swift` with:

```swift
import Foundation

enum DailyNoteService {
    static func openTodayNote(appState: AppState) {
        openNote(for: Date(), appState: appState)
    }

    static func openNote(for date: Date, appState: AppState) {
        guard let project = focusedProject(appState) else { return }
        let filePath = DailyNoteLogic.filePath(for: date, projectPath: project.path)
        let dailyFolder = (filePath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dailyFolder) {
            try? FileManager.default.createDirectory(atPath: dailyFolder, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: filePath) {
            let dateStr = DailyNoteLogic.dateFormatter.string(from: date)
            let content = dailyNoteContent(title: dateStr, project: project)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
            appState.loadProjectFiles(project)
        }
        appState.openFile(projectId: project.id, filePath: filePath)
    }

    private static func dailyNoteContent(title: String, project: Project) -> String {
        // Check for _templates/Daily Note.md in project
        let templatePath = ((project.path as NSString).appendingPathComponent("_templates") as NSString)
            .appendingPathComponent("Daily Note.md")
        if let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) {
            let now = Date()
            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "HH:mm"
            return templateContent
                .replacingOccurrences(of: "{{date}}", with: title)
                .replacingOccurrences(of: "{{title}}", with: title)
                .replacingOccurrences(of: "{{time}}", with: timeFmt.string(from: now))
        }
        return "# \(title)\n\n"
    }

    private static func focusedProject(_ appState: AppState) -> Project? {
        if let tab = appState.primaryTab,
           let proj = appState.projects.first(where: { $0.id == tab.projectId }) { return proj }
        return appState.projects.first
    }
}
```

**What changed vs. the original:**
- `openTodayNote` now delegates to `openNote(for:appState:)` rather than duplicating logic.
- `openNote(for:appState:)` is a new entry point that accepts any `Date`.
- File creation logic uses `DailyNoteLogic.filePath(for:projectPath:)` and `DailyNoteLogic.dateFormatter` instead of a locally-created formatter.
- `dailyNoteContent(title:project:)` checks for `_templates/Daily Note.md` in the project; if found it substitutes `{{date}}`, `{{title}}`, and `{{time}}`; otherwise falls back to the plain `# YYYY-MM-DD\n\n` skeleton.

- [ ] Verify the build passes:

```
swift build
```

---

## Task 4: Yesterday/Tomorrow navigation buttons in PaneToolbar

**Files to create/modify:**
- Modify `Sources/EzmdvApp/Views/PaneToolbar.swift`

### Steps

- [ ] Add a `dailyNoteDate` computed property to `PaneToolbar`. Insert it after the existing `isDirty` computed property (after line 29, before `var body:`):

```swift
    private var dailyNoteDate: Date? {
        guard let filePath = tab?.filePath else { return nil }
        return DailyNoteLogic.date(fromDailyNotePath: filePath)
    }
```

- [ ] In the `body` HStack, insert the daily note navigation buttons after the `if let tab = tab { ... }` block (which ends at line 54) and before `Spacer()` (line 56). Replace this section:

```swift
            if let tab = tab {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(tab.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
```

with:

```swift
            if let tab = tab {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(tab.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let date = dailyNoteDate {
                HStack(spacing: 2) {
                    Button(action: {
                        let prev = DailyNoteLogic.date(byAdding: -1, to: date)
                        DailyNoteService.openNote(for: prev, appState: appState)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Yesterday")

                    Button(action: {
                        let next = DailyNoteLogic.date(byAdding: 1, to: date)
                        DailyNoteService.openNote(for: next, appState: appState)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Tomorrow")
                }
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()
```

**Notes on placement:** The chevron buttons appear inline in the toolbar between the filename area and the `Spacer()`. They are only rendered when `dailyNoteDate` is non-nil, i.e. when the current file is a daily note inside a `Daily Notes` folder. The visual style (plain button style, `0.08` opacity background, `RoundedRectangle` clip) matches the existing mode-toggle button group.

- [ ] Verify the build passes:

```
swift build
```

---

## Summary of all files changed

| File | Action |
|------|--------|
| `Sources/EzmdvCore/DailyNoteLogic.swift` | **Create** — pure date logic, no UI deps |
| `Tests/EzmdvTests/DailyNoteLogicTests.swift` | **Create** — 8 tests covering all public methods |
| `Sources/EzmdvApp/Services/DailyNoteService.swift` | **Replace** — adds `openNote(for:appState:)`, template support, delegates today logic |
| `Sources/EzmdvApp/Views/PaneToolbar.swift` | **Modify** — adds `dailyNoteDate` property and ←/→ navigation buttons |

## Template support reference

Users can create `_templates/Daily Note.md` in any project root. Supported substitution tokens:

| Token | Replaced with |
|-------|--------------|
| `{{date}}` | Date string in `yyyy-MM-dd` format |
| `{{title}}` | Same as `{{date}}` for daily notes |
| `{{time}}` | Current time in `HH:mm` format |
