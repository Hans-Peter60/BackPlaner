#!/usr/bin/env python3
"""Builds the HTML pages of the user manual for the BakePlanner website.

Reads the three Markdown manuals in this folder and writes
``website/manual-de.html``, ``website/manual-en.html`` and
``website/manual-fr.html`` in the look of ``website/index.html``. The
screenshots are copied to ``website/images`` so the relative image paths of
the Markdown keep working.

Run it again whenever a manual changes, then upload the ``website`` folder
to the ``bakeplanner`` GitHub Pages repository:

    python3 docs/build-manual-html.py

The converter understands exactly the Markdown the manuals use: ATX
headings, paragraphs, ``-`` and ``1.`` lists (not nested), ``>`` quotes,
pipe tables, ``---`` rules, images with an italic caption line below, and
inline bold / italic / code / links. Heading ids follow GitHub's slug rules
so the table of contents keeps working.
"""

from __future__ import annotations

import html
import re
import shutil
from pathlib import Path

DOCS = Path(__file__).resolve().parent
WEBSITE = DOCS / "website"

MANUALS = {
    "de": {
        "source": "Benutzerhandbuch.md",
        "title": "BakePlanner – Benutzerhandbuch",
        "back": "Hilfe und Kontakt",
        "privacy": "Datenschutz",
        "languages": "Sprache wählen",
        "top": "Nach oben",
    },
    "en": {
        "source": "User-Manual.md",
        "title": "BakePlanner – User Manual",
        "back": "Help and contact",
        "privacy": "Privacy",
        "languages": "Choose language",
        "top": "Back to top",
    },
    "fr": {
        "source": "Manuel-utilisateur.md",
        "title": "BakePlanner – Manuel de l’utilisateur",
        "back": "Aide et contact",
        "privacy": "Confidentialité",
        "languages": "Choisir la langue",
        "top": "Haut de page",
    },
}

LANGUAGE_NAMES = {"de": "Deutsch", "en": "English", "fr": "Français"}


# MARK: - Inline markup

