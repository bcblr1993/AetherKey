import Foundation

/// Pangu Spacing engine for automatic half-width spacing between CJK and alphanumeric characters.
/// Adheres strictly to standard Chinese typography conventions.
public final class PanguSpacing: Sendable {
    public static let shared = PanguSpacing()
    
    // CJK Unicode ranges
    // Unified Ideographs: 0x4E00 - 0x9FFF
    // Extensions A-G, Compatibility: 0x3400 - 0x4DBF, 0x20000 - 0x2A6DF, 0xF900 - 0xFAFF
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) ||
               (0x3400...0x4DBF).contains(v) ||
               (0x20000...0x2CEAF).contains(v) ||
               (0xF900...0xFAFF).contains(v) ||
               (0x2E80...0x2EFF).contains(v) ||
               (0x3000...0x303F).contains(v) // CJK Symbols & Punctuation
    }
    
    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        return (scalar.value >= 0x30 && scalar.value <= 0x39) || // 0-9
               (scalar.value >= 0x41 && scalar.value <= 0x5A) || // A-Z
               (scalar.value >= 0x61 && scalar.value <= 0x7A)    // a-z
    }
    
    /// Formats a complete text block with Pangu Spacing.
    public func spacing(_ text: String) -> String {
        guard text.count > 1 else { return text }
        
        var result = ""
        result.reserveCapacity(text.count + 8)
        
        let scalars = Array(text.unicodeScalars)
        for i in 0..<scalars.count {
            result.unicodeScalars.append(scalars[i])
            if i + 1 < scalars.count {
                let current = scalars[i]
                let next = scalars[i + 1]
                
                let currentIsCJK = Self.isCJK(current)
                let nextIsCJK = Self.isCJK(next)
                let currentIsAlpha = Self.isAlphanumeric(current)
                let nextIsAlpha = Self.isAlphanumeric(next)
                
                // CJK followed by Alphanumeric -> insert space
                if currentIsCJK && nextIsAlpha {
                    result.append(" ")
                }
                // Alphanumeric followed by CJK -> insert space
                else if currentIsAlpha && nextIsCJK {
                    result.append(" ")
                }
            }
        }
        return result
    }
    
    /// Determines if a leading space should be prepended to the committed text based on the preceding character.
    public func shouldPrependSpace(preceding: Character?, committing: String) -> Bool {
        guard let preceding = preceding, let firstChar = committing.first else { return false }
        guard let prevScalar = preceding.unicodeScalars.first,
              let firstScalar = firstChar.unicodeScalars.first else { return false }
        
        if Self.isCJK(prevScalar) && Self.isAlphanumeric(firstScalar) {
            return true
        }
        if Self.isAlphanumeric(prevScalar) && Self.isCJK(firstScalar) {
            return true
        }
        return false
    }
    
    /// Formats the string to be committed, incorporating surrounding context awareness.
    public func formatCommitText(preceding: Character?, committing: String) -> String {
        var formatted = spacing(committing)
        if shouldPrependSpace(preceding: preceding, committing: formatted) {
            formatted = " " + formatted
        }
        return formatted
    }
}
