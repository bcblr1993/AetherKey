import Foundation

/// V-Mode calculation engine and macro expansion for AetherKey.
/// Supports safe recursive-descent mathematical evaluation, date/time/symbol macros, Chinese numerals, and RMB currency capitalization.
public final class VModeCalculator: Sendable {
    public static let shared = VModeCalculator()

    private static let arrowSymbols: [(text: String, comment: String)] = [
        ("→", "右箭头"), ("←", "左箭头"), ("↑", "上箭头"), ("↓", "下箭头"),
        ("↔", "双向箭头"), ("⇒", "右双箭头"), ("⇔", "等价箭头"), ("↗", "右上箭头"), ("↘", "右下箭头")
    ]

    private static let mathSymbols: [(text: String, comment: String)] = [
        ("×", "乘号"), ("÷", "除号"), ("±", "正负号"), ("≈", "约等于"),
        ("≠", "不等于"), ("≤", "小于等于"), ("≥", "大于等于"), ("∞", "无穷"),
        ("√", "根号"), ("∑", "求和"), ("π", "圆周率")
    ]

    private static let greekSymbols: [(text: String, comment: String)] = [
        ("α", "alpha"), ("β", "beta"), ("γ", "gamma"), ("δ", "delta"),
        ("θ", "theta"), ("λ", "lambda"), ("μ", "mu"), ("π", "pi"),
        ("σ", "sigma"), ("φ", "phi"), ("ω", "omega"), ("Δ", "Delta"), ("Ω", "Omega")
    ]

    private static let commonSymbols: [(text: String, comment: String)] = [
        ("✓", "对勾"), ("✗", "叉号"), ("★", "实心星"), ("☆", "空心星"),
        ("•", "圆点"), ("©", "版权"), ("®", "注册"), ("™", "商标"),
        ("°", "度"), ("§", "分节"), ("⌘", "Command"), ("⌥", "Option"),
        ("⇧", "Shift"), ("⌃", "Control")
    ]

    /// Returns true when `buffer` begins with `"v"` followed strictly by one or more ASCII letters.
    public static func isMacroKeywordMode(_ buffer: String) -> Bool {
        guard buffer.hasPrefix("v"), buffer.count > 1 else { return false }
        return buffer.dropFirst().allSatisfy { $0.isASCII && $0.isLetter }
    }