INLINE_RULES = [
    (re.compile(r"`([^`]+)`"), r"<code>\1</code>"),
    (re.compile(r"\*\*(.+?)\*\*"), r"<strong>\1</strong>"),
    (re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"), r"<em>\1</em>"),
    (re.compile(r"\[([^\]]+)\]\(([^)]+)\)"), r'<a href="\2">\1</a>'),
]


def inline(text: str) -> str:
    """Escapes HTML and applies the inline Markdown rules."""
    out = html.escape(text, quote=False)
    for pattern, replacement in INLINE_RULES:
        out = pattern.sub(replacement, out)
    return out


def slug(heading: str) -> str:
    """GitHub-style anchor for a heading text."""
    s = heading.strip().lower()
    s = re.sub(r"[^\w\s-]", "", s)
    return re.sub(r"\s", "-", s)


# MARK: - Block parsing

IMAGE_LINE = re.compile(r"^!\[([^\]]*)\]\(([^)]+)\)\s*$")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
ORDERED = re.compile(r"^\d+\.\s+(.*)$")
UNORDERED = re.compile(r"^[-*]\s+(.*)$")
TABLE_SEPARATOR = re.compile(r"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")


def split_row(line: str) -> list[str]:
    cells = line.strip()
    if cells.startswith("|"):
        cells = cells[1:]
    if cells.endswith("|"):
        cells = cells[:-1]
    return [c.strip() for c in cells.split("|")]


def plain_length(cell: str) -> int:
    """Visible length of a cell without the Markdown emphasis marks."""
    return len(re.sub(r"[*`]", "", cell))


# A term column up to this many characters is kept on one line; anything
# longer gets a fixed share of the table and may wrap at spaces.
NOWRAP_LIMIT = 26


def table_html(header: list[str], rows: list[list[str]]) -> str:
    """A table whose first column is sized by its longest entry.

    Every two-column table in the manuals is "term | explanation". Left to the
    browser, the long explanations push the term column down to a sliver and
    the terms break into one word per line. The first column therefore gets an
    explicit width from its longest cell (in `ch`), and short terms are not
    allowed to wrap at all. The wrapper lets wide tables scroll sideways on a
    phone instead of crushing the columns.
    """
    first_max = max(plain_length(r[0]) for r in [header, *rows] if r)
    classes = []
    colgroup = ""
    if len(header) >= 3:
        # Three and more columns do not fit a phone at full size; the CSS
        # shrinks them a little and lets the browser hyphenate.
        classes.append("wide")
    if len(header) == 2:
        if first_max <= NOWRAP_LIMIT:
            classes.append("firm")
            colgroup = f'<colgroup><col class="first" style="--w: {first_max + 2}ch"></colgroup>'
        else:
            colgroup = '<colgroup><col class="first" style="--w: 38%"></colgroup>'
    cls = f' class="{" ".join(classes)}"' if classes else ""
    parts = [f'<div class="table-wrap"><table{cls}>', colgroup]
    parts.append("<thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in header) + "</tr></thead>")
    parts.append("<tbody>")
    for row in rows:
        parts.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
    parts.append("</tbody></table></div>")
    return "\n".join(p for p in parts if p)


def convert(markdown: str) -> tuple[str, str, str]:
    """Returns (title, subtitle, body html) for one manual."""
    lines = markdown.splitlines()
    out: list[str] = []
    title = ""
    subtitle = ""
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        if stripped == "---":
            out.append("<hr>")
            i += 1
            continue

        m = HEADING.match(stripped)
        if m:
            level = len(m.group(1))
            text = m.group(2).strip()
            if level == 1 and not title:
                title = text
                # The line after the title is the revision note.
                j = i + 1
                while j < n and not lines[j].strip():
                    j += 1
                if j < n and not HEADING.match(lines[j].strip()) and lines[j].strip() != "---":
                    subtitle = lines[j].strip()
                    i = j + 1
                else:
                    i += 1
                continue
            out.append(f'<h{level} id="{slug(text)}">{inline(text)}</h{level}>')
            i += 1
            continue

        m = IMAGE_LINE.match(stripped)
        if m:
            alt, src = m.group(1), m.group(2)
            out.append(f'<figure><img class="screenshot" src="{html.escape(src)}" '
                       f'alt="{html.escape(alt)}" loading="lazy">')
            # An italic line right after the image is its caption.
            j = i + 1
            while j < n and not lines[j].strip():
                j += 1
            caption = lines[j].strip() if j < n else ""
            if caption.startswith("*") and caption.endswith("*") and not caption.startswith("**"):
                out.append(f"<figcaption>{inline(caption[1:-1])}</figcaption>")
                i = j + 1
            else:
                i += 1
            out.append("</figure>")
            continue

        if stripped.startswith(">"):
            quote: list[str] = []
            while i < n and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append('<blockquote class="note"><p>' + "<br>".join(inline(q) for q in quote if q) + "</p></blockquote>")
            continue

        if "|" in stripped and i + 1 < n and TABLE_SEPARATOR.match(lines[i + 1].strip()):
            header = split_row(stripped)
            i += 2
            rows: list[list[str]] = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i].strip()))
                i += 1
            out.append(table_html(header, rows))
            continue

        if ORDERED.match(stripped) or UNORDERED.match(stripped):
            ordered = bool(ORDERED.match(stripped))
            pattern = ORDERED if ordered else UNORDERED
            items: list[str] = []
            while i < n:
                s = lines[i].strip()
                m = pattern.match(s)
                if not m:
                    break
                items.append(m.group(1))
                i += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(it)}</li>" for it in items) + f"</{tag}>")
            continue

        # Paragraph: consecutive non-empty lines that start no other block.
        para: list[str] = []
        while i < n:
            s = lines[i].strip()
            if (not s or s == "---" or HEADING.match(s) or IMAGE_LINE.match(s)
                    or s.startswith(">") or ORDERED.match(s) or UNORDERED.match(s)
                    or (s.startswith("|") and i + 1 < n and TABLE_SEPARATOR.match(lines[i + 1].strip()))):
                break
            para.append(s)
            i += 1
        # Manual line breaks inside a paragraph are deliberate ("**Rezept**"
        # followed by its explanation), so they become <br>.
        out.append("<p>" + "<br>".join(inline(p) for p in para) + "</p>")

    return title, subtitle, "\n".join(out)


# MARK: - Page template

