import SwiftData
import Foundation
import SwiftUI

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String?

    var contacts: [Contact]?

    var color: Color {
        guard let hex = colorHex else { return .accentColor }
        return Color(hex: hex)
    }

    init(name: String, colorHex: String? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
