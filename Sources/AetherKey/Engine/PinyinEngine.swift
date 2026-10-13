import Foundation

/// Fast Chinese Pinyin segmentation and candidate generation engine for AetherKey.
/// Optimized for Apple Silicon with lock-free reads and high-frequency lexicon caching.
public final class PinyinEngine: Sendable {
    public static let shared = PinyinEngine()
    
    public struct DictEntry: Sendable {
        public let pinyin: String     // full segmented pinyin e.g. "zhong'wen"
        public let rawPinyin: String  // unsegmented pinyin e.g. "zhongwen"
        public let abbreviation: String // initial letters e.g. "zw"
        public let word: String
        public let weight: Int
    }
    
    private let entries: [DictEntry]
    private let exactMap: [String: [DictEntry]]
    private let abbrMap: [String: [DictEntry]]
    
    public init() {
        var builtEntries: [DictEntry] = []
        
        // Load built-in comprehensive lexicon
        let rawLexicon: [(word: String, pinyin: String, abbr: String, weight: Int)] = [
            // AetherNative & Tech terms
            ("AetherKey", "aetherkey", "ak", 10000),
            ("AetherNative", "aethernative", "an", 9990),
            ("Apple Silicon", "applesilicon", "as", 9980),
            ("Swift", "swift", "s", 9970),
            ("Metal", "metal", "m", 9960),
            ("CoreAnimation", "coreanimation", "ca", 9950),
            ("ProMotion", "promotion", "pm", 9940),
            ("Liquid Glass", "liquidglass", "lg", 9930),
            
            // Core System & UI concepts
            ("液态玻璃", "ye'tai'bo'li", "ytbl", 9500),
            ("微光胶囊", "wei'guang'jiao'nang", "wgjn", 9450),
            ("暗黑质感", "an'hei'zhi'gan", "ahzg", 9400),
            ("极速输入法", "ji'su'shu'ru'fa", "jssrf", 9350),
            ("输入法", "shu'ru'fa", "srf", 9300),
            ("候选词", "hou'xuan'ci", "hxc", 9250),
            ("盘古空格", "pan'gu'kong'ge", "pgkg", 9200),
            ("智能标点", "zhi'neng'biao'dian", "znbd", 9150),
            ("场景感知", "chang'jing'gan'zhi", "cjgz", 9100),
            ("阻尼物理", "zu'ni'wu'li", "znwl", 9050),
            ("丝滑动效", "si'hua'dong'xiao", "shdx", 9000),
            ("渲染管线", "xuan'ran'guan'xian", "xrgx", 8950),
            ("零卡顿", "ling'ka'dun", "lkd", 8900),
            ("客户端", "ke'hu'duan", "khd", 8850),
            ("架构", "jia'gou", "jg", 8800),
            ("高响应", "gao'xiang'ying", "gxy", 8750),
            
            // Common greetings & greetings
            ("你好", "ni'hao", "nh", 9900),
            ("您好", "nin'hao", "nh", 9800),
            ("中国", "zhong'guo", "zg", 9850),
            ("中文", "zhong'wen", "zw", 9860),
            ("中华", "zhong'hua", "zh", 9400),
            ("北京", "bei'jing", "bj", 9700),
            ("上海", "shang'hai", "sh", 9650),
            ("深圳", "shen'zhen", "sz", 9600),
            ("广州", "guang'zhou", "gz", 9550),
            ("杭州", "hang'zhou", "hz", 9500),
            
            // Common daily phrases
            ("我们", "wo'men", "wm", 9500),
            ("你们", "ni'men", "nm", 9400),
            ("他们", "ta'men", "tm", 9300),
            ("什么", "shen'me", "sm", 9450),
            ("怎么", "zen'me", "zm", 9400),
            ("可以", "ke'yi", "ky", 9350),
            ("没有", "mei'you", "my", 9300),
            ("知道", "zhi'dao", "zd", 9250),
            ("现在", "xian'zai", "xz", 9200),
            ("今天", "jin'tian", "jt", 9150),
            ("明天", "ming'tian", "mt", 9100),
            ("昨天", "zuo'tian", "zt", 9050),
            ("时间", "shi'jian", "sj", 9000),
            ("工作", "gong'zuo", "gz", 8950),
            ("生活", "sheng'huo", "sh", 8900),
            ("开心", "kai'xin", "kx", 8850),
            ("快乐", "kuai'le", "kl", 8800),
            ("谢谢", "xie'xie", "xx", 9200),
            ("好的", "hao'de", "hd", 9300),
            ("不错", "bu'cuo", "bc", 9100),
            ("喜欢", "xi'huan", "xh", 9000),
            ("开始", "kai'shi", "ks", 8900),
            ("完成", "wan'cheng", "wc", 8850),
            ("成功", "cheng'gong", "cg", 8800),
            ("测试", "ce'shi", "cs", 8750),
            ("发布", "fa'bu", "fb", 8700),
            ("开发", "kai'fa", "kf", 8950),
            ("设计", "she'ji", "sj", 8900),
            ("代码", "dai'ma", "dm", 8850),
            ("系统", "xi'tong", "xt", 8800),
            ("苹果", "ping'guo", "pg", 8750),
            ("原生", "yuan'sheng", "ys", 8700),
            ("极速", "ji'su", "js", 8650),
            ("体验", "ti'yan", "ty", 8600),
            ("性能", "xing'neng", "xn", 8550),
            ("优化", "you'hua", "yh", 8500),
            ("科技", "ke'ji", "kj", 8450),
            ("美学", "mei'xue", "mx", 8400),
            ("未来", "wei'lai", "wl", 8350),
            ("现代", "xian'dai", "xd", 8300),
            ("世界", "shi'jie", "sj", 8250),
            ("梦想", "meng'xiang", "mx", 8200),
            ("朋友", "peng'you", "py", 8150),
            ("大家", "da'jia", "dj", 8100),
            ("学习", "xue'xi", "xx", 8050),
            ("进步", "jin'bu", "jb", 8000),
            ("思考", "si'kao", "sk", 7950),
            ("创造", "chuang'zao", "cz", 7900),
            ("构建", "gou'jian", "gj", 7850),
            ("实现", "shi'xian", "sx", 7800),
            ("探索", "tan'suo", "ts", 7750),
            ("飞速", "fei'su", "fs", 7700),
            ("优雅", "you'ya", "yy", 7650),
            ("卓越", "zhuo'yue", "zy", 7600),
            
            // Single character high-frequency lexicon
            ("我", "wo", "w", 10000),
            ("的", "de", "d", 9999),
            ("一", "yi", "y", 9998),
            ("是", "shi", "s", 9997),
            ("了", "le", "l", 9996),
            ("不", "bu", "b", 9995),
            ("在", "zai", "z", 9994),
            ("人", "ren", "r", 9993),
            ("有", "you", "y", 9992),
            ("这", "zhe", "z", 9991),
            ("个", "ge", "g", 9990),
            ("上", "shang", "s", 9989),
            ("们", "men", "m", 9988),
            ("中", "zhong", "z", 9987),
            ("来", "lai", "l", 9986),
            ("大", "da", "d", 9985),
            ("为", "wei", "w", 9984),
            ("和", "he", "h", 9983),
            ("国", "guo", "g", 9982),
            ("地", "di", "d", 9981),
            ("到", "dao", "d", 9980),
            ("以", "yi", "y", 9979),
            ("说", "shuo", "s", 9978),
            ("时", "shi", "s", 9977),
            ("要", "yao", "y", 9976),
            ("就", "jiu", "j", 9975),
            ("出", "chu", "c", 9974),
            ("会", "hui", "h", 9973),
            ("可", "ke", "k", 9972),
            ("也", "ye", "y", 9971),
            ("你", "ni", "n", 9970),
            ("对", "dui", "d", 9969),
            ("生", "sheng", "s", 9968),
            ("能", "neng", "n", 9967),
            ("而", "er", "e", 9966),
            ("子", "zi", "z", 9965),
            ("那", "na", "n", 9964),
            ("得", "de", "d", 9963),
            ("于", "yu", "y", 9962),
            ("着", "zhe", "z", 9961),
            ("下", "xia", "x", 9960),
            ("自", "zi", "z", 9959),
            ("之", "zhi", "z", 9958),
            ("年", "nian", "n", 9957),
            ("过", "guo", "g", 9956),
            ("发", "fa", "f", 9955),
            ("后", "hou", "h", 9954),
            ("作", "zuo", "z", 9953),
            ("里", "li", "l", 9952),
            ("用", "yong", "y", 9951),
            ("道", "dao", "d", 9950),
            ("行", "xing", "x", 9949),
            ("所", "suo", "s", 9948),
            ("然", "ran", "r", 9947),
            ("家", "jia", "j", 9946),
            ("种", "zhong", "z", 9945),
            ("事", "shi", "s", 9944),
            ("成", "cheng", "c", 9943),
            ("方", "fang", "f", 9942),
            ("多", "duo", "d", 9941),
            ("经", "jing", "j", 9940),
            ("么", "me", "m", 9939),
            ("去", "qu", "q", 9938),
            ("法", "fa", "f", 9937),
            ("学", "xue", "x", 9936),
            ("如", "ru", "r", 9935),
            ("都", "dou", "d", 9934),
            ("同", "tong", "t", 9933),
            ("现", "xian", "x", 9932),
            ("当", "dang", "d", 9931),
            ("没", "mei", "m", 9930),
            ("动", "dong", "d", 9929),
            ("面", "mian", "m", 9928),
            ("起", "qi", "q", 9927),
            ("看", "kan", "k", 9926),
            ("定", "ding", "d", 9925),
            ("天", "tian", "t", 9924),
            ("分", "fen", "f", 9923),
            ("特", "te", "t", 9922),
            ("相", "xiang", "x", 9921),
            ("全", "quan", "q", 9920),
            ("好", "hao", "h", 9919),
            ("美", "mei", "m", 9918),
            ("光", "guang", "g", 9917),
            ("快", "kuai", "k", 9916),
            ("极", "ji", "j", 9915),
            ("原", "yuan", "y", 9914),
            ("速", "su", "s", 9913)
        ]
        
        for item in rawLexicon {
            let rawP = item.pinyin.replacingOccurrences(of: "'", with: "")
            builtEntries.append(DictEntry(
                pinyin: item.pinyin,
                rawPinyin: rawP,
                abbreviation: item.abbr,
                word: item.word,
                weight: item.weight
            ))
        }
        
        self.entries = builtEntries
        
        // Build fast lookup indexes
        var exact: [String: [DictEntry]] = [:]
        var abbr: [String: [DictEntry]] = [:]
        
        for e in builtEntries {
            exact[e.rawPinyin, default: []].append(e)
            if e.rawPinyin != e.pinyin {
                exact[e.pinyin, default: []].append(e)
            }
            abbr[e.abbreviation, default: []].append(e)
        }
        
        // Sort buckets by weight descending
        for key in exact.keys {
            exact[key]?.sort { $0.weight > $1.weight }
        }
        for key in abbr.keys {
            abbr[key]?.sort { $0.weight > $1.weight }
        }
        
        self.exactMap = exact
        self.abbrMap = abbr
    }
    
