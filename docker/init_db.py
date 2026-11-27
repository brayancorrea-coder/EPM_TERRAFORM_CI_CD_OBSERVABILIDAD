"""Inicializa el esquema de EPM la primera vez que el contenedor arranca.

- Espera a que MySQL acepte conexiones (RDS tarda unos segundos tras crearse).
- Usa GET_LOCK para que, si hay varios contenedores arrancando a la vez, solo uno cargue el esquema.
- Si la tabla `usuarios` ya existe NO toca nada (los datos nunca se borran).
- Ignora las sentencias DROP DATABASE / CREATE DATABASE / USE de schema.sql: la base
  de datos ya la crea RDS (variable db_name de Terraform) y el usuario no debe borrarla.

Configuracion por variables de entorno (las mismas que usa la app):
MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB, SCHEMA_FILE (opcional).
"""
import logging
import os
import re
import sys
import time

import mysql.connector

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s init_db: %(message)s")
log = logging.getLogger("init_db")

SALTAR = re.compile(r"^\s*(DROP\s+DATABASE|CREATE\s+DATABASE|USE)\b", re.IGNORECASE)


def dividir_sentencias(sql):
    """Separa un script SQL en sentencias respetando comillas y comentarios."""
    sentencias, actual = [], []
    i, n = 0, len(sql)
    comilla = None
    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""
        if comilla:
            actual.append(ch)
            if ch == "\\" and comilla != "`":
                actual.append(nxt)
                i += 2
                continue
            if ch == comilla:
                if nxt == comilla:  # comilla escapada ('')
                    actual.append(nxt)
                    i += 2
                    continue
                comilla = None
            i += 1
            continue
        if ch == "-" and nxt == "-" and (i + 2 >= n or sql[i + 2] in " \t\r\n"):
            while i < n and sql[i] != "\n":
                i += 1
            continue
        if ch == "#":
            while i < n and sql[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            fin = sql.find("*/", i + 2)
            i = n if fin == -1 else fin + 2
            continue
        if ch in ("'", '"', "`"):
            comilla = ch
            actual.append(ch)
            i += 1
            continue
        if ch == ";":
            texto = "".join(actual).strip()
            if texto:
                sentencias.append(texto)
            actual = []
            i += 1
            continue
        actual.append(ch)
        i += 1
    resto = "".join(actual).strip()
    if resto:
        sentencias.append(resto)
    return sentencias


def sentencias_a_ejecutar(sql):
    return [s for s in dividir_sentencias(sql) if not SALTAR.match(s)]


def conectar(reintentos=40, espera=3):
    cfg = dict(
        host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ.get("MYSQL_USER", "root"),
        password=os.environ.get("MYSQL_PASSWORD", ""),
        database=os.environ.get("MYSQL_DB", "epm_db"),
        charset="utf8mb4",
        connection_timeout=5,
    )
    for intento in range(1, reintentos + 1):
        try:
            return mysql.connector.connect(**cfg)
        except mysql.connector.Error as exc:
            log.warning("MySQL no disponible (%s/%s): %s", intento, reintentos, exc)
            time.sleep(espera)
    log.error("No se pudo conectar a MySQL; se aborta el arranque.")
    sys.exit(1)


def main():
    ruta = os.environ.get("SCHEMA_FILE", os.path.join(os.path.dirname(__file__), "..", "schema.sql"))
    with open(ruta, encoding="utf-8") as fh:
        sentencias = sentencias_a_ejecutar(fh.read())

    conn = conectar()
    cur = conn.cursor()
    try:
        cur.execute("SELECT GET_LOCK('epm_init_schema', 120)")
        if cur.fetchone()[0] != 1:
            log.error("No se obtuvo el lock de inicializacion.")
            sys.exit(1)

        cur.execute(
            "SELECT COUNT(*) FROM information_schema.tables "
            "WHERE table_schema = DATABASE() AND table_name = 'usuarios'"
        )
        if cur.fetchone()[0] > 0:
            log.info("El esquema ya existe: no se modifica nada.")
        else:
            log.info("Base vacia: cargando %s sentencias de schema.sql ...", len(sentencias))
            for sentencia in sentencias:
                cur.execute(sentencia)
            conn.commit()
            log.info("Esquema y datos iniciales cargados.")
        cur.execute("SELECT RELEASE_LOCK('epm_init_schema')")
        cur.fetchall()
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
