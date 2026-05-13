FROM python:3.9-slim

WORKDIR /app

# Install necessary system dependencies for Pillow (libjpeg, zlib)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# FIX: Use --no-cache-dir and --only-binary to satisfy SonarCloud security requirements
RUN pip install --no-cache-dir --only-binary :all: -r requirements.txt

COPY . .

# Expose the port your app runs on
EXPOSE 5000

CMD ["python", "app.py"]