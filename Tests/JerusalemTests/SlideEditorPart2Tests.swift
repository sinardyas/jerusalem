import XCTest
import AppKit
import SwiftData
@testable import Jerusalem

/// Phase 8 Part 2 gates (headless). Each test maps to one phase's checkpoint
/// from `docs/PHASE-8-PART-2-PLAN.md`, picking the slice that XCTest can
/// actually observe — the rest of each gate (hardware-dependent UX) is in
/// `docs/DRESS-REHEARSAL.md` §10.1–§10.6.
final class SlideEditorPart2Tests: XCTestCase {

    // MARK: - 8.2.3 — Item.aspectRatio

    func testAspectRatioDefaultsTo16x9AndParsesOverrides() {
        let item = Item(kind: .text, title: "T")
        XCTAssertEqual(item.aspectRatioValue, 16.0 / 9.0, accuracy: 1e-9)
        item.aspectRatio = "4:3"
        XCTAssertEqual(item.aspectRatioValue, 4.0 / 3.0, accuracy: 1e-9)
        item.aspectRatio = "garbage"
        XCTAssertEqual(item.aspectRatioValue, 16.0 / 9.0, accuracy: 1e-9)
    }

    // MARK: - Inspector tabs (Format · Arrange · Slide)

    func testInspectorTabAutoSwitchAndCases() {
        // Selecting an object focuses Format; deselecting returns to Slide.
        XCTAssertEqual(InspectorTab.onSelectionChange(hasSelection: true), .format)
        XCTAssertEqual(InspectorTab.onSelectionChange(hasSelection: false), .slide)
        // The segmented bar's order is fixed left-to-right.
        XCTAssertEqual(InspectorTab.allCases, [.format, .arrange, .slide])
        XCTAssertEqual(InspectorTab.allCases.map(\.title), ["Format", "Arrange", "Slide"])
    }

    // MARK: - Canvas zoom (pinch / ⌘-scroll math)

    func testCanvasZoomClampsAndApplies() {
        XCTAssertEqual(CanvasZoomMath.clamp(5), 2.0, accuracy: 1e-9)        // upper bound
        XCTAssertEqual(CanvasZoomMath.clamp(0.1), 0.5, accuracy: 1e-9)      // lower bound
        // Pinch out by 50% from 1.0 → 1.5; an extreme magnify clamps to 2.0.
        XCTAssertEqual(CanvasZoomMath.applying(magnify: 0.5, to: 1.0), 1.5, accuracy: 1e-9)
        XCTAssertEqual(CanvasZoomMath.applying(magnify: 5, to: 1.0), 2.0, accuracy: 1e-9)
        // ⌘-scroll adds the (pre-scaled) delta, clamped.
        XCTAssertEqual(CanvasZoomMath.applying(scroll: 0.2, to: 1.0), 1.2, accuracy: 1e-9)
        XCTAssertEqual(CanvasZoomMath.applying(scroll: -10, to: 1.0), 0.5, accuracy: 1e-9)
    }

    // MARK: - 8.3.1 — Text styling depth

    func testJustifyAlignmentRoundTripsThroughSnapshot() {
        let element = SlideElement(kind: .text, order: 0, text: "Hi")
        element.alignment = .justified
        let snapshot = RenderableElement(element)
        XCTAssertEqual(snapshot.alignment, .justified)
    }

    func testTypographyDepthFieldsCopyIntoRenderable() {
        let element = SlideElement(kind: .text, order: 0, text: "Hi")
        element.lineSpacingMultiplier = 2.0
        element.letterSpacing = 5
        element.strokeWidth = 8
        element.strokeColorHex = "#FF0000"
        element.shadowBlur = 30
        element.shadowOffsetY = -10
        element.shadowColorHex = "#00FF00CC"
        element.isUnderlined = true
        let snapshot = RenderableElement(element)
        XCTAssertEqual(snapshot.lineSpacingMultiplier, 2.0, accuracy: 1e-9)
        XCTAssertEqual(snapshot.letterSpacing, 5, accuracy: 1e-9)
        XCTAssertEqual(snapshot.strokeWidth, 8, accuracy: 1e-9)
        XCTAssertEqual(snapshot.strokeColorHex, "#FF0000")
        XCTAssertEqual(snapshot.shadowBlur, 30, accuracy: 1e-9)
        XCTAssertEqual(snapshot.shadowOffsetY, -10, accuracy: 1e-9)
        XCTAssertEqual(snapshot.shadowColorHex, "#00FF00CC")
        XCTAssertTrue(snapshot.isUnderlined)
    }