    public func candidates(for input: String) -> [Candidate] {
        guard input.hasPrefix("v"), input.count > 1 else { return [] }

        let expression = String(input.dropFirst())
        var results: [Candidate] = []
        let now = Date()

        // 1. Date / Time / Utility / Symbol macros
        let lower = expression.lowercased()
        if lower == "now" || lower == "dt" || lower == "datetime" {
            let dt1 = DateFormatter()
            dt1.locale = Locale(identifier: "en_US_POSIX")
            dt1.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let dt2 = DateFormatter()
            dt2.locale = Locale(identifier: "en_US_POSIX")
            dt2.dateFormat = "yyyy年MM月dd日 HH:mm"
            let iso = ISO8601DateFormatter()
            iso.timeZone = .current
            results.append(Candidate(text: dt1.string(from: now), comment: "日期时间", isVMode: true))
            results.append(Candidate(text: dt2.string(from: now), comment: "日期时间 (中文)", isVMode: true))
            results.append(Candidate(text: iso.string(from: now), comment: "ISO 8601", isVMode: true))
        } else if lower == "d" || lower == "rq" || lower.starts(with: "date") {
            let df1 = DateFormatter()
            df1.dateFormat = "yyyy年MM月dd日"
            let df2 = DateFormatter()
            df2.dateFormat = "yyyy-MM-dd"
            results.append(Candidate(text: df1.string(from: now), comment: "日期 (全称)", isVMode: true))
            results.append(Candidate(text: df2.string(from: now), comment: "日期 (ISO)", isVMode: true))
        }

        if lower == "ts" || lower == "timestamp" {
            let epoch = now.timeIntervalSince1970
            let seconds = Int64(epoch)
            let millis = Int64((epoch * 1000.0).rounded())
            results.append(Candidate(text: String(seconds), comment: "Unix 时间戳 (秒)", isVMode: true))
            results.append(Candidate(text: String(millis), comment: "Unix 时间戳 (毫秒)", isVMode: true))
        } else if lower.starts(with: "time") || lower == "sj" || lower == "t" {
            let tf1 = DateFormatter()
            tf1.dateFormat = "HH:mm:ss"
            let tf2 = DateFormatter()
            tf2.dateFormat = "HH:mm"
            results.append(Candidate(text: tf1.string(from: now), comment: "时间 (精准)", isVMode: true))
            results.append(Candidate(text: tf2.string(from: now), comment: "时间 (标准)", isVMode: true))
        }

        if lower.starts(with: "week") || lower == "xq" {
            let wf = DateFormatter()
            wf.locale = Locale(identifier: "zh_CN")
            wf.dateFormat = "EEEE"
            let wfEn = DateFormatter()
            wfEn.locale = Locale(identifier: "en_US")
            wfEn.dateFormat = "EEEE"
            results.append(Candidate(text: wf.string(from: now), comment: "星期 (中文)", isVMode: true))
            results.append(Candidate(text: wfEn.string(from: now), comment: "Weekday", isVMode: true))
        }

        if lower == "uuid" {
            let uuid = UUID().uuidString
            results.append(Candidate(text: uuid.lowercased(), comment: "UUID (小写)", isVMode: true))
            results.append(Candidate(text: uuid.uppercased(), comment: "UUID (大写)", isVMode: true))
        }

        if lower == "arrow" || lower == "jt" {
            results.append(contentsOf: Self.symbolCandidates(Self.arrowSymbols))
        } else if lower == "math" || lower == "sx" {
            results.append(contentsOf: Self.symbolCandidates(Self.mathSymbols))
        } else if lower == "greek" || lower == "xl" {
            results.append(contentsOf: Self.symbolCandidates(Self.greekSymbols))
        } else if lower == "fh" || lower == "fuhao" || lower == "sym" {
            results.append(contentsOf: Self.symbolCandidates(Self.commonSymbols))
        }

        // 2. Mathematical expression evaluation (safe recursive descent parser, never throws ObjC NSException)
        if let mathResult = evaluateMath(expression) {
            results.append(Candidate(text: mathResult, comment: "= 计算结果", isVMode: true))
            results.append(Candidate(text: "\(expression)=\(mathResult)", comment: "完整算式", isVMode: true))
        }

        // 3. RMB currency capitalization if numeric
        if let num = Double(expression), num > 0, num < 1_000_000_000_000 {
            let rmb = convertToRMB(amount: num)
            results.append(Candidate(text: rmb, comment: "人民币大写", isVMode: true))
        }

        // 4. Lowercase Chinese numeral for non-negative pure integers
        if !expression.isEmpty,
           expression.allSatisfy({ $0.isASCII && $0.isNumber }),
           let intVal = Int64(expression),
           (0...999_999_999_999).contains(intVal) {
            results.append(Candidate(text: convertToChineseNumeral(integer: intVal), comment: "中文数字", isVMode: true))
        }

        return results
    }

    private static func symbolCandidates(_ items: [(text: String, comment: String)]) -> [Candidate] {
        items.map { Candidate(text: $0.text, comment: $0.comment, isVMode: true) }
    }
    
    /// Pure Swift recursive-descent arithmetic evaluator supporting +, -, *, /, %, ^, **, and parentheses.
    /// Safely returns nil on incomplete or malformed expressions during incremental typing.
    private func evaluateMath(_ expr: String) -> String? {
        let sanitized = expr
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "**", with: "^")
            .replacingOccurrences(of: " ", with: "")
        
