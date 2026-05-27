import Foundation
import SwiftData

/// A reusable visual style applied to slides. The MVP ships one default theme;
/// a full theme library is a later phase.
@Model
final class Theme {
    var uuid: UUID = UUID()
    var name: String = "Default Dark"
    var backgroundColorHex: String = "#0F172A"
    var fontName: String = "Avenir Next"
    var fontSize: Double = 48
    var textColorHex: String = "#FFFFFF"

    init(name: String = "Default Dark") {
        self.name = name
    }
}
