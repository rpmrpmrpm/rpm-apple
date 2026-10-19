import Foundation

/// Only enough protobuf for one message.
///
/// This is not a full protobuf implementation. It has no maps, no packed repeated fields, no zigzag encoding, and no groups.
/// It writes the six fields that ``CastMessage`` uses. It reads any field well enough to skip the ones it does not know.
/// See that type for why no library is used.
enum Protobuf {
    /// The wire types that this protocol uses. The group types are not used. They were removed from proto3, and
    /// they are not in this schema.
    enum Wire: Int, Sendable {
        case varint = 0
        case fixed64 = 1
        case bytes = 2
        case fixed32 = 5
    }

    struct Writer {
        private(set) var bytes = Data()

        mutating func varint(_ field: Int, _ value: Int) {
            tag(field, .varint)
            varint(value)
        }

        mutating func string(_ field: Int, _ value: String) {
            let utf8 = Data(value.utf8)
            tag(field, .bytes)
            varint(utf8.count)
            bytes.append(utf8)
        }

        private mutating func tag(_ field: Int, _ wire: Wire) {
            varint(field << 3 | wire.rawValue)
        }

        /// Seven bits at a time, least significant first. The top bit means that more bytes follow.
        private mutating func varint(_ value: Int) {
            var left = UInt64(bitPattern: Int64(value))

            repeat {
                var byte = UInt8(left & 0x7F)
                left >>= 7
                if left != 0 { byte |= 0x80 }
                bytes.append(byte)
            } while left != 0
        }
    }

    struct Reader {
        private let data: Data
        private var at: Int

        init(_ data: Data) {
            self.data = data
            self.at = data.startIndex
        }

        var done: Bool { at >= data.endIndex }

        mutating func tag() -> (field: Int, wire: Wire)? {
            guard !done, let key = varint(), let wire = Wire(rawValue: Int(key) & 0x07) else {
                return nil
            }
            return (Int(key >> 3), wire)
        }

        mutating func string() -> String? {
            guard let length = varint(), let end = shift(by: Int(length)) else { return nil }
            return String(data: data[at..<end], encoding: .utf8).map { value in
                at = end
                return value
            }
        }

        /// Steps over a field that this code does not know about.
        mutating func skip(_ wire: Wire) -> Bool {
            switch wire {
            case .varint: return varint() != nil
            case .fixed64: return step(by: 8)
            case .fixed32: return step(by: 4)
            case .bytes:
                guard let length = varint() else { return false }
                return step(by: Int(length))
            }
        }

        private mutating func varint() -> UInt64? {
            var value: UInt64 = 0
            var shifted: UInt64 = 0

            while at < data.endIndex {
                let byte = data[at]
                at += 1

                value |= UInt64(byte & 0x7F) << shifted
                if byte & 0x80 == 0 { return value }

                shifted += 7
                // Ten groups of seven bits cover a 64-bit value. More than that means the data is corrupt,
                // not that the number is long.
                if shifted > 63 { return nil }
            }
            return nil
        }

        private mutating func step(by count: Int) -> Bool {
            guard let end = shift(by: count) else { return false }
            at = end
            return true
        }

        private func shift(by count: Int) -> Int? {
            guard count >= 0, data.endIndex - at >= count else { return nil }
            return at + count
        }
    }
}
