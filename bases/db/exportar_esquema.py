"""Lee los SQL de las fases y actualiza la sección «Base de datos» de la ventana técnica.

Uso (desde la raíz del repositorio):
    python3 bases/db/exportar_esquema.py

No necesita base de datos ni dependencias: lee los archivos fase*_*.sql, saca
tablas, columnas, vistas, funciones, comentarios, interruptores y parámetros, y
los escribe como JSON dentro de estructura-tecnica.html, entre las marcas
<!-- esquema:inicio --> y <!-- esquema:fin -->.

Para que el lector funcione, los SQL siguen tres normas de formato:
  · una columna por línea, con dos espacios de sangría;
  · las restricciones de tabla empiezan por CHECK, CONSTRAINT, PRIMARY KEY,
    UNIQUE, FOREIGN KEY o EXCLUDE (y sus continuaciones van más sangradas);
  · los comentarios se escriben con COMMENT ON … IS '…'; en una sola línea.
"""

import datetime
import json
import re
from pathlib import Path

DIR = Path(__file__).resolve().parent
HTML = DIR.parent.parent / "estructura-tecnica.html"

PALABRAS_RESTRICCION = ("CHECK", "CONSTRAINT", "PRIMARY", "UNIQUE", "FOREIGN", "EXCLUDE")
FIN_DE_TIPO = re.compile(r"\s+(NOT NULL|NULL|DEFAULT|REFERENCES|PRIMARY KEY|UNIQUE|CHECK|GENERATED)\b")
COMENTARIO = re.compile(
    r"COMMENT ON (SCHEMA|TABLE|VIEW|COLUMN|FUNCTION|CONSTRAINT)\s+([\w.]+)(?:\([^)]*\))?(?:\s+ON\s+([\w.]+))?\s+IS\s+'((?:[^']|'')*)';"
)
INTERRUPTOR = re.compile(r"\('(\w+)',\s*'((?:[^']|'')*)',\s*(\d),\s*'((?:[^']|'')*)'\)")
PARAMETRO = re.compile(
    r"\('([\w.]+)',\s*'((?:[^']|'')*)',\s*(NULL|'(?:[^']|'')*'),\s*'([\d-]+)',\s*'((?:[^']|'')*)'\)"
)


def texto(sql_literal):
    return sql_literal.replace("''", "'")


def leer_cabecera(sql):
    """Título y resumen del bloque de comentarios del principio del archivo."""
    lineas = [l[2:].strip() for l in sql.splitlines() if l.startswith("--")]
    titulo, resumen, dentro = "", [], False
    for l in lineas:
        if l.startswith("FASE"):
            titulo, dentro = l, True
        elif dentro and set(l) <= set("-="):
            if resumen:
                break
        elif dentro:
            resumen.append(l)
    return titulo, " ".join(resumen)


def leer_columnas(cuerpo):
    columnas, pk_tabla, fk_tabla = [], set(), {}
    for linea in cuerpo.splitlines():
        if not linea.startswith("  ") or linea.startswith("   "):
            continue
        limpia = linea.strip().rstrip(",")
        primera = limpia.split()[0]
        if primera in PALABRAS_RESTRICCION:
            m = re.match(r"PRIMARY KEY \(([^)]*)\)", limpia)
            if m:
                pk_tabla.update(c.strip() for c in m.group(1).split(","))
            m = re.match(r"FOREIGN KEY \(([^)]*)\) REFERENCES ([\w.]+)", limpia)
            if m:
                for c in m.group(1).split(","):
                    fk_tabla[c.strip()] = m.group(2)
            continue
        nombre, resto = limpia.split(None, 1)
        corte = FIN_DE_TIPO.search(" " + resto)
        tipo = (" " + resto)[: corte.start()].strip() if corte else resto
        ref = re.search(r"REFERENCES ([\w.]+)", resto)
        columnas.append({
            "nombre": nombre,
            "tipo": tipo,
            "pk": "PRIMARY KEY" in resto,
            "nn": "NOT NULL" in resto or "PRIMARY KEY" in resto,
            "unico": bool(re.search(r"\bUNIQUE\b", resto)),
            "fk": ref.group(1) if ref else None,
            "calculada": "GENERATED ALWAYS AS (" in resto,
        })
    for c in columnas:
        if c["nombre"] in pk_tabla:
            c["pk"] = c["nn"] = True
        if c["nombre"] in fk_tabla and not c["fk"]:
            c["fk"] = fk_tabla[c["nombre"]]
    return columnas


