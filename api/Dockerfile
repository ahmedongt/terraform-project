FROM python:3.9-slim

# 1. Create a non-root user
RUN useradd -m user-1

WORKDIR /app

# 2. Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Copy requirements (Read-only for Sonar compliance)
COPY --chown=user-1:user-1 requirements.txt .
USER root
RUN chmod 444 requirements.txt

# 4. Security environment variables
ENV PIP_NO_CACHE_DIR=1
ENV PATH="/home/user-1/.local/bin:${PATH}"

# 5. Install dependencies as user-1
USER user-1
RUN pip install --no-cache-dir --user --only-binary=:all: -r requirements.txt

# 6. Setup writable directories as ROOT
USER root
RUN mkdir -p /app/downloads /app/static && \
    chown -R user-1:user-1 /app/downloads /app/static && \
    chmod -R 755 /app/downloads /app/static

# 7. Copy app code as READ-ONLY (Fixes "Make sure no write permissions are assigned")
COPY --chown=user-1:user-1 app.py .
USER root
RUN chmod 444 app.py

# 8. Final switch to non-root user
USER user-1

EXPOSE 5000

# Execute via production-grade Gunicorn server natively inside the image
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]