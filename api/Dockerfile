FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# FIX: We use --require-hashes or strict versioning via requirements.txt
# We add PIP_NO_CACHE_DIR to double-confirm the security policy
ENV PIP_NO_CACHE_DIR=1

RUN pip install --only-binary :all: -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]