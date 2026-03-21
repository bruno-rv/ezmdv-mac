import Foundation

enum TemplateService {
    /// Returns all .md files found in `_templates/` under the project root.
    static func listTemplates(in project: Project) -> [URL] {
        let dir = URL(fileURLWithPath: project.path).appendingPathComponent("_templates")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return contents
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Renders a template with substituted variables.
    static func apply(templateURL: URL, title: String) -> String {
        guard let content = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return "# \(title)\n\n"
        }
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        let now = Date()
        return content
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{date}}", with: dateFmt.string(from: now))
            .replacingOccurrences(of: "{{time}}", with: timeFmt.string(from: now))
    }
}
