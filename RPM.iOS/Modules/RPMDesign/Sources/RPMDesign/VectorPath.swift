import Foundation
import CoreGraphics

/// A path written the way a drawing program writes one.
///
/// The rpm wordmark is one long string of SVG path data. It is kept as a string rather than as an
/// image, for the same reason the desktop app does this. It paints on the first frame, at any size.
/// There is no file to load, and nothing that can go missing. The price is that the string has to
/// be read, which takes a small parser.
///
/// Only the commands that letterforms are made of are read: move, line, horizontal, vertical, cubic,
/// quadratic, close. A path with an arc in it is drawn up to the arc, and no further. The alternative
/// would be a parser twice that size for a command that no glyph uses.
///
/// Quadratics are needed because a TrueType outline is made of them. Anything taken from a font file,
/// rather than from a drawing program, is one long run of Q commands. The artist mark is exactly that.
/// Without quadratic support, the mark would draw as a dot.
public enum VectorPath {
    /// The result is a **copy**, so it is immutable. It can be held in a `static let` without relying
    /// on anything the compiler cannot check.
    public static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()

        var here = CGPoint.zero
        var started = CGPoint.zero
        var reader = Reader(data)

        while let command = reader.command() {
            let relative = command.isLowercase
            func point() -> CGPoint {
                let x = reader.number() ?? 0, y = reader.number() ?? 0
                return relative ? CGPoint(x: here.x + x, y: here.y + y) : CGPoint(x: x, y: y)
            }

            switch command.lowercased() {
            case "m":
                here = point()
                started = here
                path.move(to: here)

                // A move followed by more numbers is a line, as the format defines it. The pen is
                // already down.
                while reader.hasNumber {
                    here = point()
                    path.addLine(to: here)
                }

            case "l":
                repeat { here = point(); path.addLine(to: here) } while reader.hasNumber

            case "h":
                repeat {
                    let x = reader.number() ?? 0
                    here.x = relative ? here.x + x : x
                    path.addLine(to: here)
                } while reader.hasNumber

            case "v":
                repeat {
                    let y = reader.number() ?? 0
                    here.y = relative ? here.y + y : y
                    path.addLine(to: here)
                } while reader.hasNumber

            case "c":
                repeat {
                    let first = point(), second = point()
                    here = point()
                    path.addCurve(to: here, control1: first, control2: second)
                } while reader.hasNumber

            case "q":
                repeat {
                    let control = point()
                    here = point()
                    path.addQuadCurve(to: here, control: control)
                } while reader.hasNumber

            case "z":
                path.closeSubpath()
                here = started

            default:
                // A command this code does not draw. Stop here. Carrying on would use a pen position
                // that is now a guess.
                return path.copy() ?? path
            }
        }

        return path.copy() ?? path
    }

    /// The same path, scaled to sit inside a box and centred in it, keeping its proportions. This is
    /// what `Stretch="Uniform"` does in XAML. The wordmark cannot be drawn without it, because its
    /// coordinates run from -143 to 52 and mean nothing to a view.
    ///
    /// **Not flipped.** These are SVG coordinates, where y grows downward, as on a screen. The glyph
    /// sits above the baseline at negative y, and the descender of the p hangs below it at positive y.
    /// Flipping them would draw the wordmark upside down. Negative y can look like font coordinates,
    /// but no flip is needed.
    public static func fitted(_ path: CGPath, in box: CGRect) -> CGPath {
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0, box.width > 0, box.height > 0 else { return path }

        let scale = Swift.min(box.width / bounds.width, box.height / bounds.height)
        let width = bounds.width * scale, height = bounds.height * scale

        var transform = CGAffineTransform.identity
            .translatedBy(x: box.minX + (box.width - width) / 2,
                          y: box.minY + (box.height - height) / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)

        return path.copy(using: &transform) ?? path
    }

    /// A cursor over the data.
    private struct Reader {
        private let text: [Character]
        private var at = 0

        init(_ data: String) { text = Array(data) }

        mutating func command() -> Character? {
            skip()
            guard at < text.count, text[at].isLetter else { return nil }
            defer { at += 1 }
            return text[at]
        }

        var hasNumber: Bool {
            var ahead = at
            while ahead < text.count, text[ahead] == " " || text[ahead] == "," { ahead += 1 }
            guard ahead < text.count else { return false }
            return text[ahead].isNumber || text[ahead] == "-" || text[ahead] == "+"
                || text[ahead] == "."
        }

        mutating func number() -> Double? {
            skip()
            let from = at

            if at < text.count, text[at] == "-" || text[at] == "+" { at += 1 }
            while at < text.count, text[at].isNumber || text[at] == "." { at += 1 }

            // Exponents are read too. A drawing program can write them. A path that stopped at one would
            // be a wordmark with a corner missing.
            if at < text.count, text[at] == "e" || text[at] == "E" {
                at += 1
                if at < text.count, text[at] == "-" || text[at] == "+" { at += 1 }
                while at < text.count, text[at].isNumber { at += 1 }
            }

            guard at > from else { return nil }
            return Double(String(text[from..<at]))
        }

        private mutating func skip() {
            while at < text.count, text[at] == " " || text[at] == "," || text[at] == "\n" { at += 1 }
        }
    }
}
