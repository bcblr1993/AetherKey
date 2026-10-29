# 五笔 86 码表

AetherKey ships `wubi86.dict.yaml` unchanged from rime/rime-wubi:
https://github.com/rime/rime-wubi/tree/152a0d3f3efe40cae216d1e3b338242446848d07

SHA-256: f833d86b72341fe82e069a425b6625f29ef85f1bc0f34f6fb7975fe514888b5a
Retrieved: 2026-10-28. Upstream table version: 0.7.

The dictionary and AUTHORS are covered by the upstream GNU LGPL version 3;
LICENSE.LGPL-3.0 and its incorporated LICENSE.GPL-3.0 are included here.
Original table authors and conversion history remain in the dictionary header.
This source file is the preferred editable form; no generated or compiled table
is required. AetherKey reads tab-separated table rows directly from this folder.
The code does not link librime. To modify the table, edit/replace this YAML file
in the source tree and rebuild with the checked-in project.yml / Xcode project.
The original upstream file, credits and licenses remain independently available
in the app's Contents/Resources/Wubi86 directory and the project source tree.

Implementation notes: normal codes use a–y and 1–4 keystrokes. Exact-code
candidates precede up to 128 incomplete-code suggestions; exact matches are not
truncated. z + pinyin uses AetherKey's local pinyin engine for reverse lookup,
showing available five-stroke codes. Rare characters without a code in this
upstream table cannot be returned by reverse lookup. User learning, custom
phrases, pinning and forgetting use a separate wubi86: namespace.
