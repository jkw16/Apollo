import SwiftUI
import AppKit

enum LyricStyle: String, CaseIterable, Codable, Identifiable {
    case ship = "Ship", fisheye = "Fisheye", visual = "Visual", fisheyeVisual = "Fisheye Visual"
    var id: String { rawValue }
    var usesFisheye: Bool { self == .fisheye || self == .fisheyeVisual }
    var usesBlur: Bool { self == .visual || self == .fisheyeVisual }
}

enum LyricTypeface: String, CaseIterable, Codable, Identifiable {
    case sfPro = "SF Pro", sfRounded = "SF Rounded", newYork = "New York"
    case helvetica = "Helvetica Neue", avenir = "Avenir Next", futura = "Futura", didot = "Didot"
    var id: String { rawValue }
    func font(size: CGFloat) -> Font {
        switch self {
        case .sfPro: return .system(size: size, weight: .bold)
        case .sfRounded: return .system(size: size, weight: .bold, design: .rounded)
        case .newYork: return .system(size: size, weight: .bold, design: .serif)
        case .helvetica: return .custom("HelveticaNeue-Bold", size: size)
        case .avenir: return .custom("AvenirNext-DemiBold", size: size)
        case .futura: return .custom("Futura-Medium", size: size)
        case .didot: return .custom("Didot-Bold", size: size)
        }
    }
}

struct LyricColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }
}

struct LyricAppearance: Codable, Equatable {
    var style: LyricStyle = .visual
    var typeface: LyricTypeface = .sfRounded
    var textSize: Double = 33
    var keepScreenAwake = false
    var desktopVisible = false
    var displayID: String = "automatic"
    var autoSync = false
    var lyricText = LyricColor(1, 0.33, 0.35)
    var highlight = LyricColor(1, 1, 1)
    var secondaryText = LyricColor(0.73, 0.73, 0.73)

    static let storageKey = "apollo.lyricAppearance.v1"
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        value.textSize = value.textSize.isFinite ? min(60, max(20, value.textSize)) : 33
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }
    mutating func resetColors() {
        let defaults = Self()
        lyricText = defaults.lyricText; highlight = defaults.highlight; secondaryText = defaults.secondaryText
        autoSync = false
    }
}

extension NSScreen {
    var apolloDisplayID: String {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName
    }
}
