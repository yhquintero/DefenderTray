#!/usr/bin/env python3
"""Comprobación de enlaces relativos y anclas de la documentación.

Se ejecuta en la integración continua (`.github/workflows/ci.yml`) y sirve para
no publicar enlaces rotos tras mover, renombrar o reescribir un documento.

Comprueba, sobre todos los `.md` del repositorio:

1. que cada enlace relativo (`[texto](ruta)`, excluidos `http(s):`, `mailto:`
   y `data:`) apunta a un archivo o directorio que existe;
2. que cada ancla (`#fragmento`, propia o de otro `.md`) corresponde a un
   encabezado real, replicando el algoritmo de GitHub: se quitan etiquetas
   HTML y formato Markdown, se pasa a minúsculas, se eliminan los caracteres
   que no son letra, dígito, espacio, guion o subrayado (los emoji cuentan
   como tales, de ahí el guion inicial en `## 📦 Título`) y los espacios se
   convierten en guiones;
3. que no quedan marcadores de trabajo a medias (`TODO:`, `FIXME:`, `XXX:`,
   `<!-- pendiente`).

Uso local:   python3 .github/check_markdown_links.py
Código 0 si todo está correcto, 1 en caso contrario.
"""

from __future__ import annotations

import os
import re
import sys
import unicodedata

SKIP_DIRS = {".git", "node_modules", "Unselected files", "__pycache__", ".venv", "venv"}

# [texto](ruta) o [texto](ruta#ancla); el negativo evita los enlaces absolutos.
LINK_RE = re.compile(r"\[[^\]]*\]\((?!https?://|mailto:|data:)([^)\s#]*)(?:#([^)\s]+))?\)")
MARKER_RE = re.compile(r"\b(?:TODO|FIXME|XXX)\s*:|<!--\s*(?:pendiente|por hacer|todo\b)", re.I)


def slug(text: str) -> str:
    """Devuelve el ancla que generaría GitHub para el texto de un encabezado."""
    text = re.sub(r"<[^>]+>", "", text)                    # etiquetas HTML
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # enlaces internos del título
    text = re.sub(r"[`*_]", "", text)                      # formato
    text = text.lower()
    kept = [c for c in text if unicodedata.category(c)[0] in ("L", "N", "M") or c in " -_"]
    return "".join(kept).replace(" ", "-")


def markdown_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if name.endswith(".md"):
                yield os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")


def main() -> int:
    root = os.getcwd()
    files = list(markdown_files(root))
    bodies = {rel: open(rel, encoding="utf-8", errors="replace").read() for rel in files}

    anchors = {}
    for rel, body in bodies.items():
        found = {slug(m.group(1)) for m in re.finditer(r"^#{1,6}\s+(.*)$", body, re.M)}
        found |= {m.group(1) for m in re.finditer(r'<a\s+id="([^"]+)"', body, re.I)}
        anchors[rel] = found

    problems: list[str] = []
    for rel, body in bodies.items():
        folder = os.path.dirname(rel)

        for line_no, line in enumerate(body.splitlines(), start=1):
            if MARKER_RE.search(line):
                problems.append(f"{rel}:{line_no}: marcador de trabajo pendiente en la documentación")

        for target, fragment in LINK_RE.findall(body):
            if not target:                      # enlace tipo [x](#ancla)
                resolved_rel = rel
            else:
                resolved = os.path.normpath(os.path.join(folder, target))
                if not os.path.exists(resolved):
                    problems.append(f"{rel}: enlace roto -> {target}")
                    continue
                resolved_rel = resolved.replace(os.sep, "/")

            if fragment:
                known = anchors.get(resolved_rel)
                if known is None:               # apunta a un archivo que no es .md
                    continue
                if fragment not in known:
                    where = resolved_rel or rel
                    problems.append(f"{rel}: ancla inexistante #{fragment} en {where}")

    if problems:
        for problem in problems:
            print(problem)
        print(f"\n{len(problems)} problema(s) de documentación.", file=sys.stderr)
        return 1

    print(f"Documentación coherente: {len(files)} archivos .md con enlaces y anclas verificados.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
