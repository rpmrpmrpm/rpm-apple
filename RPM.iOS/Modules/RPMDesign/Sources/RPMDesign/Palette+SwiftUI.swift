#if canImport(SwiftUI)
import SwiftUI

// This file is the bridge to SwiftUI. The palette arithmetic does not import SwiftUI, so it stays
// testable without a UI framework. The one line here turns a palette answer into a value a view can
// paint with.

extension RGB {
    public var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

extension GlassInk {
    /// The lifted colour, ready to paint with.
    public var color: Color { rgb.color }
}

extension Accent {
    /// The drawer look: the three-stop ramp, top to foot.
    public var drawer: LinearGradient {
        LinearGradient(colors: gradient.map(\.color), startPoint: .top, endPoint: .bottom)
    }
}
#endif
