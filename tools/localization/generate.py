"""Generate embedded AS3 catalogs from messages.json, without a runtime dependency.

Usage: python generate.py MOD_DIRECTORY [MOD_DIRECTORY ...] [--check]
Pass D:/RemainsMod/mods/Sandevistan for Sandevistan; never edit its game mirror.
"""
import argparse
import json
import re
from pathlib import Path


def generate(root: Path, check: bool) -> int:
    count = 0
    for source in sorted((root / "src").rglob("modlocales/*/messages.json")):
        data = json.loads(source.read_text(encoding="utf-8-sig"))
        helpers = [p for p in source.parent.glob("*Locale.as")]
        if len(helpers) != 1:
            raise ValueError(f"Expected one locale helper next to {source}")
        helper = helpers[0]
        package = re.search(r"package\s+([\w.]+)", helper.read_text(encoding="utf-8"))[1]
        name = helper.stem + "Messages"
        for key, translations in data.items():
            if not key or set(translations) != {"en", "ru"}:
                raise ValueError(f"Invalid language keys: {source}: {key}")
            for code, value in translations.items():
                if not isinstance(value, str) or not value.strip() or re.search(r"[\u3400-\u9fff]", value):
                    raise ValueError(f"Missing translation: {source}: {key}: {code}")
                if sorted(re.findall(r"\{\d+\}", key)) != sorted(re.findall(r"\{\d+\}", value)):
                    raise ValueError(f"Placeholder mismatch: {source}: {key}: {code}")
        text = (f"package {package} {{\n   public class {name} {{\n"
                "      public static const DATA:Object = "
                + json.dumps(data, ensure_ascii=False, indent=2)
                + ";\n   }\n}\n")
        output = source.with_name(name + ".as")
        if check:
            if not output.exists() or output.read_text(encoding="utf-8") != text:
                raise ValueError(f"Catalog needs regeneration: {output}")
        else:
            output.write_text(text, encoding="utf-8")
        count += len(data)
        print(f"{root.name}: {len(data)} messages ({'checked' if check else 'generated'})")
    if not count:
        raise ValueError(f"No localization catalogs found in {root}")
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    total = sum(generate(root, args.check) for root in args.roots)
    print(f"Total: {total} messages, English and Russian")
