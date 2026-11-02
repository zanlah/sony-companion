import Foundation

public enum NoiseMode: String, CaseIterable {
    case cancelling = "Noise cancelling", ambient = "Ambient sound", off = "Off"
    public var symbol: String {
        switch self { case .cancelling: return "waveform.slash"; case .ambient: return "waveform"; case .off: return "power" }
    }
}

public struct NoiseState: Equatable {
    public var mode: NoiseMode
    public var level: Int
    public var focus: Bool
    public var command: [UInt8] {
        [0x68, 0x17, 1, mode == .off ? 0 : 1, mode == .ambient ? 1 : 0, focus ? 1 : 0, UInt8(clamping: min(20, max(1, level)))]
    }
}

public enum EQPreset: UInt8, CaseIterable {
    case off = 0, bright = 0x10, excited, mellow, relaxed, vocal, trebleBoost, bassBoost, speech
    case manual = 0xa0, custom1, custom2
    public var title: String {
        switch self {
        case .off: return "Off"; case .bright: return "Bright"; case .excited: return "Excited"
        case .mellow: return "Mellow"; case .relaxed: return "Relaxed"; case .vocal: return "Vocal"
        case .trebleBoost: return "Treble boost"; case .bassBoost: return "Bass boost"; case .speech: return "Speech"
        case .manual: return "Manual"; case .custom1: return "Custom 1"; case .custom2: return "Custom 2"
        }
    }
}

/// State is populated exclusively by headset replies; nil means unconfirmed.
public struct HeadphoneState {
    public var ready = false
    public var unsupported = false
    public var table2Supported = false
    public var battery: Int?
    public var charging = false
    public var noise: NoiseState?
    public var preset: UInt8?
    public var eqValues: [Int]?
    public var dsee: Bool?
    public var speakToChat: Bool?
    public var codec: String?
    public init() {}

    public static let queries: [[UInt8]] = [[0x22, 0], [0x66, 0x17], [0x56, 0], [0xe6, 1], [0xf6, 0x0c], [0x12, 2]]

    public mutating func apply(_ p: [UInt8]) {
        guard let opcode = p.first else { return }
        switch opcode {
        case 0x01:
            ready = p.count == 8 && p[1] == 0
            unsupported = !ready
            table2Supported = ready && p[7] == 0
        case 0x23, 0x25:
            if p.count >= 4, p[1] == 0, p[2] <= 100 { battery = Int(p[2]); charging = p[3] == 1 }
        case 0x67, 0x69:
            if p.count == 7, p[1] == 0x17 {
                noise = NoiseState(mode: p[3] == 0 ? .off : p[4] == 0 ? .cancelling : .ambient,
                                   level: min(20, max(1, Int(p[6]))), focus: p[5] == 1)
            }
        case 0x57, 0x59:
            if p.count == 10, p[1] == 0, p[3] == 6 {
                preset = p[2]; eqValues = p[4...9].map { Int(min($0, 20)) - 10 }
            }
        case 0xe7, 0xe9:
            if p.count >= 3, p[1] == 1 { dsee = p[2] == 1 }
        case 0xf7, 0xf9:
            if p.count >= 3, p[1] == 0x0c { speakToChat = p[2] == 0 }
        case 0x13, 0x15:
            if p.count >= 3, p[1] == 2 { codec = [1: "SBC", 2: "AAC", 16: "LDAC"][Int(p[2])] ?? "Unknown" }
        default: break
        }
    }

    public static func manualEQ(_ values: [Int]) -> [UInt8]? {
        guard values.count == 6 else { return nil }
        return [0x58, 0, 0xa0, 6] + values.map { UInt8(min(10, max(-10, $0)) + 10) }
    }
}
