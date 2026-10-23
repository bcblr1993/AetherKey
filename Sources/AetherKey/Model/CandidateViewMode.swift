import Foundation

/// Sogou-style Candidate Presentation Style:
/// - paging: Traditional fixed-page pagination mode (翻页模式, e.g. 7 candidates per page with -/= or [/] page turning)
/// - scroll: Continuous flow / scrolling carousel mode (卷轴模式, expanded multi-candidate grid / continuous scroll stream)
public enum CandidateViewMode: String, CaseIterable, Sendable {
    case paging = "paging" // 翻页模式
    case scroll = "scroll" // 卷轴模式
    
    public var title: String {
        switch self {
        case .paging: return "翻页"
        case .scroll: return "卷轴"
        }
    }
}
