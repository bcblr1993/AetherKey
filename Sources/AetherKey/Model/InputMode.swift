import Foundation

/// Active IME input mode.
public enum InputMode: String, CaseIterable, Sendable {
    case chinese = "中"
    case english = "EN"
    case vMode   = "v 宏"
    
    public var badgeTitle: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        case .vMode:   return "v 宏"
        }
    }
    
    public var accentColorHex: String {
        switch self {
        case .chinese: return "#00E5FF" // Neon Cyan
        case .english: return "#9E9E9E" // Titanium Gray
        case .vMode:   return "#FF9100" // Electric Amber
        }
    }
}
