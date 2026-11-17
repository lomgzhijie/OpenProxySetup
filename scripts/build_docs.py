"""Render the website docs from the project READMEs.

Install markdown-it-py==4.0.0, then run:
    python scripts/build_docs.py <OpenProxySetup main checkout>
"""

import argparse
from html import escape
from pathlib import Path
import re
from urllib.parse import urljoin

from markdown_it import MarkdownIt
from markdown_it.token import Token

SITE = Path(__file__).resolve().parents[1]
REPO = "https://github.com/lomgzhijie/OpenProxySetup"
LANGUAGES = {
    "zh-CN": ("简体中文", "README.md", "index.html", "使用文档", "首页", "下载", "本页目录", "语言"),
    "en": ("English", "README.en.md", "en.html", "Documentation", "Home", "Download", "On this page", "Language"),
    "ja": ("日本語", "README.ja.md", "ja.html", "ドキュメント", "ホーム", "ダウンロード", "このページの目次", "言語"),
    "ko": ("한국어", "README.ko.md", "ko.html", "문서", "홈", "다운로드", "이 페이지의 목차", "언어"),
}
READMES = {values[1]: lang for lang, values in LANGUAGES.items()}


def doc_path(lang: str) -> str:
    return "./" if lang == "zh-CN" else LANGUAGES[lang][2]


def render_readme(source: str, lang: str) -> tuple[str, str]:
    # The shared page header replaces the README's language switcher.
    source = re.sub(r"^\[简体中文\]\(README\.md\).*\n", "", source, count=1, flags=re.MULTILINE)
    markdown = MarkdownIt("js-default")
    tokens = markdown.parse(source)
    toc: list[str] = []
    anchors: set[str] = set()
    for index, token in enumerate(tokens):
        if token.type == "heading_open" and token.tag == "h2":
            label = tokens[index + 1].content
            slug = re.sub(r"[^\w-]+", "-", label.lower()).strip("-") or "section"
            anchor = slug
            suffix = 2
            while anchor in anchors:
                anchor = f"{slug}-{suffix}"
                suffix += 1
            anchors.add(anchor)
            token.attrSet("id", anchor)
            toc.append(f'<li><a href="#{escape(anchor)}">{escape(label)}</a></li>')
        for child in token.children or ():
            if child.type != "link_open":
                continue
            href = child.attrGet("href")
            if href in READMES:
                child.attrSet("href", doc_path(READMES[href]))
            elif href == f"{REPO}/releases/latest":
                child.attrSet("href", f"../?lang={lang}#downloads")
            elif href and not href.startswith(("#", "https://", "http://", "mailto:")):
                child.attrSet("href", urljoin(f"{REPO}/blob/main/", href))

    # Keep wide compatibility tables independently scrollable on phones.
    table_label = {"zh-CN": "客户端适配情况", "en": "Client compatibility", "ja": "対応クライアント", "ko": "지원 클라이언트"}[lang]
    wrapped: list[Token] = []
    for token in tokens:
        if token.type == "table_open":
            wrapped.append(Token("html_block", "", 0, content=f'<div class="docs-table" role="region" aria-label="{table_label}" tabindex="0">\n'))
        wrapped.append(token)
        if token.type == "table_close":
            wrapped.append(Token("html_block", "", 0, content="</div>\n"))
    article = markdown.renderer.render(wrapped, markdown.options, {})
    return article, "\n".join(toc)


def build_page(project: Path, lang: str) -> str:
    _, readme, _, title, home, download, contents, language = LANGUAGES[lang]
    article, toc = render_readme((project / readme).read_text(encoding="utf-8-sig"), lang)
    choices = []
    for locale, (label, *_) in LANGUAGES.items():
        current = ' aria-current="page"' if locale == lang else ""
        choices.append(f'<a href="{doc_path(locale)}" hreflang="{locale}" lang="{locale}"{current}>{label}</a>')
    switches = "\n      ".join(choices)
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#f6f8fc">
<title>{title} · OpenProxySetup</title>
<link rel="icon" type="image/png" sizes="64x64" href="../openproxysetup-icon.png">
<link rel="stylesheet" href="../style.css?v=docs">
</head>
<body>
<header class="top">
  <div class="shell nav">
    <a class="brand" href="../?lang={lang}"><img class="mark" src="../openproxysetup-icon.png" width="35" height="35" alt="">OpenProxySetup</a>
    <nav aria-label="{home}">
      <a href="../?lang={lang}">{home}</a>
      <a href="../?lang={lang}#downloads">{download}</a>
    </nav>
  </div>
</header>
<main class="shell docs-layout">
  <div class="docs-toolbar">
    <p class="docs-title">{title}</p>
    <nav class="docs-languages" aria-label="{language}">
      {switches}
    </nav>
  </div>
  <aside class="docs-sidebar">
    <nav aria-label="{contents}">
      <p>{contents}</p>
      <ul>{toc}</ul>
    </nav>
  </aside>
  <article class="docs-article">
{article}
  </article>
</main>
<footer class="shell footer"><a class="brand" href="../?lang={lang}">OpenProxySetup</a></footer>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    project = parser.parse_args().project
    pages = {values[2]: build_page(project, lang) for lang, values in LANGUAGES.items()}
    docs = SITE / "docs"
    docs.mkdir(exist_ok=True)
    for filename, page in pages.items():
        (docs / filename).write_text(page, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
