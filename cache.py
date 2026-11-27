"""Cache opcional en memoria (Valkey/Redis) para el dashboard de EPM.

Si la variable de entorno CACHE_HOST no existe, todas las funciones son
transparentes: se ejecuta el loader y no se toca ninguna red. Por eso el mismo
contenedor funciona con o sin ElastiCache (variable enable_cache en Terraform).
Si el cache falla en tiempo de ejecucion, la aplicacion sigue funcionando con
MySQL (degradacion elegante) y se deja un WARNING en el log.
"""
import json
import logging
import os
from decimal import Decimal

log = logging.getLogger("epm.cache")

_client = None


def habilitado():
    return bool(os.environ.get("CACHE_HOST"))


def _cliente():
    global _client
    if not habilitado():
        return None
    if _client is None:
        import redis  # import perezoso: solo si el cache esta habilitado

        _client = redis.Redis(
            host=os.environ["CACHE_HOST"],
            port=int(os.environ.get("CACHE_PORT", "6379")),
            socket_connect_timeout=0.5,
            socket_timeout=0.5,
            decode_responses=True,
        )
    return _client


def _default(obj):
    if isinstance(obj, Decimal):
        return {"__decimal__": str(obj)}
    raise TypeError(f"No serializable: {type(obj)!r}")


def _hook(obj):
    if "__decimal__" in obj:
        return Decimal(obj["__decimal__"])
    return obj


def dumps(valor):
    return json.dumps(valor, default=_default)


def loads(texto):
    return json.loads(texto, object_hook=_hook)


def cached(clave, ttl, loader):
    """Devuelve loader() usando el cache con TTL (segundos) cuando esta habilitado."""
    c = _cliente()
    if c is None:
        return loader()
    try:
        crudo = c.get(clave)
        if crudo is not None:
            return loads(crudo)
    except Exception as exc:  # noqa: BLE001 - el cache nunca debe tumbar la app
        log.warning("cache GET fallo (%s): %s", clave, exc.__class__.__name__)
        return loader()
    valor = loader()
    try:
        c.setex(clave, ttl, dumps(valor))
    except Exception as exc:  # noqa: BLE001
        log.warning("cache SET fallo (%s): %s", clave, exc.__class__.__name__)
    return valor


def ping():
    """Devuelve 'ok', 'deshabilitado' o 'error: <Tipo>' (para /health/ready)."""
    c = _cliente()
    if c is None:
        return "deshabilitado"
    try:
        c.ping()
        return "ok"
    except Exception as exc:  # noqa: BLE001
        return f"error: {exc.__class__.__name__}"
