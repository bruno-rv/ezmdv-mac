import Foundation

struct SavedProject: Codable {
    let name: String
    let path: String
}

struct SavedTab: Codable {
    let projectPath: String  // match by project path since UUIDs change
    let filePath: String
    var isPinned: Bool?
}

struct SavedState: Codable {
    let projects: [SavedProject]
    let isDarkMode: Bool
    var tabs: [SavedTab]?
    var activeTabFilePath: String?
    var recentFilePaths: [String]?
    var projectSortOrders: [String: String]?  // project path → FileSortOrder raw value
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
