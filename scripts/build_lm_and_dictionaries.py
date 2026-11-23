#!/usr/bin/env python3
"""Build and re-rank AetherKey 2.0.0 offline dictionaries and language model.

Owned outputs:
  - Resources/lexicon.json
  - Resources/characters.json
  - Resources/lm.json
  - Resources/english_lexicon.json
  - Resources/chaizi.json
"""

from __future__ import annotations

from collections import Counter, defaultdict
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
WUBI_PATH = RESOURCES / "Wubi86" / "wubi86.dict.yaml"
LEXICON_PATH = RESOURCES / "lexicon.json"
CHARACTERS_PATH = RESOURCES / "characters.json"
LM_PATH = RESOURCES / "lm.json"
ENGLISH_PATH = RESOURCES / "english_lexicon.json"
CHAIZI_PATH = RESOURCES / "chaizi.json"
PINYIN_ENGINE_SWIFT = ROOT / "Sources" / "AetherKey" / "Engine" / "PinyinEngine.swift"


# ---------------------------------------------------------------------------
# 1. Curated lexicon overrides, modern 2022-2026 words, and demotions
# ---------------------------------------------------------------------------

# Exact top prefix guaranteed for critical keys (any remaining existing entries follow).
CRITICAL_LEXICON_PREFIX: dict[str, list[str]] = {
    "xianshi": ["显示", "现实", "先是", "县市", "西安市"],
    "yiyang": ["一样", "异样", "益阳"],
    "kending": ["肯定", "垦丁"],
    "yichang": ["一场", "异常", "宜昌"],
    "xiangxi": ["详细", "向西", "湘西"],
    "xingqi": ["星期", "兴起"],
    "shiyan": ["实验", "试验", "十堰"],
    "dali": ["大力", "打理", "搭理", "大理"],
    "weihai": ["危害", "威海"],
    "beihai": ["北海", "被害"],
    "yiwu": ["义务", "衣物", "义乌"],
    "yanji": ["演技", "延吉"],
    "xini": ["细腻", "悉尼"],
    "fujian": ["附件", "福建"],
    "chengdu": ["程度", "成都"],
    "xinxiang": ["心想", "信箱", "新乡"],
    "caigou": ["采购", "才够"],
    "dandang": ["担当", "但当"],
    "zaiqu": ["灾区", "再去"],
    "yifan": ["一番", "一翻"],
    "muji": ["募集", "目击", "母鸡"],
    "huaxiang": ["画像", "花香"],
    "xinlang": ["新浪", "新郎"],
    "zhiyuan": ["支援", "志愿", "职员", "只愿"],
    "weibo": ["微博", "微波", "微薄"],
    "jingdong": ["京东", "惊动"],
    "dingding": ["钉钉", "叮叮", "丁丁"],
    "xiecheng": ["携程", "写成", "协程"],
    "jiekou": ["接口", "借口"],
    "zujian": ["组件", "组建"],
    "paiqi": ["排期", "排气"],
    "faban": ["发版", "法办"],
    "duiqi": ["对齐", "对其"],
    "xicha": ["喜茶", "细查"],
    "duomotai": ["多模态", "多摸太"],
    "banwei": ["班味", "班委", "版位"],
    "dazi": ["打字", "搭子", "大字"],
    # Missing & modern daily / AI / office / colloquial entries
    "pinduoduo": ["拼多多"],
    "gaode": ["高德", "高的", "搞得", "搞的", "高得"],
    "bawangchaji": ["霸王茶姬"],
    "gongzuoliu": ["工作流"],
    "tishici": ["提示词"],
    "zhishiku": ["知识库"],
    "zhinengti": ["智能体"],
    "renxingjiqiren": ["人形机器人"],
    "zhinengjiashi": ["智能驾驶"],
    "qingxujiazhi": ["情绪价值"],
    "songchigan": ["松弛感"],
    "feishu": ["飞书", "飞鼠"],
    "qiyeweixin": ["企业微信"],
    "doubao": ["豆包"],
    "ruixing": ["瑞幸", "瑞星"],
    "mixuebingcheng": ["蜜雪冰城"],
    "weifuwu": ["微服务"],
    "yunsheng": ["云原生", "云生"],
    "yunyuansheng": ["云原生"],
    "yihuir": ["一会儿"],
    "yidianr": ["一点儿"],
    "meishir": ["没事儿"],
    "haowanr": ["好玩儿"],
    "zher": ["这儿"],
    "nar": ["那儿"],
    "youmeiyou": ["有没有", "又没有"],
    "xingqiyi": ["星期一"],
    "xingqier": ["星期二"],
    "xingqisan": ["星期三"],
    "xingqisi": ["星期四"],
    "xingqiwu": ["星期五"],
    "xingqiliu": ["星期六"],
    "xingqitian": ["星期天"],
    "xingqiri": ["星期日"],
    "gongzuoyichang": ["工作异常"],
    "xianshiyixia": ["显示一下"],
    "shurufa": ["输入法"],
}

# Additional 2022-2026 modern words & daily phrases to add or boost to #1.
MODERN_PHRASES: dict[str, list[str]] = {
    "damoxing": ["大模型"],
    "zidongjiashi": ["自动驾驶"],
    "tengxunhuiyi": ["腾讯会议"],
    "shipinhao": ["视频号"],
    "shuziyoumin": ["数字游民"],
    "chabaidao": ["茶百道"],
    "guming": ["古茗", "故名", "古名"],
    "kudi": ["库迪"],
    "naixuedecha": ["奈雪的茶"],
    "tongyiqianwen": ["通义千问"],
    "wenxinyiyan": ["文心一言"],
    "xiangliangshujuku": ["向量数据库"],
    "huaweiyun": ["华为云"],
    "tengxunyun": ["腾讯云"],
    "xiugaiyixia": ["修改一下"],
    "querenyixia": ["确认一下", "确认以下"],
    "duiqiyixia": ["对齐一下"],
    "fayixia": ["发一下"],
    "kanyixia": ["看一下"],
    "denglubushang": ["登录不上"],
    "eleme": ["饿了么"],
    "feizhu": ["飞猪", "肥猪"],
    "didi": ["滴滴", "弟弟", "嘀嘀"],
    "yanzhi": ["颜值", "研制", "胭脂"],
    "xianyu": ["闲鱼", "咸鱼", "限于"],
    "yingweida": ["英伟达"],
    "wangyiyun": ["网易云"],
    "xiaohongshu": ["小红书"],
    "zhifubao": ["支付宝"],
    "weixinzhifu": ["微信支付"],
    "zhongguancun": ["中关村"],
    "weilaikejicheng": ["未来科技城"],
    "qingshuru": ["请输入"],
    "kanxia": ["看下"],
    "nide": ["你的"],
    "wode": ["我的"],
    "tade": ["他的", "她的", "它的"],
    "meidian": ["没电"],
    "meidianle": ["没电了"],
    "youdianka": ["有点卡"],
    "youdian": ["有点", "优点", "邮电"],
    "dianle": ["电了"],
    "zaijia": ["在家", "再加", "在架"],
    "gangdao": ["刚到"],
    "jiudao": ["就到"],
    "bushang": ["不上"],
    "yixia": ["一下"],
    "jidian": ["几点", "极点", "积淀", "基点"],
    "bangwo": ["帮我"],
    "qingbangwo": ["请帮我"],
    "meiwenti": ["没问题"],
    "zhansan": ["张三"],
    "zhangsan": ["张三"],
    "huoguo": ["火锅"],
    "shuijiao": ["睡觉", "水饺"],
    "fandazi": ["饭搭子"],
    "lvyou": ["旅游", "驴友"],
    "jiaxiao": ["驾校"],
    "guzhi": ["估值", "股指"],
    "qixing": ["骑行", "七星"],
    "dadie": ["大跌", "大碟"],
    "aidou": ["爱豆"],
    "baohuo": ["爆火"],
    "shanma": ["删吗"],
    "henku": ["很酷", "很苦"],
    "nishi": ["你是"],
    "woshi": ["我是"],
    "bushi": ["不是", "不时", "不适", "布什"],
    "tashi": ["他是", "她是", "它是"],
    "wozai": ["我在"],
    "nizai": ["你在"],
    "zhina": ["只拿"],
    "aile": ["爱了"],
    "lihe": ["礼盒"],
    "mibao": ["密保"],
    "fulei": ["父类"],
    "sizhai": ["死宅"],
    "weijie": ["未接"],
    "shengju": ["省局"],
    "baoxiao": ["报销"],
    "citie": ["磁铁"],
    "diyu": ["低于", "地狱"],
    "wuyu": ["无语"],
    "youxian": ["优先", "有限"],
    "shoudao": ["收到", "受到"],
    "meishi": ["没事", "美食"],
    "haoma": ["好吗", "号码"],
    "zhenshi": ["真是", "真实"],
    "shihua": ["实话", "石化"],
    "youming": ["有名"],
    "meiren": ["没人"],
    "bujian": ["不见", "部件"],
    "shangwu": ["上午", "商务"],
    "yisheng": ["医生", "一生"],
    "gaosu": ["告诉", "高速"],
    "tuiding": ["退订"],
    "zaizhe": ["在这"],
    "shanghao": ["上号", "上好"],
    "daban": ["打扮", "大半", "大阪"],
    "jingdu": ["精度", "京都"],
    "taizhong": ["太重", "台中"],
    "shiyanshi": ["实验室", "试验室", "十堰市"],
    "dalishi": ["大理石", "大力士", "大理市"],
    "jianshi": ["监视", "见识", "坚实"],
    "luanshi": ["乱世", "卵石"],
    "nantongshi": ["男同事", "南通市"],
    "yiwushi": ["医务室", "义乌市"],
    "yiyangshi": ["一样是", "益阳市"],
    "xianzhan": ["先占", "先站"],
    "chuhehanjie": ["楚河汉界", "楚河汉街"],
    "bantian": ["半天", "坂田"],
    "changdu": ["长度", "昌都"],
    "chengyu": ["成语", "成渝"],
    "chongsheng": ["重生", "冲绳"],
    "fuzhou": ["福州", "抚州"],
    "suzhou": ["苏州", "宿州"],
    "xian": ["西安", "西岸"],
    "jincheng": ["进程", "晋城"],
    "jinli": ["尽力", "锦鲤"],
    "meizhou": ["每周", "美洲", "梅州"],
    "qingyuan": ["情缘", "清远"],
    "xingtai": ["形态", "邢台"],
    "xinyang": ["信仰", "信阳"],
    "xinyu": ["信誉", "新余"],
    "yanbian": ["演变", "延边"],
    "yunfu": ["孕妇", "云浮"],
    "yunqi": ["运气", "孕期"],
    "zhuji": ["主机", "逐级", "诸暨"],
    "zigong": ["子宫", "自贡"],
    "jiayi": ["加以", "加一", "嘉义"],
    "liangzhu": ["梁祝", "良渚"],
    "guanggu": ["光顾", "光谷"],
    "jinjiang": ["金奖", "晋江"],
    "jiujiang": ["就将", "九江"],
    "linzhi": ["磷脂", "林芝"],
    "mohe": ["磨合", "漠河"],
    "qiantan": ["浅谈", "前滩"],
    "qufu": ["屈服", "曲阜"],
    "qujing": ["取景", "取经", "曲靖"],
    "tonghua": ["通话", "童话", "通化"],
    "tongling": ["统领", "同龄", "铜陵"],
    "tongxiang": ["通向", "同乡", "桐乡"],
    "weinan": ["为难", "危难", "渭南"],
    "wuwei": ["无畏", "无为", "武威"],
    "wuyuan": ["无缘", "婺源"],
    "xuancheng": ["宣称", "宣城"],
    "yili": ["毅力", "伊犁"],
    "yuxi": ["预习", "玉溪"],
    "baise": ["白色", "百色"],
    "anqing": ["案情", "安庆"],
    "aba": ["阿爸", "阿坝"],
    "changshu": ["常数", "常熟"],
    "changlong": ["长隆", "长龙"],
    "yingtan": ["影坛", "鹰潭"],
    "wuhai": ["无害", "乌海"],
    "hebi": ["何必", "鹤壁"],
    "hezhou": ["喝粥", "贺州"],
    "guyuan": ["雇员", "固原"],
    "guangyuan": ["光源", "广元"],
    "dazhou": ["大洲", "达州"],
    "ziyang": ["滋养", "资阳"],
    "xinzhu": ["新竹", "新主"],
    "hualian": ["花脸", "花莲"],
    "xiasha": ["吓傻", "下沙"],
    "jiubao": ["酒保", "九堡"],
}

# 2008 web-corpus boilerplate or offensive terms that should never outrank everyday words.
DEMOTE_WORDS: dict[str, float] = {
    "支那": 0.001,
    "此帖": 0.01,
    "仅供": 0.05,
    "又名": 0.05,
    "邮编": 0.05,
    "致电": 0.05,
    "物语": 0.15,
    "爆笑": 0.08,
    "地域": 0.05,
    "石化": 0.10,
    "骟马": 0.01,
    "包伙": 0.01,
    "挨斗": 0.01,
    "逆势": 0.10,
    "慰藉": 0.20,
    "大字": 0.20,
    "组建": 0.40,
    "对其": 0.15,
    "大阪": 0.05,
    "京都": 0.10,
}

SPOKEN_PARTICLES = set(
    "的我你他她它这那谁吗呢吧啊呀了是在有不没很太真爱只才又再就都也还别去来看说吃喝玩给把被让和跟"
)


# ---------------------------------------------------------------------------
# 2. Load Wubi86 and Swift Foundation helpers
# ---------------------------------------------------------------------------


def load_wubi86() -> tuple[dict[str, int], dict[str, int]]:
    single_weights: dict[str, int] = {}
    phrase_weights: dict[str, int] = {}
    in_table = False
    with WUBI_PATH.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line == "...":
                in_table = True
                continue
            if not in_table or not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3 or not parts[2].isdigit():
                continue
            word, wt = parts[0], int(parts[2])
            if len(word) == 1:
                if wt > single_weights.get(word, 0):
                    single_weights[word] = wt
            else:
                if wt > phrase_weights.get(word, 0):
                    phrase_weights[word] = wt
    return single_weights, phrase_weights


def parse_pinyin_engine_constants() -> tuple[dict[str, list[str]], dict[str, str]]:
    src = PINYIN_ENGINE_SWIFT.read_text(encoding="utf-8")
    core_match = re.search(
        r"coreSyllablesChars:\s*\[String:\s*\[String\]\]\s*=\s*\[(.*?)\n    \]",
        src,
        re.S,
    )
    core_chars: dict[str, list[str]] = {}
    if core_match:
        for line in core_match.group(1).splitlines():
            lm = re.match(r'\s*"([a-z]+)":\s*\[(.*?)\]', line)
            if lm:
                core_chars[lm.group(1)] = re.findall(r'"([^"]+)"', lm.group(2))

    single_match = re.search(
        r"sentenceSingleCharMap:\s*\[String:\s*String\]\s*=\s*\[(.*?)\n    \]",
        src,
        re.S,
    )
    single_map: dict[str, str] = {}
    if single_match:
        for k, v in re.findall(r'"([a-z]+)":\s*"([^"]+)"', single_match.group(1)):
            single_map[k] = v
    return core_chars, single_map


def query_swift_character_info(chars: list[str]) -> dict[str, tuple[str, str, bool]]:
    """Return {char: (plain_syllable, toned_pinyin, is_simplified_or_neutral)} via macOS Foundation."""
    swift_code = r"""
import Foundation
let data = FileHandle.standardInput.readDataToEndOfFile()
let text = String(data: data, encoding: .utf8)!
let hantHans = StringTransform(rawValue: "Hant-Hans")
var out: [String] = []
out.reserveCapacity(text.count)
for line in text.split(separator: "\n") {
    let s = String(line)
    let latin = s.applyingTransform(.toLatin, reverse: false) ?? ""
    var scalars = ""
    for sc in latin.decomposedStringWithCanonicalMapping.unicodeScalars {
        if sc.value == 0x0308 {
            if scalars.last == "u" { scalars.removeLast(); scalars.append("v") }
        } else if sc.properties.generalCategory != .nonspacingMark {
            scalars.append(Character(sc))
        }
    }
    let syl = scalars.lowercased().filter { $0 >= "a" && $0 <= "z" }
    let simp = s.applyingTransform(hantHans, reverse: false) ?? s
    let isSimp = (simp == s) ? "1" : "0"
    out.append("\(s)\t\(syl)\t\(latin)\t\(isSimp)")
}
print(out.joined(separator: "\n"))
"""
    with tempfile.TemporaryDirectory() as td:
        src_path = Path(td) / "charinfo.swift"
        bin_path = Path(td) / "charinfo"
        src_path.write_text(swift_code, encoding="utf-8")
        subprocess.run(["swiftc", "-O", str(src_path), "-o", str(bin_path)], check=True)
        res = subprocess.run(
            [str(bin_path)],
            input="\n".join(chars),
            text=True,
            capture_output=True,
            check=True,
        )
    info: dict[str, tuple[str, str, bool]] = {}
    for line in res.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 4:
            ch, sy, toned, simp = parts
            info[ch] = (sy, toned, simp == "1")
    return info


# ---------------------------------------------------------------------------
# 3. Re-rank lexicon.json
# ---------------------------------------------------------------------------


def rerank_lexicon(
    lex: dict[str, list[str]],
    single_w: dict[str, int],
    phrase_w: dict[str, int],
) -> dict[str, list[str]]:
    boost_map: dict[tuple[str, str], int] = {}
    for key, words in MODERN_PHRASES.items():
        for rank, w in enumerate(words):
            boost_map[(key, w)] = 1_500_000_000 - rank * 50_000_000

    # Ensure all missing keys exist and contain curated words
    merged_keys: dict[str, list[str]] = {}
    all_keys = set(lex.keys()) | set(CRITICAL_LEXICON_PREFIX.keys()) | set(MODERN_PHRASES.keys())

    for key in sorted(all_keys):
        existing = list(lex.get(key, []))
        # Append any newly introduced curated words that are not yet present
        seen_set = set(existing)
        for src_dict in (CRITICAL_LEXICON_PREFIX, MODERN_PHRASES):
            for w in src_dict.get(key, []):
                if w not in seen_set:
                    existing.append(w)
                    seen_set.add(w)

        # Deduplicate preserving first index
        dedup: list[str] = []
        seen_dedup: set[str] = set()
        for w in existing:
            if w and w not in seen_dedup:
                seen_dedup.add(w)
                dedup.append(w)

        def total_score(w: str) -> float:
            base = float(phrase_w.get(w, 0))
            if w in DEMOTE_WORDS:
                base *= DEMOTE_WORDS[w]
            boost = float(boost_map.get((key, w), 0))
            return base + boost

        ranked = [w for _, w in sorted(enumerate(dedup), key=lambda x: (-total_score(x[1]), x[0]))]

        # Protect existing rank-0 modern spoken word if the top Wubi entry is too weak to displace it.
        if dedup:
            first_w = dedup[0]
            floor = 350_000.0
            if (
                len(first_w) == 2
                and (first_w[0] in SPOKEN_PARTICLES or first_w[1] in SPOKEN_PARTICLES)
                and min(single_w.get(first_w[0], 0), single_w.get(first_w[1], 0)) >= 80_000_000
            ):
                floor = 2_600_000.0
            if ranked and total_score(ranked[0]) <= max(total_score(first_w), floor):
                ranked = [first_w] + [w for w in ranked if w != first_w]

        # Enforce exact leading prefix for critical keys
        if key in CRITICAL_LEXICON_PREFIX:
            prefix = CRITICAL_LEXICON_PREFIX[key]
            prefix_set = set(prefix)
            ranked = list(prefix) + [w for w in ranked if w not in prefix_set]

        merged_keys[key] = ranked

    return merged_keys


# ---------------------------------------------------------------------------
# 4. Re-rank characters.json
# ---------------------------------------------------------------------------


def build_char_to_syllables(chars_data: dict[str, str]) -> dict[str, set[str]]:
    char_syls: dict[str, set[str]] = defaultdict(set)
    for syl, chars in chars_data.items():
        for ch in chars:
            char_syls[ch].add(syl)
            if syl == "lve":
                char_syls[ch].add("lue")
            elif syl == "nve":
                char_syls[ch].add("nue")
    return char_syls


def split_key_for_word(key: str, word: str, char_syls: dict[str, set[str]]) -> list[str] | None:
    clean = key.replace("'", "")
    n, m = len(clean), len(word)
    memo: dict[tuple[int, int], list[str] | None] = {}

    def dfs(ki: int, wi: int) -> list[str] | None:
        state = (ki, wi)
        if state in memo:
            return memo[state]
        if wi == m:
            res: list[str] | None = [] if ki == n else None
            memo[state] = res
            return res
        allowed = char_syls.get(word[wi], set())
        for length in range(1, min(7, n - ki + 1)):
            sub = clean[ki : ki + length]
            if sub in allowed:
                rest = dfs(ki + length, wi + 1)
                if rest is not None:
                    norm = "lve" if sub == "lue" else ("nve" if sub == "nue" else sub)
                    out = [norm] + rest
                    memo[state] = out
                    return out
        memo[state] = None
        return None

    return dfs(0, 0)


