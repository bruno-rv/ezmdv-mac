import Foundation

enum FileOperationError: LocalizedError {
    case fileNotFound(String)
    case alreadyExists(String)
    case permissionDenied(String)
    case invalidPath(String)
    case notEmpty(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "File not found: \(p)"
        case .alreadyExists(let p): return "Already exists: \(p)"
        case .permissionDenied(let p): return "Permission denied: \(p)"
        case .invalidPath(let p): return "Invalid path: \(p)"
        case .notEmpty(let p): return "Directory not empty: \(p)"
        case .unknown(let msg): return msg
        }
    }
}

enum FileService {
    private static let fm = FileManager.default

    // MARK: - Create file

    static func createFile(at path: String, content: String = "") throws {
        guard !fm.fileExists(atPath: path) else {
            throw FileOperationError.alreadyExists(path)
        }
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        guard fm.createFile(atPath: path, contents: content.data(using: .utf8)) else {
            throw FileOperationError.permissionDenied(path)
        }
    }

    // MARK: - Create folder

    static func createFolder(at path: String) throws {
        guard !fm.fileExists(atPath: path) else {
            throw FileOperationError.alreadyExists(path)
        }
        do {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw FileOperationError.permissionDenied(path)
        }
    }

    // MARK: - Delete file or folder

    static func delete(at path: String) throws {
        guard fm.fileExists(atPath: path) else {
            throw FileOperationError.fileNotFound(path)
        }
        do {
            try fm.removeItem(atPath: path)
        } catch {
            throw FileOperationError.permissionDenied(path)
        }
    }

    // MARK: - Rename / move

    static func rename(from oldPath: String, to newPath: String) throws {
        guard fm.fileExists(atPath: oldPath) else {
            throw FileOperationError.fileNotFound(oldPath)
        }
        guard !fm.fileExists(atPath: newPath) else {
            throw FileOperationError.alreadyExists(newPath)
        }
        do {
            try fm.moveItem(atPath: oldPath, toPath: newPath)
        } catch {
            throw FileOperationError.unknown("Failed to rename: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: path)
    }
}
