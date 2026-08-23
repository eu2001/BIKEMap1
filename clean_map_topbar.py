#!/usr/bin/env python3
# Surgical cleanup of lib/screens/map_screen.dart:
#   - Top bar keeps only the hamburger (_openLayersPanel) button.
#   - Removes _LogoBadge / _RankingBadge / _AvatarBadge from the top Row.
#   - Recolors the "Adicionar bicicletario" FAB from green to app-blue.
# Leaves everything else (dead widget classes, imports) untouched so this
# is easy to review with `git diff` and roll back if anything looks off.

import re
import sys
from pathlib import Path

PATH = Path.home() / "Documents/Apps/bikemap_sjc/lib/screens/map_screen.dart"
BLUE = "const Color(0xFF1A56DB)"

src = PATH.read_text()
original = src

# --- 1) Top bar: strip everything after the hamburger _MapButton inside the Row.
row_pattern = re.compile(
    r"""Row\(\s*
        children:\s*\[\s*
        (_MapButton\(\s*icon:\s*const\s+Icon\(Icons\.menu\)[^)]*onTap:\s*_openLayersPanel\s*\))
        .*?
        \]\s*,?\s*\)""",
    re.DOTALL | re.VERBOSE,
)

def _replace_row(m):
    hamburger = m.group(1)
    return f"Row(\n              children: [\n                {hamburger},\n              ],\n            )"

src, n_row = row_pattern.subn(_replace_row, src, count=1)
if n_row == 0:
    print("!! could not find the top-bar Row - nothing changed.", file=sys.stderr)
    sys.exit(1)

# --- 2) FAB color: green.shade600 -> app blue.
src, n_fab = re.subn(
    r"backgroundColor:\s*Colors\.green\.shade600",
    f"backgroundColor: {BLUE}",
    src,
    count=1,
)
if n_fab == 0:
    print("!! could not find the FAB backgroundColor - top bar changes still applied.", file=sys.stderr)

if src == original:
    print("no changes made.")
    sys.exit(0)

PATH.write_text(src)
print(f"patched: top-bar Row rewritten ({n_row}), FAB recolored ({n_fab}).")
print(f"-> {PATH}")
