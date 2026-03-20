import Foundation

struct SavedProject: Codable {
    let name: String
    let path: String
}

struct SavedTab: Codable {
    let projectPath: String  // match by project path since UUIDs change
    let filePath: String
}

struct SavedState: Codable {
    let projects: [SavedProject]
    let isDarkMode: Bool
    var tabs: [SavedTab]?
    var activeTabFilePath: String?
}

struct SearchResult: Identifiable {
    let id = UUID()
    let projectId: UUID
    let projectName: String
    let filePath: String
    let fileName: String
    let preview: String?
    let matchCount: Int
}
