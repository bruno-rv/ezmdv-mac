import Foundation
import EzmdvCore

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
