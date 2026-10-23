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

def build(archive):
    assert hashlib.sha256(Path(archive).read_bytes()).hexdigest() == EXPECTED_SHA256, 'Unexpected Unihan source archive'
    readings = defaultdict(set)
    standard = {}
    primary = set()
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
                for item in value.split():
                    text = item.split(':')[-1] if ':' in item else item
                    for raw in text.split(','):
                        raw = re.sub(r'\(\d+\)$', '', raw)
                        key = normalize(raw)
                        if key:
                            readings[key].add(character)
                            if field == 'kMandarin': primary.add((key, character))
    def order(char):
        return (0, standard[char]) if char in standard else (1 if ord(char) <= 0x9fff else 2, ord(char))
    result = {key: ''.join(sorted(chars, key=order)) for key, chars in sorted(readings.items())}
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
    result, report = build(args.archive)
    args.resources.mkdir(exist_ok=True)
    output = args.resources / 'characters.json'
    output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    report['resourceSHA256'] = hashlib.sha256(output.read_bytes()).hexdigest()
    (args.resources / 'characters-source.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
