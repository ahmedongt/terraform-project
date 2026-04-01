import io
import os
from flask import Flask, request, send_file, jsonify, send_from_directory
from flask_cors import CORS
import requests

app = Flask(__name__)
CORS(app)

# 1. SET UP THE STORAGE FOLDER
# Using the absolute path where Nginx/S3 stores your files
BASE_DIR = '/var/www/html'
DOWNLOAD_FOLDER = os.path.join(BASE_DIR, 'downloads')

if not os.path.exists(DOWNLOAD_FOLDER):
    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True)

# --- THE MISSING "FRONT DOOR" ROUTE ---
@app.route('/')
def home():
    # This serves your index.html when you visit the main domain
    return send_from_directory(BASE_DIR, 'index.html')

def get_video_id(url):
    if 'youtu.be/' in url:
        return url.split('/')[-1].split('?')[0]
    elif 'v=' in url:
        return url.split('v=')[-1].split('&')[0]
    return None

# 2. THE MAIN ROUTE: GRAB AND SAVE THUMBNAIL
@app.route('/get-thumb', methods=['GET'])
def get_thumbnail():
    video_url = request.args.get('url')
    if not video_url:
        return jsonify({"error": "No URL provided"}), 400

    video_id = get_video_id(video_url)
    if not video_id:
        return jsonify({"error": "Invalid YouTube URL"}), 400

    thumb_url = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
    response = requests.get(thumb_url)
    
    if response.status_code != 200:
        thumb_url = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
        response = requests.get(thumb_url)

    if response.status_code == 200:
        filename = f"thumb_{video_id}.jpg"
        file_path = os.path.join(DOWNLOAD_FOLDER, filename)

        # Physically save the file to the AWS server
        with open(file_path, 'wb') as f:
            f.write(response.content)

        # Send back the URL paths for the frontend
        return jsonify({
            "filename": filename,
            "view_url": f"/view/{filename}",
            "delete_url": f"/delete/{filename}"
        }), 200
    
    return jsonify({"error": "Failed to fetch thumbnail"}), 500

# 3. THE VIEW ROUTE: ALLOWS BROWSER TO SEE THE IMAGE
@app.route('/view/<filename>')
def view_file(filename):
    return send_from_directory(DOWNLOAD_FOLDER, filename)

# 4. THE DELETE ROUTE: WIPES FILE FROM SERVER
@app.route('/delete/<filename>', methods=['DELETE', 'GET'])
def delete_file(filename):
    file_path = os.path.join(DOWNLOAD_FOLDER, filename)
    if os.path.exists(file_path):
        os.remove(file_path)
        return jsonify({"message": "File deleted from server"}), 200
    return jsonify({"error": "File not found"}), 404

if __name__ == '__main__':
    # Run on all interfaces so Nginx can talk to it
    app.run(host='0.0.0.0', port=5000)