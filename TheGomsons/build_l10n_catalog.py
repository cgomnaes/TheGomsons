#!/usr/bin/env python3
"""One-shot builder: l10n_catalog_data.txt -> Localizable.xcstrings"""
import json
import os

here = os.path.dirname(os.path.abspath(__file__))
data_path = os.path.join(here, "l10n_catalog_data.txt")
out_path = os.path.join(here, "Localizable.xcstrings")

strings = {}
with open(data_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            raise ValueError(f"Bad line (need key|en|nb): {line!r}")
        key, en, nb = parts
        if key in strings:
            raise ValueError(f"Duplicate key: {key}")
        strings[key] = {
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "nb": {"stringUnit": {"state": "translated", "value": nb}},
            }
        }

catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
with open(out_path, "w", encoding="utf-8") as out:
    json.dump(catalog, out, ensure_ascii=False, indent=2)
print(f"Wrote {len(strings)} strings -> {out_path}")
