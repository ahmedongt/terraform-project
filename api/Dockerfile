# 1. Use the slim version (Good choice!)
FROM python:3.11-slim

# 2. Prevent Python from writing .pyc files to disk (saves space)
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

WORKDIR /app

# 3. Install libraries (Layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Copy EVERYTHING in the current folder (app.py AND the static folder)
COPY . .

# 5. Document the port
EXPOSE 5000

CMD ["python", "app.py"]
