import Foundation

/// V-Mode calculation engine and macro expansion for AetherKey.
/// Supports mathematical evaluation, date/time macros, and Chinese RMB currency capitalization.
public final class VModeCalculator: Sendable {
    public static let shared = VModeCalculator()
    
    public func candidates(for input: String) -> [Candidate] {
        guard input.hasPrefix("v"), input.count > 1 else { return [] }
        
        let expression = String(input.dropFirst())
        var results: [Candidate] = []
        
        // 1. Date / Time macros
        let lower = expression.lowercased()
        if lower.starts(with: "date") || lower == "rq" || lower == "d" {
            let df1 = DateFormatter()
            df1.dateFormat = "yyyy年MM月dd日"
            let df2 = DateFormatter()
            df2.dateFormat = "yyyy-MM-dd"
            results.append(Candidate(text: df1.string(from: Date()), comment: "日期 (全称)", isVMode: true))
            results.append(Candidate(text: df2.string(from: Date()), comment: "日期 (ISO)", isVMode: true))
        }
        
        if lower.starts(with: "time") || lower == "sj" || lower == "t" {
            let tf1 = DateFormatter()
            tf1.dateFormat = "HH:mm:ss"
            let tf2 = DateFormatter()
            tf2.dateFormat = "HH:mm"
            results.append(Candidate(text: tf1.string(from: Date()), comment: "时间 (精准)", isVMode: true))
            results.append(Candidate(text: tf2.string(from: Date()), comment: "时间 (标准)", isVMode: true))
        }
        
        if lower.starts(with: "week") || lower == "xq" {
            let wf = DateFormatter()
            wf.locale = Locale(identifier: "zh_CN")
            wf.dateFormat = "EEEE"
            let wfEn = DateFormatter()
            wfEn.locale = Locale(identifier: "en_US")
            wfEn.dateFormat = "EEEE"
            results.append(Candidate(text: wf.string(from: Date()), comment: "星期 (中文)", isVMode: true))
            results.append(Candidate(text: wfEn.string(from: Date()), comment: "Weekday", isVMode: true))
        }
        
        // 2. Mathematical expression evaluation
        if let mathResult = evaluateMath(expression) {
            results.append(Candidate(text: mathResult, comment: "= 计算结果", isVMode: true))
            results.append(Candidate(text: "\(expression)=\(mathResult)", comment: "完整算式", isVMode: true))
        }
        
        // 3. RMB currency capitalization if numeric
        if let num = Double(expression), num > 0, num < 1_000_000_000_000 {
            let rmb = convertToRMB(amount: num)
            results.append(Candidate(text: rmb, comment: "人民币大写", isVMode: true))
        }
        
        return results
    }
    
    private func evaluateMath(_ expr: String) -> String? {
        let sanitized = expr
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")
        
        let validChars = CharacterSet(charactersIn: "0123456789+-*/.()% ")
        guard sanitized.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            return nil
        }
        
        let nsExpr = NSExpression(format: sanitized)
        if let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber {
            let doubleVal = result.doubleValue
            if doubleVal.isFinite && !doubleVal.isNaN {
                if floor(doubleVal) == doubleVal && abs(doubleVal) < Double(Int64.max) {
                    return String(Int64(doubleVal))
                } else {
                    let str = String(format: "%.6f", doubleVal)
                    return str.replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
                }
            }
        }
        return nil
    }
    
    public func convertToRMB(amount: Double) -> String {
        let digits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
        let radices = ["", "拾", "佰", "仟"]
        let bigRadices = ["", "万", "亿", "兆"]
        
        let integerPart = Int64(floor(amount))
        let fractionPart = Int(round((amount - floor(amount)) * 100))
        
        var result = ""
        
        if integerPart == 0 {
            result = "零元"
        } else {
            var tempInt = integerPart
            var sectionCount = 0
            var intStr = ""
            
            while tempInt > 0 {
                let section = Int(tempInt % 10000)
                if section > 0 {
                    var secStr = ""
                    var zeroNeeded = false
                    var tempSec = section
                    
                    for i in 0..<4 {
                        let d = tempSec % 10
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
                        tempSec /= 10
                    }
                    intStr = secStr + bigRadices[sectionCount] + intStr
                }
                sectionCount += 1
                tempInt /= 10000
            }
            result = intStr + "元"
        }
        
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
}