        guard !sanitized.isEmpty else { return nil }
        let validChars = CharacterSet(charactersIn: "0123456789+-*/.^%()")
        guard sanitized.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            return nil
        }
        
        var parser = MathParser(Array(sanitized))
        guard let doubleVal = parser.parseExpression(),
              parser.isAtEnd,
              doubleVal.isFinite,
              !doubleVal.isNaN else {
            return nil
        }
        
        if floor(doubleVal) == doubleVal && abs(doubleVal) < Double(Int64.max) {
            return String(Int64(doubleVal))
        } else {
            let str = String(format: "%.6f", doubleVal)
            return str.replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }
    
    private struct MathParser {
        let chars: [Character]
        var pos: Int = 0
        
        init(_ chars: [Character]) {
            self.chars = chars
        }
        
        var isAtEnd: Bool { pos >= chars.count }
        
        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while !isAtEnd {
                let op = chars[pos]
                if op == "+" || op == "-" {
                    pos += 1
                    guard let rhs = parseTerm() else { return nil }
                    lhs = (op == "+") ? (lhs + rhs) : (lhs - rhs)
                } else {
                    break
                }
            }
            return lhs
        }
        
        mutating func parseTerm() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while !isAtEnd {
                let op = chars[pos]
                if op == "*" || op == "/" || op == "%" {
                    pos += 1
                    guard let rhs = parsePower() else { return nil }
                    if op == "*" {
                        lhs *= rhs
                    } else if op == "/" {
                        guard rhs != 0 else { return nil }
                        lhs /= rhs
                    } else {
                        guard rhs != 0 else { return nil }
                        lhs = lhs.truncatingRemainder(dividingBy: rhs)
                    }
                } else {
                    break
                }
            }
            return lhs
        }
        
        mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if !isAtEnd && chars[pos] == "^" {
                pos += 1
                guard let exponent = parsePower() else { return nil }
                return pow(base, exponent)
            }
            return base
        }
        
        mutating func parseUnary() -> Double? {
            if !isAtEnd {
                if chars[pos] == "+" {
                    pos += 1
                    return parseUnary()
                } else if chars[pos] == "-" {
                    pos += 1
                    guard let val = parseUnary() else { return nil }
                    return -val
                }
            }
            return parsePrimary()
        }
        
        mutating func parsePrimary() -> Double? {
            guard !isAtEnd else { return nil }
            if chars[pos] == "(" {
                pos += 1
                guard let val = parseExpression() else { return nil }
                guard !isAtEnd && chars[pos] == ")" else { return nil }
                pos += 1
                return val
            }
            
            let start = pos
            var hasDot = false
            while !isAtEnd {
                let c = chars[pos]
                if c.isNumber {
                    pos += 1
                } else if c == "." && !hasDot {
                    hasDot = true
                    pos += 1
                } else {
                    break
                }
            }
            guard pos > start else { return nil }
            let numStr = String(chars[start..<pos])
            guard numStr != "." else { return nil }
            return Double(numStr)
        }
    }
    
    /// Converts a non-negative integer (`0...999_999_999_999`) to standard lowercase Chinese numerals.
    public func convertToChineseNumeral(integer value: Int64) -> String {
        guard value >= 0 else {
            if value == Int64.min { return "" }
            return "负" + convertToChineseNumeral(integer: -value)
        }
        if value == 0 { return "零" }
        return Self.formatChineseInteger(
            value,
            digits: ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"],
            radices: ["", "十", "百", "千"],
            omitLeadingOneForTen: true
        )
    }

    public func convertToRMB(amount: Double) -> String {
        let digits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
        let totalCents = Int64((max(0, amount) * 100.0).rounded())
        let integerPart = totalCents / 100
        let fractionPart = Int(totalCents % 100)

        let intStr = integerPart == 0
            ? digits[0]
            : Self.formatChineseInteger(
                integerPart,
                digits: digits,
                radices: ["", "拾", "佰", "仟"],
                omitLeadingOneForTen: false
            )
        var result = intStr + "元"

        let jiao = fractionPart / 10
        let fen = fractionPart % 10
        if jiao == 0 && fen == 0 {
            result += "整"
        } else {
            if jiao > 0 {
                result += digits[jiao] + "角"
            } else if integerPart > 0 {
                result += "零"
            }
            if fen > 0 {
                result += digits[fen] + "分"
            } else {
                result += "整"
            }
        }
        return result
    }

    private static func formatChineseInteger(
        _ value: Int64,
        digits: [String],
        radices: [String],
        omitLeadingOneForTen: Bool
    ) -> String {
        let bigRadices = ["", "万", "亿", "兆"]

        func formatSection(_ section: Int) -> String {
            var secStr = ""
            var zeroNeeded = false
            var temp = section
            for i in 0..<4 {
                let d = temp % 10
                if d == 0 {
                    if !secStr.isEmpty && !zeroNeeded {
                        zeroNeeded = true
                    }
                } else {
                    if zeroNeeded {
                        secStr = digits[0] + secStr
                        zeroNeeded = false
                    }
                    secStr = digits[d] + radices[i] + secStr
                }
                temp /= 10
            }
            return secStr
        }

        var sections: [Int] = []
        var tempInt = value
        while tempInt > 0 {
            sections.append(Int(tempInt % 10000))
            tempInt /= 10000
        }
        var intStr = ""
        var zeroPending = false
        for idx in stride(from: sections.count - 1, through: 0, by: -1) {
            let sec = sections[idx]
            if sec == 0 {
                if !intStr.isEmpty {
                    zeroPending = true
                }
                continue
            }
            let isLeadingSection = intStr.isEmpty
            if !isLeadingSection && (zeroPending || sec < 1000) {
                intStr += digits[0]
            }
            zeroPending = false
            var secStr = formatSection(sec)
            if omitLeadingOneForTen && isLeadingSection && (10..<20).contains(sec) {
                secStr = String(secStr.dropFirst())
            }
            let unit = idx < bigRadices.count ? bigRadices[idx] : ""
            intStr += secStr + unit
        }
        return intStr
    }
}
