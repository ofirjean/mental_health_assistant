FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Use HTTPS mirrors first, then update/install CA + curl
RUN set -eux; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i -e 's|http://deb.debian.org|https://deb.debian.org|g' \
             -e 's|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list; \
    fi; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      sed -i -e 's|http://deb.debian.org|https://deb.debian.org|g' \
             -e 's|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list.d/debian.sources; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m pip install --upgrade pip setuptools wheel \
 && pip uninstall -y bson || true \
 && pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000
CMD ["python", "app.py"]
