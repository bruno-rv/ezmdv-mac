import Testing
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
        // Round-trip through the canonical formatter to verify date value
        #expect(DailyNoteLogic.dateFormatter.string(from: result!) == "2026-03-21")
    }

    @Test func dateFromDailyNotePath_returnsNilForNonDailyNote() {
        let result = DailyNoteLogic.date(fromDailyNotePath: "/path/Other Folder/readme.md")
        #expect(result == nil)
    }

    // MARK: - filePath(for:projectPath:)

    @Test func filePathForDate_returnsCorrectPath() {
        let date = DailyNoteLogic.dateFormatter.date(from: "2026-03-21")!
        let result = DailyNoteLogic.filePath(for: date, projectPath: "/my/project")
        #expect(result == "/my/project/Daily Notes/2026-03-21.md")
    }

    // MARK: - date(byAdding:to:)

    @Test func dateByAdding_addOneDay() {
        let base = DailyNoteLogic.dateFormatter.date(from: "2026-03-21")!
        let next = DailyNoteLogic.date(byAdding: 1, to: base)
        #expect(DailyNoteLogic.dateFormatter.string(from: next) == "2026-03-22")
    }

    @Test func dateByAdding_subtractOneDay() {
        let base = DailyNoteLogic.dateFormatter.date(from: "2026-03-21")!
        let prev = DailyNoteLogic.date(byAdding: -1, to: base)
        #expect(DailyNoteLogic.dateFormatter.string(from: prev) == "2026-03-20")
    }
}
