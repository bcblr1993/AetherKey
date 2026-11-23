import Foundation

/// Statistical unigram & bigram language model backed by `Resources/lm.json`,
/// with embedded high-frequency function-word and spoken-pair fallbacks.
public final class LanguageModel: @unchecked Sendable {
    public static let shared = LanguageModel()

    private struct RawPayload: Decodable {
        let u: [String: Int]?
        let b: [String: Int]?
    }

    private struct ModelData: Sendable {
        let unigrams: [String: Int]
        let bigrams: [String: Int]
    }

    private static let sourceRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private let lock = NSLock()
    private let customResourceURL: URL?
    private var cachedData: ModelData?

    public init(resourceURL: URL? = nil) {
        self.customResourceURL = resourceURL
    }

    /// Preloads `lm.json` into memory if not already loaded.
    public func preload() {
        _ = loadModelDataIfNeeded()
    }

    /// Returns scaled log10 unigram probability (`round(log10(prob) * 100)`).
    public func unigramScore(for word: String) -> Double {
        guard !word.isEmpty else { return -800.0 }
        let data = loadModelDataIfNeeded()
        if let score = data.unigrams[word] {
            return Double(score)
        }
        if let fallback = Self.fallbackUnigrams[word] {
            return fallback
        }
        switch word.count {
        case 1: return -620.0
        case 2: return -680.0
        case 3: return -730.0
        default: return -780.0
        }
    }

    /// Returns positive transition bonus for `(prev, next)` in the same `100 * log10` scale.
    public func bigramBonus(prev: String, next: String) -> Double {
        guard !prev.isEmpty, !next.isEmpty else { return 0.0 }
        let data = loadModelDataIfNeeded()
        let key = "\(prev)\t\(next)"
        if let bonus = data.bigrams[key] {
            return Double(bonus)
        }
        return Self.fallbackBigrams[key] ?? 0.0
    }

    /// Monotonic positive weight derived from `unigramScore` for single-word & DoublePinyin tie-breaking.
    public func wordWeight(for word: String) -> Double {
        let score = unigramScore(for: word)
        return score > -999.0 ? (score + 1000.0) : exp((score + 999.0) / 100.0)
    }

    private func loadModelDataIfNeeded() -> ModelData {
        lock.lock()
        if let cached = cachedData {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.readFromDisk(customURL: customResourceURL)

        lock.lock()
        if let cached = cachedData {
            lock.unlock()
            return cached
        }
        cachedData = loaded
        lock.unlock()
        return loaded
    }

    private static func readFromDisk(customURL: URL?) -> ModelData {
        var candidates: [URL?] = []
        if let customURL {
            candidates.append(customURL)
        } else {
            candidates.append(Bundle.main.url(forResource: "lm", withExtension: "json"))
            candidates.append(Bundle(for: LanguageModel.self).url(forResource: "lm", withExtension: "json"))
            candidates.append(sourceRoot.appendingPathComponent("Resources/lm.json"))
        }

        for case let url? in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let raw = try? Data(contentsOf: url),
                  !raw.isEmpty,
                  let decoded = try? JSONDecoder().decode(RawPayload.self, from: raw) else {
                continue
            }
            return ModelData(unigrams: decoded.u ?? [:], bigrams: decoded.b ?? [:])
        }

        return ModelData(unigrams: [:], bigrams: [:])
    }

