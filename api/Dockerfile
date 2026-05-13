FROM python:3.9-slim

WORKDIR /app

# 1. Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Copy the locked requirements
COPY requirements.txt .

# 3. Security environment variables
ENV PIP_NO_CACHE_DIR=1

# 4. Install dependencies 
# SonarCloud prefers this clean format when versions are already in the .txt file
RUN pip install --no-cache-dir -r requirements.txt

# 5. Copy application code
COPY . .

EXPOSE 5000

CMD ["python", "app.py"]