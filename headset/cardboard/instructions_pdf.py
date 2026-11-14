"""INSTRUCTIONS.md + overview.png -> instructions.pdf.

    uv run --with weasyprint --with markdown instructions_pdf.py
"""
from pathlib import Path
import markdown
from weasyprint import HTML

here = Path(__file__).parent
CSS = """
@page { size: Letter; margin: 15mm; @bottom-right { content: counter(page); font-size: 8pt; } }
body { font: 10pt/1.35 "DejaVu Sans", "Liberation Sans", sans-serif; }
h1 { font-size: 16pt; margin: 0 0 6pt; } h2 { font-size: 12pt; margin: 12pt 0 4pt; break-after: avoid; }
img { width: 100%; } table { border-collapse: collapse; width: 100%; margin: 6pt 0; }
td, th { border: 0.5pt solid #888; padding: 2pt 4pt; text-align: left; vertical-align: top; font-size: 9pt; }
code { font-size: 9pt; } li { margin: 1.5pt 0; }
"""
body = markdown.markdown((here / "INSTRUCTIONS.md").read_text(), extensions=["tables", "sane_lists"])
body = body.replace("[ ] ", "&#9744; ")
HTML(string=f"<style>{CSS}</style>{body}", base_url=str(here)).write_pdf(here / "instructions.pdf")
