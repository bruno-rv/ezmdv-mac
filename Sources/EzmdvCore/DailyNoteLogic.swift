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
