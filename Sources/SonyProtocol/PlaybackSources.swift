import Foundation

// Sony's second command table, adapted from aecca/sound-connect (MIT).
public struct PlaybackDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let playing: Bool
    public init(id: String, name: String, playing: Bool) {
        self.id = id; self.name = name; self.playing = playing
    }
}

public enum DeviceListLayout: UInt8 {
    case classic = 0, withClass = 2
    public var query: [UInt8] { [0x36, rawValue] }
}

public enum SourceReply: Equatable {
    case capabilities(DeviceListLayout?)
    case devices([PlaybackDevice])
    case switchAcknowledged
}

public enum PlaybackSources {
    public static let capabilityQuery: [UInt8] = [0x06, 0]

    public static func switchCommand(address: String) -> [UInt8]? {
        let bytes = Array(address.utf8)
        guard validAddress(bytes) else { return nil }
        return [0x3c, 1] + bytes
    }

    private static func validAddress(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 17 else { return false }
        return bytes.enumerated().allSatisfy { index, byte in
            index % 3 == 2 ? byte == 0x3a : (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    public static func parse(_ p: [UInt8]) -> SourceReply? {
        guard p.count >= 2 else { return nil }
        switch p[0] {
        case 0x07:
            guard p[1] == 0, p.count >= 3, p.count == 3 + Int(p[2]) * 2 else { return nil }
            let functions = stride(from: 3, to: p.count, by: 2).map { p[$0] }
            let layout: DeviceListLayout? = functions.contains(0x32) || functions.contains(0x33)
                ? .withClass : functions.contains(0x30) ? .classic : nil
            return .capabilities(layout)
        case 0x37, 0x39:
            guard let layout = DeviceListLayout(rawValue: p[1]), p.count >= 4 else { return nil }
            var cursor = 3
            var entries: [(address: String, slot: UInt8, name: String)] = []
            for _ in 0..<Int(p[2]) {
                guard p.count - cursor >= 18 else { return nil }
                let addressBytes = Array(p[cursor..<cursor + 17])
                guard validAddress(addressBytes) else { return nil }
                let address = String(decoding: addressBytes, as: UTF8.self)
                cursor += 17
                let slot = p[cursor]; cursor += 1
                if layout == .withClass {
                    guard p.count - cursor >= 3 else { return nil }
                    cursor += 3
                }
                guard cursor < p.count else { return nil }
                let length = Int(p[cursor]); cursor += 1
                guard p.count - cursor >= length else { return nil }
                let name = String(decoding: p[cursor..<cursor + length], as: UTF8.self)
                cursor += length
                entries.append((address, slot, name))
            }
            guard cursor == p.count - 1 else { return nil }
            let activeSlot = p[cursor]
            let connected = entries.filter { $0.slot != 0 }
            guard Set(connected.map { $0.address.uppercased() }).count == connected.count else { return nil }
            return .devices(connected.map {
                PlaybackDevice(id: $0.address, name: $0.name.isEmpty ? $0.address : $0.name,
                               playing: activeSlot != 0 && $0.slot == activeSlot)
            })
        case 0x3d:
            return p[1] == 1 ? .switchAcknowledged : nil
        default: return nil
        }
    }
}
