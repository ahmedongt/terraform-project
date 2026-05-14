FROM python:3.9-slim

# 1. Create a non-root user
RUN useradd -m user-1

WORKDIR /app

# 2. Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Copy requirements (Read-only as requested for Sonar)
COPY --chown=user-1:user-1 --chmod=444 requirements.txt .

ENV PIP_NO_CACHE_DIR=1
ENV PATH="/home/user-1/.local/bin:${PATH}"

# 4. Install dependencies as the user
USER user-1
RUN pip install --no-cache-dir --user -r requirements.txt

# 5. Switch back to ROOT temporarily to set up infrastructure
USER root

# 6. Pre-create directories and set OWNERSHIP to user-1
# This ensures the app doesn't have to "create" them, just write to them.
RUN mkdir -p /app/downloads /app/static && \
    chown -R user-1:user-1 /app/downloads /app/static && \
    chmod -R 755 /app/downloads /app/static

# 7. Copy app code (Read-only for security hotspots)
COPY --chown=user-1:user-1 --chmod=444 app.py .

# 8. Final switch to non-root user
USER user-1

EXPOSE 5000

CMD ["python", "app.py"]