    /// Top daily function characters and frequent colloquial tokens used when `lm.json` is absent or omits an entry.
    private static let fallbackUnigrams: [String: Double] = [
        "的": -110, "了": -125, "是": -130, "我": -135, "在": -140,
        "有": -145, "不": -145, "这": -150, "你": -152, "他": -158,
        "人": -162, "个": -164, "和": -166, "就": -168, "都": -170,
        "也": -172, "要": -174, "说": -176, "到": -178, "去": -180,
        "会": -182, "上": -184, "来": -185, "大": -186, "好": -188,
        "很": -190, "能": -192, "还": -194, "看": -195, "想": -196,
        "那": -198, "她": -200, "它": -205, "们": -206, "着": -208,
        "过": -210, "得": -212, "里": -214, "中": -215, "下": -216,
        "为": -218, "对": -220, "把": -222, "被": -224, "给": -225,
        "让": -226, "从": -228, "可": -230, "没": -232, "吗": -234,
        "呢": -236, "吧": -238, "啊": -240, "呀": -242, "多": -244,
        "少": -246, "小": -248, "吃": -250, "用": -252, "请": -254,
        "问": -256, "刚": -258, "先": -260, "别": -262, "跟": -264,
        "向": -266, "往": -268, "比": -270, "按": -272, "太": -274,
        "真": -276, "只": -278, "才": -280, "又": -282, "再": -284,
        "已": -286, "将": -288, "做": -290, "找": -292, "买": -294,
        "写": -296, "读": -298, "听": -300, "走": -302, "开": -304,
        "关": -306, "等": -308, "回": -310, "出": -312, "起": -314,
        "发": -316, "打": -318, "点": -320, "成": -322, "新": -324,
        "快": -326, "早": -328, "今": -330, "明": -332, "天": -334,
        "时": -336, "家": -338, "水": -340, "电": -342, "车": -344,
        "钱": -346, "事": -348, "话": -350, "字": -352,
        // Common 2-4 char colloquial words
        "我们": -210, "你们": -240, "他们": -245, "什么": -220, "怎么": -230,
        "可以": -225, "没有": -222, "有没有": -275, "今天": -235, "明天": -240,
        "现在": -238, "已经": -242, "因为": -250, "所以": -252, "如果": -254,
        "但是": -248, "然后": -256, "知道": -246, "觉得": -258, "喜欢": -262,
        "需要": -255, "工作": -244, "显示": -270, "现实": -285, "一样": -245,
        "肯定": -260, "异常": -290, "详细": -280, "星期": -275, "实验": -288,
        "公司": -250, "密码": -295, "水饺": -330, "问题": -248, "一下": -265,
        "一会儿": -295, "电脑": -278, "手机": -268, "在家": -305, "输入": -285,
        "你的": -255, "我的": -230, "看下": -315, "就到": -320, "没问题": -310,
        "一起": -262, "吃饭": -292, "没电": -335, "有点": -280, "帮我": -295,
        "修改": -298, "登录": -295, "不上": -325, "几点": -315, "电了": -345,
        "星期一": -300, "星期二": -302, "星期三": -302, "星期四": -304,
        "星期五": -300, "星期六": -302, "星期日": -305, "星期天": -305,
        "北京": -260, "上海": -262, "西安": -290, "陕西": -298, "山西": -300
    ]

    /// Curated high-priority spoken bigram bonuses used when `lm.json` has not been merged or lacks a pair.
    private static let fallbackBigrams: [String: Double] = [
        "明天\t是": 220, "今天\t是": 220,
        "是\t星期一": 200, "是\t星期二": 200, "是\t星期三": 200, "是\t星期四": 200,
        "是\t星期五": 200, "是\t星期六": 200, "是\t星期日": 200, "是\t星期天": 200,
        "请\t输入": 220, "输入\t你的": 220, "你的\t密码": 240,
        "看下\t有没有": 230, "有没有\t问题": 240,
        "你\t是": 180, "是\t在家": 210, "在家\t吗": 220,
        "刚\t到": 200, "到\t公司": 220,
        "吃\t水饺": 210, "吃\t饭": 210,
        "去\t西安": 210, "去\t北京": 210, "去\t上海": 210, "去\t陕西": 200, "去\t山西": 200,
        "显示\t一下": 220, "工作\t异常": 220,
        "我的\t肯定": 200, "肯定\t没问题": 240,
        "我\t一会儿": 210, "一会儿\t就到": 240,
        "登录\t不上": 230, "修改\t一下": 230,
        "一起\t吃饭": 230, "现在\t几点": 220,
        "手机\t没电": 230, "电脑\t有点": 220, "没\t电了": 210, "有点\t卡": 220,
        "请\t帮我": 220, "帮我\t看": 220
    ]
}