def rerank_characters(
    chars_data: dict[str, str],
    lex_data: dict[str, list[str]],
    single_w: dict[str, int],
    phrase_w: dict[str, int],
    char_info: dict[str, tuple[str, str, bool]],
    core_chars: dict[str, list[str]],
    sentence_single: dict[str, str],
) -> dict[str, str]:
    char_syls = build_char_to_syllables(chars_data)
    phrase_ev: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    total_ev: dict[str, int] = defaultdict(int)

    for ch, sw in single_w.items():
        total_ev[ch] += sw

    for key, words in lex_data.items():
        for idx, word in enumerate(words):
            if not (2 <= len(word) <= 6):
                continue
            wt = phrase_w.get(word, 0) or max(100_000, 1_000_000 // (idx + 1))
            syls = split_key_for_word(key, word, char_syls)
            if syls:
                for ch, sy in zip(word, syls):
                    phrase_ev[sy][ch] += wt
                    total_ev[ch] += wt

    reranked: dict[str, str] = {}
    for sy, orig in chars_data.items():
        core = core_chars.get(sy, [])
        top_single = sentence_single.get(sy)
        rows = []
        for idx, ch in enumerate(orig):
            pr, _, is_simp = char_info.get(ch, ("", "", True))
            pr_norm = "lve" if pr == "lue" else ("nve" if pr == "nue" else pr)
            is_primary = pr_norm == sy
            ev = phrase_ev[sy][ch]
            tot = max(1, total_ev[ch])
            is_core = ch in core
            sw = single_w.get(ch, 0)

            # Genuine modern polyphones (e.g. 行/hang, 长/chang, 地/di, 乐/yue) remain in primary tier,
            # while archaic/variant readings (e.g. 而/neng, 登/de, 夭/wo, 说/shui) are demoted.
            is_polyphone = (not is_primary) and (
                (ev >= 10_000_000 and ev * 50 >= tot)
                or (is_core and ev >= 500_000)
            )
            is_modern = is_primary or is_polyphone

            bmp_rank = 0 if (ord(ch) <= 0x9FFF and is_simp) else (1 if ord(ch) <= 0x9FFF else 2)
            if is_modern:
                # Separate non-core rare-ratio polyphones (like 的 in di) after common primary chars
                if is_primary or is_core:
                    tier = bmp_rank
                else:
                    tier = 0 if bmp_rank == 0 and ev * 10 >= tot else (bmp_rank + 1)
                single_boost = 500_000_000_000 if ch == top_single else 0
                core_boost = (200 - core.index(ch)) * 1_000_000_000 if is_core else 0
                freq_score = single_boost + core_boost + (sw if is_primary else 0) + ev
            else:
                tier = 4 + bmp_rank
                freq_score = ev + (sw // 100)

            rows.append((tier, -freq_score, idx, ch))
        rows.sort()
        reranked[sy] = "".join(r[3] for r in rows)
    return reranked


# ---------------------------------------------------------------------------
# 5. Language model (lm.json)
# ---------------------------------------------------------------------------

HIGH_PRIORITY_FUNCTION_CHARS = [
    ("的", -110), ("了", -120), ("是", -122), ("我", -124), ("你", -126),
    ("在", -128), ("有", -130), ("不", -132), ("这", -136), ("他", -138),
    ("她", -142), ("它", -148), ("一", -134), ("个", -140), ("好", -144),
    ("就", -145), ("都", -146), ("也", -147), ("要", -149), ("会", -150),
    ("去", -152), ("来", -153), ("看", -154), ("说", -155), ("想", -156),
    ("能", -158), ("很", -160), ("还", -162), ("那", -163), ("和", -164),
    ("到", -165), ("上", -166), ("下", -167), ("里", -168), ("中", -169),
    ("人", -170), ("大", -172), ("小", -174), ("多", -175), ("少", -176),
    ("吃", -177), ("给", -178), ("对", -179), ("没", -180), ("吗", -181),
    ("呢", -182), ("吧", -183), ("啊", -184), ("呀", -185), ("把", -186),
    ("被", -187), ("让", -188), ("从", -189), ("为", -190), ("用", -191),
    ("请", -192), ("问", -193), ("刚", -194), ("先", -195), ("别", -196),
    ("跟", -197), ("向", -198), ("往", -199), ("比", -200), ("按", -202),
    ("太", -203), ("真", -204), ("只", -205), ("才", -206), ("又", -207),
    ("再", -208), ("已", -209), ("将", -210), ("可", -211), ("得", -212),
    ("着", -213), ("过", -214), ("谁", -216), ("哪", -218), ("啥", -222),
]

CURATED_UNIGRAMS: dict[str, int] = {
    "明天": -240, "今天": -235, "昨天": -260, "现在": -238, "已经": -242,
    "可以": -225, "没有": -220, "知道": -236, "什么": -228, "怎么": -232,
    "我们": -215, "你们": -245, "他们": -248, "这个": -226, "那个": -234,
    "我的": -228, "你的": -230, "他的": -248, "她的": -254, "我们的": -275,
    "星期一": -320, "星期二": -325, "星期三": -325, "星期四": -325,
    "星期五": -320, "星期六": -325, "星期天": -320, "星期日": -325,
    "输入": -260, "密码": -278, "看下": -290, "看一下": -282, "有没有": -265,
    "问题": -238, "在家": -285, "公司": -250, "水饺": -330, "睡觉": -315,
    "西安": -280, "北京": -245, "上海": -247, "陕西": -292, "山西": -300,
    "显示": -242, "一下": -248, "显示一下": -280, "工作": -240, "异常": -295,
    "工作异常": -285, "肯定": -260, "没问题": -275, "一会儿": -288, "就到": -305,
    "登录": -272, "不上": -302, "登录不上": -290, "修改": -270, "修改一下": -285,
    "一起": -252, "吃饭": -274, "一起吃饭": -285, "几点": -294, "现在几点": -290,
    "手机": -254, "没电": -308, "电了": -322, "手机没电": -295,
    "电脑": -256, "有点": -272, "帮我": -280,
    "一点儿": -308, "没事儿": -315, "好玩儿": -325, "这儿": -308, "那儿": -310,
    "输入法": -292, "工作流": -318, "提示词": -318, "知识库": -312, "智能体": -318,
    "多模态": -328, "拼多多": -308, "高德": -308, "飞书": -312, "豆包": -318,
    "瑞幸": -318, "蜜雪冰城": -322, "霸王茶姬": -332, "企业微信": -312,
    "微服务": -322, "云原生": -328, "大模型": -302, "情绪价值": -328,
    "松弛感": -332, "智能驾驶": -328, "人形机器人": -338, "喜茶": -322,
    "排期": -318, "发版": -322, "班味": -338, "搭子": -328, "微博": -286,
    "京东": -284, "钉钉": -296, "携程": -302, "组件": -290, "对齐": -294,
    "接口": -276, "打字": -298,
}

CURATED_BIGRAMS: dict[str, int] = {
    "明天\t是": 250, "今天\t是": 250,
    "是\t星期一": 260, "是\t星期二": 260, "是\t星期三": 260, "是\t星期四": 260,
    "是\t星期五": 260, "是\t星期六": 260, "是\t星期天": 260, "是\t星期日": 260,
    "请\t输入": 265, "输入\t你的": 255, "你的\t密码": 270,
    "看下\t有没有": 265, "看一下\t有没有": 255, "有没有\t问题": 275,
    "你\t是": 225, "我\t是": 225, "他\t是": 215, "是\t在家": 255, "在家\t吗": 260,
    "刚\t到": 240, "到\t公司": 260, "刚到\t公司": 265,
    "吃\t水饺": 295, "吃\t饭": 280, "去\t西安": 280, "去\t北京": 270,
    "去\t上海": 270, "去\t陕西": 275, "去\t山西": 265,
    "显示\t一下": 285, "工作\t异常": 280,
    "我的\t肯定": 260, "肯定\t没问题": 285,
    "我\t一会儿": 270, "一会儿\t就到": 290,
    "登录\t不上": 280, "修改\t一下": 275, "一起\t吃饭": 280,
    "现在\t几点": 280, "手机\t没电": 280, "电脑\t有点": 270,
    "没\t电了": 280, "没电\t了": 280, "有点\t卡": 280,
    "请\t帮我": 270, "帮我\t看": 270, "帮我\t看下": 275, "帮我\t看一下": 275,
    "我\t去": 215, "我\t想": 220, "我\t在": 220, "我\t有": 205, "我\t们": 195,
    "你\t好": 225, "你\t在": 220, "你\t看": 205, "在\t吗": 225, "好\t吗": 225,
    "吃\t什么": 235, "想\t吃": 230, "去\t玩": 220, "回\t家": 230,
    "写\t代码": 245, "改\t一下": 235, "看\t一下": 245, "试\t一下": 235,
    "等\t一下": 240, "问\t一下": 235, "发\t一下": 235, "查\t一下": 235,
    "这\t个": 220, "那\t个": 215, "一\t个": 230, "有\t点": 225, "没\t有": 235,
    "不\t会": 215, "不\t行": 220, "不\t知道": 235, "很\t好": 220, "真\t好": 225,
}


def build_language_model(
    lex: dict[str, list[str]],
    single_w: dict[str, int],
    phrase_w: dict[str, int],
) -> dict[str, dict[str, int]]:
    # Compute total corpus mass for realistic log10 probability calibration
    total_mass = float(sum(single_w.values()) + sum(phrase_w.values()))
    log_total = math.log10(max(1.0, total_mass))

    unigrams: dict[str, int] = {}

    # 1. Single characters (top 6,500 from Wubi86 + all curated colloquial function chars)
    # Normalize to NFC so CJK compatibility variants do not collide under Swift String hashing.
    top_singles = sorted(single_w.items(), key=lambda x: -x[1])[:6500]
    for raw_ch, wt in top_singles:
        ch = unicodedata.normalize("NFC", raw_ch)
        raw_score = int(round((math.log10(max(1, wt)) - log_total) * 100))
        score = max(-760, min(-125, raw_score))
        if score > unigrams.get(ch, -999):
            unigrams[ch] = score

    for ch, score in HIGH_PRIORITY_FUNCTION_CHARS:
        unigrams[ch] = max(unigrams.get(ch, -800), score)

    # 2. Top phrases from Wubi86 + modern curated phrases (~68,000 phrases total)
    phrase_candidates: dict[str, int] = {}
    for w, wt in phrase_w.items():
        if 2 <= len(w) <= 6 and not any(w == bad for bad in DEMOTE_WORDS if DEMOTE_WORDS[bad] <= 0.05):
            eff_wt = int(wt * DEMOTE_WORDS.get(w, 1.0))
            if eff_wt > 0:
                phrase_candidates[w] = eff_wt

    top_phrases = sorted(phrase_candidates.items(), key=lambda x: -x[1])[:65000]
    for w, wt in top_phrases:
        raw_score = int(round((math.log10(max(1, wt)) - log_total) * 100))
        unigrams[w] = max(-800, min(-190, raw_score))

    # Supplement top-ranked modern/daily words from lexicon.json not in Wubi86
    for key, words in lex.items():
        if not words:
            continue
        top_w = words[0]
        if 2 <= len(top_w) <= 5 and top_w not in unigrams and len(unigrams) < 76000:
            if key in MODERN_PHRASES or key in CRITICAL_LEXICON_PREFIX:
                unigrams[top_w] = -330
            elif len(top_w) <= 4 and all(c in unigrams and unigrams[c] >= -420 for c in top_w):
                avg_c = sum(unigrams[c] for c in top_w) / len(top_w)
                unigrams[top_w] = max(-740, min(-380, int(round(avg_c - 160))))

    for w, score in CURATED_UNIGRAMS.items():
        unigrams[w] = max(unigrams.get(w, -800), score)

    # 3. Extract 25,000-35,000 high-value bigram bonuses strictly from 3-4 char phrases + curated pairs.
    # Avoid splitting 2-char lexical words into 1+1 bigrams so 1-char chains do not overpower real 2-char words.
    bigrams: dict[str, int] = dict(CURATED_BIGRAMS)
    bigram_ranks: dict[str, float] = {}
    vocab_set = set(unigrams.keys())

    candidates_34: list[tuple[float, str]] = []
    seen_34: set[str] = set()
    for ws in lex.values():
        for w in ws[:3]:
            if (len(w) == 3 or len(w) == 4) and w not in seen_34:
                seen_34.add(w)
                wt = phrase_w.get(w, 0)
                if wt > 0:
                    score = math.log10(wt)
                elif len(w) == 4 and w[:2] in unigrams and w[2:] in unigrams:
                    score = 5.5 + (unigrams[w[:2]] + unigrams[w[2:]]) / 300.0
                elif len(w) == 3 and ((w[0] in unigrams and w[1:] in unigrams) or (w[:2] in unigrams and w[2] in unigrams)):
                    score = 5.2 + sum(unigrams.get(c, -600) for c in w) / 450.0
                else:
                    continue
                candidates_34.append((score, w))

    candidates_34.sort(reverse=True)
    for score, word in candidates_34:
        splits: list[tuple[str, str]] = []
        if len(word) == 4:
            a, b = word[:2], word[2:]
            if a in vocab_set and b in vocab_set:
                splits.append((a, b))
        elif len(word) == 3:
            if word[0] in vocab_set and word[1:] in vocab_set and unigrams.get(word[1:], -800) >= -580:
                splits.append((word[0], word[1:]))
            if word[:2] in vocab_set and word[2] in vocab_set and unigrams.get(word[:2], -800) >= -580:
                splits.append((word[:2], word[2]))
        for prev_w, next_w in splits:
            pair_key = f"{prev_w}\t{next_w}"
            if score > bigram_ranks.get(pair_key, -1e9):
                bigram_ranks[pair_key] = score
        if len(bigram_ranks) >= 32000:
            break

    sorted_pairs = sorted(bigram_ranks.items(), key=lambda x: -x[1])[:31000]
    if sorted_pairs:
        s_max = sorted_pairs[0][1]
        s_min = sorted_pairs[-1][1]
        span = max(0.01, s_max - s_min)
        for pair_key, sc in sorted_pairs:
            norm = (sc - s_min) / span
            bonus = int(round(55 + norm * 215))
            if pair_key not in bigrams:
                bigrams[pair_key] = bonus
            else:
                bigrams[pair_key] = max(bigrams[pair_key], bonus)

    return {"u": unigrams, "b": bigrams}


# ---------------------------------------------------------------------------
# 6. English lexicon (english_lexicon.json)
# ---------------------------------------------------------------------------

# (DisplayCase, weight, preferFirst)
TECH_AND_CRITICAL_ENGLISH: list[tuple[str, int, bool]] = [
    ("OK", 995, True), ("bug", 940, False), ("App", 960, True), ("API", 970, True),
    ("PPT", 955, True), ("PDF", 960, True), ("WiFi", 955, True), ("Mac", 930, False),
    ("macOS", 965, True), ("iPhone", 955, True), ("iPad", 945, True), ("WeChat", 930, True),
    ("GitHub", 955, True), ("VSCode", 945, True), ("Python", 950, True), ("Swift", 945, True),
    ("Docker", 940, True), ("JSON", 925, False), ("HTTP", 935, True), ("HTTPS", 935, True),
    ("URL", 935, True), ("AI", 985, False), ("LLM", 945, True), ("GPT", 950, True),
    ("ChatGPT", 950, True), ("OpenAI", 935, True), ("Claude", 935, True), ("Gemini", 900, False),
    ("DeepSeek", 940, True), ("Cursor", 930, True), ("PR", 910, False), ("MR", 880, False),
    ("UI", 920, False), ("UX", 895, False), ("PM", 905, False), ("CEO", 910, False),
    ("CTO", 895, False), ("KPI", 925, True), ("OKR", 920, True), ("TODO", 905, False),
    ("demo", 910, False), ("debug", 930, True), ("deploy", 900, False), ("commit", 925, True),
    ("merge", 890, False), ("branch", 885, False), ("email", 920, False), ("code", 915, False),
    ("Xcode", 935, True), ("bilibili", 895, False), ("Linux", 920, True), ("Windows", 905, False),
    ("Android", 915, True), ("iOS", 940, True), ("React", 900, False), ("Vue", 885, False),
    ("Node", 880, False), ("Rust", 890, False), ("SQL", 930, True), ("Redis", 910, True),
    ("Git", 915, False), ("SSH", 925, True), ("VPN", 935, True), ("CPU", 940, True),
    ("GPU", 945, True), ("iCloud", 925, True), ("AirDrop", 915, True),
    ("hello", 910, False), ("world", 900, False), ("thanks", 905, False), ("sorry", 900, False),
    ("good", 915, False), ("nice", 900, False), ("test", 910, False), ("fix", 905, False),
    ("file", 895, False), ("data", 910, False), ("user", 905, False), ("time", 910, False),
    ("true", 890, False), ("false", 890, False), ("null", 885, False), ("async", 895, False),
    ("await", 890, False),
    # Extra tech / AI / office / macOS / dev terms
    ("TypeScript", 910, True), ("JavaScript", 910, True), ("Kubernetes", 895, True),
    ("GraphQL", 890, True), ("OAuth", 890, True), ("Markdown", 895, True),
    ("YAML", 900, True), ("HTML", 920, True), ("CSS", 915, True), ("DOM", 870, False),
    ("SVG", 895, True), ("PNG", 900, True), ("JPG", 895, True), ("JPEG", 880, True),
    ("WebP", 875, True), ("MP3", 890, True), ("MP4", 895, True), ("SDK", 915, True),
    ("CLI", 910, True), ("IDE", 905, True), ("RAM", 900, False), ("SSD", 905, True),
    ("HDD", 875, True), ("USB", 920, True), ("HDMI", 900, True), ("DNS", 905, True),
    ("TCP", 895, True), ("UDP", 890, True), ("IP", 910, False), ("SSL", 900, True),
    ("TLS", 895, True), ("JWT", 895, True), ("UUID", 890, True), ("Regex", 885, False),
    ("SQLite", 895, True), ("PostgreSQL", 890, True), ("MongoDB", 885, True),
    ("Nginx", 890, True), ("Homebrew", 885, True), ("Finder", 875, False),
    ("Safari", 880, False), ("Chrome", 895, False), ("Slack", 885, False),
    ("Zoom", 880, False), ("Notion", 895, False), ("Figma", 900, True),
    ("Jira", 890, True), ("Linear", 875, False), ("Vercel", 885, True),
    ("Cloudflare", 885, True), ("AWS", 915, True), ("Azure", 890, True),
    ("GCP", 895, True), ("PyTorch", 900, True), ("TensorFlow", 885, True),
    ("Anthropic", 890, True), ("RAG", 880, False), ("Agent", 885, False),
    ("Prompt", 890, False), ("Token", 890, False), ("AetherKey", 950, True),
    ("SwiftUI", 905, True), ("AppKit", 895, True), ("XcodeGen", 880, True),
    ("npm", 895, True), ("pnpm", 890, True), ("yarn", 880, False), ("pip", 880, False),
    ("pytest", 885, True), ("localhost", 895, True), ("dev", 885, False),
    ("prod", 880, False), ("staging", 870, False), ("hotfix", 885, True),
    ("rollback", 875, False), ("benchmark", 875, False), ("webhook", 880, True),
    ("endpoint", 875, False), ("payload", 870, False), ("config", 890, False),
    ("regex", 885, False), ("cron", 875, False), ("sudo", 890, True),
    ("brew", 875, False), ("curl", 880, False), ("grep", 885, True),
    ("nvim", 880, True), ("vim", 885, False), ("tmux", 885, True),
    ("zsh", 890, True), ("bash", 885, False), ("ssh", 925, True),
    ("Apple", 905, False), ("Google", 910, False), ("Microsoft", 895, False),
    ("Tesla", 875, False), ("NVIDIA", 915, True), ("AMD", 900, True),
    ("Intel", 895, True), ("ARM", 890, False), ("M1", 880, True),
    ("M2", 880, True), ("M3", 885, True), ("M4", 890, True),
    ("Excel", 915, False), ("Word", 905, False), ("Outlook", 885, False),
    ("Teams", 885, False), ("Zoom", 880, False), ("Feishu", 870, False),
    ("HR", 900, False), ("PR", 910, False), ("QA", 905, False), ("RD", 895, False),
    ("FE", 885, False), ("BE", 880, False), ("Ops", 890, False), ("DevOps", 905, True),
    ("ROI", 895, True), ("GMV", 890, True), ("DAU", 895, True), ("MAU", 890, True),
    ("B2B", 890, True), ("B2C", 885, True), ("SaaS", 905, True), ("PaaS", 880, True),
    ("IaaS", 875, True), ("VIP", 920, True), ("FAQ", 910, True), ("DIY", 905, True),
    ("ETA", 890, False), ("FYI", 895, True), ("ASAP", 905, True), ("TBD", 890, True),
    ("LGTM", 895, True), ("BTW", 890, True), ("IMO", 885, True), ("OMG", 880, True),
    ("WFH", 890, True), ("PTO", 885, True), ("SOP", 905, True), ("PRD", 910, True),
    ("NDA", 890, True), ("IPO", 900, True), ("GDP", 900, True), ("CPI", 890, True),
]

# ~3,500+ high-frequency everyday English words (space-separated, verified against /usr/share/dict/words).
COMMON_ENGLISH_RAW = """
about above abroad absence absent absolute absolutely absorb abuse academic accept access accident
accompany accomplish according account accurate accuse achieve achievement acid acknowledge acquire
across act action active actively activity actor actress actual actually ad adapt add addition
additional address adequate adjust administration admire admit adopt adult advance advanced advantage
adventure advertise advertisement advice advise affair affect afford afraid after afternoon again
against age agency agenda agent aggressive ago agree agreement ahead aid aim air aircraft airline
airport alarm album alcohol alive all allow almost alone along already also alter alternative
although always amazing ambition among amount analysis analyst analyze ancient and anger angle
angry animal anniversary announce announcement annual another answer anticipate anxiety anxious any
anybody anymore anyone anything anyway anywhere apart apartment apparent apparently appeal appear
appearance apple application apply appoint appointment appreciate approach appropriate approval approve
approximately architect architecture area argue argument arise arm armed army around arrange
arrangement arrest arrival arrive art article artist artistic as ash aside ask asleep aspect
assault assert assess assessment asset assign assignment assist assistance assistant associate
association assume assumption assure at athlete athletic atmosphere attach attack attempt attend
attention attitude attorney attract attraction attractive attribute audience author authority auto
automatic automatically available average avoid award aware awareness away awful
baby back background backup bad badly bag bake balance ball ban band bank bar bare barely barrel
barrier base baseball basic basically basis basket basketball bath bathroom battery battle be beach
bean bear beat beautiful beauty because become bed bedroom beer before begin beginning behavior
behind being belief believe bell belong below belt bench bend beneath benefit beside besides best
bet better between beyond bicycle bid big bike bill billion bind biological bird birth birthday
bit bite black blade blame blank blanket blind block blood blow blue board boat body boil bold
bomb bond bone bonus book boom boot border bore boring born borrow boss both bother bottle bottom
bounce bound boundary bow bowl box boy brain branch brand brave bread break breakfast breast breath
breathe brick bridge brief briefly bright brilliant bring broad broadcast broken brother brown brush
buck budget buffer bug build builder building bulk bullet bunch burden burn burst bury bus bush
business busy but butter button buy buyer by
cabin cabinet cable cafe cage cake calculate calculation calendar call calm camera camp campaign
campus can cancel cancer candidate candle candy cap capability capable capacity capital captain
capture car carbon card care career careful carefully cargo carpet carrier carry cart case cash
cast castle cat catalog catch category cause ceiling celebrate celebration celebrity cell center
central century ceremony certain certainly chain chair chairman challenge chamber champion
championship chance change channel chaos chapter character characteristic characterize charge
charity chart chase cheap check cheek cheese chef chemical chemistry chest chicken chief child
childhood chip chocolate choice choose chop church cigarette circle circumstance cite citizen city
civil civilian claim class classic classical classroom clean clear clearly clerk click client cliff
climate climb clinic clinical clock close closely closer closet cloth clothes clothing cloud club
clue cluster coach coal coast coat code coffee coin cold collapse collar colleague collect
collection collective college colonial color column combination combine come comedy comfort
comfortable command commander comment commercial commission commit commitment committee common
commonly communicate communication community company compare comparison compete competition
competitive competitor complain complaint complete completely complex complexity component compose
composition comprehensive computer concentrate concentration concept concern concerned concert
conclude conclusion concrete condition conduct conference confidence confident confirm conflict
confront confusion congress connect connection conscious consensus consequence conservative consider
considerable considerably consideration consist consistent constant constantly constitute construct
construction consult consultant consume consumer consumption contact contain container contemporary
content contest context continue continued contract contrast contribute contribution control
controversial controversy convention conventional conversation convert conviction convince cook
cookie cooking cool cooperate cooperation coordinate cop cope copy copyright core corn corner
corporate corporation correct correctly correlation correspond cost cotton couch could council
counsel count counter country county couple courage course court cousin cover coverage cow crack
craft crash crazy cream create creation creative creature credit crew crime criminal crisis criteria
critic critical criticism criticize crop cross crowd crucial cruel cruise crush cry crystal cube
cultural culture cup curb cure curiosity curious current currently curriculum curve custom customer
cut cute cycle
dad daily damage dance dancer danger dangerous dare dark darkness data database date daughter dawn
day dead deadline deal dealer dear death debate debt decade decide decision deck declare decline
decorate decrease dedicate deep deeply defeat defend defendant defense defensive deficit define
definitely definition degree delay deliberate delicate deliver delivery demand democracy democrat
democratic demonstrate demonstration deny department depend dependent depending deposit depress
depression depth derive describe description desert deserve design designer desire desk desperate
despite destroy destruction detail detailed detect determine develop developer development device
devote dialogue diamond diary dictate dictionary die diet differ difference different differently
difficult difficulty dig digital dimension dining dinner direct direction directly director dirt
dirty disable disagree disappear disappoint disaster disc discipline disclose discount discourse
discover discovery discuss discussion disease dish disk dismiss disorder display dispute distance
distant distinct distinction distinguish distribute distribution district disturb diverse diversity
divide division divorce do doctor document dog dollar domain domestic dominant dominate donate
donation done donkey door dose dot double doubt down downtown dozen draft drag drain drama dramatic
dramatically draw drawer drawing dream dress drift drill drink drive driver drop drug drum dry
duck due dull dumb dump during dust duty dynamic
each eager ear early earn earnings earth ease easily east eastern easy eat echo economic economics
economist economy edge edit edition editor educate education educational effect effective
effectively efficiency efficient effort egg eight either elaborate elbow elder elderly elect
election electric electrical electricity electronic electronics element elementary eliminate elite
else elsewhere email embrace emerge emergency emission emotion emotional emphasis emphasize
employ employee employer employment empty enable encounter encourage end endless endorse endure
enemy energy enforce engage engagement engine engineer engineering enhance enjoy enormous enough
ensure enter enterprise entertainment entire entirely entitle entity entrance entry environment
environmental episode equal equally equation equip equipment equivalent era error escape especially
essay essential essentially establish establishment estate estimate etc ethnic evaluate evaluation
even evening event eventually ever every everybody everyday everyone everything everywhere evidence
evident evil evolution evolve exact exactly exam examination examine example exceed excellent
except exception exchange excite exciting exclude exclusive execute executive exercise exhaust
exhibit exhibition exist existence existing exit expand expansion expect expectation expense
expensive experience experiment experimental expert explain explanation explode explore explosion
export expose exposure express expression extend extension extensive extent external extra
extraordinary extreme extremely eye
fabric face facility fact factor factory faculty fade fail failure faint fair fairly faith fall
false fame familiar family famous fan fancy fantastic far fare farm farmer fashion fast fat fatal
fate father fault favor favorite fear feature federal fee feed feedback feel feeling fellow female
fence festival fetch fever few fiber fiction field fierce fifteen fifth fifty fight fighter figure
file fill film filter final finally finance financial find finding fine finger finish fire firm
first fiscal fish fit fitness five fix fixed flag flame flash flat flavor flaw flee fleet flesh
flexible flight flip float flood floor flow flower fluid fly focus fold folk follow following
food fool foot football for forbid force forecast foreign forest forever forget forgive fork form
formal format formation former formula forth fortune forty forward foster found foundation founder
four fourth frame framework franchise frankly free freedom freeze french frequency frequent
frequently fresh friend friendly friendship from front frost fruit frustrate frustration fry fuel
full fully fun function functional fund fundamental funding funeral funny fur furniture furthermore
future
gain galaxy gallery game gang gap garage garbage garden garlic gas gate gather gauge gay gaze gear
gender gene general generally generate generation generous genetic genius gentle gentleman gently
genuine gesture get ghost giant gift gifted girl girlfriend give given glad glance glass global
globe gloom glory glove glow go goal goat god gold golden golf good goodbye goods goose govern
government governor grace grade gradual gradually graduate grain grand grandfather grandmother
grant grape graph grasp grass grateful grave gravity gray great greatly green greet grid grief
grin grind grip grocery gross ground group grow growth guarantee guard guess guest guide guideline
guilty guitar gun guy gym
habit habitat hair half hall halt hand handful handle hang happen happily happy harbor hard hardly
hardware harm harmony harsh harvest hat hate haul have he head headline headquarters heal health
healthy hear hearing heart heat heaven heavily heavy heel height helicopter hell hello helmet help
helpful hence her herb here heritage hero hesitate hey hi hidden hide high highlight highly highway
hill him himself hint hip hire his historian historic historical history hit hobby hold holder hole
holiday hollow holy home homeless honest honestly honey honor hook hope horizon horizontal horn
horror horse hospital host hot hotel hour house household housing how however huge human humor
hundred hungry hunt hunter hurdle hurt husband hypothesis
ice icon idea ideal identical identify identity ideology if ignore ill illegal illness illustrate
image imagination imagine immediate immediately immigrant immigration impact implement implementation
implication imply import importance important impose impossible impress impression impressive
improve improvement in incentive inch incident include including income incorporate increase
increased increasing increasingly incredible indeed independence independent index indicate
indication individual industrial industry infant infection inflation influence inform information
ingredient initial initially initiative injure injury ink inner innocent input inquiry insect insert
inside insight insist inspect inspection inspire install instance instant instead instinct
institute institution institutional instruct instruction instructor instrument insurance intellectual
intelligence intelligent intend intense intensity intent intention interact interaction interest
interested interesting internal international internet interpret interpretation interrupt interval
intervention interview into introduce introduction invade invasion invest investigate investigation
investigator investment investor invite involve involved involvement iron island isolate issue it
item its itself
jacket jail jam jar jaw jazz jeans jet jewel job join joint joke journal journalist journey joy
judge judgment juice jump junction junior jury just justice justify
keen keep kernel key keyboard kick kid kill killer killing kind king kingdom kiss kit kitchen knee
knife knock knot know knowledge known
lab label labor laboratory lack ladder lady lake lamb lamp land landing landlord landmark landscape
lane language lap large largely laser last late lately later latest latter laugh launch laundry law
lawn lawsuit lawyer lay layer lazy lead leader leadership leading leaf league lean leap learn
learning least leather leave lecture left leg legacy legal legend legislation legitimate lemon
lend length less lesson let letter level liberal liberty library license lid lie life lifestyle
lifetime lift light like likely limit limitation limited line link lion lip liquid list listen
listener literally literary literature little live lively liver living load loan lobby local locate
location lock log logic logical lonely long look loop loose lose loss lost lot lots loud lounge
love lovely lover low lower loyal loyalty luck lucky lunch lung luxury
machine mad magazine magic mail main mainly maintain maintenance major majority make maker makeup
male mall mama man manage management manager mandate manner mansion manual manufacture manufacturer
many map marathon marble margin mark market marketing marriage married marry mask mass massive
master match mate material math matter mature max maximum may maybe mayor me meal mean meaning
meanwhile measure measurement meat mechanic mechanical mechanism medal media medical medication
medicine medium meet meeting melt member membership memory mental mention menu merchant mere
merely merge merit mess message metal meter method metric middle might migrate migration mild
military milk mill million mind mine mineral minimal minimize minimum minister minor minority minute
miracle mirror miss missile mission mistake mix mixed mixture mobile mode model moderate modern
modest modify module moisture mold mole moment momentum Monday money monitor monkey monster month
monthly mood moon moral more moreover morning mortal mortgage most mostly mother motion motivate
motivation motor mount mountain mouse mouth move movement movie much mud multiple multiply murder
muscle museum music musical musician must mutual my myself mystery myth
nail naked name narrative narrow nasty nation national native natural naturally nature naval near
nearby nearly neat necessarily necessary necessity neck need negative neglect negotiate negotiation
neighbor neighborhood neither nerve nervous nest net network neutral never nevertheless new newly
news newspaper next nice nickname night nine nineteen ninety ninth no nobody nod noise noisy
nominal none nonetheless noon nor norm normal normally north northern nose not notable notably
note notebook nothing notice notion noun novel now nowhere nuclear number numerous nurse nut
oak object objective obligation observe observer obstacle obtain obvious obviously occasion
occasional occasionally occupation occupy occur ocean odd odds of off offend offense offensive
offer office officer official often oh oil ok okay old olympic on once one ongoing onion online
only onto open opening openly operate operating operation operator opinion opponent opportunity
oppose opposite opposition opt optic optical optimal optimism optimistic option or oral orange
orbit order ordinary organ organic organization organize organized orientation origin original
originally other others otherwise ought our ours ourselves out outcome outdoor outer outfit outlet
outline output outside outstanding oven over overall overcome overflow overhead overlook overnight
overseas overwhelm overwhelming owe own owner ownership oxygen
pace pack package pad page pain painful paint painter painting pair palace pale palm pan panel
panic pant paper parade parallel parent park parking parliament part partial partially participant
participate participation particle particular particularly partly partner partnership party pass
passage passenger passion passive past pat patch patent path patient patrol pattern pause pay
payment peace peaceful peak peanut pear peasant peer pen penalty pencil pending penny people
pepper per perceive percent percentage perception perfect perfectly perform performance perhaps
period permanent permission permit persist person personal personality personally personnel
perspective persuade pet petition phase phenomenon philosophy phone photo photograph photographer
photography phrase physical physically physician physics piano pick picture pie piece pig pile
pill pilot pin pinch pine pink pioneer pipe pitch pizza place plain plan plane planet planning
plant plastic plate platform play player please pleasure plenty plot plug plugin plus pocket poem
poet poetry point pointed poison pole police policy polish polite political politically politician
politics poll pollute pollution pond pool poor pop popular popularity population porch pork port
portable portal portion portrait pose position positive possess possibility possible possibly post
poster pot potato potential potentially pound pour poverty powder power powerful practical
practically practice praise pray prayer preach precise precisely predict prediction prefer
preference pregnancy pregnant prejudice preliminary premier premise premium prepare preparation
prescription presence present presentation preserve president presidential press pressure presumably
pretend pretty prevail prevent previous previously price pride priest primarily primary prime
prince princess principal principle print printer prior priority prison prisoner privacy private
probably problem procedure proceed process produce producer product production profession
professional professor profile profit program programmer progress project prominent promise promote
promotion prompt proof proper properly property proportion proposal propose proposed prosecutor
prospect protect protection protein protest proud prove provide provider province provision
provoke psychological psychology pub public publication publicly publish publisher pull pulse pump
punch punish punishment pupil purchase pure purely purple purpose purse pursue pursuit push put
puzzle
qualify quality quantity quarter queen quest question quick quickly quiet quietly quit quite quote
rabbit race racial rack radar radiation radical radio rage rail railroad rain rainbow raise rally
random range rank rapid rapidly rare rarely rat rate rather rating ratio rational raw reach react
reaction read reader reading ready real realistic reality realize really realm rear reason
reasonable reasonably rebel rebuild recall receive recent recently recipe recipient recognition
recognize recommend recommendation record recording recover recovery recruit red reduce reduction
refer reference reflect reflection reform refrigerator refuse regard regarding regardless regime
region regional register registration regret regular regularly regulate regulation reinforce
reject relate related relation relationship relative relatively relax release relevant reliable
relief relieve religion religious rely remain remaining remark remarkable remember remind remote
removal remove render rent repair repeat repeatedly replace replacement reply report reporter
represent representation representative republic republican request require requirement rescue
research researcher resemble reservation reserve resident resist resistance resolution resolve
resort resource respect respective respectively respond respondent response responsibility
responsible rest restaurant restore restrict restriction result resume retail retain retire
retirement retreat return reveal revenue reverse review revise revision revolution revolutionary
reward rhythm ribbon rice rich rid ride rider ridge ridiculous rifle right rigid ring riot rip
rise risk ritual rival river road roar roast rob robot rock rocket rod role roll roller roman
romantic roof room root rope rose rough roughly round route routine row royal rub rubber rubbish
rude rug ruin rule ruler rumor run runner running rural rush russian
sacred sad sadly safe safely safety sail sailor sake salad salary sale sales salt same sample
sanction sand sandwich satellite satisfaction satisfy Saturday sauce save saving say scale scan
scandal scare scared scary scatter scenario scene schedule scheme scholar scholarship school
science scientific scientist scope score scramble scratch scream screen script sculpture sea seal
search season seat second secondary secret secretary section sector secure security see seed seek
seem seemingly segment seize seldom select selection self sell seller senate senator send senior
sense sensitive sentence separate separately sequence series serious seriously servant serve
server service session set setting settle settlement seven seventeen seventy several severe
severely sex sexual shade shadow shaft shake shall shallow shame shape share shared shark sharp
sharply shatter she shear shed sheep sheer sheet shelf shell shelter shepherd shield shift shine
ship shirt shock shoe shoot shooting shop shopping shore short shortage shortly shot should
shoulder shout show shower shrink shrug shut shuttle shy sibling sick side sigh sight sign signal
signature significance significant significantly silence silent silk silly silver similar similarly
simple simply simulate simulation sin since sincere sing singer single sink sir sister sit site
situation six sixteen sixty size skate sketch ski skill skilled skin skip skirt skull sky slam
slap slash slave sleep sleeve slice slide slight slightly slim slip slope slot slow slowly small
smart smash smell smile smoke smooth snack snake snap snatch sneak snow so soak soap soccer
social society sock soft software soil solar soldier sole solely solid solution solve some somebody
somehow someone something sometimes somewhat somewhere son song soon sophisticated sorry sort soul
sound soup source south southern space span spanish spare spark speak speaker special specialist
specialize species specific specifically specify specimen spectacle spectrum speech speed spell
spend spending sphere spice spider spill spin spine spirit spiritual spite split spoil spoke
spokesman sponsor sport spot spouse spray spread spring spy squad square squeeze stability stable
stack staff stage stain stair stake stand standard standing star stare start state statement
station statistics status stay steady steal steam steel steep steer stem step stereo stick
stiff still stimulate stimulus stir stock stomach stone stop storage store storm story stove
straight strain strand strange stranger strategic strategy straw strawberry stream street strength
strengthen stress stretch strict strictly strike striking string strip stripe stroke strong
strongly structural structure struggle stuck student studio study stuff stumble stupid style
subject submit subsequent subset substance substantial subtle suburb succeed success successful
successfully such suck sudden suddenly sue suffer sufficient sugar suggest suggestion suicide suit
suitable suite sum summary summer summit sun Sunday sunlight sunny super superb superior
supermarket supervise supervision supply support supporter suppose supposed supposedly supreme sure
surely surface surgeon surgery surprise surprised surprising surprisingly surround survey survival
survive survivor suspect suspend suspicion sustain swallow swan swap swear sweat sweater sweep
sweet swell swim swing switch sword symbol symptom syndrome syntax system
table tablet tackle tactic tag tail tailor take tale talent talk tall tank tap tape target task
taste tax taxi tea teach teacher teaching team tear tease technical technique technology teen
teenager telephone telescope television tell temper temperature temple temporary ten tend tendency
tender tennis tent tenth term terminal terms terrible terribly territory terror terrorism terrorist
test testify testimony text texture than thank thanks that the theater their theirs them theme
themselves then theory therapy there thereby therefore these they thick thief thin thing think
thinking third thirst thirteen thirty this thorough thoroughly those though thought thousand thread
threat threaten three threshold throat through throughout throw thumb thunder Thursday thus ticket
tide tidy tie tiger tight tightly till tilt timber time timeline timing tiny tip tire tired tissue
title to tobacco today toe together toilet token tolerate toll tomato tomorrow ton tone tongue
tonight too tool tooth top topic torch torture toss total totally touch tough tour tourism tourist
tournament toward towards towel tower town toxic toy trace track trade tradition traditional traffic
tragedy trail train trainer training trait transaction transfer transform transformation transit
transition translate translation transmit transparent transport transportation trap trash trauma
travel traveler tray treasure treat treatment treaty tree trek tremendous trend trial triangle
tribe trick trigger trim trip triumph troop trophy tropical trouble troubling truck true truly
trust truth try tube Tuesday tug tumble tumor tune tunnel turkey turn turnover tv twelve twenty
twice twin twist two type typical typically
ugly ultimate ultimately unable unaware uncle under undergo underlying undermine understand
understanding undertake undo unemployment unexpected unfortunately unhappy uniform union unique
unit unite united unity universal universe university unknown unless unlike unlikely unlimited
unload unlock until unusual unusually up update upgrade uphold upon upper upset upside upstairs
urban urge urgent us usage use used useful user usual usually utility utilize utter utterly
vacation vaccine vacuum vague valid validate validity valley valuable value van vanish vanity
variable variation variety various vary vast vegetable vehicle vein velocity vendor venture venue
verb verbal verdict verify version versus vertical very vessel veteran via viable vibrant vice
victim victory video view viewer village villain violate violation violence violent virtual
virtually virtue virus visible vision visit visitor visual vital vitamin vivid vocal voice void
volume voluntary volunteer vote voter vulnerable
wage wagon waist wait waiter wake walk wall wallet wander want war ward warehouse warm warmth
warn warning warrant warrior wash waste watch water wave way we weak weakness wealth wealthy
weapon wear weather weave web website wedding Wednesday weed week weekend weekly weigh weight
weird welcome welfare well west western wet whale what whatever wheat wheel when whenever where
whereas wherever whether which while whip whisper white who whoever whole whom whose why wide
widely widen widespread widow width wife wild wildlife will willing willingly win wind window wine
wing winner winter wipe wire wisdom wise wish wit with withdraw within without witness wolf woman
wonder wonderful wood wooden wool word work worker working workout workshop world worldwide worm
worried worry worse worship worst worth worthy would wound wow wrap wreck wrist write writer
writing written wrong
yard yarn yawn yeah year yearly yell yellow yes yesterday yet yield you young younger youngster your
yours yourself youth zone zoom
"""


def load_system_dict_words() -> set[str]:
    words_path = Path("/usr/share/dict/words")
    if not words_path.exists():
        return set()
    return {line.strip().lower() for line in words_path.read_text(encoding="utf-8").splitlines() if line.strip()}


def build_english_lexicon() -> dict[str, object]:
    system_words = load_system_dict_words()
    entries_by_key: dict[str, tuple[str, int, bool]] = {}

    for display, weight, prefer_first in TECH_AND_CRITICAL_ENGLISH:
        entries_by_key[display.lower()] = (display, weight, prefer_first)

    raw_tokens = COMMON_ENGLISH_RAW.split()
    total = max(1, len(raw_tokens))
    for idx, tok in enumerate(raw_tokens):
        w = tok.strip()
        if not w or not w.isalpha():
            continue
        k = w.lower()
        if k in entries_by_key:
            continue
        # Verify against /usr/share/dict/words when available (allowing simple regular forms)
        if system_words and k not in system_words:
            stem = k[:-1] if k.endswith("s") else k
            if stem not in system_words and k not in {"ok", "okay", "yeah", "tv", "wifi", "online", "email", "website", "offline", "plugin", "dev", "prod", "kids", "goods", "terms", "lots", "others", "odds", "yours", "ours", "theirs", "towards"}:
                continue
        # Weight smoothly decaying from 680 down to 180
        weight = max(180, min(680, int(round(680 - (idx / total) * 500))))
        display = w if w in {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"} else k
        entries_by_key[k] = (display, weight, False)

    words_list = [
        {"k": k, "t": t, "w": w, "p": p}
        for k, (t, w, p) in sorted(entries_by_key.items(), key=lambda x: (-x[1][1], x[0]))
    ]
    mixed = {
        "bzhan": "B站",
        "azhan": "A站",
        "upzhu": "UP主",
        "cp": "CP",
        "p1": "P1",
        "p0": "P0",
        "p2": "P2",
    }
    return {"words": words_list, "mixed": mixed}


# ---------------------------------------------------------------------------
# 7. Chaizi decomposition & 5-stroke index (chaizi.json)
# ---------------------------------------------------------------------------

COMPONENT_PINYIN: dict[str, str] = {
    "氵": "shui", "水": "shui", "氺": "shui",
    "火": "huo", "灬": "huo",
    "木": "mu", "林": "lin",
    "土": "tu", "圭": "gui",
    "金": "jin", "钅": "jin",
    "日": "ri", "曰": "yue",
    "月": "yue", "⺼": "yue",
    "山": "shan", "石": "shi", "口": "kou",
    "人": "ren", "亻": "ren", "入": "ru",
    "女": "nv", "子": "zi",
    "心": "xin", "忄": "xin",
    "手": "shou", "扌": "shou",
    "目": "mu", "田": "tian", "力": "li",
    "禾": "he", "米": "mi", "竹": "zhu", "⺮": "zhu",
    "艹": "cao", "草": "cao", "虫": "chong",
    "鱼": "yu", "鸟": "niao", "马": "ma", "牛": "niu", "牜": "niu",
    "羊": "yang", "犬": "quan", "犭": "quan",
    "车": "che", "車": "che", "门": "men",
    "王": "wang", "玉": "yu", "白": "bai", "黑": "hei",
    "贝": "bei", "见": "jian", "言": "yan", "讠": "yan",
    "走": "zou", "辶": "zou", "足": "zu", "⻊": "zu",
    "身": "shen", "耳": "er", "舌": "she", "舟": "zhou",
    "弓": "gong", "刀": "dao", "刂": "dao", "斤": "jin",
    "戈": "ge", "矢": "shi", "矛": "mao",
    "示": "shi", "礻": "shi", "衣": "yi", "衤": "yi",
    "巾": "jin", "广": "guang", "厂": "chang", "尸": "shi", "户": "hu",
    "穴": "xue", "雨": "yu", "风": "feng", "云": "yun", "气": "qi",
    "音": "yin", "页": "ye", "首": "shou", "食": "shi", "饣": "shi",
    "骨": "gu", "鬼": "gui", "龙": "long", "龍": "long",
    "丝": "si", "纟": "si", "宀": "bao", "阝": "er",
    "攵": "wen", "彳": "chi", "疒": "bing", "冫": "bing",
    "囗": "wei", "夕": "xi", "大": "da", "小": "xiao",
    "寸": "cun", "又": "you", "士": "shi", "工": "gong",
    "干": "gan", "几": "ji", "儿": "er", "八": "ba",
    "十": "shi", "七": "qi", "九": "jiu", "一": "yi", "二": "er",
    "三": "san", "四": "si", "五": "wu", "六": "liu",
    "千": "qian", "万": "wan", "上": "shang", "下": "xia", "中": "zhong",
    "天": "tian", "地": "di", "不": "bu", "少": "shao", "正": "zheng",
    "止": "zhi", "比": "bi", "毛": "mao", "氏": "shi", "父": "fu",
    "母": "mu", "生": "sheng", "用": "yong", "皮": "pi", "皿": "min",
    "立": "li", "老": "lao", "而": "er", "自": "zi", "至": "zhi",
    "色": "se", "血": "xue", "行": "xing", "西": "xi", "豆": "dou",
    "辰": "chen", "辛": "xin", "酉": "you", "里": "li", "长": "chang",
    "青": "qing", "非": "fei", "面": "mian", "革": "ge", "高": "gao",
    "黄": "huang", "齐": "qi", "欠": "qian", "方": "fang", "文": "wen",
    "斗": "dou", "元": "yuan", "主": "zhu", "也": "ye", "巴": "ba",
    "包": "bao", "半": "ban", "本": "ben", "必": "bi", "并": "bing",
    "才": "cai", "仓": "cang", "成": "cheng", "出": "chu", "川": "chuan",
    "次": "ci", "从": "cong", "达": "da", "代": "dai", "单": "dan",
    "旦": "dan", "当": "dang", "登": "deng", "丁": "ding", "东": "dong",
    "冬": "dong", "动": "dong", "度": "du", "段": "duan", "兑": "dui",
    "多": "duo", "尔": "er", "发": "fa", "反": "fan", "分": "fen",
    "丰": "feng", "夫": "fu", "付": "fu", "复": "fu", "各": "ge",
    "艮": "gen", "共": "gong", "古": "gu", "谷": "gu", "官": "guan",
    "光": "guang", "果": "guo", "合": "he", "胡": "hu", "化": "hua",
    "回": "hui", "会": "hui", "吉": "ji", "及": "ji", "加": "jia",
    "甲": "jia", "间": "jian", "兼": "jian", "交": "jiao", "角": "jiao",
    "今": "jin", "京": "jing", "井": "jing", "竟": "jing", "句": "ju",
    "巨": "ju", "军": "jun", "开": "kai", "可": "ke", "克": "ke",
    "空": "kong", "夸": "kua", "昆": "kun", "来": "lai", "兰": "lan",
    "良": "liang", "令": "ling", "留": "liu", "卢": "lu", "仑": "lun",
    "罗": "luo", "每": "mei", "门": "men", "蒙": "meng", "民": "min",
    "名": "ming", "明": "ming", "莫": "mo", "内": "nei", "乃": "nai",
    "南": "nan", "农": "nong", "票": "piao", "平": "ping", "其": "qi",
    "奇": "qi", "前": "qian", "乔": "qiao", "区": "qu", "去": "qu",
    "全": "quan", "泉": "quan", "然": "ran", "任": "ren", "容": "rong",
    "如": "ru", "若": "ruo", "申": "shen", "失": "shi", "师": "shi",
    "世": "shi", "市": "shi", "是": "shi", "寿": "shou", "司": "si",
    "寺": "si", "台": "tai", "太": "tai", "唐": "tang", "堂": "tang",
    "同": "tong", "童": "tong", "屯": "tun", "韦": "wei", "未": "wei",
    "乌": "wu", "无": "wu", "吴": "wu", "午": "wu", "昔": "xi",
    "相": "xiang", "向": "xiang", "肖": "xiao", "星": "xing", "兴": "xing",
    "兄": "xiong", "秀": "xiu", "宣": "xuan", "玄": "xuan", "牙": "ya",
    "亚": "ya", "延": "yan", "彦": "yan", "央": "yang", "易": "yi",
    "因": "yin", "由": "you", "尤": "you", "余": "yu", "与": "yu",
    "原": "yuan", "早": "zao", "曾": "zeng", "占": "zhan", "章": "zhang",
    "召": "zhao", "者": "zhe", "真": "zhen", "支": "zhi", "直": "zhi",
    "只": "zhi", "周": "zhou", "朱": "zhu", "专": "zhuan", "卓": "zhuo",
    "宗": "zong", "卒": "zu", "左": "zuo", "作": "zuo",
    "肀": "yu", "聿": "yu", "夬": "guai", "戋": "jian", "尧": "yao",
    "兆": "zhao", "免": "mian", "兔": "tu", "象": "xiang", "鹿": "lu",
    "隹": "zhui", "羽": "yu", "飞": "fei", "习": "xi", "寸": "cun",
    "戈": "ge", "弋": "yi", "卜": "bu", "厂": "chang", "广": "guang",
    "尸": "shi", "户": "hu", "匚": "fang", "凵": "kan", "卩": "jie",
    "厶": "si", "彐": "ji", "彡": "shan", "廾": "gong", "癶": "bo",
    "罒": "si", "虍": "hu", "耂": "lao", "爫": "zhao", "勹": "bao",
    "廴": "yin", "冃": "mao", "冖": "mi", "亠": "tou", "丷": "ba",
    "訁": "yan", "釒": "jin", "飠": "shi", "糹": "si",
}

# Exact curated compound character decompositions (character: "part1+part2[+part3]")
# Covers all doubles/triples plus 1,500+ compound characters across major radicals.
CHAIZI_GROUPS: list[tuple[str, str]] = [
    # Doubles, triples, quadruples & iconic classics
    ("炎", "火+火"), ("焱", "火+火+火"), ("燚", "火+火+火+火"),
    ("林", "木+木"), ("森", "木+木+木"),
    ("沝", "水+水"), ("淼", "水+水+水"),
    ("鍂", "金+金"), ("鑫", "金+金+金"),
    ("圭", "土+土"), ("垚", "土+土+土"),
    ("砳", "石+石"), ("磊", "石+石+石"),
    ("牪", "牛+牛"), ("犇", "牛+牛+牛"),
    ("龖", "龍+龍"), ("龘", "龍+龍+龍"),
    ("昍", "日+日"), ("昌", "日+日"), ("晶", "日+日+日"),
    ("朋", "月+月"), ("朤", "月+月+月+月"),
    ("从", "人+人"), ("众", "人+人+人"),
    ("吕", "口+口"), ("品", "口+口+口"), ("吅", "口+口"),
    ("双", "又+又"), ("叒", "又+又+又"), ("叕", "又+又+又+又"),
    ("虤", "虎+虎"), ("多", "夕+夕"), ("出", "山+山"),
    ("比", "匕+匕"), ("丝", "纟+纟"), ("赫", "赤+赤"),
    ("喆", "吉+吉"), ("囍", "喜+喜"), ("轰", "车+车+车"), ("轟", "車+車+車"),
    ("骉", "马+马+马"), ("羴", "羊+羊+羊"), ("鱻", "鱼+鱼+鱼"),
    ("毳", "毛+毛+毛"), ("姦", "女+女+女"), ("奸", "女+干"),
    ("蟲", "虫+虫+虫"), ("劦", "力+力+力"), ("惢", "心+心+心"),
    ("譶", "言+言+言"), ("誩", "言+言"), ("飍", "风+风+风"),
    ("靐", "雷+雷+雷"), ("刕", "刀+刀+刀"), ("茻", "艹+艹"),
    ("掱", "手+手+手"), ("孨", "子+子+子"), ("皛", "白+白+白"),
    ("飝", "飞+飞+飞"), ("灥", "泉+泉+泉"), ("厽", "厶+厶+厶"),
    ("尛", "小+小+小"), ("枣", "朿+朿"), ("棘", "朿+朿"),
    ("哥", "可+可"), ("竞", "立+兄"), ("兢", "克+克"), ("敫", "白+放"),
    ("明", "日+月"), ("古", "十+口"), ("好", "女+子"), ("男", "田+力"),
    ("尖", "小+大"), ("岩", "山+石"), ("看", "手+目"), ("泉", "白+水"),
    ("柏", "木+白"), ("休", "亻+木"), ("沐", "氵+木"), ("灿", "火+山"),
    ("歪", "不+正"), ("尘", "小+土"), ("拿", "合+手"), ("掰", "手+分+手"),
    ("孬", "不+好"), ("忐", "上+心"), ("忑", "下+心"), ("卡", "上+下"),
    ("鲜", "鱼+羊"), ("明", "日+月"), ("旦", "日+一"), ("早", "日+十"),
    ("旱", "日+干"), ("旺", "日+王"), ("时", "日+寸"), ("旷", "日+广"),
    ("昀", "日+匀"), ("昕", "日+斤"), ("昊", "日+天"), ("昆", "日+比"),
    ("昂", "日+卯"), ("昌", "日+日"), ("易", "日+勿"), ("昔", "艹+日"),
    ("星", "日+生"), ("映", "日+央"), ("春", "三+人+日"), ("是", "日+正"),
    ("昨", "日+乍"), ("昭", "日+召"), ("昼", "尺+旦"), ("显", "日+业"),
    ("晃", "日+光"), ("晒", "日+西"), ("晓", "日+尧"), ("晕", "日+军"),
    ("晚", "日+免"), ("景", "日+京"), ("晴", "日+青"), ("智", "知+日"),
    ("暂", "斩+日"), ("暑", "日+者"), ("暖", "日+爰"), ("暗", "日+音"),
    ("暴", "日+共+水"), ("暮", "莫+日"), ("曦", "日+羲"), ("普", "并+日"),
    ("替", "夫+夫+日"), ("曾", "丷+田+日"), ("最", "日+取"), ("旭", "九+日"),
    ("旮", "九+日"), ("旯", "日+九"),
    # 氵 (水)
    ("汗", "氵+干"), ("江", "氵+工"), ("污", "氵+亏"), ("汤", "氵+扬"),
    ("汪", "氵+王"), ("汰", "氵+太"), ("汲", "氵+及"), ("决", "氵+夬"),
    ("汽", "氵+气"), ("沃", "氵+夭"), ("沉", "氵+冗"), ("沈", "氵+冘"),
    ("沙", "氵+少"), ("沛", "氵+市"), ("沟", "氵+勾"), ("没", "氵+殳"),
    ("沪", "氵+户"), ("沫", "氵+末"), ("沮", "氵+且"), ("河", "氵+可"),
    ("沸", "氵+弗"), ("油", "氵+由"), ("治", "氵+台"), ("沼", "氵+召"),
    ("沾", "氵+占"), ("沿", "氵+几+口"), ("泄", "氵+世"), ("泊", "氵+白"),
    ("泌", "氵+必"), ("法", "氵+去"), ("泛", "氵+乏"), ("泡", "氵+包"),
    ("波", "氵+皮"), ("泣", "氵+立"), ("泥", "氵+尼"), ("注", "氵+主"),
    ("泪", "氵+目"), ("泳", "氵+永"), ("泽", "氵+尺"), ("洁", "氵+吉"),
    ("洋", "氵+羊"), ("洗", "氵+先"), ("洛", "氵+各"), ("洞", "氵+同"),
    ("津", "氵+聿"), ("洪", "氵+共"), ("洲", "氵+州"), ("活", "氵+舌"),
    ("洽", "氵+合"), ("派", "氵+辰"), ("流", "氵+㐬"), ("浅", "氵+戋"),
    ("浆", "丬+夕+水"), ("浊", "氵+虫"), ("测", "氵+则"), ("济", "氵+齐"),
    ("浑", "氵+军"), ("浓", "氵+农"), ("浙", "氵+折"), ("浦", "氵+甫"),
    ("浩", "氵+告"), ("浪", "氵+良"), ("浮", "氵+孚"), ("浴", "氵+谷"),
    ("海", "氵+每"), ("浸", "氵+彐+又"), ("涂", "氵+余"), ("消", "氵+肖"),
    ("涉", "氵+步"), ("涌", "氵+甬"), ("涛", "氵+寿"), ("润", "氵+闰"),
    ("涨", "氵+张"), ("清", "氵+青"), ("渐", "氵+斩"), ("混", "氵+昆"),
    ("添", "氵+忝"), ("浅", "氵+戋"), ("减", "冫+咸"), ("渡", "氵+度"),
    ("渣", "氵+查"), ("温", "氵+昷"), ("测", "氵+则"), ("港", "氵+巷"),
    ("游", "氵+方+子"), ("湖", "氵+胡"), ("湘", "氵+相"), ("湾", "氵+弯"),
    ("源", "氵+原"), ("溪", "氵+奚"), ("滋", "氵+兹"), ("滑", "氵+骨"),
    ("滚", "氵+衮"), ("满", "氵+艹+两"), ("滤", "氵+虑"), ("滥", "氵+监"),
    ("滨", "氵+宾"), ("滩", "氵+难"), ("滴", "氵+商"), ("演", "氵+寅"),
    ("漠", "氵+莫"), ("漫", "氵+曼"), ("潜", "氵+替"), ("潮", "氵+朝"),
    ("澎", "氵+彭"), ("激", "氵+白+方+攵"), ("灌", "氵+雚"), ("冰", "冫+水"),
    ("冷", "冫+令"), ("冻", "冫+东"), ("净", "冫+争"), ("准", "冫+隹"),
    ("凉", "冫+京"), ("凌", "冫+夌"), ("凝", "冫+疑"), ("决", "冫+夬"),
    # 木
    ("扎", "扌+乚"), ("扑", "扌+卜"), ("本", "木+一"), ("术", "木+丶"),
    ("机", "木+几"), ("杀", "乂+木"), ("杂", "九+木"), ("权", "木+又"),
    ("杆", "木+干"), ("杠", "木+工"), ("条", "夂+木"), ("来", "米+一"),
    ("杨", "木+扬"), ("极", "木+及"), ("构", "木+勾"), ("杰", "木+灬"),
    ("松", "木+公"), ("板", "木+反"), ("析", "木+斤"), ("枕", "木+冘"),
    ("枚", "木+攵"), ("枝", "木+支"), ("枢", "木+区"), ("枪", "木+仓"),
    ("枫", "木+风"), ("枯", "木+古"), ("架", "加+木"), ("柄", "木+丙"),
    ("某", "甘+木"), ("染", "氵+九+木"), ("柔", "矛+木"), ("查", "木+旦"),
    ("相", "木+目"), ("柳", "木+卯"), ("柱", "木+主"), ("标", "木+示"),
    ("栋", "木+东"), ("栏", "木+兰"), ("树", "木+对"), ("校", "木+交"),
    ("株", "木+朱"), ("核", "木+亥"), ("根", "木+艮"), ("格", "木+各"),
    ("桂", "木+圭"), ("桃", "木+兆"), ("框", "木+匡"), ("案", "安+木"),
    ("桌", "卜+日+木"), ("桑", "又+又+又+木"), ("梅", "木+每"), ("梓", "木+辛"),
    ("梦", "林+夕"), ("梯", "木+弟"), ("械", "木+戒"), ("检", "木+佥"),
    ("棉", "木+帛"), ("棋", "木+其"), ("棒", "木+奉"), ("棚", "木+朋"),
    ("植", "木+直"), ("椅", "木+奇"), ("椒", "木+叔"), ("椰", "木+耶"),
    ("楚", "林+疋"), ("楼", "木+娄"), ("概", "木+既"), ("榜", "木+旁"),
    ("模", "木+莫"), ("横", "木+黄"), ("樱", "木+婴"), ("橙", "木+登"),
    ("橡", "木+象"), ("桥", "木+乔"), ("样", "木+羊"), ("村", "木+寸"),
    ("材", "木+才"), ("杜", "木+土"), ("李", "木+子"), ("杏", "木+口"),
    ("呆", "口+木"), ("束", "木+口"), ("东", "一+小+乙"), ("果", "田+木"),
    ("杉", "木+彡"), ("杯", "木+不"), ("桶", "木+甬"), ("槽", "木+曹"),
    ("梁", "氵+刃+木"), ("梨", "利+木"), ("禁", "林+示"), ("焚", "林+火"),
    # 火 / 灬
    ("灭", "一+火"), ("灰", "厂+火"), ("灯", "火+丁"), ("灵", "彐+火"),
    ("灶", "火+土"), ("灼", "火+勺"), ("灾", "宀+火"), ("灿", "火+山"),
    ("炉", "火+户"), ("炒", "火+少"), ("炊", "火+欠"), ("炕", "火+亢"),
    ("炫", "火+玄"), ("炮", "火+包"), ("炸", "火+乍"), ("点", "占+灬"),
    ("炼", "火+东"), ("烂", "火+兰"), ("烈", "列+灬"), ("烤", "火+考"),
    ("烧", "火+尧"), ("烦", "火+页"), ("烫", "汤+火"), ("热", "执+灬"),
    ("焦", "隹+灬"), ("然", "月+犬+灬"), ("煌", "火+皇"), ("照", "昭+灬"),
    ("煮", "者+灬"), ("熊", "能+灬"), ("熏", "千+黑+灬"), ("熟", "孰+灬"),
    ("燃", "火+然"), ("爆", "火+暴"), ("烟", "火+因"), ("煤", "火+某"),
    ("熄", "火+息"), ("熔", "火+容"), ("烛", "火+虫"), ("烙", "火+各"),
    ("炖", "火+屯"), ("烘", "火+共"), ("烤", "火+考"), ("烯", "火+希"),
    ("烷", "火+完"), ("炭", "山+灰"), ("秋", "禾+火"), ("伙", "亻+火"),
    ("灵", "彐+火"), ("煲", "保+火"), ("熨", "尉+火"), ("煞", "杀+灬"),
    # 土
    ("地", "土+也"), ("场", "土+扬"), ("均", "土+匀"), ("坊", "土+方"),
    ("坏", "土+不"), ("坐", "人+人+土"), ("坑", "土+亢"), ("块", "土+夬"),
    ("坚", "臤+土"), ("坛", "土+云"), ("坝", "土+贝"), ("坟", "土+文"),
    ("坡", "土+皮"), ("坤", "土+申"), ("坦", "土+旦"), ("垂", "千+艹+土"),
    ("垃", "土+立"), ("型", "刑+土"), ("城", "土+成"), ("域", "土+或"),
    ("培", "土+咅"), ("基", "其+土"), ("堂", "尚+土"), ("堆", "土+隹"),
    ("堕", "队+土"), ("堡", "保+土"), ("堤", "土+是"), ("堪", "土+甚"),
    ("堵", "土+者"), ("塔", "土+荅"), ("填", "土+真"), ("境", "土+竟"),
    ("增", "土+曾"), ("墨", "黑+土"), ("壁", "辟+土"), ("墙", "土+啬"),
    ("坛", "土+云"), ("尘", "小+土"), ("圣", "又+土"), ("压", "厂+土+丶"),
    ("在", "十+土"), ("均", "土+匀"), ("址", "土+止"), ("埋", "土+里"),
    ("埃", "土+矣"), ("塑", "朔+土"), ("垫", "执+土"), ("坠", "队+土"),
    ("塞", "宀+井+土"), ("墓", "莫+土"), ("塌", "土+日+羽"), ("均", "土+匀"),
    ("均", "土+匀"), ("坪", "土+平"), ("坂", "土+反"), ("坞", "土+乌"),
    ("垢", "土+后"), ("垠", "土+艮"), ("堰", "土+匽"), ("坤", "土+申"),
    # 钅 (金)
    ("钉", "钅+丁"), ("针", "钅+十"), ("钓", "钅+勺"), ("钙", "钅+丐"),
    ("钝", "钅+屯"), ("钞", "钅+少"), ("钟", "钅+中"), ("钢", "钅+冈"),
    ("钦", "钅+欠"), ("钩", "钅+勾"), ("钮", "钅+丑"), ("钱", "钅+戋"),
    ("钻", "钅+占"), ("铁", "钅+失"), ("铃", "钅+令"), ("铅", "钅+台"),
    ("铜", "钅+同"), ("银", "钅+艮"), ("链", "钅+连"), ("销", "钅+肖"),
    ("锁", "钅+小+贝"), ("锅", "钅+呙"), ("锋", "钅+夆"), ("错", "钅+昔"),
    ("锚", "钅+苗"), ("锡", "钅+易"), ("锤", "钅+垂"), ("锦", "钅+帛"),
    ("键", "钅+建"), ("锻", "钅+段"), ("镇", "钅+真"), ("镜", "钅+竟"),
    ("铺", "钅+甫"), ("铝", "钅+吕"), ("铭", "钅+名"), ("锐", "钅+兑"),
    ("错", "钅+昔"), ("钢", "钅+冈"), ("铲", "钅+产"), ("铸", "钅+寿"),
    ("镁", "钅+美"), ("锂", "钅+里"), ("钠", "钅+内"), ("钾", "钅+甲"),
    ("锌", "钅+辛"), ("锰", "钅+孟"), ("镍", "钅+臬"), ("钛", "钅+太"),
    ("钨", "钅+乌"), ("铬", "钅+各"), ("银", "钅+艮"), ("鉴", "监+金"),
    ("釜", "父+金"), ("钉", "钅+丁"), ("钳", "钅+甘"), ("锣", "钅+罗"),
    # 亻 (人)
    ("亿", "亻+乙"), ("什", "亻+十"), ("仁", "亻+二"), ("仅", "亻+又"),
    ("仆", "亻+卜"), ("仇", "亻+九"), ("今", "人+一+乛"), ("介", "人+丿+丨"),
    ("仍", "亻+乃"), ("从", "人+人"), ("仔", "亻+子"), ("他", "亻+也"),
    ("付", "亻+寸"), ("仙", "亻+山"), ("代", "亻+弋"), ("令", "人+一+丶"),
    ("以", "丨+丶+人"), ("仪", "亻+义"), ("们", "亻+门"), ("仰", "亻+卬"),
    ("件", "亻+牛"), ("价", "亻+介"), ("任", "亻+壬"), ("份", "亻+分"),
    ("仿", "亻+方"), ("企", "人+止"), ("伊", "亻+尹"), ("伍", "亻+五"),
    ("伏", "亻+犬"), ("伐", "亻+戈"), ("休", "亻+木"), ("众", "人+人+人"),
    ("优", "亻+尤"), ("伙", "亻+火"), ("会", "人+云"), ("伟", "亻+韦"),
    ("传", "亻+专"), ("伤", "亻+扬"), ("伦", "亻+仑"), ("伯", "亻+白"),
    ("估", "亻+古"), ("伴", "亻+半"), ("伸", "亻+申"), ("似", "亻+以"),
    ("位", "亻+立"), ("低", "亻+氐"), ("住", "亻+主"), ("佐", "亻+左"),
    ("体", "亻+本"), ("何", "亻+可"), ("余", "人+示"), ("作", "亻+乍"),
    ("你", "亻+尔"), ("佳", "亻+圭"), ("使", "亻+吏"), ("例", "亻+列"),
    ("供", "亻+共"), ("依", "亻+衣"), ("侠", "亻+夹"), ("侣", "亻+吕"),
    ("侦", "亻+贞"), ("侧", "亻+则"), ("保", "亻+呆"), ("信", "亻+言"),
    ("修", "攸+彡"), ("俱", "亻+具"), ("倍", "亻+咅"), ("倒", "亻+到"),
    ("候", "亻+丨+矢"), ("借", "亻+昔"), ("值", "亻+直"), ("倾", "亻+顷"),
    ("假", "亻+叚"), ("偏", "亻+扁"), ("做", "亻+故"), ("停", "亻+亭"),
    ("健", "亻+建"), ("偶", "亻+禺"), ("偷", "亻+俞"), ("偿", "亻+赏"),
    ("催", "亻+崔"), ("傲", "亻+敖"), ("傻", "亻+夏"), ("像", "亻+象"),
    ("儒", "亻+需"), ("僧", "亻+曾"), ("储", "亻+诸"), ("仅", "亻+又"),
    # 口
    ("古", "十+口"), ("句", "勹+口"), ("另", "口+力"), ("只", "口+八"),
    ("叫", "口+丩"), ("叮", "口+丁"), ("可", "丁+口"), ("台", "厶+口"),
    ("史", "口+乂"), ("右", "十+口"), ("叶", "口+十"), ("号", "口+丂"),
    ("叹", "口+又"), ("司", "刁+口"), ("吃", "口+乞"), ("合", "人+一+口"),
    ("吉", "士+口"), ("吊", "口+巾"), ("同", "冂+一+口"), ("名", "夕+口"),
    ("吐", "口+土"), ("向", "丿+冂+口"), ("吓", "口+下"), ("君", "尹+口"),
    ("吧", "口+巴"), ("含", "今+口"), ("听", "口+斤"), ("启", "户+口"),
    ("吹", "口+欠"), ("吻", "口+勿"), ("呆", "口+木"), ("呈", "口+王"),
    ("告", "牛+口"), ("呐", "口+内"), ("吸", "口+及"), ("吵", "口+少"),
    ("员", "口+贝"), ("呗", "口+贝"), ("呜", "口+乌"), ("呢", "口+尼"),
    ("周", "冂+土+口"), ("味", "口+未"), ("呼", "口+乎"), ("命", "人+一+口+卩"),
    ("咀", "口+且"), ("和", "禾+口"), ("咏", "口+永"), ("咕", "口+古"),
    ("咖", "口+加"), ("咬", "口+交"), ("咱", "口+自"), ("哀", "衣+口"),
    ("品", "口+口+口"), ("哄", "口+共"), ("哇", "口+圭"), ("哈", "口+合"),
    ("响", "口+向"), ("哎", "口+艾"), ("哑", "口+亚"), ("哪", "口+那"),
    ("哭", "口+口+犬"), ("哲", "折+口"), ("唇", "辰+口"), ("唐", "广+肀+口"),
    ("唤", "口+奂"), ("售", "隹+口"), ("唯", "口+隹"), ("唱", "口+昌"),
    ("商", "立+口+八"), ("问", "门+口"), ("启", "户+口"), ("啊", "口+阿"),
    ("啡", "口+非"), ("啤", "口+卑"), ("啦", "口+拉"), ("啪", "口+拍"),
    ("喝", "口+曷"), ("喂", "口+畏"), ("喜", "士+口+口"), ("喧", "口+宣"),
    ("喷", "口+贲"), ("嘴", "口+此+角"), ("器", "口+口+犬+口+口"), ("噪", "口+喿"),
    ("嘛", "口+麻"), ("嗯", "口+恩"), ("叹", "口+又"), ("吓", "口+下"),
    # 扌 (手)
    ("打", "扌+丁"), ("扔", "扌+乃"), ("扑", "扌+卜"), ("扒", "扌+八"),
    ("扛", "扌+工"), ("扣", "扌+口"), ("托", "扌+乇"), ("扫", "扌+彐"),
    ("扬", "扌+易"), ("扭", "扌+丑"), ("扮", "扌+分"), ("扯", "扌+止"),
    ("扰", "扌+尤"), ("批", "扌+比"), ("找", "扌+戈"), ("技", "扌+支"),
    ("抄", "扌+少"), ("抓", "扌+爪"), ("投", "扌+殳"), ("抖", "扌+斗"),
    ("抗", "扌+亢"), ("折", "扌+斤"), ("抱", "扌+包"), ("抵", "扌+氐"),
    ("抹", "扌+末"), ("抽", "扌+由"), ("担", "扌+旦"), ("拆", "扌+斥"),
    ("拉", "扌+立"), ("拍", "扌+白"), ("拒", "扌+巨"), ("拔", "扌+犮"),
    ("拖", "扌+也"), ("招", "扌+召"), ("拜", "手+手"), ("拥", "扌+用"),
    ("拦", "扌+兰"), ("拨", "扌+发"), ("择", "扌+尺"), ("括", "扌+舌"),
    ("拿", "合+手"), ("持", "扌+寺"), ("指", "扌+旨"), ("按", "扌+安"),
    ("挑", "扌+兆"), ("挖", "扌+窊"), ("挤", "扌+齐"), ("拼", "扌+并"),
    ("拾", "扌+合"), ("拿", "合+手"), ("振", "扌+辰"), ("挺", "扌+廷"),
    ("捉", "扌+足"), ("捐", "扌+肙"), ("捕", "扌+甫"), ("损", "扌+员"),
    ("换", "扌+奂"), ("捷", "扌+疌"), ("授", "扌+受"), ("掉", "扌+卓"),
    ("掌", "尚+手"), ("排", "扌+非"), ("接", "扌+妾"), ("控", "扌+空"),
    ("推", "扌+隹"), ("措", "扌+昔"), ("提", "扌+是"), ("插", "扌+千+臼"),
    ("搜", "扌+叟"), ("搞", "扌+高"), ("搬", "扌+般"), ("搭", "扌+荅"),
    ("摘", "扌+啇"), ("摩", "麻+手"), ("摸", "扌+莫"), ("撑", "扌+掌"),
    ("撞", "扌+童"), ("播", "扌+番"), ("操", "扌+喿"), ("擦", "扌+察"),
    # 忄 / 心
    ("忆", "忄+乙"), ("忙", "忄+亡"), ("怀", "忄+不"), ("态", "太+心"),
    ("忠", "中+心"), ("忧", "忄+尤"), ("快", "忄+夬"), ("念", "今+心"),
    ("忽", "勿+心"), ("思", "田+心"), ("急", "⺈+彐+心"), ("性", "忄+生"),
    ("怨", "夗+心"), ("怪", "忄+圣"), ("总", "丷+口+心"), ("恋", "亦+心"),
    ("恐", "工+凡+心"), ("恨", "忄+艮"), ("恩", "因+心"), ("息", "自+心"),
    ("恰", "忄+合"), ("恶", "亚+心"), ("患", "串+心"), ("悦", "忄+兑"),
    ("您", "你+心"), ("悬", "县+心"), ("悲", "非+心"), ("情", "忄+青"),
    ("惊", "忄+京"), ("惜", "忄+昔"), ("惠", "由+心"), ("想", "相+心"),
    ("意", "音+心"), ("感", "咸+心"), ("愚", "禺+心"), ("爱", "爫+冖+友"),
    ("慌", "忄+荒"), ("慎", "忄+真"), ("慢", "忄+曼"), ("慧", "丰+丰+彐+心"),
    ("懂", "忄+董"), ("懒", "忄+赖"), ("愿", "原+心"), ("忠", "中+心"),
    ("忍", "刃+心"), ("志", "士+心"), ("忘", "亡+心"), ("忙", "忄+亡"),
    ("怕", "忄+白"), ("悟", "忄+吾"), ("悔", "忄+每"), ("愉", "忄+俞"),
    # 讠 (言)
    ("计", "讠+十"), ("订", "讠+丁"), ("认", "讠+人"), ("议", "讠+义"),
    ("讯", "讠+卂"), ("记", "讠+己"), ("讲", "讠+井"), ("讳", "讠+韦"),
    ("讶", "讠+牙"), ("许", "讠+午"), ("论", "讠+仑"), ("设", "讠+殳"),
    ("访", "讠+方"), ("证", "讠+正"), ("评", "讠+平"), ("识", "讠+只"),
    ("诉", "讠+斥"), ("词", "讠+司"), ("译", "讠+泽"), ("试", "讠+式"),
    ("诗", "讠+寺"), ("诚", "讠+成"), ("话", "讠+舌"), ("诞", "讠+延"),
    ("询", "讠+旬"), ("该", "讠+亥"), ("详", "讠+羊"), ("语", "讠+吾"),
    ("误", "讠+吴"), ("说", "讠+兑"), ("请", "讠+青"), ("诸", "讠+者"),
    ("读", "讠+卖"), ("课", "讠+果"), ("调", "讠+周"), ("谈", "讠+炎"),
    ("谁", "讠+隹"), ("谋", "讠+某"), ("谍", "讠+枼"), ("谎", "讠+荒"),
    ("谜", "讠+迷"), ("谢", "讠+射"), ("谨", "讠+堇"), ("谱", "讠+普"),
    ("警", "敬+言"), ("誓", "折+言"), ("计", "讠+十"), ("让", "讠+上"),
    # 艹 (草)
    ("艾", "艹+乂"), ("节", "艹+卩"), ("花", "艹+化"), ("芳", "艹+方"),
    ("芽", "艹+牙"), ("苍", "艹+仓"), ("苏", "艹+办"), ("若", "艹+右"),
    ("苦", "艹+古"), ("英", "艹+央"), ("茂", "艹+戊"), ("范", "艹+氵+卩"),
    ("茶", "艹+人+木"), ("草", "艹+早"), ("荒", "艹+亡+川"), ("药", "艹+约"),
    ("荷", "艹+何"), ("获", "艹+犭+犬"), ("莲", "艹+连"), ("莫", "艹+日+大"),
    ("菜", "艹+采"), ("菲", "艹+非"), ("营", "艹+冖+吕"), ("落", "艹+洛"),
    ("著", "艹+者"), ("董", "艹+重"), ("葡", "艹+匍"), ("葱", "艹+匆"),
    ("蓝", "艹+监"), ("藏", "艹+臣+戈"), ("薄", "艹+溥"), ("薪", "艹+新"),
    ("艺", "艹+乙"), ("苗", "艹+田"), ("芽", "艹+牙"), ("茎", "艹+圣"),
    ("茄", "艹+加"), ("茅", "艹+矛"), ("苹", "艹+平"), ("范", "艹+泛"),
    ("茶", "艹+人+木"), ("菌", "艹+困"), ("菊", "艹+匊"), ("萌", "艹+明"),
    ("蓉", "艹+容"), ("蒙", "艹+冖+豕"), ("蒸", "艹+丞+灬"), ("薯", "艹+暑"),
    # 女
    ("奴", "女+又"), ("奶", "女+乃"), ("奸", "女+干"), ("她", "女+也"),
    ("好", "女+子"), ("如", "女+口"), ("妈", "女+马"), ("妹", "女+未"),
    ("妻", "十+彐+女"), ("姑", "女+古"), ("姓", "女+生"), ("姐", "女+且"),
    ("始", "女+台"), ("委", "禾+女"), ("姜", "羊+女"), ("姨", "女+夷"),
    ("娃", "女+圭"), ("威", "戌+女"), ("娘", "女+良"), ("婚", "女+昏"),
    ("婆", "波+女"), ("媒", "女+某"), ("嫁", "女+家"), ("嫌", "女+兼"),
    ("嫩", "女+束+攵"), ("妙", "女+少"), ("妖", "女+夭"), ("妥", "爫+女"),
    ("妨", "女+方"), ("妇", "女+彐"), ("安", "宀+女"), ("姿", "次+女"),
    # 纟 (丝)
    ("红", "纟+工"), ("约", "纟+勺"), ("级", "纟+及"), ("纪", "纟+己"),
    ("纯", "纟+屯"), ("纲", "纟+冈"), ("纳", "纟+内"), ("纵", "纟+从"),
    ("纷", "纟+分"), ("纸", "纟+氏"), ("纹", "纟+文"), ("线", "纟+戋"),
    ("组", "纟+且"), ("细", "纟+田"), ("终", "纟+冬"), ("经", "纟+圣"),
    ("结", "纟+吉"), ("绕", "纟+尧"), ("绘", "纟+会"), ("给", "纟+合"),
    ("绝", "纟+色"), ("统", "纟+充"), ("继", "纟+米+乙"), ("绩", "纟+责"),
    ("维", "纟+隹"), ("综", "纟+宗"), ("绿", "纟+录"), ("编", "纟+扁"),
    ("缓", "纟+爰"), ("练", "纟+东"), ("缩", "纟+宿"), ("繁", "敏+糸"),
    ("织", "纟+只"), ("绍", "纟+召"), ("绑", "纟+邦"), ("绪", "纟+者"),
    # 宀 / 广 / 厂 / 疒 / 门 / 辶 / 阝 / 穴 / 雨
    ("宁", "宀+丁"), ("它", "宀+匕"), ("安", "宀+女"), ("守", "宀+寸"),
    ("宅", "宀+乇"), ("字", "宀+子"), ("完", "宀+元"), ("宏", "宀+厷"),
    ("宗", "宀+示"), ("官", "宀+吕"), ("定", "宀+正"), ("宜", "宀+且"),
    ("宝", "宀+玉"), ("实", "宀+头"), ("客", "宀+各"), ("室", "宀+至"),
    ("宫", "宀+吕"), ("害", "宀+丰+口"), ("宽", "宀+艹+见"), ("家", "宀+豕"),
    ("容", "宀+谷"), ("宿", "宀+亻+百"), ("密", "宀+必+山"), ("富", "宀+一+口+田"),
    ("寒", "宀+井+八"), ("察", "宀+祭"), ("审", "宀+申"), ("写", "冖+与"),
    ("军", "冖+车"), ("冠", "冖+元+寸"), ("农", "冖+衣"), ("空", "穴+工"),
    ("穿", "穴+牙"), ("突", "穴+犬"), ("窗", "穴+囱"), ("究", "穴+九"),
    ("穷", "穴+力"), ("广", "丶+厂"), ("庄", "广+土"), ("庆", "广+大"),
    ("床", "广+木"), ("序", "广+予"), ("库", "广+车"), ("应", "广+心"),
    ("底", "广+氐"), ("店", "广+占"), ("府", "广+付"), ("度", "广+廿+又"),
    ("座", "广+坐"), ("庭", "广+廷"), ("康", "广+隶"), ("废", "广+发"),
    ("厅", "厂+丁"), ("历", "厂+力"), ("压", "厂+土+丶"), ("厌", "厂+犬"),
    ("厚", "厂+日+子"), ("原", "厂+白+小"), ("病", "疒+丙"), ("疼", "疒+冬"),
    ("痛", "疒+甬"), ("疯", "疒+风"), ("疲", "疒+皮"), ("症", "疒+正"),
    ("瘦", "疒+叟"), ("疗", "疒+了"), ("闪", "门+人"), ("闭", "门+才"),
    ("问", "门+口"), ("闯", "门+马"), ("闲", "门+木"), ("间", "门+日"),
    ("闷", "门+心"), ("闹", "门+市"), ("闻", "门+耳"), ("阅", "门+兑"),
    ("阔", "门+活"), ("边", "力+辶"), ("达", "大+辶"), ("迁", "千+辶"),
    ("过", "寸+辶"), ("迈", "万+辶"), ("迎", "卬+辶"), ("运", "云+辶"),
    ("近", "斤+辶"), ("返", "反+辶"), ("还", "不+辶"), ("这", "文+辶"),
    ("进", "井+辶"), ("远", "元+辶"), ("连", "车+辶"), ("迟", "尺+辶"),
    ("追", "𠂤+辶"), ("退", "艮+辶"), ("送", "关+辶"), ("选", "先+辶"),
    ("通", "甬+辶"), ("速", "束+辶"), ("造", "告+辶"), ("逢", "夆+辶"),
    ("道", "首+辶"), ("遇", "禺+辶"), ("遍", "扁+辶"), ("避", "辟+辶"),
    ("队", "阝+人"), ("阳", "阝+日"), ("阴", "阝+月"), ("阵", "阝+车"),
    ("阶", "阝+介"), ("际", "阝+示"), ("阿", "阝+可"), ("附", "阝+付"),
    ("限", "阝+艮"), ("院", "阝+完"), ("除", "阝+余"), ("险", "阝+佥"),
    ("陪", "阝+咅"), ("随", "阝+有"), ("隔", "阝+鬲"), ("那", "冄+阝"),
    ("邦", "丰+阝"), ("邮", "由+阝"), ("邻", "令+阝"), ("郊", "交+阝"),
    ("郎", "良+阝"), ("郑", "关+阝"), ("部", "咅+阝"), ("都", "者+阝"),
    ("雪", "雨+彐"), ("零", "雨+令"), ("雷", "雨+田"), ("需", "雨+而"),
    ("震", "雨+辰"), ("霜", "雨+相"), ("露", "雨+路"), ("雾", "雨+务"),
    ("云", "二+厶"), ("电", "日+乚"), ("灵", "彐+火"), ("霍", "雨+隹"),
    # 贝 / 见 / 页 / 食(饣) / 车 / 马 / 牛 / 羊 / 犬(犭) / 鸟 / 鱼 / 虫
    ("财", "贝+才"), ("贡", "工+贝"), ("货", "化+贝"), ("质", "斤+十+贝"),
    ("贪", "今+贝"), ("贫", "分+贝"), ("购", "贝+勾"), ("账", "贝+长"),
    ("贩", "贝+反"), ("败", "贝+攵"), ("贴", "贝+占"), ("贵", "中+一+贝"),
    ("贷", "代+贝"), ("费", "弗+贝"), ("贺", "加+贝"), ("资", "次+贝"),
    ("贼", "贝+戎"), ("赏", "尚+贝"), ("赖", "束+负"), ("赛", "宀+井+贝"),
    ("赞", "先+先+贝"), ("观", "又+见"), ("规", "夫+见"), ("视", "礻+见"),
    ("览", "监+见"), ("觉", "学+见"), ("顶", "丁+页"), ("顺", "川+页"),
    ("须", "彡+页"), ("预", "予+页"), ("领", "令+页"), ("颇", "皮+页"),
    ("颜", "彦+页"), ("题", "是+页"), ("额", "客+页"), ("颗", "果+页"),
    ("饭", "饣+反"), ("饮", "饣+欠"), ("饱", "饣+包"), ("饿", "饣+我"),
    ("馆", "饣+官"), ("饼", "饣+并"), ("饺", "饣+交"), ("饰", "饣+市"),
    ("轨", "车+九"), ("轮", "车+仑"), ("软", "车+欠"), ("轻", "车+圣"),
    ("载", "十+戈+车"), ("较", "车+交"), ("辅", "车+甫"), ("辆", "车+两"),
    ("辈", "非+车"), ("输", "车+俞"), ("转", "车+专"), ("驱", "马+区"),
    ("驰", "马+也"), ("驳", "马+爻"), ("驻", "马+主"), ("驾", "加+马"),
    ("驶", "马+史"), ("验", "马+佥"), ("骑", "马+奇"), ("骗", "马+扁"),
    ("骚", "马+蚤"), ("物", "牛+勿"), ("特", "牛+寺"), ("牺", "牛+西"),
    ("牧", "牛+攵"), ("鲜", "鱼+羊"), ("美", "羊+大"), ("洋", "氵+羊"),
    ("详", "讠+羊"), ("群", "君+羊"), ("义", "丶+乂"), ("着", "羊+目"),
    ("犯", "犭+卩"), ("状", "丬+犬"), ("狂", "犭+王"), ("独", "犭+虫"),
    ("猜", "犭+青"), ("猫", "犭+苗"), ("猴", "犭+侯"), ("狗", "犭+句"),
    ("狼", "犭+良"), ("猪", "犭+者"), ("鸡", "又+鸟"), ("鸭", "甲+鸟"),
    ("鹅", "我+鸟"), ("鸣", "口+鸟"), ("鸿", "江+鸟"), ("鹤", "雚+鸟"),
    ("鲁", "鱼+日"), ("鲜", "鱼+羊"), ("鲤", "鱼+里"), ("鲸", "鱼+京"),
    ("蚂", "虫+马"), ("蚁", "虫+义"), ("蛋", "疋+虫"), ("蜜", "宀+必+虫"),
    ("蝶", "虫+枼"), ("蜂", "虫+夆"), ("融", "鬲+虫"), ("虾", "虫+下"),
    # 日 / 月 / 山 / 石 / 禾 / 米 / 竹(⺮) / 田 / 目 / 耳 / 足(⻊) / 身 / 舟 / 刀(刂) / 攵 / 示(礻) / 衣(衤)
    ("肝", "月+干"), ("肚", "月+土"), ("肥", "月+巴"), ("肩", "户+月"),
    ("肯", "止+月"), ("育", "云+月"), ("肺", "月+市"), ("背", "北+月"),
    ("胎", "月+台"), ("胜", "月+生"), ("胞", "月+包"), ("胡", "古+月"),
    ("胶", "月+交"), ("胸", "月+匈"), ("能", "厶+月+匕+匕"), ("脂", "月+旨"),
    ("脆", "月+危"), ("脉", "月+永"), ("脏", "月+庄"), ("脑", "月+凶"),
    ("脚", "月+去+卩"), ("脱", "月+兑"), ("脸", "月+佥"), ("腰", "月+要"),
    ("腹", "月+复"), ("腿", "月+退"), ("膀", "月+旁"), ("膜", "月+莫"),
    ("岁", "山+夕"), ("岂", "山+己"), ("岗", "山+冈"), ("岛", "鸟+山"),
    ("峰", "山+夆"), ("崇", "山+宗"), ("崩", "山+朋"), ("岳", "丘+山"),
    ("岸", "山+厂+干"), ("炭", "山+灰"), ("岭", "山+令"), ("峡", "山+夹"),
    ("矿", "石+广"), ("码", "石+马"), ("研", "石+开"), ("砖", "石+专"),
    ("破", "石+皮"), ("硬", "石+更"), ("确", "石+角"), ("碎", "石+卒"),
    ("碗", "石+宛"), ("碟", "石+枼"), ("碰", "石+并"), ("磁", "石+兹"),
    ("磨", "麻+石"), ("碧", "王+白+石"), ("利", "禾+刂"), ("私", "禾+厶"),
    ("秋", "禾+火"), ("科", "禾+斗"), ("秒", "禾+少"), ("租", "禾+且"),
    ("积", "禾+只"), ("称", "禾+尔"), ("移", "禾+多"), ("程", "禾+呈"),
    ("税", "禾+兑"), ("稳", "禾+急"), ("种", "禾+中"), ("稿", "禾+高"),
    ("粉", "米+分"), ("粒", "米+立"), ("粗", "米+且"), ("精", "米+青"),
    ("糊", "米+胡"), ("糖", "米+唐"), ("糕", "米+羔"), ("粮", "米+良"),
    ("料", "米+斗"), ("类", "米+大"), ("笑", "⺮+夭"), ("笔", "⺮+毛"),
    ("笨", "⺮+本"), ("第", "⺮+弟"), ("符", "⺮+付"), ("答", "⺮+合"),
    ("策", "⺮+朿"), ("算", "⺮+目+廾"), ("管", "⺮+官"), ("简", "⺮+间"),
    ("箱", "⺮+相"), ("篇", "⺮+扁"), ("篮", "⺮+监"), ("等", "⺮+寺"),
    ("思", "田+心"), ("界", "田+介"), ("留", "卯+田"), ("略", "田+各"),
    ("番", "采+田"), ("画", "一+田+凵"), ("异", "巳+廾"), ("当", "小+彐"),
    ("盯", "目+丁"), ("盲", "亡+目"), ("相", "木+目"), ("省", "少+目"),
    ("眉", "尸+目"), ("真", "十+具"), ("眼", "目+艮"), ("睡", "目+垂"),
    ("睁", "目+争"), ("瞎", "目+害"), ("瞧", "目+焦"), ("取", "耳+又"),
    ("联", "耳+关"), ("聊", "耳+卯"), ("聪", "耳+总"), ("职", "耳+只"),
    ("闻", "门+耳"), ("声", "士+尸"), ("跳", "⻊+兆"), ("跑", "⻊+包"),
    ("跨", "⻊+夸"), ("路", "⻊+各"), ("跟", "⻊+艮"), ("踩", "⻊+采"),
    ("踏", "⻊+水+日"), ("踢", "⻊+易"), ("跃", "⻊+夭"), ("距", "⻊+巨"),
    ("射", "身+寸"), ("躺", "身+尚"), ("躲", "身+朵"), ("航", "舟+亢"),
    ("般", "舟+殳"), ("船", "舟+几+口"), ("舰", "舟+见"), ("艇", "舟+廷"),
    ("切", "七+刀"), ("分", "八+刀"), ("刊", "千+刂"), ("刑", "开+刂"),
    ("列", "歹+刂"), ("刘", "文+刂"), ("刚", "冈+刂"), ("创", "仓+刂"),
    ("初", "衤+刀"), ("删", "册+刂"), ("别", "另+刂"), ("到", "至+刂"),
    ("制", "牛+巾+刂"), ("刷", "尸+巾+刂"), ("刺", "朿+刂"), ("刻", "亥+刂"),
    ("剂", "齐+刂"), ("前", "丷+月+刂"), ("剑", "佥+刂"), ("剧", "居+刂"),
    ("副", "一+口+田+刂"), ("割", "害+刂"), ("剩", "乘+刂"), ("收", "丩+攵"),
    ("改", "己+攵"), ("攻", "工+攵"), ("放", "方+攵"), ("政", "正+攵"),
    ("故", "古+攵"), ("效", "交+攵"), ("敏", "每+攵"), ("救", "求+攵"),
    ("教", "孝+攵"), ("散", "艹+月+攵"), ("数", "娄+攵"), ("敌", "舌+攵"),
    ("整", "束+攵+正"), ("敢", "耳+攵"), ("礼", "礻+乙"), ("社", "礻+土"),
    ("神", "礻+申"), ("祖", "礻+且"), ("祝", "礻+兄"), ("票", "西+示"),
    ("福", "礻+一+口+田"), ("祸", "礻+呙"), ("祥", "礻+羊"), ("补", "衤+卜"),
    ("衬", "衤+寸"), ("衫", "衤+彡"), ("袖", "衤+由"), ("被", "衤+皮"),
    ("装", "壮+衣"), ("裤", "衤+库"), ("裙", "衤+君"), ("裕", "衤+谷"),
    # 王 / 白 / 巾 / 广 / 弓 / 斤 / 戈 / 王 / 欠 / 彳 / 囗 / 门 / 匚 / 勹 / 几
    ("玩", "王+元"), ("现", "王+见"), ("班", "王+刂+王"), ("球", "王+求"),
    ("理", "王+里"), ("环", "王+不"), ("珠", "王+朱"), ("珍", "王+人+彡"),
    ("玻", "王+皮"), ("璃", "王+离"), ("瑞", "王+端"), ("琴", "王+王+今"),
    ("皇", "白+王"), ("的", "白+勺"), ("百", "一+白"), ("皆", "比+白"),
    ("布", "十+巾"), ("希", "乂+布"), ("师", "丨+丿+巾"), ("帅", "丨+丿+巾"),
    ("帝", "立+冖+巾"), ("席", "广+廿+巾"), ("带", "廿+冖+巾"), ("常", "尚+巾"),
    ("帮", "邦+巾"), ("幅", "巾+一+口+田"), ("帽", "巾+冒"), ("幕", "莫+巾"),
    ("引", "弓+丨"), ("张", "弓+长"), ("强", "弓+虽"), ("弹", "弓+单"),
    ("弱", "弓+冫+弓"), ("弯", "亦+弓"), ("斤", "厂+丁+丨"), ("新", "亲+斤"),
    ("断", "米+乙+斤"), ("斯", "其+斤"), ("所", "户+斤"), ("斩", "车+斤"),
    ("欣", "斤+欠"), ("欢", "又+欠"), ("欧", "区+欠"), ("欲", "谷+欠"),
    ("欺", "其+欠"), ("款", "士+示+欠"), ("歌", "哥+欠"), ("软", "车+欠"),
    ("行", "彳+亍"), ("往", "彳+主"), ("征", "彳+正"), ("待", "彳+寺"),
    ("很", "彳+艮"), ("律", "彳+聿"), ("后", "厂+一+口"), ("徒", "彳+走"),
    ("得", "彳+日+寸"), ("循", "彳+盾"), ("微", "彳+山+一+兀+攵"), ("德", "彳+十+罒+心"),
    ("囚", "囗+人"), ("四", "囗+儿"), ("回", "囗+口"), ("因", "囗+大"),
    ("团", "囗+才"), ("园", "囗+元"), ("困", "囗+木"), ("围", "囗+韦"),
    ("图", "囗+冬"), ("固", "囗+古"), ("国", "囗+玉"), ("圆", "囗+员"),
    ("圈", "囗+卷"), ("国", "囗+玉"), ("风", "几+乂"), ("凤", "几+又"),
    ("凡", "几+丶"), ("凭", "任+几"), ("凯", "岂+几"), ("机", "木+几"),
    ("医", "匚+矢"), ("区", "匚+乂"), ("匹", "匚+儿"), ("巨", "匚+工"),
    ("匠", "匚+斤"), ("匣", "匚+甲"), ("匪", "匚+非"), ("汇", "氵+匚"),
    ("勺", "勹+丶"), ("匀", "勹+二"), ("勾", "勹+厶"), ("勿", "勹+丿+丿"),
    ("包", "勹+巳"), ("旬", "勹+日"), ("句", "勹+口"), ("够", "句+多"),
    # Everyday high-frequency compounds (100+ additional common structures)
    ("全", "人+王"), ("企", "人+止"), ("会", "人+云"), ("合", "人+一+口"),
    ("今", "人+一+乛"), ("令", "人+一+丶"), ("拿", "合+手"), ("盒", "合+皿"),
    ("盆", "分+皿"), ("盘", "般+皿"), ("盛", "成+皿"), ("盟", "明+皿"),
    ("监", "丨+丨+皿"), ("盗", "次+皿"), ("益", "丷+一+皿"), ("盐", "土+卜+皿"),
    ("盖", "羊+皿"), ("尽", "尺+冫"), ("层", "尸+云"), ("居", "尸+古"),
    ("局", "尸+口"), ("屋", "尸+至"), ("届", "尸+由"), ("尾", "尸+毛"),
    ("尿", "尸+水"), ("展", "尸+艹+衣"), ("属", "尸+禹"), ("屏", "尸+并"),
    ("尼", "尸+匕"), ("尺", "尸+丶"), ("房", "户+方"), ("所", "户+斤"),
    ("扇", "户+羽"), ("启", "户+口"), ("扁", "户+册"), ("肩", "户+月"),
    ("加", "力+口"), ("办", "力+八"), ("动", "云+力"), ("助", "且+力"),
    ("努", "奴+力"), ("劲", "圣+力"), ("劳", "艹+冖+力"), ("势", "执+力"),
    ("勇", "甬+力"), ("勉", "免+力"), ("勒", "革+力"), ("勤", "堇+力"),
    ("功", "工+力"), ("攻", "工+攵"), ("项", "工+页"), ("巧", "工+丂"),
    ("左", "十+工"), ("右", "十+口"), ("布", "十+巾"), ("有", "十+月"),
    ("友", "十+又"), ("灰", "厂+火"), ("在", "十+土"), ("存", "十+子"),
    ("孝", "耂+子"), ("老", "耂+匕"), ("考", "耂+丂"), ("者", "耂+日"),
    ("李", "木+子"), ("字", "宀+子"), ("孙", "子+小"), ("季", "禾+子"),
    ("学", "⺌+冖+子"), ("孩", "子+亥"), ("孤", "子+瓜"), ("孔", "子+乚"),
    ("孕", "乃+子"), ("孟", "子+皿"), ("保", "亻+呆"), ("呆", "口+木"),
    ("查", "木+旦"), ("杳", "木+日"), ("杲", "日+木"), ("东", "一+小+乙"),
    ("香", "禾+日"), ("音", "立+日"), ("意", "音+心"), ("章", "立+早"),
    ("竟", "立+日+儿"), ("童", "立+里"), ("站", "立+占"), ("亲", "立+木"),
    ("新", "亲+斤"), ("辛", "立+十"), ("辣", "辛+束"), ("辨", "辛+刂+辛"),
    ("辩", "辛+讠+辛"), ("辞", "舌+辛"), ("站", "立+占"), ("端", "立+山+而"),
    ("奇", "大+可"), ("奈", "大+示"), ("套", "大+长"), ("太", "大+丶"),
    ("犬", "大+丶"), ("天", "一+大"), ("夫", "二+人"), ("央", "丨+大"),
    ("夹", "一+人+大"), ("套", "大+长"), ("奔", "大+卉"), ("奖", "丬+夕+大"),
    ("契", "丰+刀+大"), ("奠", "酋+大"), ("奥", "丿+米+大"), ("夺", "大+寸"),
    ("奋", "大+田"), ("爽", "大+乂+乂"), ("美", "羊+大"), ("达", "大+辶"),
    ("莫", "艹+日+大"), ("笑", "⺮+夭"), ("吴", "口+天"), ("吞", "天+口"),
    ("蚕", "天+虫"), ("关", "丷+天"), ("送", "关+辶"), ("联", "耳+关"),
    ("咲", "口+关"), ("联", "耳+关"), ("郑", "关+阝"), ("美", "羊+大"),
    ("着", "羊+目"), ("差", "羊+工"), ("养", "羊+介"), ("羞", "羊+丑"),
    ("群", "君+羊"), ("鲜", "鱼+羊"), ("祥", "礻+羊"), ("详", "讠+羊"),
    ("洋", "氵+羊"), ("样", "木+羊"), ("氧", "气+羊"), ("氢", "气+圣"),
    ("氮", "气+炎"), ("氯", "气+录"), ("氦", "气+亥"), ("氨", "气+安"),
    ("氛", "气+分"), ("氟", "气+弗"), ("氖", "气+乃"), ("氩", "气+亚"),
    ("男", "田+力"), ("思", "田+心"), ("界", "田+介"), ("留", "卯+田"),
    ("略", "田+各"), ("胃", "田+月"), ("累", "田+糸"), ("细", "纟+田"),
    ("苗", "艹+田"), ("猫", "犭+苗"), ("描", "扌+苗"), ("瞄", "目+苗"),
    ("锚", "钅+苗"), ("雷", "雨+田"), ("电", "日+乚"), ("画", "一+田+凵"),
    ("番", "采+田"), ("翻", "番+羽"), ("审", "宀+申"), ("伸", "亻+申"),
    ("神", "礻+申"), ("坤", "土+申"), ("畅", "申+易"), ("甲", "田+丨"),
    ("鸭", "甲+鸟"), ("押", "扌+甲"), ("闸", "门+甲"), ("钾", "钅+甲"),
    ("由", "田+丨"), ("油", "氵+由"), ("抽", "扌+由"), ("袖", "衤+由"),
    ("邮", "由+阝"), ("届", "尸+由"), ("迪", "由+辶"), ("轴", "车+由"),
    ("青", "丰+月"), ("清", "氵+青"), ("晴", "日+青"), ("情", "忄+青"),
    ("请", "讠+青"), ("精", "米+青"), ("猜", "犭+青"), ("静", "青+争"),
    ("蜻", "虫+青"), ("菁", "艹+青"), ("靓", "青+见"), ("靖", "立+青"),
    ("白", "丿+日"), ("百", "一+白"), ("伯", "亻+白"), ("柏", "木+白"),
    ("拍", "扌+白"), ("泊", "氵+白"), ("怕", "忄+白"), ("迫", "白+辶"),
    ("皇", "白+王"), ("泉", "白+水"), ("碧", "王+白+石"), ("的", "白+勺"),
    ("自", "丿+目"), ("息", "自+心"), ("咱", "口+自"), ("臭", "自+犬"),
    ("鼻", "自+田+廾"), ("首", "丷+一+自"), ("道", "首+辶"), ("导", "巳+寸"),
    ("古", "十+口"), ("估", "亻+古"), ("故", "古+攵"), ("固", "囗+古"),
    ("姑", "女+古"), ("咕", "口+古"), ("枯", "木+古"), ("苦", "艹+古"),
    ("胡", "古+月"), ("湖", "氵+胡"), ("糊", "米+胡"), ("居", "尸+古"),
    ("吉", "士+口"), ("结", "纟+吉"), ("洁", "氵+吉"), ("桔", "木+吉"),
    ("喆", "吉+吉"), ("可", "丁+口"), ("何", "亻+可"), ("河", "氵+可"),
    ("呵", "口+可"), ("荷", "艹+何"), ("奇", "大+可"), ("哥", "可+可"),
    ("歌", "哥+欠"), ("阿", "阝+可"), ("啊", "口+阿"), ("同", "冂+一+口"),
    ("铜", "钅+同"), ("洞", "氵+同"), ("桐", "木+同"), ("筒", "⺮+同"),
    ("司", "刁+口"), ("词", "讠+司"), ("饲", "饣+司"), ("同", "冂+一+口"),
    ("周", "冂+土+口"), ("调", "讠+周"), ("雕", "周+隹"), ("稠", "禾+周"),
    ("工", "一+丨+一"), ("功", "工+力"), ("红", "纟+工"), ("江", "氵+工"),
    ("扛", "扌+工"), ("空", "穴+工"), ("虹", "虫+工"), ("贡", "工+贝"),
    ("项", "工+页"), ("巧", "工+丂"), ("左", "十+工"), ("差", "羊+工"),
    ("主", "丶+王"), ("住", "亻+主"), ("注", "氵+主"), ("柱", "木+主"),
    ("驻", "马+主"), ("往", "彳+主"), ("玉", "王+丶"), ("国", "囗+玉"),
    ("宝", "宀+玉"), ("王", "三+丨"), ("全", "人+王"), ("金", "人+王+丷"),
    ("铁", "钅+失"), ("银", "钅+艮"), ("钱", "钅+戋"), ("钟", "钅+中"),
    ("铜", "钅+同"), ("错", "钅+昔"), ("镜", "钅+竟"), ("键", "钅+建"),
    ("化", "亻+匕"), ("花", "艹+化"), ("货", "化+贝"), ("华", "化+十"),
    ("分", "八+刀"), ("份", "亻+分"), ("粉", "米+分"), ("纷", "纟+分"),
    ("盆", "分+皿"), ("贫", "分+贝"), ("盼", "目+分"), ("扮", "扌+分"),
    ("反", "厂+又"), ("饭", "饣+反"), ("板", "木+反"), ("版", "片+反"),
    ("返", "反+辶"), ("贩", "贝+反"), ("坂", "土+反"), ("皮", "乛+丿+丨+又"),
    ("波", "氵+皮"), ("破", "石+皮"), ("被", "衤+皮"), ("坡", "土+皮"),
    ("疲", "疒+皮"), ("彼", "彳+皮"), ("玻", "王+皮"), ("颇", "皮+页"),
    ("巴", "乛+丨+一+乚"), ("把", "扌+巴"), ("吧", "口+巴"), ("爸", "父+巴"),
    ("肥", "月+巴"), ("爬", "爪+巴"), ("色", "⺈+巴"), ("绝", "纟+色"),
    ("包", "勹+巳"), ("抱", "扌+包"), ("泡", "氵+包"), ("炮", "火+包"),
    ("跑", "⻊+包"), ("饱", "饣+包"), ("胞", "月+包"), ("袍", "衤+包"),
    ("令", "人+一+丶"), ("冷", "冫+令"), ("铃", "钅+令"), ("领", "令+页"),
    ("邻", "令+阝"), ("零", "雨+令"), ("龄", "齿+令"), ("岭", "山+令"),
    ("今", "人+一+乛"), ("含", "今+口"), ("念", "今+心"), ("贪", "今+贝"),
    ("阴", "阝+月"), ("阳", "阝+日"), ("琴", "王+王+今"), ("含", "今+口"),
    ("方", "亠+万"), ("房", "户+方"), ("防", "阝+方"), ("放", "方+攵"),
    ("访", "讠+方"), ("仿", "亻+方"), ("芳", "艹+方"), ("妨", "女+方"),
    ("旁", "立+冖+方"), ("傍", "亻+旁"), ("榜", "木+旁"), ("膀", "月+旁"),
    ("文", "亠+乂"), ("纹", "纟+文"), ("蚊", "虫+文"), ("坟", "土+文"),
    ("这", "文+辶"), ("刘", "文+刂"), ("产", "立+丿"), ("齐", "文+丿+丨"),
    ("交", "亠+父"), ("校", "木+交"), ("较", "车+交"), ("效", "交+攵"),
    ("咬", "口+交"), ("胶", "月+交"), ("饺", "饣+交"), ("郊", "交+阝"),
    ("京", "亠+口+小"), ("凉", "冫+京"), ("惊", "忄+京"), ("景", "日+京"),
    ("影", "景+彡"), ("就", "京+尤"), ("鲸", "鱼+京"), ("高", "亠+口+冂+口"),
    ("搞", "扌+高"), ("稿", "禾+高"), ("亮", "亠+口+冖+几"), ("亭", "亠+口+冖+丁"),
    ("停", "亻+亭"), ("享", "亠+口+子"), ("熟", "孰+灬"), ("毫", "亠+口+冖+毛"),
    ("早", "日+十"), ("草", "艹+早"), ("章", "立+早"), ("障", "阝+章"),
    ("彰", "章+彡"), ("卓", "卜+早"), ("掉", "扌+卓"), ("桌", "卜+日+木"),
    ("朝", "十+日+十+月"), ("潮", "氵+朝"), ("韩", "十+日+十+韦"), ("干", "一+十"),
    ("汗", "氵+干"), ("肝", "月+干"), ("杆", "木+干"), ("赶", "走+干"),
    ("刊", "千+刂"), ("平", "干+丷"), ("评", "讠+平"), ("坪", "土+平"),
    ("苹", "艹+平"), ("称", "禾+尔"), ("秤", "禾+平"), ("千", "丿+十"),
    ("迁", "千+辶"), ("舌", "千+口"), ("活", "氵+舌"), ("话", "讠+舌"),
    ("甜", "舌+甘"), ("乱", "舌+乚"), ("辞", "舌+辛"), ("敌", "舌+攵"),
    ("中", "口+丨"), ("忠", "中+心"), ("钟", "钅+中"), ("种", "禾+中"),
    ("冲", "冫+中"), ("仲", "亻+中"), ("串", "口+口+丨"), ("患", "串+心"),
    ("申", "日+丨"), ("电", "日+乚"), ("由", "田+丨"), ("甲", "田+丨"),
    ("果", "田+木"), ("课", "讠+果"), ("颗", "果+页"), ("棵", "木+果"),
    ("裹", "衣+果"), ("巢", "巛+果"), ("里", "田+土"), ("理", "王+里"),
    ("埋", "土+里"), ("鲤", "鱼+里"), ("量", "旦+里"), ("重", "千+里"),
    ("懂", "忄+董"), ("董", "艹+重"), ("动", "云+力"), ("童", "立+里"),
    ("撞", "扌+童"), ("钟", "钅+中"), ("东", "一+小+乙"), ("冻", "冫+东"),
    ("栋", "木+东"), ("练", "纟+东"), ("炼", "火+东"), ("陈", "阝+东"),
    ("车", "一+𠃋+一+丨"), ("连", "车+辶"), ("库", "广+车"), ("阵", "阝+车"),
    ("军", "冖+车"), ("辉", "光+军"), ("挥", "扌+军"), ("浑", "氵+军"),
    ("晕", "日+军"), ("运", "云+辶"), ("动", "云+力"), ("坛", "土+云"),
    ("会", "人+云"), ("层", "尸+云"), ("魂", "云+鬼"), ("芸", "艹+云"),
    ("元", "二+儿"), ("完", "宀+元"), ("玩", "王+元"), ("园", "囗+元"),
    ("远", "元+辶"), ("院", "阝+完"), ("冠", "冖+元+寸"), ("顽", "元+页"),
    ("光", "⺌+兀"), ("晃", "日+光"), ("辉", "光+军"), ("耀", "光+翟"),
    ("先", "牛+儿"), ("洗", "氵+先"), ("选", "先+辶"), ("赞", "先+先+贝"),
    ("见", "冂+儿"), ("现", "王+见"), ("观", "又+见"), ("规", "夫+见"),
    ("视", "礻+见"), ("觉", "学+见"), ("览", "监+见"), ("宽", "宀+艹+见"),
    ("兄", "口+儿"), ("克", "十+兄"), ("竞", "立+兄"), ("祝", "礻+兄"),
    ("况", "冫+兄"), ("说", "讠+兑"), ("税", "禾+兑"), ("悦", "忄+兑"),
    ("脱", "月+兑"), ("阅", "门+兑"), ("锐", "钅+兑"), ("兑", "丷+兄"),
    ("只", "口+八"), ("识", "讠+只"), ("职", "耳+只"), ("织", "纟+只"),
    ("积", "禾+只"), ("站", "立+占"), ("点", "占+灬"), ("店", "广+占"),
    ("贴", "贝+占"), ("粘", "米+占"), ("钻", "钅+占"), ("沾", "氵+占"),
    ("战", "占+戈"), ("台", "厶+口"), ("始", "女+台"), ("治", "氵+台"),
    ("抬", "扌+台"), ("胎", "月+台"), ("态", "太+心"), ("怠", "台+心"),
    ("能", "厶+月+匕+匕"), ("熊", "能+灬"), ("罢", "罒+去"), ("去", "土+厶"),
    ("法", "氵+去"), ("丢", "丿+去"), ("却", "去+卩"), ("劫", "去+力"),
    ("云", "二+厶"), ("公", "八+厶"), ("松", "木+公"), ("颂", "公+页"),
    ("私", "禾+厶"), ("勾", "勹+厶"), ("么", "丿+厶"), ("至", "一+厶+土"),
    ("到", "至+刂"), ("倒", "亻+到"), ("室", "宀+至"), ("屋", "尸+至"),
    ("致", "至+攵"), ("台", "厶+口"), ("弁", "厶+廾"), ("参", "厶+大+彡"),
    ("生", "丿+三+丨"), ("星", "日+生"), ("姓", "女+生"), ("性", "忄+生"),
    ("胜", "月+生"), ("产", "立+丿"), ("醒", "酉+星"), ("姓", "女+生"),
    ("主", "丶+王"), ("全", "人+王"), ("呈", "口+王"), ("程", "禾+呈"),
    ("圣", "又+土"), ("怪", "忄+圣"), ("经", "纟+圣"), ("轻", "车+圣"),
    ("径", "彳+圣"), ("劲", "圣+力"), ("氢", "气+圣"), ("茎", "艹+圣"),
    ("各", "夂+口"), ("客", "宀+各"), ("格", "木+各"), ("落", "艹+洛"),
    ("洛", "氵+各"), ("略", "田+各"), ("路", "⻊+各"), ("露", "雨+路"),
    ("格", "木+各"), ("额", "客+页"), ("阁", "门+各"), ("络", "纟+各"),
    ("合", "人+一+口"), ("哈", "口+合"), ("拾", "扌+合"), ("给", "纟+合"),
    ("答", "⺮+合"), ("恰", "忄+合"), ("洽", "氵+合"), ("盒", "合+皿"),
    ("鸽", "合+鸟"), ("拿", "合+手"), ("命", "人+一+口+卩"), ("令", "人+一+丶"),
    ("者", "耂+日"), ("都", "者+阝"), ("猪", "犭+者"), ("诸", "讠+者"),
    ("煮", "者+灬"), ("暑", "日+者"), ("署", "罒+者"), ("著", "艹+者"),
    ("堵", "土+者"), ("绪", "纟+者"), ("赌", "贝+者"), ("奢", "大+者"),
    ("正", "一+止"), ("政", "正+攵"), ("证", "讠+正"), ("症", "疒+正"),
    ("整", "束+攵+正"), ("征", "彳+正"), ("歪", "不+正"), ("定", "宀+正"),
    ("是", "日+正"), ("提", "扌+是"), ("题", "是+页"), ("堤", "土+是"),
    ("成", "厂+丁+戈"), ("城", "土+成"), ("诚", "讠+成"), ("盛", "成+皿"),
    ("感", "咸+心"), ("减", "冫+咸"), ("喊", "口+咸"), ("威", "戌+女"),
    ("或", "戈+口+一"), ("国", "囗+玉"), ("域", "土+或"), ("惑", "或+心"),
    ("我", "手+戈"), ("找", "扌+戈"), ("戏", "又+戈"), ("划", "戈+刂"),
    ("战", "占+戈"), ("载", "十+戈+车"), ("戴", "十+戈+田+共"), ("栽", "十+戈+木"),
    ("裁", "十+戈+衣"), ("截", "十+戈+隹"), ("钱", "钅+戋"), ("浅", "氵+戋"),
    ("线", "纟+戋"), ("践", "⻊+戋"), ("残", "歹+戋"), ("贱", "贝+戋"),
    ("比", "匕+匕"), ("批", "扌+比"), ("毕", "比+十"), ("皆", "比+白"),
    ("混", "氵+昆"), ("昆", "日+比"), ("北", "丨+一+匕"), ("背", "北+月"),
    ("能", "厶+月+匕+匕"), ("尼", "尸+匕"), ("泥", "氵+尼"), ("呢", "口+尼"),
    ("真", "十+具"), ("镇", "钅+真"), ("填", "土+真"), ("慎", "忄+真"),
    ("直", "十+目+∟"), ("值", "亻+直"), ("植", "木+直"), ("置", "罒+直"),
    ("真", "十+具"), ("具", "目+一+八"), ("俱", "亻+具"), ("惧", "忄+具"),
    ("相", "木+目"), ("想", "相+心"), ("箱", "⺮+相"), ("霜", "雨+相"),
    ("湘", "氵+相"), ("目", "冂+三"), ("看", "手+目"), ("着", "羊+目"),
    ("眉", "尸+目"), ("省", "少+目"), ("冒", "曰+目"), ("帽", "巾+冒"),
    ("曼", "曰+罒+又"), ("慢", "忄+曼"), ("漫", "氵+曼"), ("温", "氵+昷"),
    ("民", "乙+一+乙"), ("眠", "目+民"), ("婚", "女+昏"), ("昏", "氏+日"),
    ("闻", "门+耳"), ("问", "门+口"), ("间", "门+日"), ("简", "⺮+间"),
    ("闪", "门+人"), ("闲", "门+木"), ("闭", "门+才"), ("闷", "门+心"),
    ("闹", "门+市"), ("闯", "门+马"), ("阅", "门+兑"), ("开", "一+廾"),
    ("研", "石+开"), ("刑", "开+刂"), ("型", "刑+土"), ("形", "开+彡"),
    ("影", "景+彡"), ("彩", "采+彡"), ("须", "彡+页"), ("杉", "木+彡"),
    ("珍", "王+人+彡"), ("参", "厶+大+彡"), ("修", "攸+彡"), ("彭", "壴+彡"),
    ("良", "丶+艮"), ("浪", "氵+良"), ("狼", "犭+良"), ("娘", "女+良"),
    ("粮", "米+良"), ("朗", "良+月"), ("郎", "良+阝"), ("限", "阝+艮"),
    ("很", "彳+艮"), ("恨", "忄+艮"), ("根", "木+艮"), ("跟", "⻊+艮"),
    ("退", "艮+辶"), ("眼", "目+艮"), ("银", "钅+艮"), ("恳", "艮+心"),
    ("莫", "艹+日+大"), ("摸", "扌+莫"), ("模", "木+莫"), ("膜", "月+莫"),
    ("漠", "氵+莫"), ("幕", "莫+巾"), ("墓", "莫+土"), ("暮", "莫+日"),
    ("慕", "莫+小"), ("昔", "艹+日"), ("借", "亻+昔"), ("错", "钅+昔"),
    ("惜", "忄+昔"), ("措", "扌+昔"), ("散", "艹+月+攵"), ("撒", "扌+散"),
    ("每", "丿+一+母"), ("海", "氵+每"), ("梅", "木+每"), ("悔", "忄+每"),
    ("敏", "每+攵"), ("繁", "敏+糸"), ("母", "母"), ("毒", "主+母"),
    ("求", "一+水+丶"), ("球", "王+求"), ("救", "求+攵"), ("永", "丶+水"),
    ("泳", "氵+永"), ("咏", "口+永"), ("脉", "月+永"), ("水", "水"),
    ("录", "彐+水"), ("绿", "纟+录"), ("碌", "石+录"), ("氯", "气+录"),
    ("剥", "录+刂"), ("皮", "皮"), ("波", "氵+皮"), ("破", "石+皮"),
    ("希", "乂+布"), ("稀", "禾+希"), ("烯", "火+希"), ("杀", "乂+木"),
    ("文", "亠+乂"), ("义", "丶+乂"), ("叉", "又+丶"), ("双", "又+又"),
    ("欢", "又+欠"), ("观", "又+见"), ("难", "又+隹"), ("鸡", "又+鸟"),
    ("对", "又+寸"), ("树", "木+对"), ("权", "木+又"), ("凤", "几+又"),
    ("叹", "口+又"), ("戏", "又+戈"), ("圣", "又+土"), ("奴", "女+又"),
    ("取", "耳+又"), ("最", "日+取"), ("趣", "走+取"), ("聚", "取+众"),
    ("受", "爫+冖+又"), ("授", "扌+受"), ("爱", "爫+冖+友"), ("采", "爫+木"),
    ("菜", "艹+采"), ("踩", "⻊+采"), ("彩", "采+彡"), ("翻", "番+羽"),
    ("习", "乛+冫"), ("羽", "习+习"), ("扇", "户+羽"), ("翠", "羽+卒"),
    ("翼", "羽+异"), ("翔", "羊+羽"), ("翁", "公+羽"), ("飞", "飞"),
    ("非", "非"), ("悲", "非+心"), ("罪", "罒+非"), ("排", "扌+非"),
    ("啡", "口+非"), ("菲", "艹+非"), ("辈", "非+车"), ("靠", "告+非"),
    ("罪", "罒+非"), ("罗", "罒+夕"), ("置", "罒+直"), ("署", "罒+者"),
    ("罢", "罒+去"), ("罚", "罒+讠+刂"), ("骂", "口+口+马"), ("买", "乛+头"),
    ("卖", "十+买"), ("读", "讠+卖"), ("续", "纟+卖"), ("实", "宀+头"),
    ("头", "丶+丶+大"), ("买", "乛+头"), ("类", "米+大"), ("兴", "丷+一+八"),
    ("举", "兴+丰"), ("单", "丷+甲"), ("弹", "弓+单"), ("禅", "礻+单"),
    ("战", "占+戈"), ("兽", "丷+田+一+口"), ("益", "丷+一+皿"), ("前", "丷+月+刂"),
    ("剪", "前+刀"), ("煎", "前+灬"), ("箭", "⺮+前"), ("半", "丷+十"),
    ("伴", "亻+半"), ("胖", "月+半"), ("判", "半+刂"), ("叛", "半+反"),
    ("平", "干+丷"), ("并", "丷+开"), ("拼", "扌+并"), ("饼", "饣+并"),
    ("屏", "尸+并"), ("普", "并+日"), ("碰", "石+并"), ("兼", "丷+一+彐+八"),
    ("谦", "讠+兼"), ("赚", "贝+兼"), ("嫌", "女+兼"), ("廉", "广+兼"),
    ("羊", "丷+三+丨"), ("美", "羊+大"), ("着", "羊+目"), ("差", "羊+工"),
    ("义", "丶+乂"), ("议", "讠+义"), ("仪", "亻+义"), ("蚁", "虫+义"),
    ("区", "匚+乂"), ("欧", "区+欠"), ("驱", "马+区"), ("枢", "木+区"),
    ("风", "几+乂"), ("疯", "疒+风"), ("枫", "木+风"), ("讽", "讠+风"),
    ("义", "丶+乂"), ("冈", "冂+乂"), ("刚", "冈+刂"), ("钢", "钅+冈"),
    ("纲", "纟+冈"), ("岗", "山+冈"), ("网", "冂+乂+乂"), ("内", "冂+人"),
    ("肉", "冂+人+人"), ("纳", "纟+内"), ("呐", "口+内"), ("钠", "钅+内"),
    ("同", "冂+一+口"), ("用", "冂+丰"), ("拥", "扌+用"), ("周", "冂+土+口"),
    ("问", "门+口"), ("向", "丿+冂+口"), ("高", "亠+口+冂+口"), ("市", "亠+巾"),
    ("闹", "门+市"), ("肺", "月+市"), ("沛", "氵+市"), ("布", "十+巾"),
    ("希", "乂+布"), ("右", "十+口"), ("左", "十+工"), ("有", "十+月"),
    ("友", "十+又"), ("存", "十+子"), ("在", "十+土"), ("克", "十+兄"),
    ("古", "十+口"), ("早", "日+十"), ("卓", "卜+早"), ("协", "十+办"),
    ("博", "十+尃"), ("南", "十+冂+羊"), ("直", "十+目+∟"), ("真", "十+具"),
    ("卖", "十+买"), ("支", "十+又"), ("技", "扌+支"), ("枝", "木+支"),
    ("肢", "月+支"), ("鼓", "壴+支"), ("老", "耂+匕"), ("者", "耂+日"),
    ("考", "耂+丂"), ("孝", "耂+子"), ("教", "孝+攵"), ("都", "者+阝"),
    ("猪", "犭+者"), ("诸", "讠+者"), ("煮", "者+灬"), ("暑", "日+者"),
    ("署", "罒+者"), ("著", "艹+者"), ("堵", "土+者"), ("绪", "纟+者"),
    ("赌", "贝+者"), ("奢", "大+者"), ("煮", "者+灬"), ("屠", "尸+者"),
    ("马", "马"), ("吗", "口+马"), ("妈", "女+马"), ("码", "石+马"),
    ("骂", "口+口+马"), ("蚂", "虫+马"), ("闯", "门+马"), ("冯", "冫+马"),
    ("驾", "加+马"), ("骂", "口+口+马"), ("乌", "乌"), ("呜", "口+乌"),
    ("坞", "土+乌"), ("钨", "钅+乌"), ("鸟", "鸟"), ("鸣", "口+鸟"),
    ("岛", "鸟+山"), ("鸡", "又+鸟"), ("鸭", "甲+鸟"), ("鹅", "我+鸟"),
    ("鱼", "鱼"), ("渔", "氵+鱼"), ("鲁", "鱼+日"), ("鲜", "鱼+羊"),
    ("虫", "虫"), ("虽", "口+虫"), ("强", "弓+虽"), ("蛋", "疋+虫"),
    ("蛇", "虫+它"), ("蛙", "虫+圭"), ("虾", "虫+下"), ("蜜", "宀+必+虫"),
    ("融", "鬲+虫"), ("独", "犭+虫"), ("蚀", "饣+虫"), ("虹", "虫+工"),
    ("龙", "龙"), ("笼", "⺮+龙"), ("聋", "龙+耳"), ("宠", "宀+龙"),
    ("庞", "广+龙"), ("袭", "龙+衣"), ("龚", "龙+共"), ("龟", "⺈+电"),
    ("鬼", "鬼"), ("魂", "云+鬼"), ("魅", "鬼+未"), ("魔", "麻+鬼"),
    ("魏", "委+鬼"), ("愧", "忄+鬼"), ("块", "土+夬"), ("快", "忄+夬"),
    ("决", "氵+夬"), ("缺", "缶+夬"), ("诀", "讠+夬"), ("联", "耳+关"),
    ("共", "廿+八"), ("供", "亻+共"), ("洪", "氵+共"), ("哄", "口+共"),
    ("烘", "火+共"), ("恭", "共+小"), ("选", "先+辶"), ("异", "巳+廾"),
    ("巷", "共+巳"), ("港", "氵+巷"), ("黄", "廿+由+八"), ("横", "木+黄"),
    ("广", "丶+厂"), ("昔", "艹+日"), ("散", "艹+月+攵"), ("蓝", "艹+监"),
    ("篮", "⺮+监"), ("监", "丨+丨+皿"), ("盐", "土+卜+皿"), ("滥", "氵+监"),
    ("览", "监+见"), ("鉴", "监+金"), ("世", "廿+∟"), ("叶", "口+十"),
    ("某", "甘+木"), ("煤", "火+某"), ("谋", "讠+某"), ("媒", "女+某"),
    ("甜", "舌+甘"), ("甚", "甘+匹"), ("堪", "土+甚"), ("基", "其+土"),
    ("其", "甘+八"), ("期", "其+月"), ("旗", "方+人+其"), ("棋", "木+其"),
    ("欺", "其+欠"), ("斯", "其+斤"), ("撕", "扌+斯"), ("嘶", "口+斯"),
    ("革", "廿+口+十"), ("鞋", "革+圭"), ("勒", "革+力"), ("霸", "雨+革+月"),
    ("勤", "堇+力"), ("谨", "讠+堇"), ("仅", "亻+又"), ("难", "又+隹"),
    ("谁", "讠+隹"), ("推", "扌+隹"), ("堆", "土+隹"), ("唯", "口+隹"),
    ("准", "冫+隹"), ("维", "纟+隹"), ("雄", "厷+隹"), ("集", "隹+木"),
    ("售", "隹+口"), ("焦", "隹+灬"), ("霍", "雨+隹"), ("耀", "光+翟"),
    ("进", "井+辶"), ("讲", "讠+井"), ("耕", "耒+井"), ("井", "二+丿+丨"),
    ("开", "一+廾"), ("弄", "王+廾"), ("弃", "亠+厶+廾"), ("异", "巳+廾"),
    ("算", "⺮+目+廾"), ("鼻", "自+田+廾"), ("升", "丿+廾"), ("飞", "飞"),
    ("世", "廿+∟"), ("泄", "氵+世"), ("替", "夫+夫+日"), ("潜", "氵+替"),
    ("夫", "二+人"), ("规", "夫+见"), ("扶", "扌+夫"), ("肤", "月+夫"),
    ("失", "丿+夫"), ("铁", "钅+失"), ("跌", "⻊+失"), ("秩", "禾+失"),
    ("迭", "失+辶"), ("朱", "丿+未"), ("珠", "王+朱"), ("株", "木+朱"),
    ("殊", "歹+朱"), ("诛", "讠+朱"), ("未", "一+木"), ("味", "口+未"),
    ("妹", "女+未"), ("魅", "鬼+未"), ("末", "一+木"), ("抹", "扌+末"),
    ("沫", "氵+末"), ("本", "木+一"), ("笨", "⺮+本"), ("体", "亻+本"),
    ("果", "田+木"), ("东", "一+小+乙"), ("乐", "丿+∟+小"), ("药", "艹+约"),
    ("约", "纟+勺"), ("的", "白+勺"), ("钓", "钅+勺"), ("均", "土+匀"),
    ("匀", "勹+二"), ("韵", "音+匀"), ("昀", "日+匀"), ("旬", "勹+日"),
    ("询", "讠+旬"), ("荀", "艹+旬"), ("狗", "犭+句"), ("够", "句+多"),
    ("局", "尸+口"), ("句", "勹+口"), ("拘", "扌+句"), ("驹", "马+句"),
    ("足", "口+止"), ("捉", "扌+足"), ("促", "亻+足"), ("路", "⻊+各"),
    ("正", "一+止"), ("企", "人+止"), ("步", "止+少"), ("涉", "氵+步"),
    ("岁", "山+夕"), ("肯", "止+月"), ("此", "止+匕"), ("些", "此+二"),
    ("紫", "此+糸"), ("嘴", "口+此+角"), ("柴", "此+木"), ("雌", "此+隹"),
    ("武", "一+止+戈"), ("赋", "贝+武"), ("比", "匕+匕"), ("化", "亻+匕"),
    ("死", "歹+匕"), ("列", "歹+刂"), ("例", "亻+列"), ("烈", "列+灬"),
    ("裂", "列+衣"), ("殊", "歹+朱"), ("残", "歹+戋"), ("死", "歹+匕"),
    ("多", "夕+夕"), ("名", "夕+口"), ("外", "夕+卜"), ("梦", "林+夕"),
    ("罗", "罒+夕"), ("移", "禾+多"), ("夜", "亠+亻+夕+丶"), ("液", "氵+夜"),
    ("处", "夂+卜"), ("冬", "夂+冫"), ("终", "纟+冬"), ("疼", "疒+冬"),
    ("图", "囗+冬"), ("条", "夂+木"), ("务", "夂+力"), ("雾", "雨+务"),
    ("夏", "一+自+夂"), ("傻", "亻+夏"), ("复", "丿+一+日+夂"), ("腹", "月+复"),
    ("履", "尸+彳+复"), ("备", "夂+田"), ("条", "夂+木"), ("麦", "丰+夂"),
    ("面", "一+丿+囗+目"), ("缅", "纟+面"), ("革", "廿+口+十"), ("音", "立+日"),
    ("暗", "日+音"), ("意", "音+心"), ("韵", "音+匀"), ("竟", "立+日+儿"),
    ("境", "土+竟"), ("镜", "钅+竟"), ("竟", "立+日+儿"), ("竞", "立+兄"),
    ("立", "亠+丷+一"), ("位", "亻+立"), ("拉", "扌+立"), ("泣", "氵+立"),
    ("粒", "米+立"), ("站", "立+占"), ("童", "立+里"), ("产", "立+丿"),
    ("辛", "立+十"), ("亲", "立+木"), ("帝", "立+冖+巾"), ("商", "立+口+八"),
    ("旁", "立+冖+方"), ("意", "音+心"), ("章", "立+早"), ("倍", "亻+咅"),
    ("部", "咅+阝"), ("陪", "阝+咅"), ("培", "土+咅"), ("赔", "贝+咅"),
    ("音", "立+日"), ("识", "讠+只"), ("织", "纟+只"), ("积", "禾+只"),
    ("区", "匚+乂"), ("巨", "匚+工"), ("拒", "扌+巨"), ("距", "⻊+巨"),
    ("柜", "木+巨"), ("矩", "矢+巨"), ("知", "矢+口"), ("智", "知+日"),
    ("短", "矢+豆"), ("矫", "矢+乔"), ("医", "匚+矢"), ("矣", "厶+矢"),
    ("埃", "土+矣"), ("族", "方+人+矢"), ("侯", "亻+工+矢"), ("候", "亻+丨+矢"),
    ("豆", "一+口+丷+一"), ("短", "矢+豆"), ("逗", "豆+辶"), ("头", "丶+丶+大"),
    ("登", "癶+豆"), ("灯", "火+丁"), ("橙", "木+登"), ("凳", "登+几"),
    ("发", "乙+丿+又"), ("废", "广+发"), ("拨", "扌+发"), ("泼", "氵+发"),
    ("般", "舟+殳"), ("搬", "扌+般"), ("盘", "般+皿"), ("段", "段"),
    ("锻", "钅+段"), ("设", "讠+殳"), ("没", "氵+殳"), ("投", "扌+殳"),
    ("役", "彳+殳"), ("股", "月+殳"), ("杀", "乂+木"), ("殿", "尸+共+殳"),
    ("毁", "臼+工+殳"), ("毅", "立+豕+殳"), ("壳", "士+冖+几"), ("击", "二+山"),
    ("陆", "阝+击"), ("山", "山"), ("出", "山+山"), ("础", "石+出"),
    ("屈", "尸+出"), ("掘", "扌+屈"), ("岁", "山+夕"), ("仙", "亻+山"),
    ("灿", "火+山"), ("岩", "山+石"), ("岸", "山+厂+干"), ("炭", "山+灰"),
    ("峰", "山+夆"), ("逢", "夆+辶"), ("缝", "纟+逢"), ("锋", "钅+夆"),
    ("蜂", "虫+夆"), ("降", "阝+夆"), ("条", "夂+木"), ("茶", "艹+人+木"),
    ("余", "人+示"), ("涂", "氵+余"), ("除", "阝+余"), ("途", "余+辶"),
    ("徐", "彳+余"), ("叙", "余+又"), ("斜", "余+斗"), ("全", "人+王"),
    ("金", "人+王+丷"), ("企", "人+止"), ("合", "人+一+口"), ("会", "人+云"),
    ("介", "人+丿+丨"), ("界", "田+介"), ("价", "亻+介"), ("阶", "阝+介"),
    ("仑", "人+匕"), ("论", "讠+仑"), ("伦", "亻+仑"), ("轮", "车+仑"),
    ("仓", "人+㔾"), ("创", "仓+刂"), ("抢", "扌+仓"), ("枪", "木+仓"),
    ("苍", "艹+仓"), ("舱", "舟+仓"), ("令", "人+一+丶"), ("今", "人+一+乛"),
    ("命", "人+一+口+卩"), ("伞", "人+十+十"), ("众", "人+人+人"), ("从", "人+人"),
    ("食", "人+良"), ("饮", "饣+欠"), ("良", "丶+艮"), ("浪", "氵+良"),
    ("舍", "人+舌"), ("舒", "舍+予"), ("野", "里+予"), ("预", "予+页"),
    ("序", "广+予"), ("矛", "矛"), ("柔", "矛+木"), ("茅", "艹+矛"),
    ("务", "夂+力"), ("初", "衤+刀"), ("切", "七+刀"), ("分", "八+刀"),
    ("召", "刀+口"), ("招", "扌+召"), ("照", "昭+灬"), ("昭", "日+召"),
    ("沼", "氵+召"), ("绍", "纟+召"), ("超", "走+召"), ("赶", "走+干"),
    ("起", "走+己"), ("越", "走+戉"), ("趣", "走+取"), ("赵", "走+乂"),
    ("赴", "走+卜"), ("趁", "走+人+彡"), ("己", "己"), ("记", "讠+己"),
    ("纪", "纟+己"), ("起", "走+己"), ("改", "己+攵"), ("忌", "己+心"),
    ("配", "酉+己"), ("已", "已"), ("包", "勹+巳"), ("导", "巳+寸"),
    ("异", "巳+廾"), ("巷", "共+巳"), ("选", "先+辶"), ("巴", "巴"),
    ("色", "⺈+巴"), ("绝", "纟+色"), ("免", "免"), ("晚", "日+免"),
    ("勉", "免+力"), ("逸", "兔+辶"), ("象", "象"), ("像", "亻+象"),
    ("橡", "木+象"), ("家", "宀+豕"), ("逐", "豕+辶"), ("豪", "亠+口+冖+豕"),
    ("猪", "犭+者"), ("队", "阝+人"), ("认", "讠+人"), ("入", "入"),
    ("内", "冂+人"), ("闪", "门+人"), ("囚", "囗+人"), ("肉", "冂+人+人"),
    ("坐", "人+人+土"), ("座", "广+坐"), ("巫", "工+人+人"), ("夹", "一+人+大"),
    ("侠", "亻+夹"), ("峡", "山+夹"), ("狭", "犭+夹"), ("陕", "阝+夹"),
    ("来", "米+一"), ("夫", "二+人"), ("天", "一+大"), ("太", "大+丶"),
    ("犬", "大+丶"), ("伏", "亻+犬"), ("突", "穴+犬"), ("哭", "口+口+犬"),
    ("器", "口+口+犬+口+口"), ("臭", "自+犬"), ("然", "月+犬+灬"), ("献", "南+犬"),
    ("尤", "大+乚"), ("优", "亻+尤"), ("忧", "忄+尤"), ("犹", "犭+尤"),
    ("就", "京+尤"), ("龙", "龙"), ("尤", "尤"), ("抛", "扌+尤+力"),
    ("抛", "扌+九+力"), ("九", "九"), ("轨", "车+九"), ("究", "穴+九"),
    ("仇", "亻+九"), ("丸", "九+丶"), ("执", "扌+丸"), ("热", "执+灬"),
    ("势", "执+力"), ("熟", "孰+灬"), ("几", "几"), ("机", "木+几"),
    ("肌", "月+几"), ("饥", "饣+几"), ("亮", "亠+口+冖+几"), ("沉", "氵+冗"),
    ("抗", "扌+亢"), ("航", "舟+亢"), ("坑", "土+亢"), ("炕", "火+亢"),
    ("元", "二+儿"), ("兄", "口+儿"), ("充", "亠+厶+儿"), ("统", "纟+充"),
    ("流", "氵+㐬"), ("育", "云+月"), ("弃", "亠+厶+廾"), ("云", "二+厶"),
    ("亡", "亠+∟"), ("忘", "亡+心"), ("忙", "忄+亡"), ("盲", "亡+目"),
    ("荒", "艹+亡+川"), ("慌", "忄+荒"), ("谎", "讠+荒"), ("网", "冂+乂+乂"),
    ("望", "亡+月+王"), ("妄", "亡+女"), ("丧", "十+丷+衣"), ("良", "丶+艮"),
    ("退", "艮+辶"), ("很", "彳+艮"), ("狠", "犭+艮"), ("恨", "忄+艮"),
    ("根", "木+艮"), ("跟", "⻊+艮"), ("眼", "目+艮"), ("银", "钅+艮"),
    ("限", "阝+艮"), ("食", "人+良"), ("浪", "氵+良"), ("娘", "女+良"),
    ("狼", "犭+良"), ("粮", "米+良"), ("郎", "良+阝"), ("朗", "良+月"),
    ("既", "艮+旡"), ("概", "木+既"), ("即", "艮+卩"), ("节", "艹+卩"),
    ("印", "卯+卩"), ("迎", "卬+辶"), ("抑", "扌+卬"), ("仰", "亻+卬"),
    ("却", "去+卩"), ("服", "月+卩+又"), ("报", "扌+卩+又"), ("服", "月+报"),
    ("报", "扌+报"), ("危", "⺈+厂+㔾"), ("脆", "月+危"), ("卷", "龹+㔾"),
    ("圈", "囗+卷"), ("券", "龹+刀"), ("拳", "龹+手"), ("胜", "月+生"),
    ("服", "月+卩+又"), ("肥", "月+巴"), ("胆", "月+旦"), ("坦", "土+旦"),
    ("担", "扌+旦"), ("但", "亻+旦"), ("诞", "讠+延"), ("延", "延"),
    ("挺", "扌+廷"), ("庭", "广+廷"), ("艇", "舟+廷"), ("建", "廴+聿"),
    ("健", "亻+建"), ("键", "钅+建"), ("律", "彳+聿"), ("津", "氵+聿"),
    ("笔", "⺮+毛"), ("尾", "尸+毛"), ("托", "扌+乇"), ("宅", "宀+乇"),
    ("七", "七"), ("切", "七+刀"), ("彻", "彳+切"), ("窃", "穴+切"),
    ("化", "亻+匕"), ("北", "丨+一+匕"), ("比", "匕+匕"), ("死", "歹+匕"),
    ("尼", "尸+匕"), ("老", "耂+匕"), ("它", "宀+匕"), ("旨", "匕+日"),
    ("指", "扌+旨"), ("脂", "月+旨"), ("能", "厶+月+匕+匕"), ("毕", "比+十"),
    ("皆", "比+白"), ("谐", "讠+皆"), ("阶", "阝+介"), ("介", "人+丿+丨"),
    ("价", "亻+介"), ("界", "田+介"), ("养", "羊+介"), ("芥", "艹+介"),
    ("齐", "文+丿+丨"), ("剂", "齐+刂"), ("济", "氵+齐"), ("挤", "扌+齐"),
    ("亦", "亠+八+丿+丨"), ("变", "亦+又"), ("恋", "亦+心"), ("弯", "亦+弓"),
    ("湾", "氵+弯"), ("蛮", "亦+虫"), ("赤", "土+小"), ("赫", "赤+赤"),
    ("赦", "赤+攵"), ("走", "土+龰"), ("徒", "彳+走"), ("超", "走+召"),
    ("赶", "走+干"), ("起", "走+己"), ("越", "走+戉"), ("趣", "走+取"),
    ("赵", "走+乂"), ("赴", "走+卜"), ("趁", "走+人+彡"), ("定", "宀+正"),
    ("是", "日+正"), ("足", "口+止"), ("定", "宀+正"), ("促", "亻+足"),
    ("捉", "扌+足"), ("疏", "疋+㐬"), ("疑", "匕+矢+矛+疋"), ("蛋", "疋+虫"),
    ("楚", "林+疋"), ("之", "丶+乙"), ("乏", "丿+之"), ("泛", "氵+乏"),
    ("贬", "贝+乏"), ("眨", "目+乏"), ("芝", "艹+之"), ("艺", "艹+乙"),
    ("亿", "亻+乙"), ("忆", "忄+乙"), ("礼", "礻+乙"), ("扎", "扌+乚"),
    ("乱", "舌+乚"), ("孔", "子+乚"), ("乳", "孚+乚"), ("浮", "氵+孚"),
    ("采", "爫+木"), ("受", "爫+冖+又"), ("爱", "爫+冖+友"), ("妥", "爫+女"),
    ("溪", "氵+奚"), ("摇", "扌+䍃"), ("谣", "讠+䍃"), ("遥", "䍃+辶"),
    ("争", "⺈+彐+亅"), ("静", "青+争"), ("净", "冫+争"), ("睁", "目+争"),
    ("急", "⺈+彐+心"), ("稳", "禾+急"), ("隐", "阝+急"), ("雪", "雨+彐"),
    ("扫", "扌+彐"), ("妇", "女+彐"), ("归", "丨+丿+彐"), ("当", "小+彐"),
    ("寻", "彐+寸"), ("灵", "彐+火"), ("录", "彐+水"), ("寻", "彐+寸"),
    ("导", "巳+寸"), ("守", "宀+寸"), ("对", "又+寸"), ("付", "亻+寸"),
    ("村", "木+寸"), ("过", "寸+辶"), ("时", "日+寸"), ("讨", "讠+寸"),
    ("封", "圭+寸"), ("射", "身+寸"), ("谢", "讠+射"), ("尊", "酋+寸"),
    ("遵", "尊+辶"), ("夺", "大+寸"), ("耐", "而+寸"), ("寿", "丰+寸"),
    ("涛", "氵+寿"), ("铸", "钅+寿"), ("筹", "⺮+寿"), ("等", "⺮+寺"),
    ("寺", "土+寸"), ("诗", "讠+寺"), ("持", "扌+寺"), ("特", "牛+寺"),
    ("待", "彳+寺"), ("侍", "亻+寺"), ("府", "广+付"), ("附", "阝+付"),
    ("符", "⺮+付"), ("腐", "府+肉"), ("博", "十+尃"), ("薄", "艹+溥"),
    ("专", "二+乙+丶"), ("转", "车+专"), ("传", "亻+专"), ("砖", "石+专"),
    ("团", "囗+才"), ("闭", "门+才"), ("财", "贝+才"), ("材", "木+才"),
    ("才", "才"), ("木", "木"), ("林", "木+木"), ("森", "木+木+木"),
    ("寸", "寸"), ("丁", "丁"), ("打", "扌+丁"), ("盯", "目+丁"),
    ("钉", "钅+丁"), ("订", "讠+丁"), ("叮", "口+丁"), ("灯", "火+丁"),
    ("顶", "丁+页"), ("宁", "宀+丁"), ("厅", "厂+丁"), ("可", "丁+口"),
    ("于", "二+亅"), ("宇", "宀+于"), ("芋", "艹+于"), ("孟", "子+皿"),
    ("盂", "于+皿"), ("干", "干"), ("平", "干+丷"), ("千", "千"),
    ("万", "万"), ("迈", "万+辶"), ("方", "方"), ("芳", "艹+方"),
    ("艺", "艹+乙"), ("下", "下"), ("吓", "口+下"), ("虾", "虫+下"),
    ("上", "上"), ("让", "讠+上"), ("止", "止"), ("正", "一+止"),
    ("址", "土+止"), ("此", "止+匕"), ("步", "止+少"), ("卡", "上+下"),
    ("忐", "上+心"), ("忑", "下+心"), ("尖", "小+大"), ("尘", "小+土"),
    ("少", "小+丿"), ("抄", "扌+少"), ("炒", "火+少"), ("沙", "氵+少"),
    ("秒", "禾+少"), ("妙", "女+少"), ("省", "少+目"), ("吵", "口+少"),
    ("纱", "纟+少"), ("劣", "少+力"), ("雀", "小+隹"), ("尚", "⺌+口"),
    ("堂", "尚+土"), ("常", "尚+巾"), ("掌", "尚+手"), ("赏", "尚+贝"),
    ("尝", "⺌+云"), ("党", "⺌+兄"), ("躺", "身+尚"), ("趟", "走+尚"),
    ("光", "⺌+兀"), ("肖", "⺌+月"), ("消", "氵+肖"), ("销", "钅+肖"),
    ("悄", "忄+肖"), ("梢", "木+肖"), ("稍", "禾+肖"), ("哨", "口+肖"),
    ("赵", "走+乂"), ("赵", "走+乂"), ("削", "肖+刂"), ("赵", "走+乂"),
    ("半", "丷+十"), ("判", "半+刂"), ("叛", "半+反"), ("平", "干+丷"),
    ("并", "丷+开"), ("兰", "丷+三"), ("拦", "扌+兰"), ("烂", "火+兰"),
    ("栏", "木+兰"), ("羊", "羊"), ("美", "羊+大"), ("洋", "氵+羊"),
    ("详", "讠+羊"), ("样", "木+羊"), ("祥", "礻+羊"), ("鲜", "鱼+羊"),
    ("群", "君+羊"), ("翔", "羊+羽"), ("氧", "气+羊"), ("差", "羊+工"),
    ("着", "羊+目"), ("羞", "羊+丑"), ("姜", "羊+女"), ("盖", "羊+皿"),
    ("兼", "丷+一+彐+八"), ("歉", "兼+欠"), ("谦", "讠+兼"), ("赚", "贝+兼"),
    ("嫌", "女+兼"), ("廉", "广+兼"), ("前", "丷+月+刂"), ("煎", "前+灬"),
    ("剪", "前+刀"), ("箭", "⺮+前"), ("首", "丷+一+自"), ("道", "首+辶"),
    ("道", "首+辶"), ("曾", "丷+田+日"), ("增", "土+曾"), ("赠", "贝+曾"),
    ("僧", "亻+曾"), ("层", "尸+云"), ("普", "并+日"), ("谱", "讠+普"),
    ("业", "业"), ("显", "日+业"), ("亚", "亚"), ("恶", "亚+心"),
    ("壶", "士+冖+业"), ("严", "一+亚"), ("产", "立+丿"), ("并", "丷+开"),
    ("并", "丷+开"), ("兹", "艹+丝"), ("滋", "氵+兹"), ("磁", "石+兹"),
    ("慈", "兹+心"), ("幺", "幺"), ("幻", "幺+乛"), ("幼", "幺+力"),
    ("乡", "幺+丿"), ("幽", "山+幺+幺"), ("丝", "纟+纟"), ("系", "丿+糸"),
    ("紧", "臤+糸"), ("累", "田+糸"), ("紫", "此+糸"), ("素", "丰+糸"),
    ("索", "十+冖+糸"), ("繁", "敏+糸"), ("县", "且+乙"), ("悬", "县+心"),
    ("玄", "亠+幺"), ("炫", "火+玄"), ("弦", "弓+玄"), ("牵", "大+冖+牛"),
    ("畜", "玄+田"), ("蓄", "艹+畜"), ("率", "玄+十"), ("摔", "扌+率"),
    ("卒", "亠+从+十"), ("碎", "石+卒"), ("醉", "酉+卒"), ("翠", "羽+卒"),
    ("杂", "九+木"), ("亲", "立+木"), ("杀", "乂+木"), ("茶", "艹+人+木"),
    ("深", "氵+冖+木"), ("探", "扌+冖+木"), ("架", "加+木"), ("柔", "矛+木"),
    ("呆", "口+木"), ("杏", "木+口"), ("李", "木+子"), ("束", "木+口"),
    ("整", "束+攵+正"), ("速", "束+辶"), ("辣", "辛+束"), ("赖", "束+负"),
    ("懒", "忄+赖"), ("策", "⺮+朿"), ("刺", "朿+刂"), ("枣", "朿+朿"),
    ("东", "一+小+乙"), ("陈", "阝+东"), ("练", "纟+东"), ("炼", "火+东"),
    ("冻", "冫+东"), ("栋", "木+东"), ("乐", "乐"), ("药", "艹+约"),
    ("栎", "木+乐"), ("烁", "火+乐"), ("铄", "钅+乐"), ("车", "车"),
    ("库", "广+车"), ("连", "车+辶"), ("军", "冖+车"), ("转", "车+专"),
    ("轮", "车+仑"), ("轻", "车+圣"), ("软", "车+欠"), ("较", "车+交"),
    ("辅", "车+甫"), ("辆", "车+两"), ("输", "车+俞"), ("斩", "车+斤"),
    ("暂", "斩+日"), ("渐", "氵+斩"), ("惭", "忄+斩"), ("辈", "非+车"),
    ("轰", "车+车+车"), ("轟", "車+車+車"),
    # Additional 300 common compound characters to ensure 1,500+ total unique characters
    ("安", "宀+女"), ("案", "安+木"), ("按", "扌+安"), ("暗", "日+音"),
    ("昂", "日+卯"), ("熬", "敖+灬"), ("傲", "亻+敖"), ("澳", "氵+奥"),
    ("八", "八"), ("巴", "巴"), ("拔", "扌+犮"), ("罢", "罒+去"),
    ("白", "白"), ("百", "一+白"), ("败", "贝+攵"), ("拜", "手+手"),
    ("班", "王+刂+王"), ("般", "舟+殳"), ("搬", "扌+般"), ("版", "片+反"),
    ("办", "力+八"), ("半", "丷+十"), ("伴", "亻+半"), ("扮", "扌+分"),
    ("邦", "丰+阝"), ("帮", "邦+巾"), ("榜", "木+旁"), ("傍", "亻+旁"),
    ("棒", "木+奉"), ("包", "勹+巳"), ("胞", "月+包"), ("饱", "饣+包"),
    ("宝", "宀+玉"), ("保", "亻+呆"), ("堡", "保+土"), ("报", "扌+卩+又"),
    ("抱", "扌+包"), ("暴", "日+共+水"), ("爆", "火+暴"), ("悲", "非+心"),
    ("碑", "石+卑"), ("杯", "木+不"), ("北", "丨+一+匕"), ("背", "北+月"),
    ("倍", "亻+咅"), ("备", "夂+田"), ("辈", "非+车"), ("被", "衤+皮"),
    ("本", "木+一"), ("笨", "⺮+本"), ("奔", "大+卉"), ("崩", "山+朋"),
    ("逼", "畐+辶"), ("鼻", "自+田+廾"), ("比", "匕+匕"), ("彼", "彳+皮"),
    ("笔", "⺮+毛"), ("币", "丿+巾"), ("毕", "比+十"), ("闭", "门+才"),
    ("避", "辟+辶"), ("壁", "辟+土"), ("碧", "王+白+石"), ("边", "力+辶"),
    ("编", "纟+扁"), ("遍", "扁+辶"), ("变", "亦+又"), ("便", "亻+更"),
    ("辩", "辛+讠+辛"), ("辨", "辛+刂+辛"), ("标", "木+示"), ("表", "丰+衣"),
    ("别", "另+刂"), ("宾", "宀+兵"), ("滨", "氵+宾"), ("冰", "冫+水"),
    ("兵", "丘+八"), ("丙", "一+内"), ("柄", "木+丙"), ("饼", "饣+并"),
    ("并", "丷+开"), ("病", "疒+丙"), ("拨", "扌+发"), ("波", "氵+皮"),
    ("玻", "王+皮"), ("播", "扌+番"), ("伯", "亻+白"), ("驳", "马+爻"),
    ("泊", "氵+白"), ("柏", "木+白"), ("博", "十+尃"), ("薄", "艹+溥"),
    ("补", "衤+卜"), ("捕", "扌+甫"), ("不", "一+丿+丨+丶"), ("布", "十+巾"),
    ("步", "止+少"), ("部", "咅+阝"), ("擦", "扌+察"), ("猜", "犭+青"),
    ("才", "才"), ("材", "木+才"), ("财", "贝+才"), ("裁", "十+戈+衣"),
    ("采", "爫+木"), ("彩", "采+彡"), ("踩", "⻊+采"), ("菜", "艹+采"),
    ("参", "厶+大+彡"), ("餐", "占+又+食"), ("残", "歹+戋"), ("惨", "忄+参"),
    ("仓", "人+㔾"), ("苍", "艹+仓"), ("舱", "舟+仓"), ("藏", "艹+臣+戈"),
    ("操", "扌+喿"), ("槽", "木+曹"), ("草", "艹+早"), ("测", "氵+则"),
    ("策", "⺮+朿"), ("侧", "亻+则"), ("层", "尸+云"), ("曾", "丷+田+日"),
    ("叉", "又+丶"), ("查", "木+旦"), ("茶", "艹+人+木"), ("察", "宀+祭"),
    ("差", "羊+工"), ("拆", "扌+斥"), ("柴", "此+木"), ("产", "立+丿"),
    ("铲", "钅+产"), ("阐", "门+单"), ("昌", "日+日"), ("长", "长"),
    ("肠", "月+扬"), ("尝", "⺌+云"), ("偿", "亻+赏"), ("常", "尚+巾"),
    ("厂", "厂"), ("场", "土+扬"), ("畅", "申+易"), ("唱", "口+昌"),
    ("抄", "扌+少"), ("超", "走+召"), ("朝", "十+日+十+月"), ("潮", "氵+朝"),
    ("炒", "火+少"), ("吵", "口+少"), ("车", "车"), ("扯", "扌+止"),
    ("彻", "彳+切"), ("沉", "氵+冗"), ("陈", "阝+东"), ("晨", "日+辰"),
    ("尘", "小+土"), ("称", "禾+尔"), ("撑", "扌+掌"), ("成", "成"),
    ("城", "土+成"), ("诚", "讠+成"), ("承", "了+三+手"), ("程", "禾+呈"),
    ("乘", "禾+北"), ("惩", "征+心"), ("吃", "口+乞"), ("池", "氵+也"),
    ("迟", "尺+辶"), ("持", "扌+寺"), ("尺", "尸+丶"), ("齿", "止+凵+人"),
    ("冲", "冫+中"), ("充", "亠+厶+儿"), ("虫", "虫"), ("崇", "山+宗"),
    ("抽", "扌+由"), ("仇", "亻+九"), ("愁", "秋+心"), ("稠", "禾+周"),
    ("筹", "⺮+寿"), ("臭", "自+犬"), ("出", "山+山"), ("初", "衤+刀"),
    ("除", "阝+余"), ("厨", "厂+豆+寸"), ("础", "石+出"), ("储", "亻+诸"),
    ("楚", "林+疋"), ("处", "夂+卜"), ("触", "角+虫"), ("穿", "穴+牙"),
    ("传", "亻+专"), ("船", "舟+几+口"), ("窗", "穴+囱"), ("床", "广+木"),
    ("闯", "门+马"), ("创", "仓+刂"), ("吹", "口+欠"), ("垂", "垂"),
    ("春", "三+人+日"), ("纯", "纟+屯"), ("唇", "辰+口"), ("词", "讠+司"),
    ("慈", "兹+心"), ("磁", "石+兹"), ("辞", "舌+辛"), ("此", "止+匕"),
    ("次", "冫+欠"), ("刺", "朿+刂"), ("从", "人+人"), ("聪", "耳+总"),
    ("葱", "艹+匆"), ("粗", "米+且"), ("促", "亻+足"), ("催", "亻+崔"),
    ("脆", "月+危"), ("翠", "羽+卒"), ("村", "木+寸"), ("存", "十+子"),
    ("寸", "寸"), ("错", "钅+昔"), ("措", "扌+昔"), ("搭", "扌+荅"),
    ("达", "大+辶"), ("答", "⺮+合"), ("打", "扌+丁"), ("大", "大"),
    ("呆", "口+木"), ("代", "亻+弋"), ("带", "廿+冖+巾"), ("待", "彳+寺"),
    ("袋", "代+衣"), ("贷", "代+贝"), ("单", "丷+甲"), ("担", "扌+旦"),
    ("胆", "月+旦"), ("但", "亻+旦"), ("诞", "讠+延"), ("淡", "氵+炎"),
    ("蛋", "疋+虫"), ("当", "小+彐"), ("党", "⺌+兄"), ("挡", "扌+当"),
    ("档", "木+当"), ("刀", "刀"), ("导", "巳+寸"), ("岛", "鸟+山"),
    ("倒", "亻+到"), ("到", "至+刂"), ("道", "首+辶"), ("得", "彳+日+寸"),
    ("德", "彳+十+罒+心"), ("的", "白+勺"), ("灯", "火+丁"), ("登", "癶+豆"),
    ("等", "⺮+寺"), ("低", "亻+氐"), ("堤", "土+是"), ("滴", "氵+商"),
    ("敌", "舌+攵"), ("底", "广+氐"), ("抵", "扌+氐"), ("地", "土+也"),
    ("第", "⺮+弟"), ("帝", "立+冖+巾"), ("递", "弟+辶"), ("典", "曲+八"),
    ("点", "占+灬"), ("电", "日+乚"), ("店", "广+占"), ("垫", "执+土"),
    ("殿", "尸+共+殳"), ("雕", "周+隹"), ("吊", "口+巾"), ("钓", "钅+勺"),
    ("调", "讠+周"), ("掉", "扌+卓"), ("跌", "⻊+失"), ("蝶", "虫+枼"),
    ("叠", "又+又+又+冖+且"), ("丁", "丁"), ("叮", "口+丁"), ("盯", "目+丁"),
    ("钉", "钅+丁"), ("顶", "丁+页"), ("订", "讠+丁"), ("定", "宀+正"),
    ("丢", "丿+去"), ("东", "东"), ("冬", "夂+冫"), ("懂", "忄+董"),
    ("动", "云+力"), ("冻", "冫+东"), ("洞", "氵+同"), ("栋", "木+东"),
    ("都", "者+阝"), ("抖", "扌+斗"), ("斗", "斗"), ("豆", "豆"),
    ("逗", "豆+辶"), ("毒", "主+母"), ("独", "犭+虫"), ("读", "讠+卖"),
    ("堵", "土+者"), ("赌", "贝+者"), ("肚", "月+土"), ("度", "广+廿+又"),
    ("渡", "氵+度"), ("端", "立+山+而"), ("短", "矢+豆"), ("段", "段"),
    ("断", "米+乙+斤"), ("锻", "钅+段"), ("堆", "土+隹"), ("队", "阝+人"),
    ("对", "又+寸"), ("兑", "丷+兄"), ("吨", "口+屯"), ("顿", "屯+页"),
    ("盾", "厂+十+目"), ("多", "夕+夕"), ("夺", "大+寸"), ("朵", "几+木"),
    ("躲", "身+朵"), ("堕", "队+土"), ("鹅", "我+鸟"), ("额", "客+页"),
    ("恶", "亚+心"), ("饿", "饣+我"), ("恩", "因+心"), ("儿", "儿"),
    ("而", "而"), ("耳", "耳"), ("二", "二"), ("发", "发"),
    ("罚", "罒+讠+刂"), ("伐", "亻+戈"), ("法", "氵+去"), ("帆", "巾+凡"),
    ("番", "采+田"), ("翻", "番+羽"), ("凡", "几+丶"), ("烦", "火+页"),
    ("繁", "敏+糸"), ("反", "反"), ("返", "反+辶"), ("犯", "犭+卩"),
    ("泛", "氵+乏"), ("饭", "饣+反"), ("范", "艹+氵+卩"), ("贩", "贝+反"),
    ("方", "方"), ("坊", "土+方"), ("芳", "艹+方"), ("防", "阝+方"),
    ("妨", "女+方"), ("房", "户+方"), ("仿", "亻+方"), ("访", "讠+方"),
    ("放", "方+攵"), ("飞", "飞"), ("非", "非"), ("啡", "口+非"),
    ("菲", "艹+非"), ("肥", "月+巴"), ("肺", "月+市"), ("废", "广+发"),
    ("费", "弗+贝"), ("沸", "氵+弗"), ("分", "八+刀"), ("纷", "纟+分"),
    ("坟", "土+文"), ("粉", "米+分"), ("份", "亻+分"), ("奋", "大+田"),
    ("愤", "忄+贲"), ("丰", "丰"), ("风", "几+乂"), ("封", "圭+寸"),
    ("疯", "疒+风"), ("峰", "山+夆"), ("锋", "钅+夆"), ("蜂", "虫+夆"),
    ("冯", "冫+马"), ("逢", "夆+辶"), ("缝", "纟+逢"), ("凤", "几+又"),
    ("佛", "亻+弗"), ("否", "不+口"), ("夫", "二+人"), ("肤", "月+夫"),
    ("扶", "扌+夫"), ("服", "月+卩+又"), ("浮", "氵+孚"), ("福", "礻+一+口+田"),
    ("幅", "巾+一+口+田"), ("符", "⺮+付"), ("伏", "亻+犬"), ("辅", "车+甫"),
    ("俯", "亻+府"), ("府", "广+付"), ("腐", "府+肉"), ("父", "父"),
    ("付", "亻+寸"), ("妇", "女+彐"), ("负", "⺈+贝"), ("附", "阝+付"),
    ("复", "复"), ("副", "一+口+田+刂"), ("富", "宀+一+口+田"), ("腹", "月+复"),
    ("赋", "贝+武"), ("覆", "西+复"), ("该", "讠+亥"), ("改", "己+攵"),
    ("概", "木+既"), ("盖", "羊+皿"), ("钙", "钅+丐"), ("干", "干"),
    ("甘", "甘"), ("杆", "木+干"), ("肝", "月+干"), ("赶", "走+干"),
    ("感", "咸+心"), ("敢", "耳+攵"), ("刚", "冈+刂"), ("纲", "纟+冈"),
    ("钢", "钅+冈"), ("岗", "山+冈"), ("港", "氵+巷"), ("杠", "木+工"),
    ("高", "高"), ("糕", "米+羔"), ("搞", "扌+高"), ("稿", "禾+高"),
    ("告", "牛+口"), ("哥", "可+可"), ("歌", "哥+欠"), ("割", "害+刂"),
    ("搁", "扌+阁"), ("阁", "门+各"), ("格", "木+各"), ("隔", "阝+鬲"),
    ("个", "人+丨"), ("各", "夂+口"), ("给", "纟+合"), ("根", "木+艮"),
    ("跟", "⻊+艮"), ("更", "一+曰+乂"), ("耕", "耒+井"), ("工", "工"),
    ("公", "八+厶"), ("功", "工+力"), ("攻", "工+攵"), ("供", "亻+共"),
    ("宫", "宀+吕"), ("恭", "共+小"), ("共", "廿+八"), ("贡", "工+贝"),
    ("沟", "氵+勾"), ("勾", "勹+厶"), ("钩", "钅+勾"), ("狗", "犭+句"),
    ("构", "木+勾"), ("购", "贝+勾"), ("够", "句+多"), ("孤", "子+瓜"),
    ("姑", "女+古"), ("估", "亻+古"), ("古", "十+口"), ("谷", "八+人+口"),
    ("股", "月+殳"), ("骨", "骨"), ("鼓", "壴+支"), ("固", "囗+古"),
    ("故", "古+攵"), ("顾", "厄+页"), ("瓜", "瓜"), ("刮", "舌+刂"),
    ("挂", "扌+圭"), ("乖", "千+北"), ("拐", "扌+另"), ("怪", "忄+圣"),
    ("关", "丷+天"), ("观", "又+见"), ("官", "宀+吕"), ("冠", "冖+元+寸"),
    ("馆", "饣+官"), ("管", "⺮+官"), ("贯", "毌+贝"), ("惯", "忄+贯"),
    ("灌", "氵+雚"), ("光", "⺌+兀"), ("广", "广"), ("归", "丨+丿+彐"),
    ("规", "夫+见"), ("鬼", "鬼"), ("柜", "木+巨"), ("贵", "中+一+贝"),
    ("滚", "氵+衮"), ("锅", "钅+呙"), ("国", "囗+玉"), ("果", "田+木"),
    ("裹", "衣+果"), ("过", "寸+辶"),
]

# GB standard 5-stroke sequences: h=横/提, s=竖/竖钩, p=撇, n=点/捺, z=折
CHAR_STROKES: list[tuple[str, str]] = [
    ("一", "h"), ("丨", "s"), ("丿", "p"), ("丶", "n"), ("乙", "z"),
    ("二", "hh"), ("十", "hs"), ("厂", "hp"), ("亠", "nh"), ("七", "hz"), ("丁", "hz"),
    ("上", "shh"), ("卜", "sn"), ("川", "pss"), ("少", "spnp"), ("水", "szpn"),
    ("山", "szs"), ("生", "phhsh"), ("个", "pns"), ("人", "pn"), ("入", "pn"), ("八", "pn"),
    ("几", "pz"), ("九", "pz"), ("儿", "pz"), ("文", "nhpn"), ("门", "nsz"), ("义", "npn"),
    ("冫", "nn"), ("之", "nzn"), ("心", "nznn"), ("子", "zsh"), ("了", "zs"), ("力", "zp"),
    ("刀", "zp"), ("乃", "zp"), ("又", "zn"), ("马", "zzh"), ("丝", "zzzzh"),
    ("三", "hhh"), ("干", "hhs"), ("于", "hhs"), ("工", "hsh"), ("万", "hzp"),
    ("土", "hsh"), ("士", "hsh"), ("下", "hsn"), ("区", "hpnz"), ("大", "hpn"),
    ("元", "hhpz"), ("无", "hhpz"), ("专", "hhzn"), ("云", "hhzn"), ("止", "shsh"),
    ("小", "spn"), ("口", "szh"), ("日", "szhh"), ("中", "szhs"), ("虫", "szhshhn"),
    ("贝", "szpn"), ("见", "szpz"), ("千", "phs"), ("牛", "phhs"), ("火", "nppn"),
    ("全", "pnhhsh"), ("及", "pzn"), ("风", "pzpn"), ("飞", "zpn"), ("女", "zph"),
    ("才", "hsp"), ("与", "hzh"), ("广", "nhp"), ("亡", "nhz"), ("习", "znh"), ("弓", "zhz"),
    ("木", "hspn"), ("王", "hhsh"), ("玉", "hhshn"), ("天", "hhpn"), ("夫", "hhpn"),
    ("太", "hpnn"), ("犬", "hpnn"), ("开", "hhps"), ("井", "hhps"), ("月", "pzhh"),
    ("田", "szhsh"), ("由", "szhsh"), ("甲", "szhhs"), ("申", "szhhs"), ("电", "szhhz"),
    ("目", "szhhh"), ("正", "hshsh"), ("在", "hpshsh"), ("有", "hpszhh"), ("不", "hpsn"),
    ("石", "hpszh"), ("本", "hspnh"), ("未", "hhspn"), ("末", "hhspn"), ("禾", "phspn"),
    ("米", "nphspn"), ("手", "phhs"), ("耳", "hsshhh"), ("羊", "nphhhs"), ("主", "nhhsh"),
    ("方", "nhzp"), ("为", "npzn"), ("必", "nznpn"), ("好", "zphzsh"), ("男", "szhshzp"),
    ("明", "szhhpzhh"), ("白", "pszhh"), ("的", "pszhhpzn"), ("我", "phshzpn"), ("你", "pspzspn"),
    ("他", "pszsz"), ("她", "zphzsz"), ("它", "nnzpz"), ("是", "szhhhshpn"), ("字", "nnzzsh"),
    ("学", "nnpnzzsh"), ("关", "nphhpn"), ("雨", "hszsnnnn"), ("气", "phhz"), ("国", "szhhshnh"),
    ("母", "zznhn"), ("出", "zsszs"), ("可", "hszhs"), ("长", "phzn"), ("车", "hzhs"),
    ("东", "hzspn"), ("皮", "zpszn"), ("凹", "szszh"), ("凸", "shszh"), ("忄", "nns"),
    ("丰", "hhhs"), ("青", "hhshszhh"), ("先", "phshpz"), ("鱼", "pzszhshh"), ("鸟", "pznzh"),
    ("头", "nnphn"), ("兴", "nnpnpn"), ("介", "pnpn"), ("合", "pnhszh"), ("会", "pnhhzn"),
    ("今", "pnhz"), ("令", "pnhzn"), ("六", "nhpn"), ("四", "szpzh"), ("五", "hszh"),
    ("百", "hpszhh"), ("右", "hpszhh"), ("左", "hphsh"), ("里", "szhhshh"), ("己", "zhz"),
    ("已", "zhz"), ("弓", "zhz"), ("夕", "pzn"), ("久", "pzn"), ("民", "zhzhz"),
    ("巨", "hzsz"), ("匹", "hpzh"), ("金", "pnhhshn"), ("林", "hspnhspn"), ("炎", "nppnnppn"),
    ("垚", "hshhshhsh"), ("品", "szhszhszh"), ("晶", "szhhszhhszhh"), ("朋", "pzhhpzhh"),
    ("众", "pnpnpn"), ("从", "pnpn"), ("磊", "hpszhpszhpszh"), ("森", "hspnhspnhspn"),
    ("焱", "nppnnppnnppn"), ("淼", "szpnszpnszpn"), ("鑫", "pnhhnhhnhh"), ("古", "hsszh"),
    ("尖", "spnhpn"), ("岩", "szshpszh"), ("看", "phhsszhhh"), ("泉", "pszhszpn"),
    ("柏", "hspnpszhh"), ("休", "pshspn"), ("沐", "nnhhspn"), ("打", "hshhz"),
    ("地", "hshzsz"), ("把", "hshzzhz"), ("问", "nszszh"), ("间", "nszszhh"),
    ("爱", "pnnznzhzn"), ("年", "phhshs"), ("家", "nnzhpppn"), ("安", "nnzzph"),
    ("道", "nphszhhhnzn"), ("这", "nhpnzzn"), ("那", "zzhhpz"), ("说", "nznpszhpz"),
    ("请", "nzhhshszhh"), ("话", "nzphsszh"), ("语", "nzhszhszh"), ("读", "nzhszznhn"),
    ("认", "nzpn"), ("让", "nzshh"), ("老", "hshppz"), ("考", "hshphz"),
    ("者", "hshpszhh"), ("友", "hpzn"), ("吃", "szhpz"), ("喝", "szhszhhpzpz"),
    ("叫", "szhzs"), ("听", "szhpphs"), ("味", "szhhhspn"), ("吗", "szhzzh"),
    ("呢", "szhzphzp"), ("吧", "szhzhz"), ("啊", "szhzszhsz"), ("和", "phspnszh"),
    ("秋", "phspnnppn"), ("种", "phspnszhs"), ("科", "phspnnnhs"), ("行", "ppshhs"),
    ("很", "ppszhhhpn"), ("得", "ppsszhhhhszn"), ("往", "ppsnhhsh"), ("待", "ppshshhzn"),
    ("前", "nphszhhs"), ("送", "nznphhpnnzn"), ("进", "nhhpsnzn"), ("过", "hsnzn"),
    ("还", "hpsnnzn"), ("平", "hnphhs"), ("来", "hnnphspn"), ("去", "hshzn"),
    ("看", "phhsszhhh"), ("说", "nznpszhpz"), ("想", "hspnszhhhnzn"), ("要", "hszssphzph"),
    ("能", "znzzhhzpzp"), ("会", "pnhhzn"), ("多", "pznpzn"), ("少", "spnp"),
    ("高", "nhszhszhsz"), ("低", "pspzhzhn"), ("新", "nhpnhspnpphs"), ("旧", "sszhh"),
    ("早", "szhhhs"), ("晚", "szhhpzszn"), ("黑", "szhnhshhnnnn"), ("红", "zzhzsh"),
    ("绿", "zzhzzhhspn"), ("蓝", "hsszhhsshh"), ("黄", "hssszhsphn"), ("花", "hsspspz"),
    ("草", "hssszhhhs"), ("树", "hspnznzhs"), ("叶", "szhhs"), ("果", "szhhhspn"),
    ("瓜", "ppzpn"), ("豆", "hszhnnh"), ("菜", "hsspnnhspn"), ("饭", "pzzhpszn"),
    ("茶", "hsspnnhspn"), ("酒", "nnhhszhzzhh"), ("肉", "szpnpn"), ("蛋", "zhshszhshhn"),
    ("鸡", "znpznzh"), ("鸭", "szhhspznzh"), ("鹅", "phshzpnpznzh"),
    ("猫", "pzpnszhs"), ("狗", "pzpnpzszh"), ("猪", "pzpnzshhszhh"), ("羊", "nphhhs"),
    ("虎", "shzphzsz"), ("龙", "hpzpzn"), ("蛇", "szhshhnnnpzz"),
    ("书", "zzsn"), ("画", "hszhszhsz"), ("字", "nnzzsh"), ("词", "nzzhszh"),
    ("句", "pzhzh"), ("段", "pshhzn"), ("章", "nhnpnhszhhhs"), ("页", "hpzszn"),
    ("笔", "phnphnphhz"), ("纸", "zzhpshz"), ("墨", "szhnhshhnnnnhsh"), ("桌", "shszhhhspn"),
    ("椅", "hspnhpnshszhs"), ("床", "nhphspn"), ("灯", "nppnhzs"), ("窗", "nnpnhspnzhsn"),
    ("镜", "phhhznhnpszhhpz"), ("钟", "phhhzszhs"), ("表", "hhshppzn"), ("船", "ppzznhszh"),
    ("机", "hspnpzz"), ("飞", "zpn"), ("路", "szhshshpznszh"), ("桥", "hspnphspps"),
    ("河", "nnhhszhs"), ("湖", "nnhhsszhpzhh"), ("海", "nnhpzznhhn"), ("江", "nnhhsh"),
    ("溪", "nnhpnnpzzphn"), ("泉", "pszhszpn"), ("池", "nnhzsz"), ("洋", "nnhnphhhs"),
    ("风", "pzpn"), ("雨", "hszsnnnn"), ("雪", "hszsnnnnzzh"), ("雷", "hszsnnnnszhsh"),
    ("云", "hhzn"), ("电", "szhhz"), ("霜", "hszsnnnnhspnszhhh"), ("雾", "hszsnnnnpznhzp"),
    ("春", "hhhpnzhh"), ("夏", "hpzhhhpn"), ("秋", "phspnnppn"), ("冬", "pznnn"),
    ("东", "hzspn"), ("南", "hsszhhshs"), ("西", "hszpzh"), ("北", "shhszz"),
    ("前", "nphszhhs"), ("后", "ppzhs"), ("左", "hphsh"), ("右", "hpszhh"),
    ("内", "szpn"), ("外", "pznsh"), ("中", "szhs"), ("间", "nszszhh"),
    ("头", "nnphn"), ("发", "zhpzn"), ("眼", "szhhhzhhpn"), ("耳", "hsshhh"),
    ("鼻", "pszhhszhshhpss"), ("嘴", "szhshzphzs"), ("牙", "hzsp"), ("舌", "phsszh"),
    ("手", "phhs"), ("脚", "pzhhhshzsz"), ("腿", "pzhhzhhhpzn"), ("心", "nznn"),
    ("身", "pszhhhpn"), ("体", "pshspnh"), ("血", "pszsssh"), ("骨", "szszsznzhh"),
    ("父", "pnpn"), ("母", "zznhn"), ("爸", "pnpnzzhz"), ("妈", "zphzzh"),
    ("兄", "szhpz"), ("弟", "nphzzsp"), ("姐", "zphszhhh"), ("妹", "zphhhspn"),
    ("男", "szhshzp"), ("女", "zph"), ("老", "hshppz"), ("少", "spnp"),
    ("朋", "pzhhpzhh"), ("友", "hpzn"), ("师", "sppszhzs"), ("生", "phhsh"),
    ("工", "hsh"), ("农", "nzhpzn"), ("商", "nhnpnszpn"), ("医", "hpphnpnz"),
    ("军", "nzhzhs"), ("警", "hssszhpzn"), ("兵", "pshhpn"), ("官", "nnzszhzh"),
    ("城", "hshhpzzp"), ("乡", "zzp"), ("村", "hspnhzn"), ("镇", "phhhzhsshhhpn"),
    ("省", "spnpszhh"), ("市", "nhszhs"), ("区", "hpnz"), ("县", "szhhhzhn"),
    ("街", "ppshshhshhs"), ("巷", "hsshpnhzz"), ("院", "zzshnnzhpz"), ("校", "hspnnhpnpn"),
    ("班", "hhshhshnhhhsh"), ("级", "zzhpzn"), ("组", "zzhszhhh"), ("队", "zzspn"),
    ("公", "pnzn"), ("司", "zhszh"), ("厂", "hp"), ("店", "nhpszh"),
    ("房", "nhzhzp"), ("屋", "zzphshsh"), ("厅", "hphz"), ("室", "nnpzhsh"),
    ("厨", "hphszhhszn"), ("厕", "hpszhhpzs"), ("卫", "zhsh"), ("浴", "nnhpnpnszh"),
    ("衣", "nhpzzn"), ("裤", "nzzhszhzhs"), ("鞋", "hsszhhshshhsh"), ("帽", "szhszhhszhhh"),
    ("袜", "nzzhhsph"), ("裙", "nzzhzphszh"), ("包", "pzhhz"), ("带", "hsssnzhzs"),
    ("吃", "szhpz"), ("喝", "szhszhhpzpz"), ("睡", "szhhhphshhh"), ("走", "hshshpn"),
    ("跑", "szhshshzpzhhz"), ("跳", "szhshshzppn"), ("飞", "zpn"), ("坐", "pnpnhsh"),
    ("站", "nhnphshszh"), ("立", "nhnph"), ("躺", "pszhhhpnspn"), ("笑", "phnphnpn"),
    ("哭", "szhszhhpnn"), ("唱", "szhszhhszhh"), ("听", "szhpphs"), ("看", "phhsszhhh"),
    ("写", "nzhhzz"), ("读", "nzhszznhn"), ("说", "nznpszhpz"), ("问", "nszszh"),
    ("答", "phnphnpnhszh"), ("想", "hspnszhhhnzn"), ("思", "szhshnznn"), ("念", "pnhznznn"),
    ("忘", "nhznznn"), ("记", "nzzhz"), ("学", "nnpnzzsh"), ("习", "znh"),
    ("教", "hshppznzh"), ("练", "zzhhzspn"), ("考", "hshphz"), ("试", "nzhhsnhz"),
    ("做", "pshsszhpzh"), ("作", "psphss"), ("办", "zppn"), ("干", "hhs"),
    ("忙", "nnsnhz"), ("累", "szhshzznpp"), ("闲", "nszhspn"), ("休", "pshspn"),
    ("玩", "hhshhhpz"), ("乐", "pzhspn"), ("喜", "hshszhnphszh"), ("怒", "zphznnznn"),
    ("哀", "nhszhpzn"), ("怕", "nnspszhh"), ("惊", "nnsnhszhspn"), ("爱", "pnnznzhzn"),
    ("恨", "nnszhhpzn"), ("愁", "phspnnppnnznn"), ("苦", "hsshsszh"), ("甜", "phsszhhs"),
    ("酸", "hszpzhpzpn"), ("辣", "nhnpnhshhspn"), ("咸", "hpnhszhzn"), ("香", "phspnszhh"),
    ("臭", "pszhhhpnn"), ("冷", "nnpnhzn"), ("热", "hszhpznnnn"), ("温", "nnhszhhszhh"),
    ("凉", "nnnhszhspn"), ("暖", "szhhpnhhpzn"), ("亮", "nhszhzzpz"), ("暗", "szhhnhnpnszhh"),
    ("明", "szhhpzhh"), ("白", "pszhh"), ("黑", "szhnhshhnnnn"), ("灰", "hpnppn"),
    ("红", "zzhzsh"), ("蓝", "hsszhhsshh"), ("绿", "zzhzzhhspn"), ("紫", "shshzhhzzspn"),
    ("青", "hhshszhh"), ("金", "pnhhshn"), ("银", "phhhzzhhhpzn"), ("铜", "phhhzszhszh"),
    ("铁", "phhhzphhpn"), ("钢", "phhhzszp"), ("木", "hspn"), ("石", "hpszh"),
    ("土", "hsh"), ("沙", "nnhspnp"), ("尘", "spnhsh"), ("泥", "nnhzphpz"),
    ("冰", "nnszpn"), ("汽", "nnhphhz"), ("油", "nnhszhsh"), ("盐", "hshszhshshh"),
    ("糖", "nphspnnhpzzsh"), ("奶", "zphzp"), ("酒", "nnhhszhzzhh"), ("烟", "nppnszhpnh"),
    ("开", "hhps"), ("关", "nphhpn"), ("进", "nhhpsnzn"), ("出", "zsszs"),
    ("来", "hnnphspn"), ("去", "hshzn"), ("回", "szhszh"), ("到", "hznshhss"),
    ("达", "hpnzn"), ("离", "nhpzzszpn"), ("起", "hshshpnzhz"), ("落", "hssnnhpzn"),
    ("升", "phps"), ("降", "zzpznzzhs"), ("加", "zpszh"), ("减", "nnhpnhszhzn"),
    ("乘", "phssppnhspn"), ("除", "zzpnhhspn"), ("等", "phnphnhshhzn"), ("于", "hhs"),
    ("同", "szhszh"), ("异", "zhshhs"), ("真", "hsszhhhpn"), ("假", "pszshhpzn"),
    ("对", "znhsn"), ("错", "phhhzhssszhh"), ("好", "zphzsh"), ("坏", "hshhpsn"),
    ("美", "nphhhshpn"), ("丑", "zhs"), ("强", "zzhszhszhhshn"), ("弱", "zzhnnzzhnn"),
    ("快", "nnszhpn"), ("慢", "nnszhhszhzzn"), ("远", "hhpznzn"), ("近", "pphsnzn"),
    ("长", "phzn"), ("短", "phhpnhszhnnh"), ("宽", "nnhsshszpz"), ("窄", "nnnpnpphs"),
    ("深", "nnhnzhspn"), ("浅", "nnhhhzn"), ("重", "phszhhhshh"), ("轻", "hzhszznhsh"),
    ("粗", "nphspnszhhh"), ("细", "zzhszhsh"), ("厚", "hpszhhzsh"), ("薄", "hssnnhhszhs"),
    ("满", "nnhhssszhpn"), ("空", "nnnpnhsh"), ("正", "hshsh"), ("反", "hpzn"),
    ("单", "npszhhs"), ("双", "znzn"), ("多", "pznpzn"), ("全", "pnhhsh"),
    ("半", "nphhs"), ("零", "hszsnnnnpnhzn"), ("一", "h"), ("二", "hh"),
    ("三", "hhh"), ("四", "szpzh"), ("五", "hszh"), ("六", "nhpn"),
    ("七", "hz"), ("八", "pn"), ("九", "pz"), ("十", "hs"),
    ("百", "hpszhh"), ("千", "phs"), ("万", "hzp"), ("亿", "pszh"),
    ("点", "shszhnnnn"), ("分", "pnzp"), ("秒", "phspnspnp"), ("时", "szhhhsn"),
    ("刻", "nhpzzppn"), ("天", "hhpn"), ("年", "phhshs"), ("周", "pzhshszh"),
    ("今", "pnhz"), ("明", "szhhpzhh"), ("昨", "szhhphsh"), ("现", "hhshszpz"),
    ("在", "hpshsh"), ("已", "zhz"), ("经", "zzhzznhsh"), ("将", "nzhpzhsn"),
    ("要", "hszssphzph"), ("正", "hshsh"), ("刚", "szpns"), ("才", "hsp"),
    ("就", "nhszhspnpzhn"), ("都", "hshpszhhzz"), ("也", "zsz"), ("还", "hpsnnzn"),
    ("又", "zn"), ("再", "hszssh"), ("更", "hszhhpn"), ("最", "szhhhshszhzn"),
    ("很", "ppszhhhpn"), ("太", "hpnn"), ("非", "shhhshhh"), ("常", "snznphszhs"),
    ("极", "hspnpzn"), ("特", "phhshshhzn"), ("别", "szhzpps"), ("只", "szhpn"),
    ("但", "psszhhh"), ("而", "hpzszs"), ("因", "szhpn"), ("为", "npzn"),
    ("所", "nzhpphs"), ("以", "zhpn"), ("如", "zphszh"), ("果", "szhhhspn"),
    ("虽", "szhszhshhn"), ("然", "pznphnn"), ("却", "hshzzsz"), ("或", "hszhzn"),
    ("和", "phspnszh"), ("与", "hzh"), ("跟", "szhshshzzhhpn"), ("对", "znhsn"),
    ("把", "hshzzhz"), ("被", "nzzhzpszn"), ("让", "nzshh"), ("给", "zzhpnhszh"),
    ("从", "pnpn"), ("向", "pszszh"), ("往", "ppsnhhsh"), ("在", "hpshsh"),
    ("于", "hhs"), ("的", "pszhhpzn"), ("地", "hshzsz"), ("得", "ppsszhhhhszn"),
    ("着", "nphhhpszh"), ("了", "zs"), ("过", "hsnzn"), ("吗", "szhzzh"),
    ("呢", "szhzphzp"), ("吧", "szhzhz"), ("啊", "szhzszhsz"), ("呀", "szhhzsp"),
    ("请", "nzhhshszhh"), ("谢", "nzpszzhhhszn"), ("帮", "hhhzszhsz"), ("助", "szhhhzn"),
    ("看", "phhsszhhh"), ("见", "szpz"), ("找", "hshhzn"), ("用", "pzhhhs"),
    ("买", "zznhn"), ("卖", "hshzznhn"), ("送", "nznphhpnnzn"), ("拿", "pnhszhphhs"),
    ("放", "nhzppnpn"), ("留", "pznzzszhsh"), ("带", "hsssnzhzs"), ("穿", "nnnpnhzp"),
    ("住", "psnhhsh"), ("坐", "pnpnhsh"), ("立", "nhnph"), ("睡", "szhhhphshhh"),
    ("醒", "hszpzhszhhphhsh"), ("梦", "hspnhspnpz"), ("想", "hspnszhhhnzn"),
    ("希", "pnhsnzs"), ("望", "nhzpzhhhs"), ("信", "psnhszh"), ("知", "phhpnszh"),
    ("懂", "nnshsshszhhhs"), ("会", "pnhhzn"), ("能", "znzzhhzpzp"), ("可", "hszhs"),
    ("应", "nhpppn"), ("该", "nznhpppn"), ("必", "nznpn"), ("须", "ppphpzszn"),
    ("需", "hszsnnnnhpzss"), ("愿", "hpszhhspnznn"), ("敢", "hsshhhpnpn"),
    ("怕", "nnspszhh"), ("喜", "hshszhnphszh"), ("爱", "pnnznzhzn"), ("讨", "nzhsn"),
    ("厌", "hphpnn"), ("笑", "phnphnpn"), ("哭", "szhszhhpnn"), ("喊", "szhhpnhszhzpn"),
    ("唱", "szhszhhszhh"), ("跳", "szhshshzppn"), ("画", "hszhszhsz"), ("读", "nzhszznhn"),
    ("写", "nzhhzz"), ("算", "phnphnszhhhhs"), ("测", "nnhszpnpn"), ("试", "nzhhsnhz"),
    ("改", "zhzpnpn"), ("修", "psssppnp"), ("删", "pzzpzzhh"), ("查", "hspnszhhh"),
    ("搜", "hshpszhhszn"), ("发", "zhpzn"), ("收", "zzpn"), ("存", "hpzsh"),
    ("取", "hsshhhzn"), ("换", "hshpzszhpn"), ("转", "hzhshzn"), ("移", "phspnpznpzn"),
    ("复", "phszhhhpn"), ("制", "phhszzhs"), ("粘", "nphspnshszh"), ("贴", "szpnshszh"),
    ("登", "zpnphszhnnh"), ("录", "zzhszpnn"), ("退", "zhhhpnzn"), ("关", "nphhpn"),
    ("锁", "phhhzsnpszhpn"), ("打", "hshhz"), ("敲", "nhszhszhpnhszh"), ("按", "hshnnzzph"),
    ("点", "shszhnnnn"), ("选", "phshpnzn"), ("确", "hpszhpzzhhhs"), ("认", "nzpn"),
    ("取", "hsshhhzn"), ("消", "nnhsnhpzhh"), ("成", "hpzzpn"), ("功", "hshzp"),
    ("失", "phhpn"), ("败", "szpnphppn"), ("错", "phhhzhssszhh"), ("误", "nzszhzhpn"),
    ("正", "hshsh"), ("常", "snznphszhs"), ("异", "zhshhs"), ("危", "pzhhzp"),
    ("险", "zzspnhnnh"), ("安", "nnzzph"), ("全", "pnhhsh"), ("快", "nnszhpn"),
    ("慢", "nnszhhszhzzn"), ("好", "zphzsh"), ("坏", "hshhpsn"), ("新", "nhpnhspnpphs"),
    ("老", "hshppz"), ("高", "nhszhszhsz"), ("矮", "phhpnhspnzph"), ("胖", "pzhhnphhs"),
    ("瘦", "nhpsnzzhshzn"), ("美", "nphhhshpn"), ("丑", "zhs"), ("贵", "szhsphszpn"),
    ("便", "pshszhhpn"), ("宜", "nnszhhh"), ("丰", "hhhs"), ("富", "nnhszhszhsh"),
    ("穷", "nnnpnzp"), ("干", "hhs"), ("净", "nnpzzhh"), ("脏", "pzhhnhphsh"),
    ("清", "nnhhhshszhh"), ("浊", "nnhszhshhn"), ("香", "phspnszhh"), ("臭", "pszhhhpnn"),
    ("亮", "nhszhzzpz"), ("暗", "szhhnhnpnszhh"), ("声", "hshzpsp"), ("音", "nhnphszhh"),
    ("色", "pzzhsz"), ("光", "spnphz"), ("电", "szhhz"), ("热", "hszhpznnnn"),
    ("冷", "nnpnhzn"), ("暖", "szhhpnhhpzn"), ("网", "szpnpn"), ("线", "zzhhhzn"),
    ("屏", "zzhnpnhhs"), ("键", "phhhzzzhshhhn"), ("盘", "ppnzhszhhsh"), ("鼠", "pzhsshhzznzzn"),
    ("标", "hspnhhspn"), ("机", "hspnpzz"), ("器", "szhszhhpnnshszh"), ("软", "hzhspzpn"),
    ("硬", "hpszhszhshpn"), ("件", "psphhs"), ("程", "phspnszhhsh"), ("序", "nhpzzs"),
    ("代", "pshzn"), ("码", "hpszhhzzh"), ("数", "nphspnzhzpnpn"), ("据", "hshzzphsszh"),
    ("库", "nhphzhss"), ("文", "nhpn"), ("件", "psphhs"), ("夹", "hnphnpn"),
    ("目", "szhhh"), ("录", "zzhszpnn"), ("路", "szhshshpznszh"), ("径", "ppszpnhsh"),
    ("端", "nhnphszsshpzzss"), ("口", "szh"), ("服", "pzhhzhzn"), ("务", "pznzp"),
    ("器", "szhszhhpnnshszh"), ("云", "hhzn"), ("智", "phhpnszhszhh"), ("能", "znzzhhzpzp"),
    ("体", "pshspnh"), ("模", "hspnhssszhhhpn"), ("型", "hhpssshsh"), ("提", "hshszhhhshpn"),
    ("示", "hhspn"), ("词", "nzzhszh"), ("流", "nnhnhzzpspz"), ("卡", "shshn"),
    ("顿", "hzznhpzszn"), ("死", "hpzpz"), ("活", "nnhphsszh"), ("动", "hhznzp"),
    ("静", "hhshszhhpzzh"), ("止", "shsh"), ("步", "shshspp"), ("跑", "szhshshzpzhhz"),
    ("跳", "szhshshzppn"), ("飞", "zpn"), ("游", "nnhnhzppznzh"), ("泳", "nnhnhzzpn"),
    ("球", "hhshhszpnn"), ("赛", "nnnhhhspnszpn"), ("赢", "nhszhpzhszzhzzpn"), ("输", "hzhsphshzs"),
    ("欢", "znpzpnpn"), ("迎", "pzhhzzn"), ("谢", "nzpszzhhhszn"), ("抱", "hshzzhz"),
    ("歉", "nphhhppzpnpn"), ("再", "hszssh"), ("见", "szpz"), ("拜", "phhhphhs"),
    ("早", "szhhhs"), ("安", "nnzzph"), ("晚", "szhhpzszn"), ("好", "zphzsh"),
    ("你", "pspzspn"), ("我", "phshzpn"), ("他", "pszsz"), ("她", "zphzsz"),
    ("们", "psnsz"), ("的", "pszhhpzn"), ("是", "szhhhshpn"), ("不", "hpsn"),
    ("了", "zs"), ("在", "hpshsh"), ("有", "hpszhh"), ("和", "phspnszh"),
]


def build_chaizi(
    char_info: dict[str, tuple[str, str, bool]],
    single_w: dict[str, int],
) -> tuple[dict[str, object], int]:
    parts_raw: dict[str, list[tuple[int, int, str, str, str]]] = defaultdict(list)

    def resolve_comp_pinyins(comp: str) -> list[str]:
        if comp in COMPONENT_PINYIN:
            return [COMPONENT_PINYIN[comp]]
        pr = char_info.get(comp, ("", "", True))[0]
        if pr:
            return [pr]
        return []

    seen_per_key: dict[str, set[str]] = defaultdict(set)
    unique_chars: set[str] = set()

    for ch, decomp in CHAIZI_GROUPS:
        if "+" not in decomp:
            continue
        toned = char_info.get(ch, ("", "", True))[1]
        if not toned:
            continue
        comps = decomp.split("+")
        comp_pinyins: list[str] = []
        ok = True
        for comp in comps:
            pys = resolve_comp_pinyins(comp)
            if not pys:
                ok = False
                break
            comp_pinyins.append(pys[0])
        if not ok:
            continue

        unique_chars.add(ch)
        wt = single_w.get(ch, 0)
        canonical_key = "".join(comp_pinyins)
        if ch not in seen_per_key[canonical_key]:
            seen_per_key[canonical_key].add(ch)
            parts_raw[canonical_key].append((0, -wt, ch, decomp, toned))

        # For 2-part compounds, also index reversed component order (e.g. mushui->沐, baimu->柏, koushi->古)
        if len(comp_pinyins) == 2 and comp_pinyins[0] != comp_pinyins[1]:
            rev_key = comp_pinyins[1] + comp_pinyins[0]
            if ch not in seen_per_key[rev_key]:
                seen_per_key[rev_key].add(ch)
                parts_raw[rev_key].append((1, -wt, ch, decomp, toned))

    # Guarantee exact prompt showcase entries are always present at top of their keys
    showcase: list[tuple[str, str, str]] = [
        ("huohuo", "炎", "火+火"),
        ("huohuohuo", "焱", "火+火+火"),
        ("mumu", "林", "木+木"),
        ("mumumu", "森", "木+木+木"),
        ("shuishui", "沝", "水+水"),
        ("shuishuishui", "淼", "水+水+水"),
        ("jinjin", "鍂", "金+金"),
        ("jinjinjin", "鑫", "金+金+金"),
        ("tututu", "垚", "土+土+土"),
        ("shishishi", "磊", "石+石+石"),
        ("niuniuniu", "犇", "牛+牛+牛"),
        ("longlonglong", "龘", "龍+龍+龍"),
        ("ririri", "晶", "日+日+日"),
        ("riyue", "明", "日+月"),
        ("koushi", "古", "十+口"),
        ("renren", "从", "人+人"),
        ("renrenren", "众", "人+人+人"),
        ("nvzi", "好", "女+子"),
        ("tianli", "男", "田+力"),
        ("xiaoda", "尖", "小+大"),
        ("shanshi", "岩", "山+石"),
        ("jiji", "喆", "吉+吉"),
        ("yueyue", "朋", "月+月"),
        ("checheche", "轰", "车+车+车"),
        ("checheche", "轟", "車+車+車"),
        ("shoumu", "看", "手+目"),
        ("baishui", "泉", "白+水"),
        ("baimu", "柏", "木+白"),
        ("renmu", "休", "亻+木"),
        ("koukoukou", "品", "口+口+口"),
        ("mushui", "沐", "氵+木"),
        ("huoshan", "灿", "火+山"),
    ]
    for key, ch, decomp in reversed(showcase):
        toned = char_info.get(ch, ("", "", True))[1]
        existing = [row for row in parts_raw[key] if row[2] != ch]
        parts_raw[key] = [(-1, -single_w.get(ch, 0), ch, decomp, toned)] + existing
        unique_chars.add(ch)

    parts_out: dict[str, list[dict[str, str]]] = {}
    for key in sorted(parts_raw.keys()):
        rows = sorted(parts_raw[key], key=lambda r: (r[0], r[1], r[2]))
        parts_out[key] = [{"c": r[2], "d": r[3], "p": r[4]} for r in rows]

    # Build strokes index from CHAR_STROKES (clean h/s/p/n/z only, sorted by frequency)
    strokes_bucket: dict[str, list[str]] = defaultdict(list)
    seen_char_stroke: set[tuple[str, str]] = set()
    for ch, raw_code in CHAR_STROKES:
        code = raw_code.replace(" ", "")
        if not code or not all(c in "hspnz" for c in code):
            continue
        if (code, ch) not in seen_char_stroke:
            seen_char_stroke.add((code, ch))
            strokes_bucket[code].append(ch)

    strokes_out: dict[str, list[str]] = {
        code: sorted(chars, key=lambda x: (-single_w.get(x, 0), x))
        for code, chars in sorted(strokes_bucket.items())
    }

    return {"parts": parts_out, "strokes": strokes_out}, len(unique_chars)


# ---------------------------------------------------------------------------
# 8. Main driver and verification assertions
# ---------------------------------------------------------------------------


def write_compact_json(path: Path, data: object) -> int:
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    path.write_text(text, encoding="utf-8")
    return path.stat().st_size


def main() -> None:
    print("Loading Wubi86, lexicon.json, characters.json...")
    single_w, phrase_w = load_wubi86()
    orig_lex: dict[str, list[str]] = json.loads(LEXICON_PATH.read_text(encoding="utf-8"))
    orig_chars: dict[str, str] = json.loads(CHARACTERS_PATH.read_text(encoding="utf-8"))
    core_chars, sentence_single = parse_pinyin_engine_constants()

    all_uniq_chars = sorted(set().union(*orig_chars.values()) | {ch for ch, _ in CHAIZI_GROUPS} | {"鍂", "轟", "龘", "淼", "垚", "犇"})
    print(f"Querying macOS Foundation readings for {len(all_uniq_chars)} characters...")
    char_info = query_swift_character_info(all_uniq_chars)

    print("1/5 Re-ranking Resources/lexicon.json...")
    new_lex = rerank_lexicon(orig_lex, single_w, phrase_w)
    lex_bytes = write_compact_json(LEXICON_PATH, new_lex)
    print(f"  -> lexicon.json: {len(new_lex)} keys, {sum(len(v) for v in new_lex.values())} words, {lex_bytes / 1024 / 1024:.2f} MB")

    print("2/5 Re-ranking Resources/characters.json...")
    new_chars = rerank_characters(orig_chars, new_lex, single_w, phrase_w, char_info, core_chars, sentence_single)
    chars_bytes = write_compact_json(CHARACTERS_PATH, new_chars)
    print(f"  -> characters.json: {len(new_chars)} keys, {len(set().union(*new_chars.values()))} unique chars, {chars_bytes / 1024:.1f} KB")

    print("3/5 Building Resources/lm.json...")
    lm_data = build_language_model(new_lex, single_w, phrase_w)
    lm_bytes = write_compact_json(LM_PATH, lm_data)
    print(f"  -> lm.json: {len(lm_data['u'])} unigrams, {len(lm_data['b'])} bigrams, {lm_bytes / 1024 / 1024:.2f} MB")

    print("4/5 Building Resources/english_lexicon.json...")
    eng_data = build_english_lexicon()
    eng_bytes = write_compact_json(ENGLISH_PATH, eng_data)
    print(f"  -> english_lexicon.json: {len(eng_data['words'])} words, {len(eng_data['mixed'])} mixed, {eng_bytes / 1024:.1f} KB")

    print("5/5 Building Resources/chaizi.json...")
    chaizi_data, chaizi_char_count = build_chaizi(char_info, single_w)
    chaizi_bytes = write_compact_json(CHAIZI_PATH, chaizi_data)
    print(f"  -> chaizi.json: {len(chaizi_data['parts'])} part keys ({chaizi_char_count} compound chars), {len(chaizi_data['strokes'])} stroke keys, {chaizi_bytes / 1024:.1f} KB")

    # Verification assertions
    assert len(new_chars) == 426, f"Expected 426 syllables, got {len(new_chars)}"
    assert len(set().union(*new_chars.values())) == 44359, "Unique char count invariant violated!"
    for sy in orig_chars:
        assert Counter(new_chars[sy]) == Counter(orig_chars[sy]), f"Char multiset changed for {sy}"
    for key, prefix in CRITICAL_LEXICON_PREFIX.items():
        assert new_lex[key][: len(prefix)] == prefix, f"Prefix mismatch for {key}: {new_lex[key][:6]}"
    for key, words in new_lex.items():
        assert len(words) == len(set(words)), f"Duplicates in lexicon[{key}]"
    assert lm_bytes <= int(2.5 * 1024 * 1024), f"lm.json too large: {lm_bytes}"
    assert eng_bytes <= 400 * 1024, f"english_lexicon.json too large: {eng_bytes}"
    assert len(eng_data["words"]) >= 3500, f"Too few English words: {len(eng_data['words'])}"
    assert chaizi_bytes <= 250 * 1024, f"chaizi.json too large: {chaizi_bytes}"
    assert chaizi_char_count >= 1500, f"Too few compound chars in chaizi.json: {chaizi_char_count}"
    print("ALL ASSERTIONS PASSED!")


if __name__ == "__main__":
    main()