    /// Underlined text writes more non-background pixels than the same text
    /// without an underline (the underline rule fills extra rows below glyphs).
    func testUnderlinedTextRasterizesExtraPixels() throws {
        var withUnderline = renderableText("HELLO")
        withUnderline.isUnderlined = true
        let without = renderableText("HELLO")

        let underlineSlide = RenderableSlide(backgroundColorHex: "#000000",
                                             elements: [withUnderline])
        let plainSlide = RenderableSlide(backgroundColorHex: "#000000",
                                         elements: [without])
        let size = CGSize(width: 480, height: 270)
        let a = try XCTUnwrap(SlideRenderer.makeImage(underlineSlide, pixelSize: size))
        let b = try XCTUnwrap(SlideRenderer.makeImage(plainSlide, pixelSize: size))
        XCTAssertGreaterThan(nonBlackPixelCount(a), nonBlackPixelCount(b))
    }

    // MARK: - 8.3.2 — Gradient background

    func testGradientBackgroundDiffersAtTopVsBottom() throws {
        let slide = RenderableSlide(
            backgroundKind: .gradient,
            backgroundColorHex: "#FF0000",
            elements: [],
            gradientHex2: "#0000FF",
            gradientAngle: 90)   // top → bottom in renderer's coordinates
        let image = try XCTUnwrap(
            SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 100, height: 100)))
        let top = pixelRGB(image, x: 50, y: 5)
        let bottom = pixelRGB(image, x: 50, y: 95)
        // Top and bottom shouldn't both be the same color — that's the
        // whole point of a gradient.
        XCTAssertFalse(top.r == bottom.r && top.g == bottom.g && top.b == bottom.b,
                       "Gradient produced uniform output: top=\(top) bottom=\(bottom)")
    }

    func testColorBackgroundKindFillsTheWholeSlide() throws {
        let slide = RenderableSlide(
            backgroundKind: .color,
            backgroundColorHex: "#FF0000",
            elements: [])
        let image = try XCTUnwrap(
            SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 80, height: 80)))
        let top = pixelRGB(image, x: 40, y: 4)
        let bottom = pixelRGB(image, x: 40, y: 76)
        XCTAssertEqual(top.r, 255); XCTAssertEqual(top.g, 0); XCTAssertEqual(top.b, 0)
        XCTAssertEqual(bottom.r, top.r)
        XCTAssertEqual(bottom.g, top.g)
        XCTAssertEqual(bottom.b, top.b)
    }

    // MARK: - 8.3.3 — Theme.copy(from:)

    func testThemeCopyCapturesElementTypography() {
        let theme = Theme.makeDefault()
        let element = SlideElement(kind: .text, order: 0, text: "Hi")
        element.fontName = "Georgia"
        element.fontSize = 64
        element.colorHex = "#FF00FF"
        element.alignment = .trailing
        element.isBold = false
        element.isItalic = true
        element.isUnderlined = true
        element.hasShadow = false
        element.hasStroke = true
        element.autoFit = false
        element.lineSpacingMultiplier = 1.6
        element.letterSpacing = 4
        element.strokeWidth = 5
        element.strokeColorHex = "#00FF00"
        element.shadowBlur = 18
        element.shadowOffsetY = -8
        element.shadowColorHex = "#FFFFFF88"

        theme.copy(from: element)
        XCTAssertEqual(theme.fontName, "Georgia")
        XCTAssertEqual(theme.fontSize, 64, accuracy: 1e-9)
        XCTAssertEqual(theme.textColorHex, "#FF00FF")
        XCTAssertEqual(theme.alignment, .trailing)
        XCTAssertFalse(theme.isBold)
        XCTAssertTrue(theme.isItalic)
        XCTAssertTrue(theme.isUnderlined)
        XCTAssertFalse(theme.hasShadow)
        XCTAssertTrue(theme.hasStroke)
        XCTAssertFalse(theme.autoFit)
        XCTAssertEqual(theme.lineSpacingMultiplier, 1.6, accuracy: 1e-9)
        XCTAssertEqual(theme.letterSpacing, 4, accuracy: 1e-9)
        XCTAssertEqual(theme.strokeWidth, 5, accuracy: 1e-9)
        XCTAssertEqual(theme.strokeColorHex, "#00FF00")
        XCTAssertEqual(theme.shadowBlur, 18, accuracy: 1e-9)
        XCTAssertEqual(theme.shadowOffsetY, -8, accuracy: 1e-9)
        XCTAssertEqual(theme.shadowColorHex, "#FFFFFF88")
    }

    /// Set-as-default → Add Text on a new slide should yield an element that
    /// carries the same typography the theme just absorbed.
    func testThemeAppliedAfterCopyProducesMatchingElement() {
        let theme = Theme.makeDefault()
        let source = SlideElement(kind: .text, order: 0, text: "Source")
        source.fontName = "Menlo"
        source.colorHex = "#123456"
        source.letterSpacing = 7
        theme.copy(from: source)

        let fresh = SlideElement(kind: .text, order: 0, text: "New")
        theme.apply(to: fresh)
        XCTAssertEqual(fresh.fontName, "Menlo")
        XCTAssertEqual(fresh.colorHex, "#123456")
        XCTAssertEqual(fresh.letterSpacing, 7, accuracy: 1e-9)
    }

    // MARK: - Persistence smoke: the new fields survive a context save

    @MainActor
    func testNewSlideElementAndSlideFieldsPersistAcrossContexts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jer-part2-\(UUID().uuidString).store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let configuration = ModelConfiguration(schema: Persistence.schema, url: url)

        // Write
        do {
            let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
            let context = ModelContext(container)
            let item = Item(kind: .text, title: "T")
            item.aspectRatio = "4:3"
            let slide = Slide(order: 0)
            slide.backgroundKind = .gradient
            slide.gradientHex2 = "#ABCDEF"
            slide.gradientAngle = 45
            let element = SlideElement(kind: .text, text: "Hi")
            element.lineSpacingMultiplier = 1.9
            element.letterSpacing = 3
            element.strokeWidth = 7
            element.isUnderlined = true
            slide.elements = [element]
            item.slides = [slide]
            context.insert(item)
            try context.save()
        }

        // Read back
        let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<Item>())
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.aspectRatio, "4:3")
        let slide = try XCTUnwrap(item.orderedSlides.first)
        XCTAssertEqual(slide.backgroundKind, .gradient)
        XCTAssertEqual(slide.gradientHex2, "#ABCDEF")
        XCTAssertEqual(slide.gradientAngle, 45, accuracy: 1e-9)
        let element = try XCTUnwrap(slide.orderedElements.first)
        XCTAssertEqual(element.lineSpacingMultiplier, 1.9, accuracy: 1e-9)
        XCTAssertEqual(element.letterSpacing, 3, accuracy: 1e-9)
        XCTAssertEqual(element.strokeWidth, 7, accuracy: 1e-9)
        XCTAssertTrue(element.isUnderlined)
    }

    // MARK: - Helpers

    private func renderableText(_ text: String) -> RenderableElement {
        RenderableElement(
            kind: .text, text: text,
            x: 0.08, y: 0.30, width: 0.84, height: 0.40,
            fontName: "Avenir Next", fontSize: 64, colorHex: "#FFFFFF",
            alignment: .center, isBold: true, isItalic: false,
            isUnderlined: false,
            hasShadow: false, hasStroke: false, autoFit: false,
            imageFilename: nil)
    }

    private func nonBlackPixelCount(_ image: CGImage) -> Int {
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

    private struct RGB { let r: Int; let g: Int; let b: Int }

    private func pixelRGB(_ image: CGImage, x: Int, y: Int) -> RGB {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return RGB(r: 0, g: 0, b: 0) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = (y * width + x) * 4
        return RGB(r: Int(data[index]), g: Int(data[index + 1]), b: Int(data[index + 2]))
    }
}
