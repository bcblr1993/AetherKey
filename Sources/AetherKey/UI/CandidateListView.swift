import SwiftUI
import AppKit

/// PreferenceKey to report the layout bounds of each candidate item in the coordinate space
private struct CandidateItemFramePreferenceKey: PreferenceKey {
    typealias Value = [Int: CGRect]
    static let defaultValue: [Int: CGRect] = [:]
    
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Horizontal Candidate List View matching AetherNative aesthetic.
/// Pure GPU-accelerated spring animations at 120fps with zero layout thrashing.
public struct CandidateListView: View {
    public let inputString: String
    public let mode: InputMode
    public let candidates: [Candidate]
    public let selectedIndex: Int
    public let currentPage: Int
    public let totalPages: Int

    @State private var itemFrames: [Int: CGRect] = [:]
    
    public init(
        inputString: String,
        mode: InputMode,
        candidates: [Candidate],
        selectedIndex: Int,
        currentPage: Int = 1,
        totalPages: Int = 1
    ) {
        self.inputString = inputString
        self.mode = mode
        self.candidates = candidates
        self.selectedIndex = selectedIndex
        self.currentPage = currentPage
        self.totalPages = totalPages
    }

    public var body: some View {
        LiquidGlassContainer(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 7) {
                // Top Header: Mode Badge + Input Buffer
                HStack(spacing: 8) {
                    // Futuristic Mode Badge
                    Text(mode.badgeTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.20, green: 0.90, blue: 1.0),
                                            Color(red: 0.00, green: 0.75, blue: 0.95)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color(red: 0.00, green: 0.80, blue: 1.0).opacity(0.4), radius: 4, x: 0, y: 1)
                    
                    // Pinyin / Raw Input String
                    Text(inputString)
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                    
                    Spacer(minLength: 8)
                    
                    // Page indicator
                    if totalPages > 1 {
                        Text("\(currentPage)/\(totalPages)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                
                // Divider line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)
                
                // Candidate Strip with GPU-Interpolated Sliding Glow Capsule
                ZStack(alignment: .topLeading) {
                    // GPU-driven subtle glow capsule sliding under active candidate
                    if let activeFrame = itemFrames[selectedIndex] {
                        SubtleGlowCapsule()
                            .frame(width: activeFrame.width, height: activeFrame.height)
                            .offset(x: activeFrame.minX, y: activeFrame.minY)
                            .animation(.spring(response: 0.16, dampingFraction: 0.86), value: selectedIndex)
                    }
                    
                    // Candidates Row
                    HStack(spacing: 4) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            candidateItemView(index: index, candidate: candidate)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: CandidateItemFramePreferenceKey.self,
                                            value: [index: geo.frame(in: .named("CandidateContainerSpace"))]
                                        )
                                    }
                                )
                        }
                    }
                    .coordinateSpace(name: "CandidateContainerSpace")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 7)
            }
            .padding(4)
        }
        .onPreferenceChange(CandidateItemFramePreferenceKey.self) { frames in
            self.itemFrames = frames
        }
        .fixedSize()
    }
    
    @ViewBuilder
    private func candidateItemView(index: Int, candidate: Candidate) -> some View {
        let isSelected = (index == selectedIndex)
        
        HStack(spacing: 5) {
            // Index number: SF Pro Text Monospaced
            Text("\(index + 1)")
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.40))
            
            // Candidate Word: SF Pro Text Medium
            Text(candidate.text)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .default))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
            
            // Optional comment (e.g., formula result, abbreviation)
            if let comment = candidate.comment {
                Text(comment)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(isSelected ? Color(red: 0.20, green: 0.90, blue: 1.0).opacity(0.9) : Color.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
