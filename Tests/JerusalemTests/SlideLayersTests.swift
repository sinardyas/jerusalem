import XCTest
import AppKit
@testable import Jerusalem

/// Phase 8.6 gate: the Layers panel's pure reorder math, the single-ordered-pass
/// renderer (any object can stack above/below any other), and the per-element
/// layer label.
final class SlideLayersTests: XCTestCase {

    // MARK: - SlideLayers.reorder

    /// Dragging the back-most layer to the front (display top) makes it the
    /// highest `order`; the others shift down.
    func testReorderMovesBackElementToFront() {
        let a = SlideElement(kind: .text, order: 0)   // back
        let b = SlideElement(kind: .text, order: 1)
        let c = SlideElement(kind: .text, order: 2)   // front
        // Front-first display = [c, b, a]; drag `a` (index 2) to the top (0).
        SlideLayers.reorder(frontFirst: [c, b, a], from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(a.order, 2, "moved-to-front element gets the highest order")
        XCTAssertEqual(c.order, 1)
        XCTAssertEqual(b.order, 0, "back-most element gets order 0")
    }

    /// Dragging the front layer to the back inverts the relevant orders.
    func testReorderMovesFrontElementToBack() {
        let a = SlideElement(kind: .text, order: 0)
        let b = SlideElement(kind: .text, order: 1)
        let c = SlideElement(kind: .text, order: 2)   // front (display index 0)
        SlideLayers.reorder(frontFirst: [c, b, a], from: IndexSet(integer: 0), to: 3)
        // Display becomes [b, a, c] → orders b=2, a=1, c=0.
        XCTAssertEqual(c.order, 0, "moved-to-back element gets order 0")
        XCTAssertEqual(b.order, 2)
        XCTAssertEqual(a.order, 1)
    }

    // MARK: - Renderer single ordered pass

    /// Two full-slide shapes: whichever has the higher `order` (drawn last) wins
    /// the center pixel — proving the renderer stacks by order across elements.
    func testRendererDrawsElementsInLayerOrder() throws {
        let black = shape(fill: "#000000")
        let white = shape(fill: "#FFFFFF")
        let size = CGSize(width: 80, height: 80)

        // elements are passed back→front; last drawn wins.
        let whiteOnTop = RenderableSlide(backgroundColorHex: "#222222", elements: [black, white])
        let blackOnTop = RenderableSlide(backgroundColorHex: "#222222", elements: [white, black])

        let a = try XCTUnwrap(SlideRenderer.makeImage(whiteOnTop, pixelSize: size))
        let b = try XCTUnwrap(SlideRenderer.makeImage(blackOnTop, pixelSize: size))
        XCTAssertGreaterThan(centerRed(a), 200, "white shape on top → white center")
        XCTAssertLessThan(centerRed(b), 60, "black shape on top → black center")
    }

    // MARK: - layerName

    func testLayerNameForEachKind() {
        let text = SlideElement(kind: .text, text: "  Amazing grace  ")
        XCTAssertEqual(text.layerName, "Amazing grace")

        let empty = SlideElement(kind: .text, text: "   ")
        XCTAssertEqual(empty.layerName, "Text")

        let image = SlideElement(kind: .image)
        image.imageFilename = "logo.png"
        XCTAssertEqual(image.layerName, "logo.png")

        let rect = SlideElement(kind: .shape); rect.shapeType = .rectangle
        XCTAssertEqual(rect.layerName, "Rectangle")
        let ellipse = SlideElement(kind: .shape); ellipse.shapeType = .ellipse
        XCTAssertEqual(ellipse.layerName, "Ellipse")
        let rounded = SlideElement(kind: .shape); rounded.shapeType = .roundedRectangle
        XCTAssertEqual(rounded.layerName, "Rounded Rectangle")
    }

    // MARK: - Helpers

    private func shape(fill: String) -> RenderableElement {
        RenderableElement(
            kind: .shape, text: nil,
            x: 0, y: 0, width: 1, height: 1,
            fontName: "Avenir Next", fontSize: 48, colorHex: "#FFFFFF",
            alignment: .center, isBold: false, isItalic: false,
            hasShadow: false, hasStroke: false, autoFit: false,
            imageFilename: nil,
            shapeType: .rectangle, fillColorHex: fill, cornerRadius: 0)
    }

    private func centerRed(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = ((height / 2) * width + width / 2) * 4
        return Int(data[index])
    }
}
