import SwiftUI
import AppKit

/// Shared measurements keep the SwiftUI surface and its floating window in agreement.
enum CandidatePanelMetrics {
    static let outerPadding: CGFloat = 5
    static let headerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 3

    static func height(for mode: CandidateViewMode) -> CGFloat {
        headerHeight + 0.5 + outerPadding * 2
            + (mode == .scroll ? rowHeight * 2 + rowSpacing : rowHeight)
    }

    static func contentWidth(
        candidates: [Candidate], viewMode: CandidateViewMode, pinyin: String,
        mode: InputMode, currentPage: Int, totalPages: Int, maximum: CGFloat = 640
    ) -> CGFloat {
        func measure(_ text: String, font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let middle = (candidates.count + 1) / 2
        let rows: [[Int]] = viewMode == .scroll
            ? [Array(0..<middle), Array(middle..<candidates.count)]
            : [Array(candidates.indices)]
        let widestRow = rows.map { row in
            row.reduce(CGFloat(6)) { result, index in
                let candidate = candidates[index]
                var width = measure(candidate.text, font: .systemFont(ofSize: 15, weight: .medium)) + 14
                if index < 9 {
                    width += measure(String(index + 1), font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium)) + 5
                }
                if let comment = candidate.comment, !comment.isEmpty {
                    width += measure(comment, font: .systemFont(ofSize: 11)) + 5
                }
                return result + width + (index == row.last ? 0 : rowSpacing)
            }
        }.max() ?? 0
        let badge = measure(mode.badgeTitle, font: .systemFont(ofSize: 10, weight: .semibold)) + 8
        let pageControls: CGFloat = totalPages > 1
            ? measure("\(currentPage) / \(totalPages)", font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium)) + 40
            : 0
        let header = 10 + badge + 6 + min(120, measure(pinyin, font: .systemFont(ofSize: 12, weight: .medium)))
            + 8 + pageControls + 6 + 22 + 4
        return min(maximum, max(128, max(widestRow, header)))
    }
}

/// Compact candidate surface shared by the input method and its preview.
public struct CandidateListView: View {
    public let inputString: String
    public let displayPinyin: String
    public let mode: InputMode
    public let viewMode: CandidateViewMode
    public let candidates: [Candidate]
    public let selectedIndex: Int
    public let currentPage: Int
    public let totalPages: Int
    public let onSelectCandidate: ((Int) -> Void)?
    public let onToggleViewMode: (() -> Void)?
    public let onPageDelta: ((Int) -> Void)?
    public let viewportWidth: CGFloat?

    @State private var hoveredIndex: Int?

    public init(
        inputString: String,
        displayPinyin: String = "",
        mode: InputMode,
        viewMode: CandidateViewMode = .paging,
        candidates: [Candidate],
        selectedIndex: Int,
        currentPage: Int = 1,
        totalPages: Int = 1,
        onSelectCandidate: ((Int) -> Void)? = nil,
        onToggleViewMode: (() -> Void)? = nil,
        onPageDelta: ((Int) -> Void)? = nil,
        viewportWidth: CGFloat? = nil
    ) {
        self.inputString = inputString
        self.displayPinyin = displayPinyin
        self.mode = mode
        self.viewMode = viewMode
        self.candidates = candidates
        self.selectedIndex = selectedIndex
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.onSelectCandidate = onSelectCandidate
        self.onToggleViewMode = onToggleViewMode
        self.onPageDelta = onPageDelta
        self.viewportWidth = viewportWidth
    }

    private var rows: [[Int]] {
        let indices = Array(candidates.indices)
        guard viewMode == .scroll else { return [indices] }
        let middle = (indices.count + 1) / 2
        return [Array(indices.prefix(middle)), Array(indices.dropFirst(middle))]
            .filter { !$0.isEmpty }
    }

    // The panel passes the same measured width after applying display boundaries.
    private var contentWidth: CGFloat {
        viewportWidth ?? CandidatePanelMetrics.contentWidth(
            candidates: candidates, viewMode: viewMode,
            pinyin: displayPinyin.isEmpty ? inputString : displayPinyin,
            mode: mode, currentPage: currentPage, totalPages: totalPages
        )
    }

    public var body: some View {
        LiquidGlassContainer(cornerRadius: 11) {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)
                candidateContent
                    .padding(CandidatePanelMetrics.outerPadding)
            }
            .frame(width: contentWidth + CandidatePanelMetrics.outerPadding * 2)
        }
        .fixedSize()
    }

    private var headerView: some View {
        HStack(spacing: 6) {
            Text(mode.badgeTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 4)
                .frame(height: 18)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))

            Text(displayPinyin.isEmpty ? inputString : displayPinyin)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(displayPinyin.isEmpty ? inputString : displayPinyin)

            Spacer(minLength: 8)

            if totalPages > 1 {
                HStack(spacing: 2) {
                    pageButton(delta: -1, enabled: currentPage > 1)
                    Text("\(currentPage) / \(totalPages)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    pageButton(delta: 1, enabled: currentPage < totalPages)
                }
            }

            Button { onToggleViewMode?() } label: {
                Image(systemName: viewMode == .scroll ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewMode == .scroll ? "收起候选词 · ⌥Tab" : "展开候选词 · ⌥Tab")
            .accessibilityLabel(viewMode == .scroll ? "收起候选词" : "展开候选词")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: CandidatePanelMetrics.headerHeight)
    }

    private func pageButton(delta: Int, enabled: Bool) -> some View {
        Button { onPageDelta?(delta) } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!enabled)
        .help(delta < 0 ? "上一页" : "下一页")
        .accessibilityLabel(delta < 0 ? "上一页" : "下一页")
    }

    private var candidateContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CandidatePanelMetrics.rowSpacing) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: CandidatePanelMetrics.rowSpacing) {
                            ForEach(rows[row], id: \.self) { index in
                                candidateItem(index: index, candidate: candidates[index])
                                    .id(index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 3)
            }
            .frame(width: contentWidth, height: viewMode == .scroll
                ? CandidatePanelMetrics.rowHeight * 2 + CandidatePanelMetrics.rowSpacing
                : CandidatePanelMetrics.rowHeight)
            .onChange(of: selectedIndex) { _, index in
                proxy.scrollTo(index)
            }
            .onChange(of: candidates) { _, _ in
                proxy.scrollTo(selectedIndex)
                hoveredIndex = nil
            }
            .onChange(of: viewMode) { _, _ in proxy.scrollTo(selectedIndex) }
        }
    }

    private func candidateItem(index: Int, candidate: Candidate) -> some View {
        let selected = index == selectedIndex
        return Button { onSelectCandidate?(index) } label: {
            HStack(spacing: 5) {
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.7))
                }
                Text(candidate.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                if let comment = candidate.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: CandidatePanelMetrics.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(hoveredIndex == index ? 0.06 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex) }
        .accessibilityLabel("\(index < 9 ? String(index + 1) : "") \(candidate.text)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
