import Foundation

struct FileTab: Identifiable, Hashable {
    let id: UUID
    let projectId: UUID
    let filePath: String
    let fileName: String

    init(projectId: UUID, filePath: String) {
        self.id = UUID()
        self.projectId = projectId
        self.filePath = filePath
        self.fileName = (filePath as NSString).lastPathComponent
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(projectId)
        hasher.combine(filePath)
    }

    static func == (lhs: FileTab, rhs: FileTab) -> Bool {
        lhs.projectId == rhs.projectId && lhs.filePath == rhs.filePath
    }
}
