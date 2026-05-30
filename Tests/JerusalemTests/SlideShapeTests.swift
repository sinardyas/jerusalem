import XCTest
import AppKit
import SwiftData
@testable import Jerusalem

/// Phase 8.4 gate (headless): the new `shape` element kind round-trips through
/// the value snapshot, rasterizes through the single ``SlideRenderer`` path, and
/// persists across SwiftData contexts. The interactive parts (adding/dragging a
/// shape, the shape inspector) are verified by running the app.
final class SlideShapeTests: XCTestCase {

    private func shapeElement(_ type: ShapeType,
                              fill: String = "#FFFFFF",
                              frame: (Double, Double, Double, Double) = (0, 0, 1, 1)) -> RenderableElement {
        RenderableElement(
            kind: .shape, text: nil,
            x: frame.0, y: frame.1, width: frame.2, height: frame.3,
            fontName: "Avenir Next", fontSize: 48, colorHex: "#FFFFFF",
            alignment: .center, isBold: false, isItalic: false,
            hasShadow: false, hasStroke: false, autoFit: false,
            imageFilename: nil,
            shapeType: type, fillColorHex: fill, cornerRadius: 0)
    }

    // MARK: - Snapshot round-trip

    func testShapeRoundTripsThroughRenderableElement() {
        let element = SlideElement(kind: .shape, order: 0)
        element.shapeType = .ellipse
        element.fillColorHex = "#FF0000"
        element.cornerRadius = 24
        let snapshot = RenderableElement(element)
        XCTAssertEqual(snapshot.kind, .shape)
        XCTAssertEqual(snapshot.shapeType, .ellipse)
        XCTAssertEqual(snapshot.fillColorHex, "#FF0000")
        XCTAssertEqual(snapshot.cornerRadius, 24, accuracy: 1e-9)
    }

    func testUnknownShapeAndKindRawFallBackSafely() {
        XCTAssertNil(SlideElementKind(rawValue: "bogus"))
        XCTAssertNil(ShapeType(rawValue: "bogus"))
        // A fresh shape element exposes the default `.rectangle`.
        XCTAssertEqual(SlideElement(kind: .shape, order: 0).shapeType, .rectangle)
    }

    // MARK: - Rendering

    func testShapeRendersDistinctPixels() throws {
        let slide = RenderableSlide(backgroundColorHex: "#000000",
                                    elements: [shapeElement(.rectangle, fill: "#FFFFFF",
                                                            frame: (0.2, 0.2, 0.6, 0.6))])
        let image = try XCTUnwrap(
            SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 200, height: 200)))
        // A white rectangle on black must leave a large block of non-black pixels.
        XCTAssertGreaterThan(nonBackgroundPixelCount(image), 1000)
    }

    func testEllipseLeavesBoundingBoxCornersBackground() throws {
        let slide = RenderableSlide(backgroundColorHex: "#000000",
                                    elements: [shapeElement(.ellipse, fill: "#FFFFFF",
                                                            frame: (0, 0, 1, 1))])
        let image = try XCTUnwrap(
            SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 100, height: 100)))
        let center = pixelRGB(image, x: 50, y: 50)
        let corner = pixelRGB(image, x: 2, y: 2)
        XCTAssertGreaterThan(center.r, 200, "Ellipse center should be filled white")
        XCTAssertLessThan(corner.r, 40, "Ellipse must leave its bounding-box corner black")
    }

    func testShapeBorderUsesStrokeFields() throws {
        // A small filled shape with a thick contrasting border should still
        // render (border path doesn't crash and adds pixels). Smoke-level.
        var element = shapeElement(.roundedRectangle, fill: "#000000", frame: (0.3, 0.3, 0.4, 0.4))
        element.cornerRadius = 20
        element.hasStroke = true
        element.strokeColorHex = "#FFFFFF"
        element.strokeWidth = 6
        let slide = RenderableSlide(backgroundColorHex: "#000000", elements: [element])
        let image = try XCTUnwrap(
            SlideRenderer.makeImage(slide, pixelSize: CGSize(width: 200, height: 200)))
        XCTAssertGreaterThan(nonBackgroundPixelCount(image), 50, "White border should draw pixels")
    }

    // MARK: - Persistence

    @MainActor
    func testShapeFieldsPersistAcrossContexts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jer-shape-\(UUID().uuidString).store")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let configuration = ModelConfiguration(schema: Persistence.schema, url: url)

        do {
            let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
            let context = ModelContext(container)
            let item = Item(kind: .text, title: "T")
            let slide = Slide(order: 0)
            let element = SlideElement(kind: .shape, order: 0)
            element.shapeType = .roundedRectangle
            element.fillColorHex = "#12AB34"
            element.cornerRadius = 18
            slide.elements = [element]
            item.slides = [slide]
            context.insert(item)
            try context.save()
        }

        let container = try ModelContainer(for: Persistence.schema, configurations: configuration)
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<Item>())
        let item = try XCTUnwrap(items.first)
        let slide = try XCTUnwrap(item.orderedSlides.first)
        let element = try XCTUnwrap(slide.orderedElements.first)
        XCTAssertEqual(element.kind, .shape)
        XCTAssertEqual(element.shapeType, .roundedRectangle)
        XCTAssertEqual(element.fillColorHex, "#12AB34")
        XCTAssertEqual(element.cornerRadius, 18, accuracy: 1e-9)
    }

    // MARK: - Helpers

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
