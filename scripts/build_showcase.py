"""Embed showcase/data.json into showcase/template.html -> showcase/index.html (self-contained page)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "showcase" / "data.json").read_text(encoding="utf-8"))
html = (ROOT / "showcase" / "template.html").read_text(encoding="utf-8")
out = html.replace("__DATA__", json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/"))
(ROOT / "showcase" / "index.html").write_text(out, encoding="utf-8")
print(f"showcase/index.html {len(out) / 1024:.0f} KB")
