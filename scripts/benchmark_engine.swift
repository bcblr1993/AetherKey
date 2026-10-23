import Foundation

// Build with swiftc -O Sources/AetherKey/Engine/*.swift Sources/AetherKey/Model/*.swift scripts/benchmark_engine.swift -o /tmp/aetherkey-benchmark
@main
struct EngineBenchmark {
static func main() throws {
let words = ["nihao", "shijie", "zhongguo", "gongzuo", "xiexie", "zaijian", "tianqi", "jisuanji", "shurufa", "kaixin", "beijing", "shanghai", "nihaoshijie", "jing", "yi", "chenjingyi", "meigui", "kafei", "gongchengshi", "shengrikuaile"]
let started = DispatchTime.now().uptimeNanoseconds
let first = PinyinEngine.shared.query(rawInput: "nihao")
let coldMS = Double(DispatchTime.now().uptimeNanoseconds-started)/1e6
var samples: [Double] = []
for _ in 0..<10 { for word in words {
 let start = DispatchTime.now().uptimeNanoseconds
 _ = PinyinEngine.shared.query(rawInput: word)
 samples.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1e6)
}}
samples.sort()
let result: [String:Any] = ["queries":samples.count,"corpus":words,"coldFirstQueryMS":coldMS,"warmMedianMS":samples[samples.count/2],"warmP95MS":samples[Int(Double(samples.count)*0.95)],"warmMaxMS":samples.last!,"firstCandidate":first.first?.text ?? "", "method":"In-process Release-optimized engine query; excludes keystroke delivery, layout and display. 10 rounds x 20 pinyin strings; current local learning state."]
let data = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
print(String(decoding:data,as:UTF8.self))

}
}
