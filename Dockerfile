# Imagen de la aplicacion EPM (Flask + Gunicorn).
# Se construye en CI (GitHub Actions), se publica en Amazon ECR y se ejecuta en ECS Fargate.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Usuario sin privilegios: el contenedor no corre como root
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin epm

# Dependencias primero (aprovecha la cache de capas de Docker)
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
RUN chmod +x /app/docker/entrypoint.sh

USER epm
EXPOSE 8000

# Health check del contenedor (el ALB y ECS usan ademas su propio chequeo contra /health)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200 else 1)"

ENTRYPOINT ["/app/docker/entrypoint.sh"]
# Logs de acceso y de error a stdout/stderr -> CloudWatch Logs (driver awslogs)
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "4", \
     "--access-logfile", "-", "--error-logfile", "-", "--log-level", "info", "wsgi:application"]
