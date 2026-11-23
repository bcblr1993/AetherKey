#!/usr/bin/env python3
"""Build the offline character layer from a pinned official Unicode Unihan archive.

Download https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip and pass its path.
Common-character ordering is kept in the engine; this is the complete fallback.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import zipfile

VERSION = '17.0.0'
EXPECTED_SHA256 = 'f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e'
FIELDS = {'kMandarin', 'kHanyuPinyin', 'kXHC1983', 'kTGHZ2013', 'kHanyuPinlu'}

def normalize(reading):
    decomposed = unicodedata.normalize('NFD', reading.lower()).replace('u\u0308', 'v')
    plain = ''.join(c for c in decomposed if unicodedata.category(c) != 'Mn')
    return plain if re.fullmatch('[a-z]+', plain) else None

def load_modern_weights(resources_dir):
    """Optionally load Wubi86 single-character weights and lexicon phrase reading counts."""
    single_weights = {}
    wubi_path = resources_dir / 'Wubi86' / 'wubi86.dict.yaml'
    phrase_weights = {}
    if wubi_path.exists():
        in_table = False
        for line in wubi_path.read_text(encoding='utf-8').splitlines():
            if line == '...':
                in_table = True
                continue
            if not in_table or not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) >= 3 and parts[2].isdigit():
                word, wt = parts[0], int(parts[2])
                if len(word) == 1:
                    if wt > single_weights.get(word, 0):
                        single_weights[word] = wt
                elif wt > phrase_weights.get(word, 0):
                    phrase_weights[word] = wt
    return single_weights, phrase_weights


def build(archive, resources_dir=None):
    assert hashlib.sha256(Path(archive).read_bytes()).hexdigest() == EXPECTED_SHA256, 'Unexpected Unihan source archive'
    readings = defaultdict(set)
    standard = {}
    primary = set()
    mandarin_rank = {}
    modern_dict = set()
    pinlu_freq = defaultdict(int)
    with zipfile.ZipFile(archive) as data:
        for name in sorted(data.namelist()):
            if not name.endswith('.txt'): continue
            for line in data.read(name).decode('utf-8').splitlines():
                if not line or line.startswith('#'): continue
                scalar, field, value = line.split('\t', 2)
                character = chr(int(scalar[2:], 16))
                if field == 'kTGH':
                    standard[character] = int(value.split(':')[-1])
                if field not in FIELDS: continue
                for item_idx, item in enumerate(value.split()):
                    text = item.split(':')[-1] if ':' in item else item
                    for raw in text.split(','):
                        freq_match = re.search(r'\((\d+)\)$', raw)
                        freq_val = int(freq_match.group(1)) if freq_match else 0
                        raw = re.sub(r'\(\d+\)$', '', raw)
                        key = normalize(raw)
                        if key:
                            readings[key].add(character)
                            if field == 'kMandarin':
                                primary.add((key, character))
                                if (key, character) not in mandarin_rank or item_idx < mandarin_rank[(key, character)]:
                                    mandarin_rank[(key, character)] = item_idx
                            elif field in {'kXHC1983', 'kTGHZ2013', 'kHanyuPinlu'}:
                                modern_dict.add((key, character))
                                if field == 'kHanyuPinlu' and freq_val > pinlu_freq[(key, character)]:
                                    pinlu_freq[(key, character)] = freq_val

    single_weights, phrase_weights = load_modern_weights(resources_dir) if resources_dir else ({}, {})

    # Estimate per-(syllable, char) phrase evidence if lexicon.json is available.
    phrase_ev = defaultdict(lambda: defaultdict(int))
    total_phrase_ev = defaultdict(int)
    for ch, sw in single_weights.items():
        total_phrase_ev[ch] += sw
    lexicon_path = resources_dir / 'lexicon.json' if resources_dir else None
    if lexicon_path and lexicon_path.exists():
        char_syls = defaultdict(set)
        for syl, chars in readings.items():
            for ch in chars:
                char_syls[ch].add(syl)
                if syl == 'lve': char_syls[ch].add('lue')
                if syl == 'nve': char_syls[ch].add('nue')
        lex = json.loads(lexicon_path.read_text(encoding='utf-8'))
        for key, words in lex.items():
            clean_key = key.replace("'", '')
            for idx, word in enumerate(words):
                if not (2 <= len(word) <= 6):
                    continue
                wt = phrase_weights.get(word, 0) or max(100_000, 1_000_000 // (idx + 1))
                n, m = len(clean_key), len(word)
                memo = {}
                def split_dfs(ki, wi):
                    if (ki, wi) in memo: return memo[(ki, wi)]
                    if wi == m:
                        res = [] if ki == n else None
                        memo[(ki, wi)] = res
                        return res
                    allowed = char_syls.get(word[wi], set())
                    for l in range(1, min(7, n - ki + 1)):
                        sub = clean_key[ki:ki + l]
                        if sub in allowed:
                            rest = split_dfs(ki + l, wi + 1)
                            if rest is not None:
                                norm = 'lve' if sub == 'lue' else ('nve' if sub == 'nue' else sub)
                                memo[(ki, wi)] = [norm] + rest
                                return memo[(ki, wi)]
                    memo[(ki, wi)] = None
                    return None
                syls = split_dfs(0, 0)
                if syls:
                    for ch, sy in zip(word, syls):
                        phrase_ev[sy][ch] += wt
                        total_phrase_ev[ch] += wt

    def order(key, char):
        is_primary = (key, char) in primary
        is_standard = char in standard
        in_modern_dict = (key, char) in modern_dict
        ev = phrase_ev[key][char]
        tot = max(1, total_phrase_ev[char])
        pf = pinlu_freq[(key, char)]
        sw = single_weights.get(char, 0)
        is_genuine_polyphone = (not is_primary) and is_standard and in_modern_dict and (
            pf >= 50 or (ev >= 10_000_000 and ev * 50 >= tot)
        )
        # Tier 0: kMandarin primary + kTGH standard (or genuine high-frequency modern polyphone)
        # Tier 1: kMandarin primary (non-kTGH BMP, then Ext-B+)
        # Tier 2: Secondary kXHC1983/kTGHZ2013/kHanyuPinyin readings (kTGH first, then BMP, then Ext-B+)
        if is_primary and is_standard:
            tier = 0
            m_rank = mandarin_rank.get((key, char), 0)
            freq_score = ev + sw + pf * 100_000
            return (tier, m_rank, -freq_score, standard[char], ord(char))
        if is_genuine_polyphone:
            tier = 0
            freq_score = ev + pf * 100_000
            return (tier, 2, -freq_score, standard[char], ord(char))
        if is_primary:
            tier = 1
            bmp_rank = 0 if ord(char) <= 0x9fff else 1
            return (tier, bmp_rank, -(ev + sw), ord(char))
        tier = 2
        if is_standard:
            src_rank = 0 if in_modern_dict else 1
            return (tier, 0, src_rank, -ev, standard[char], ord(char))
        bmp_rank = 1 if ord(char) <= 0x9fff else 2
        return (tier, bmp_rank, 0, -ev, ord(char))

    result = {key: ''.join(sorted(chars, key=lambda c, k=key: order(k, c))) for key, chars in sorted(readings.items())}
    assert all(char in result[key] for key, char in primary)
    covered = set().union(*readings.values())
    missing_standard = sorted(set(standard) - covered)
    assert not missing_standard, f'Standard characters without readings: {missing_standard}'
    report = {
        'unicodeVersion': VERSION,
        'source': f'https://www.unicode.org/Public/{VERSION}/ucd/Unihan.zip',
        'sourceSHA256': hashlib.sha256(Path(archive).read_bytes()).hexdigest(),
        'fields': sorted(FIELDS), 'syllables': len(result),
        'characters': len(covered), 'readingPairs': sum(map(len, result.values())),
        'standardCharactersCovered': len(standard), 'primaryReadingPairs': len(primary)
    }
    return result, report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--resources', type=Path, default=Path(__file__).resolve().parents[1] / 'Resources')
    args = parser.parse_args()
    result, report = build(args.archive, resources_dir=args.resources)
    args.resources.mkdir(exist_ok=True)
    output = args.resources / 'characters.json'
    output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    report['resourceSHA256'] = hashlib.sha256(output.read_bytes()).hexdigest()
    (args.resources / 'characters-source.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))
