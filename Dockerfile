FROM python:3.13-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Driver oficial de Microsoft para conexiones cifradas a Azure SQL Database.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg unixodbc unixodbc-dev \
    && curl -sSL -o packages-microsoft-prod.deb https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./
RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && mkdir -p /tmp/reportes-uploads \
    && chown -R appuser:appuser /app /tmp/reportes-uploads

USER appuser
EXPOSE 10000

CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT:-10000} --workers ${WEB_CONCURRENCY:-2} --timeout 120 --access-logfile - --error-logfile - wsgi:app"]
