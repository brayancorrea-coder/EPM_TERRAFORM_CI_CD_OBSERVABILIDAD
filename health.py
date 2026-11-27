"""Endpoints de salud para el balanceador (ALB), el contenedor y el monitoreo.

/health        -> liveness: el proceso responde. No toca la base de datos, para que
                  una caida momentanea de MySQL no haga que el ALB mate los contenedores.
/health/ready  -> readiness: verifica MySQL (y el cache si esta habilitado).
                  Devuelve 503 si MySQL no responde. Util para diagnostico y alarmas.
"""
import time

from flask import Blueprint, jsonify

import cache
from db import get_db

bp = Blueprint("health", __name__)

_INICIO = time.time()


@bp.route("/health")
def liveness():
    return jsonify(status="ok", uptime_s=int(time.time() - _INICIO)), 200


@bp.route("/health/ready")
def readiness():
    checks = {}
    ok = True

    try:
        cur = get_db().cursor()
        cur.execute("SELECT 1")
        cur.fetchall()
        cur.close()
        checks["mysql"] = "ok"
    except Exception as exc:  # noqa: BLE001
        ok = False
        checks["mysql"] = f"error: {exc.__class__.__name__}"

    # El cache es opcional: su caida no vuelve "no listo" al servicio.
    checks["cache"] = cache.ping()

    return jsonify(status="ok" if ok else "degraded", checks=checks), (200 if ok else 503)
