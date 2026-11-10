FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8000

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN useradd -m -u 1001 appuser && chown -R appuser:appuser /app

EXPOSE 8000
# Railway monte le volume en root : le conteneur démarre root, donne le dossier
# de stockage à appuser, puis l'API tourne sous appuser (setpriv).
# Forme « shell » : $PORT et $WEB_CONCURRENCY sont développés au lancement.
CMD D=${STOCKAGE_DIR:-/data/fichiers}; mkdir -p "$D" && chown appuser:appuser /data "$D"; HOME=/home/appuser exec setpriv --reuid=1001 --regid=1001 --init-groups uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*' --workers ${WEB_CONCURRENCY:-2}
