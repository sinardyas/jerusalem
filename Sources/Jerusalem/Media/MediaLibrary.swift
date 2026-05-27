import Foundation

enum MediaKind: Equatable { case video, image }

/// File-type rules for imported media. Pure and testable.
enum MediaImport {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    static func kind(forExtension ext: String) -> MediaKind? {
        let lowered = ext.lowercased()
        if videoExtensions.contains(lowered) { return .video }
        if imageExtensions.contains(lowered) { return .image }
        return nil
    }
}

/// On-disk storage for imported media, under Application Support/Jerusalem/Media.
enum MediaStorage {
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Jerusalem/Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(forFilename name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Copies `source` into `dir` (default: the media directory) under a unique
    /// name, returning the stored filename. Throws on copy failure.
    @discardableResult
    static func importFile(at source: URL, into dir: URL? = nil) throws -> String {
        let directory = dir ?? self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension
        let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        return name
    }
}