def main():
    fases, objetos, funciones_sql, interruptores, parametros, esquemas = [], {}, [], [], [], {}
    comentarios = []

    for archivo in sorted(DIR.glob("fase[0-9]_*.sql")):
        sql = archivo.read_text(encoding="utf-8")
        n = int(archivo.name[4])
        titulo, resumen = leer_cabecera(sql)
        fases.append({"n": n, "archivo": f"bases/db/{archivo.name}", "titulo": titulo, "resumen": resumen})

        for m in re.finditer(r"CREATE TABLE (\w+)\.(\w+) \((.*?)\n\);", sql, re.S):
            clave = f"{m.group(1)}.{m.group(2)}"
            objetos[clave] = {"esquema": m.group(1), "nombre": m.group(2), "fase": n, "tipo": "tabla",
                              "descripcion": "", "columnas": leer_columnas(m.group(3)), "reglas": []}
        for m in re.finditer(r"CREATE VIEW (\w+)\.(\w+) AS", sql):
            clave = f"{m.group(1)}.{m.group(2)}"
            objetos[clave] = {"esquema": m.group(1), "nombre": m.group(2), "fase": n, "tipo": "vista",
                              "descripcion": "", "columnas": [], "reglas": []}
        for m in re.finditer(r"CREATE FUNCTION (\w+)\.(\w+)\(", sql):
            funciones_sql.append({"nombre": f"{m.group(1)}.{m.group(2)}", "fase": n, "descripcion": ""})

        for bloque in re.findall(r"INSERT INTO sistema\.funciones .*?\);\n", sql, re.S):
            for m in INTERRUPTOR.finditer(bloque):
                interruptores.append({"codigo": m.group(1), "nombre": texto(m.group(2)),
                                      "fase": int(m.group(3)), "descripcion": texto(m.group(4))})
        for bloque in re.findall(r"INSERT INTO sistema\.parametros .*?\);\n", sql, re.S):
            for m in PARAMETRO.finditer(bloque):
                unidad = None if m.group(3) == "NULL" else texto(m.group(3)[1:-1])
                parametros.append({"clave": m.group(1), "valor": texto(m.group(2)), "unidad": unidad,
                                   "vigente_desde": m.group(4), "descripcion": texto(m.group(5)), "fase": n})
        comentarios += COMENTARIO.findall(sql)

    funciones_por_nombre = {f["nombre"]: f for f in funciones_sql}
    for clase, objetivo, tabla, valor in comentarios:
        valor = texto(valor)
        if clase == "SCHEMA":
            esquemas[objetivo] = valor
        elif clase in ("TABLE", "VIEW") and objetivo in objetos:
            objetos[objetivo]["descripcion"] = valor
        elif clase == "COLUMN":
            esquema, tabla_col, columna = objetivo.split(".")
            for c in objetos.get(f"{esquema}.{tabla_col}", {}).get("columnas", []):
                if c["nombre"] == columna:
                    c["descripcion"] = valor
        elif clase == "FUNCTION" and objetivo in funciones_por_nombre:
            funciones_por_nombre[objetivo]["descripcion"] = valor
        elif clase == "CONSTRAINT" and tabla in objetos:
            objetos[tabla]["reglas"].append(valor)

    datos = {
        "generado": datetime.date.today().isoformat(),
        "esquemas": esquemas,
        "fases": fases,
        "objetos": list(objetos.values()),
        "funciones": funciones_sql,
        "interruptores": interruptores,
        "parametros": parametros,
    }
    carga = json.dumps(datos, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    html = HTML.read_text(encoding="utf-8")
    nuevo, cambios = re.subn(
        r"(<!-- esquema:inicio -->).*?(<!-- esquema:fin -->)",
        lambda m: f'{m.group(1)}\n<script type="application/json" id="esquema">{carga}</script>\n{m.group(2)}',
        html, flags=re.S,
    )
    if not cambios:
        raise SystemExit(f"No encuentro las marcas <!-- esquema:inicio --> y <!-- esquema:fin --> en {HTML.name}")
    HTML.write_text(nuevo, encoding="utf-8")
    tablas = sum(o["tipo"] == "tabla" for o in objetos.values())
    vistas = sum(o["tipo"] == "vista" for o in objetos.values())
    print(f"{HTML.name}: {len(fases)} fases, {tablas} tablas, {vistas} vistas, "
          f"{len(funciones_sql)} funciones, {len(parametros)} parámetros, {len(interruptores)} interruptores")


if __name__ == "__main__":
    main()