CSS = """
  :root {
    --bg-top: #FAEDD1;
    --bg-bottom: #EDCC9E;
    --card: #FFFFFF;
    --title: #593314;
    --text: #2A1A0A;
    --subtitle: #734D29;
    --accent: #945B29;
    --rule: #E6D3B8;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg-top: #291F17;
      --bg-bottom: #17120D;
      --card: #332921;
      --title: #F5E6CC;
      --text: #F2E8DA;
      --subtitle: #D1B899;
      --accent: #E3934F;
      --rule: #4A3C30;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 0 1rem 4rem;
    font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: var(--text);
    background: linear-gradient(var(--bg-top), var(--bg-bottom)) no-repeat;
    background-attachment: fixed;
  }
  main { max-width: 44rem; margin: 0 auto; }
  header { text-align: center; padding: 3rem 0 1rem; }
  h1 { color: var(--title); font-size: 2.2rem; margin: 0 0 .3rem; }
  .claim { color: var(--subtitle); margin: 0; }
  nav { text-align: center; margin: 1.5rem 0 2rem; }
  nav a {
    display: inline-block; margin: .2rem .4rem; padding: .4rem .9rem;
    color: var(--accent); text-decoration: none;
    border: 1px solid var(--accent); border-radius: 999px;
  }
  nav a:hover, nav a:focus { text-decoration: underline; }
  nav a[aria-current] { background: var(--accent); color: var(--card); }
  article {
    background: var(--card); border-radius: 16px;
    padding: 1.5rem 1.75rem; margin-bottom: 1.5rem;
  }
  /* Only running text may break inside an overlong word; table cells wrap
     at spaces, otherwise the browser squeezes the term column to a sliver. */
  article p, article li, article figcaption { overflow-wrap: break-word; }
  h2 { color: var(--title); font-size: 1.5rem; margin: 2rem 0 .6rem; }
  h3 { color: var(--title); font-size: 1.15rem; margin: 1.6rem 0 .3rem; }
  h4 { color: var(--title); font-size: 1rem; margin: 1.2rem 0 .3rem; }
  article > h2:first-child { margin-top: 0; }
  a { color: var(--accent); }
  hr { border: 0; border-top: 1px solid var(--rule); margin: 2rem 0; }
  code {
    font: .9em ui-monospace, SFMono-Regular, Menlo, monospace;
    background: var(--bg-top); border-radius: 4px; padding: 0 .3em;
  }
  blockquote.note {
    margin: 1rem 0; border-left: 4px solid var(--accent);
    padding-left: 1rem; color: var(--subtitle);
  }
  blockquote.note p { margin: 0; }
  .table-wrap { overflow-x: auto; margin: 1rem 0; }
  table { border-collapse: collapse; width: 100%; font-size: .95em; }
  th, td { text-align: left; vertical-align: top; padding: .45rem .6rem; border-bottom: 1px solid var(--rule); }
  th { color: var(--title); }
  col.first { width: var(--w); }
  table.firm th:first-child, table.firm td:first-child { white-space: nowrap; }
  @media (max-width: 480px) {
    /* On a phone a one-line term column would leave no room for the
       explanation, so the term may wrap at spaces and takes 40 %. */
    table.firm th:first-child, table.firm td:first-child { white-space: normal; }
    col.first { width: min(var(--w), 40%); }
    /* Tables with three or more columns: smaller type, tighter padding and
       hyphenation, so that the last column is not pushed off the screen. */
    table.wide { font-size: .88em; }
    table.wide th, table.wide td { padding: .35rem .4rem; hyphens: auto; }
  }
  figure { margin: 1.5rem 0; text-align: center; }
  img.screenshot {
    max-width: min(100%, 320px); height: auto;
    border-radius: 12px; box-shadow: 0 3px 10px rgba(0,0,0,.15);
  }
  figcaption { color: var(--subtitle); font-size: .9em; margin-top: .5rem; }
  footer { text-align: center; color: var(--subtitle); font-size: .9rem; }
"""

PAGE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{css}</style>
</head>
<body>
<main id="top">

<header>
  <h1>{heading}</h1>
  <p class="claim">{subtitle}</p>
</header>

<nav aria-label="{languages}">
  <a href="index.html#{lang}">{back}</a>
{language_links}
  <a href="privacy.html">{privacy}</a>
</nav>

<article>
{body}
</article>

<footer>
  <p><a href="#top">{top}</a> · <a href="index.html#{lang}">{back}</a> · <a href="privacy.html">{privacy}</a></p>
</footer>

</main>
</body>
</html>
"""


def language_links(current: str) -> str:
    links = []
    for code, name in LANGUAGE_NAMES.items():
        current_attr = ' aria-current="page"' if code == current else ""
        links.append(f'  <a href="manual-{code}.html" lang="{code}"{current_attr}>{name}</a>')
    return "\n".join(links)


def build() -> None:
    for lang, meta in MANUALS.items():
        source = (DOCS / meta["source"]).read_text(encoding="utf-8")
        heading, subtitle, body = convert(source)
        page = PAGE.format(
            lang=lang,
            title=html.escape(meta["title"]),
            css=CSS,
            heading=inline(heading or meta["title"]),
            subtitle=inline(subtitle),
            languages=meta["languages"],
            back=meta["back"],
            language_links=language_links(lang),
            privacy=meta["privacy"],
            top=meta["top"],
            body=body,
        )
        target = WEBSITE / f"manual-{lang}.html"
        target.write_text(page, encoding="utf-8")
        print(f"wrote {target.relative_to(DOCS.parent)} ({len(page):,} bytes)")

    # Screenshots, including the per-language subfolders.
    target_images = WEBSITE / "images"
    if target_images.exists():
        shutil.rmtree(target_images)
    shutil.copytree(DOCS / "images", target_images)
    count = sum(1 for p in target_images.rglob("*") if p.is_file())
    print(f"copied {count} images to {target_images.relative_to(DOCS.parent)}")


if __name__ == "__main__":
    build()
