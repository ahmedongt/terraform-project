FROM python:3.9-slim

# 1. Create a non-root user named user-1 for security
RUN useradd -m user-1

WORKDIR /app

# 2. Install system dependencies for image processing (Pillow)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Copy requirements and ensure user-1 owns the file
COPY --chown=user-1:user-1 requirements.txt .

# 4. Security and optimization environment variables
ENV PIP_NO_CACHE_DIR=1

# 5. Switch to the non-root user to install dependencies and run the app
USER user-1
RUN pip install --no-cache-dir --user --only-binary :all: -r requirements.txt

# 6. Copy application code and ensure user-1 owns it
COPY --chown=user-1:user-1 app.py .

# Add the local user-1 bin folder to the PATH so Python can find the libraries
ENV PATH="/home/user-1/.local/bin:${PATH}"

EXPOSE 5000

CMD ["python", "app.py"]