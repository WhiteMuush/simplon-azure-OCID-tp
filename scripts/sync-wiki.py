#!/usr/bin/env python3
"""Adapt a GitLab wiki checkout into a GitHub wiki checkout.

Reads every .md page from SRC (a cloned GitLab wiki), rewrites it to the
GitHub wiki conventions (Home page, flat names, fixed relative links),
writes the result into DEST (a cloned GitHub wiki) and regenerates _Sidebar.md.

Usage: sync-wiki.py <src_dir> <dest_dir>
"""
import re
import sys
from pathlib import Path


def to_github_name(slug):
    """home -> Home, TP/Enonce -> TP-Enonce."""
    if slug.lower() == "home":
        return "Home"
    return slug.replace("/", "-")


def fix_links(text):
    """Adapt relative wiki links to the GitHub naming."""
    def repl(m):
        label, target = m.group(1), m.group(2)
        if target.startswith(("http://", "https://", "#")):
            return m.group(0)
        target = "Home" if target.lower() == "home" else target.replace("/", "-")
        return f"[{label}]({target})"
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", repl, text)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])

    for old in dest.glob("*.md"):
        old.unlink()

    names = []
    for page in sorted(src.rglob("*.md")):
        slug = page.relative_to(src).with_suffix("").as_posix()
        name = to_github_name(slug)
        (dest / f"{name}.md").write_text(fix_links(page.read_text(encoding="utf-8")),
                                         encoding="utf-8")
        names.append(name)
        print(f"  {slug}  ->  {name}.md")

    if not names:
        sys.exit("No GitLab wiki page found.")

    ordered = (["Home"] if "Home" in names else []) + sorted(n for n in names if n != "Home")
    sidebar = "\n".join(f"- [{n.replace('-', ' ')}]({n})" for n in ordered)
    (dest / "_Sidebar.md").write_text(sidebar + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
