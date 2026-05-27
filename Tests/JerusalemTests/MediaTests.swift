import XCTest
import SwiftData
@testable import Jerusalem

/// Phase 5 (part 1): media import rules, on-disk import, and video clips becoming
/// navigable program items / live output. Actual AVFoundation playback needs a run.
final class MediaTests: XCTestCase {

    func testMediaKindByExtension() {
        XCTAssertEqual(MediaImport.kind(forExtension: "mp4"), .video)
        XCTAssertEqual(MediaImport.kind(forExtension: "MOV"), .video)
        XCTAssertEqual(MediaImport.kind(forExtension: "m4v"), .video)
        XCTAssertEqual(MediaImport.kind(forExtension: "png"), .image)
        XCTAssertEqual(MediaImport.kind(forExtension: "JPG"), .image)
        XCTAssertNil(MediaImport.kind(forExtension: "txt"))
    }

    func testImportFileCopiesIntoDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jx-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("clip.mp4")
        try Data([0, 1, 2, 3]).write(to: source)
        let destination = root.appendingPathComponent("media", isDirectory: true)

        let name = try MediaStorage.importFile(at: source, into: destination)
        XCTAssertTrue(name.hasSuffix(".mp4"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(name).path))
    }

    @MainActor
    func testMediaItemBecomesVideoProgramSlide() {
        let item = Item(kind: .media, title: "Welcome Loop")
        item.mediaFilename = "abc.mp4"
        item.videoLoops = true

        let program = LiveState.programSlides(for: item)
        XCTAssertEqual(program.count, 1)
        guard case .video(let cue) = program[0].kind else {
            return XCTFail("expected a video program slide")
        }
        XCTAssertTrue(cue.loops)
        XCTAssertEqual(cue.url.lastPathComponent, "abc.mp4")
    }

    @MainActor
    func testVideoProgramGoesLiveAsVideoContent() {
        let item = Item(kind: .media, title: "Bumper")
        item.mediaFilename = "b.mov"

        let live = LiveState()
        live.arm(LiveState.programSlides(for: item))
        live.next()

        guard case .video(let cue) = live.content else {
            return XCTFail("expected video content")
        }
        XCTAssertEqual(cue.url.lastPathComponent, "b.mov")
    }

    @MainActor
    func testImageMediaBecomesImageSlide() {
        let item = Item(kind: .media, title: "Backdrop")
        item.mediaFilename = "photo.png"

        let program = LiveState.programSlides(for: item)
        XCTAssertEqual(program.count, 1)
        guard case .slide(let renderable) = program[0].kind else {
            return XCTFail("expected an image slide")
        }
        XCTAssertEqual(renderable.backgroundImageURL?.lastPathComponent, "photo.png")
        XCTAssertTrue(renderable.elements.isEmpty)
    }

    @MainActor
    func testUnknownMediaTypeProducesNoProgram() {
        let item = Item(kind: .media, title: "Doc")
        item.mediaFilename = "notes.txt"
        XCTAssertTrue(LiveState.programSlides(for: item).isEmpty)
    }

    @MainActor
    func testPrewarmerCachesAssetByURL() {
        let prewarmer = VideoPrewarmer()
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        XCTAssertTrue(prewarmer.asset(for: url) === prewarmer.asset(for: url))
    }

    @MainActor
    func testPrewarmIgnoresMissingAndNil() {
        let prewarmer = VideoPrewarmer()
        prewarmer.prewarm(nil)
        prewarmer.prewarm(VideoCue(url: URL(fileURLWithPath: "/does/not/exist.mov"),
                                   loops: false, muted: true, endBehavior: .hold))
        // Must not crash; nothing else to assert.
    }
}