    /// Queries candidate list for given raw pinyin buffer.
    public func query(rawInput: String) -> [Candidate] {
        let input = rawInput.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }
        
        var seenWords = Set<String>()
        var candidates: [Candidate] = []
        
        // 1. Exact match on raw pinyin
        if let exactList = exactMap[input] {
            for e in exactList {
                if !seenWords.contains(e.word) {
                    seenWords.insert(e.word)
                    candidates.append(Candidate(text: e.word, pinyin: e.pinyin))
                }
            }
        }
        
        // 2. Abbreviation (super 简拼) match
        if let abbrList = abbrMap[input] {
            for e in abbrList {
                if !seenWords.contains(e.word) {
                    seenWords.insert(e.word)
                    candidates.append(Candidate(text: e.word, pinyin: e.pinyin))
                }
            }
        }
        
        // 3. Prefix matching on entries
        let prefixMatches = entries.filter {
            $0.rawPinyin.hasPrefix(input) || $0.abbreviation.hasPrefix(input)
        }.sorted { $0.weight > $1.weight }
        
        for e in prefixMatches {
            if !seenWords.contains(e.word) {
                seenWords.insert(e.word)
                candidates.append(Candidate(text: e.word, pinyin: e.pinyin))
            }
            if candidates.count >= 25 { break }
        }
        
        // 4. Raw buffer as fallback English option if Latin
        if !seenWords.contains(rawInput) {
            candidates.append(Candidate(text: rawInput, comment: "英"))
        }
        
        return candidates
    }
}
