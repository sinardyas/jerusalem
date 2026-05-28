import XCTest
import AppKit
@testable import Jerusalem

/// Phase 2 gate: the shared renderer produces an image at the requested size and
/// auto-fit shrinks oversized text to fit its box.
final class SlideRenderingTests: XCTestCase {

    private func textElement(_ text: String) -> RenderableElement {
        RenderableElement(
            kind: .text, text: text,
            x: 0.08, y: 0.30, width: 0.84, height: 0.40,
            fontName: "Avenir Next", fontSize: 48, colorHex: "#FFFFFF",
            alignment: .center, isBold: true, isItalic: false,
            hasShadow: true, hasStroke: false, autoFit: true, imageFilename: nil)
    }

    func testRendersImageAtRequestedPixelSize() {
        let slide = RenderableSlide(
            backgroundColorHex: "#1E3A8A",
            elements: [textElement("Amazing grace! How sweet the sound")])
        let image = SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 320, height: 180))
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, 320)
        XCTAssertEqual(image?.height, 180)
    }

    func testAutoFitShrinksOversizedText() {
        let box = CGSize(width: 400, height: 120)
        let longText = String(repeating: "Amazing grace how sweet the sound ", count: 6)
        let fitted = SlideRenderer.fittedFontSize(
            text: longText, fontName: "Avenir Next", isBold: true, isItalic: false,
            baseSize: 200, boxSize: box)
        XCTAssertLessThan(fitted, 200)
    }

    func testAutoFitLeavesFittingTextUnchanged() {
        let box = CGSize(width: 600, height: 240)
        let fitted = SlideRenderer.fittedFontSize(
            text: "Hi", fontName: "Avenir Next", isBold: true, isItalic: false,
            baseSize: 40, boxSize: box)
        XCTAssertEqual(fitted, 40, accuracy: 0.001)
    }

    func testStyledTextRasterizesPixels() throws {
        let slide = RenderableSlide(backgroundColorHex: "#000000",
                                    elements: [textElement("HELLO")])
        let image = try XCTUnwrap(
            SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 480, height: 270)))
        // White text on a black background must leave many non-black pixels.
        XCTAssertGreaterThan(nonBackgroundPixelCount(image), 200)
    }

    /// Counts pixels that differ noticeably from black — i.e., drawn glyphs.
    private func nonBackgroundPixelCount(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4)
        where data[index] > 40 || data[index + 1] > 40 || data[index + 2] > 40 {
            count += 1
        }
        return count
    }

    func testMotionBackgroundLeavesTransparentBackground() throws {
        let cue = VideoCue(url: URL(fileURLWithPath: "/tmp/none.mov"),
                           loops: true, muted: true, endBehavior: .hold)
        let motion = RenderableSlide(backgroundKind: .video,
                                     backgroundColorHex: "#1E3A8A",
                                     elements: [textElement("Hi")], backgroundVideo: cue)
        let solid = RenderableSlide(backgroundColorHex: "#1E3A8A",
                                    elements: [textElement("Hi")])

        let motionImage = try XCTUnwrap(
            SlideRenderer.makeImage(motion, pixelSize: CGSize(width: 240, height: 135)))
        let solidImage = try XCTUnwrap(
            SlideRenderer.makeImage(solid, pixelSize: CGSize(width: 240, height: 135)))

        XCTAssertGreaterThan(transparentPixelCount(motionImage), 0)  // motion bg shows through
        XCTAssertEqual(transparentPixelCount(solidImage), 0)         // solid bg is fully opaque
    }

    private func transparentPixelCount(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] == 0 {
            count += 1
        }
        return count
    }

    func testImageBackgroundIsDrawn() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jx-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("red.png")
        try writeSolidPNG(.red, size: 8, to: url)

        var slide = RenderableSlide(backgroundKind: .image,
                                    backgroundColorHex: "#000000", elements: [])
        slide.backgroundImageURL = url

        let image = try XCTUnwrap(SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 100, height: 100)))
        let (r, g, b) = centerRGB(image)
        XCTAssertGreaterThan(r, 150)   // background is the red image, not black
        XCTAssertLessThan(g, 90)
        XCTAssertLessThan(b, 90)
    }

    private func writeSolidPNG(_ color: NSColor, size: Int, to url: URL) throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func centerRGB(_ image: CGImage) -> (Int, Int, Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (0, 0, 0) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = ((height / 2) * width + width / 2) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }
}
