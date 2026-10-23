import Foundation

/// Represents a candidate word or phrase produced by the input engine.
public struct Candidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let comment: String?
    public let pinyin: String?
    public let isVMode: Bool
    public let isEmoji: Bool
    /// Number of raw buffer characters consumed when this candidate is selected (0 = consumes entire buffer).
    public let consumedInputLength: Int
    
    public init(
        id: UUID = UUID(),
        text: String,
        comment: String? = nil,
        pinyin: String? = nil,
        isVMode: Bool = false,
        isEmoji: Bool = false,
        consumedInputLength: Int = 0
    ) {
        self.id = id
        self.text = text
        self.comment = comment
        self.pinyin = pinyin
        self.isVMode = isVMode
        self.isEmoji = isEmoji
        self.consumedInputLength = consumedInputLength
    }
}
