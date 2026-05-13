FROM python:3.9-slim

WORKDIR /app

# 1. Install system dependencies for image processing (Pillow)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Copy the locked requirements (verified with == versions)
COPY requirements.txt .

# 3. Security and optimization environment variables
ENV PIP_NO_CACHE_DIR=1

# 4. Install dependencies 
# FIX: Added --only-binary :all: to prevent execution of source setup scripts
RUN pip install --no-cache-dir --only-binary :all: -r requirements.txt

# 5. Copy application code
COPY . .

EXPOSE 5000

CMD ["python", "app.py"]