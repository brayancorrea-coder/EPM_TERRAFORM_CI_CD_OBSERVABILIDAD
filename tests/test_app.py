"""Pruebas automaticas de la parte de aplicacion (se ejecutan en el pipeline de CI)."""
import importlib
import os
import sys
from decimal import Decimal

import pytest

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "docker"))


@pytest.fixture()
def cliente(monkeypatch):
    # MySQL inexistente a proposito: /health no debe depender de la base
    monkeypatch.setenv("MYSQL_HOST", "127.0.0.1")
    monkeypatch.setenv("MYSQL_PORT", "1")
    monkeypatch.delenv("CACHE_HOST", raising=False)
    import app as app_mod

    importlib.reload(app_mod)
    app_mod.app.config["TESTING"] = True
    return app_mod.app.test_client()


def test_liveness_no_depende_de_mysql(cliente):
    r = cliente.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_readiness_devuelve_503_si_mysql_cae(cliente):
    r = cliente.get("/health/ready")
    assert r.status_code == 503
    datos = r.get_json()
    assert datos["status"] == "degraded"
    assert datos["checks"]["mysql"].startswith("error")
    assert datos["checks"]["cache"] == "deshabilitado"


def test_login_responde(cliente):
    assert cliente.get("/login").status_code == 200


def test_cache_deshabilitado_ejecuta_loader(monkeypatch):
    import cache

    monkeypatch.delenv("CACHE_HOST", raising=False)
    assert cache.cached("k", 5, lambda: {"a": 1}) == {"a": 1}


def test_cache_guarda_y_lee_decimal(monkeypatch):
    import cache

    class Falso:
        def __init__(self):
            self.d = {}

        def get(self, k):
            return self.d.get(k)

        def setex(self, k, ttl, v):
            self.d[k] = v

    falso = Falso()
    monkeypatch.setenv("CACHE_HOST", "x")
    monkeypatch.setattr(cache, "_client", falso)
    llamadas = []

    def loader():
        llamadas.append(1)
        return {"presupuesto": Decimal("1234.50"), "n": 3}

    assert cache.cached("clave", 15, loader)["presupuesto"] == Decimal("1234.50")
    assert cache.cached("clave", 15, loader)["presupuesto"] == Decimal("1234.50")
    assert len(llamadas) == 1  # la segunda lectura salio del cache


def test_cache_no_tumba_la_app_si_falla(monkeypatch):
    import cache

    class Roto:
        def get(self, k):
            raise ConnectionError("caido")

    monkeypatch.setenv("CACHE_HOST", "x")
    monkeypatch.setattr(cache, "_client", Roto())
    assert cache.cached("k", 5, lambda: 42) == 42


def test_schema_se_divide_y_se_omite_drop_create_use():
    import init_db

    with open(os.path.join(RAIZ, "schema.sql"), encoding="utf-8") as fh:
        sql = fh.read()
    todas = init_db.dividir_sentencias(sql)
    utiles = init_db.sentencias_a_ejecutar(sql)
    assert len(todas) - len(utiles) == 3  # DROP DATABASE, CREATE DATABASE, USE
    assert sum(1 for s in utiles if s.upper().startswith("CREATE TABLE")) == 6
    assert not any(s.upper().startswith(("DROP DATABASE", "CREATE DATABASE", "USE ")) for s in utiles)


def test_divisor_respeta_comillas_y_comentarios():
    import init_db

    sql = "-- hola; mundo\nINSERT INTO t VALUES ('a;b', 'it''s'); /* x; y */ SELECT 1;"
    assert init_db.dividir_sentencias(sql) == ["INSERT INTO t VALUES ('a;b', 'it''s')", "SELECT 1"]
