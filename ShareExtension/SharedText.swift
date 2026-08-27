import Foundation

enum SharedText {
    static func normalized(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            result.append(plainCharacter(for: scalar))
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainCharacter(for scalar: Unicode.Scalar) -> String {
        let value = scalar.value

        if (0xFF01...0xFF5E).contains(value), let ascii = Unicode.Scalar(value - 0xFEE0) {
            return String(Character(ascii))
        }

        if let digit = mathDigit(value) {
            return String(digit)
        }

        if let letter = mathLatin(value) ?? letterlike(value) {
            return String(letter)
        }

        return String(Character(scalar))
    }

    private static func mathLatin(_ value: UInt32) -> Character? {
        let bases: [UInt32] = [
            0x1D400, 0x1D434, 0x1D468, 0x1D49C, 0x1D4D0,
            0x1D504, 0x1D538, 0x1D56C, 0x1D5A0, 0x1D5D4,
            0x1D608, 0x1D63C, 0x1D670,
        ]
        for base in bases {
            guard value >= base else { continue }
            let offset = Int(value - base)
            if offset < 26, let scalar = Unicode.Scalar(0x41 + UInt32(offset)) {
                return Character(scalar)
            }
            if offset < 52, let scalar = Unicode.Scalar(0x61 + UInt32(offset - 26)) {
                return Character(scalar)
            }
        }
        return nil
    }

    private static func mathDigit(_ value: UInt32) -> Character? {
        let bases: [UInt32] = [0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6]
        for base in bases {
            guard value >= base else { continue }
            let offset = value - base
            if offset < 10, let scalar = Unicode.Scalar(0x30 + offset) {
                return Character(scalar)
            }
        }
        return nil
    }

    private static func letterlike(_ value: UInt32) -> Character? {
        switch value {
        case 0x2102: return "C"
        case 0x210A: return "g"
        case 0x210B, 0x210C, 0x210D: return "H"
        case 0x210E: return "h"
        case 0x2110, 0x2111: return "I"
        case 0x2112: return "L"
        case 0x2115: return "N"
        case 0x2119: return "P"
        case 0x211A: return "Q"
        case 0x211B, 0x211C, 0x211D: return "R"
        case 0x2124, 0x2128: return "Z"
        case 0x212C: return "B"
        case 0x2130: return "E"
        case 0x2131: return "F"
        case 0x2133: return "M"
        default: return nil
        }
    }
}
