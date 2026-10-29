# Bases de la app de conductores

La explicación completa (arquitectura, base de datos, fases, backend, frontend, forma de trabajar y decisiones) está en **estructura-tecnica.html**, que se abre como ventana flotante desde la propuesta completa. Este archivo solo explica qué hay en esta carpeta.

## `db/`

| Archivo | Qué es |
|---|---|
| `fase0_cimientos.sql` … `fase8_adr_segunda_red.sql` | El esquema de PostgreSQL 16, una migración por fase. Se aplican en orden y cada una solo necesita las anteriores. |
| `datos_ejemplo.sql` | Un día de trabajo inventado (dos chóferes, dos camiones, repostajes, tickets, parte y monedas) para el entorno local. |
| `exportar_esquema.py` | Lee los SQL y actualiza la sección «Base de datos» de la ventana técnica. |

## Probarlo en local

```bash
docker run -d --name controldrive-db -e POSTGRES_PASSWORD=local -p 5432:5432 postgres:16
for f in bases/db/fase*_*.sql bases/db/datos_ejemplo.sql; do
  docker exec -i controldrive-db psql -U postgres -v ON_ERROR_STOP=1 < "$f"
done
```

## Después de cambiar un SQL

```bash
python3 bases/db/exportar_esquema.py
```

Sin dependencias (vale el Python 3.9 del Mac). Para que lo lea bien: una columna por línea, las restricciones de tabla empiezan por `CHECK`, `CONSTRAINT`, `PRIMARY KEY`, `UNIQUE`, `FOREIGN KEY` o `EXCLUDE`, y cada comentario es un `COMMENT ON … IS '…';` en una sola línea.

Cuando exista el repositorio de la app, estos SQL se copian a su carpeta `db/` y cada versión de Alembic ejecuta uno.
