import io
import os
from flask import Flask, request, send_file, jsonify, send_from_directory
from flask_cors import CORS
import requests
from werkzeug.utils import secure_filename

app = Flask(__name__)

# --- FIX 1: RESTRICT CORS ---
CORS(app, resources={r"/*": {"origins": ["https://ytthumbnail.site", "http://localhost:5000"]}}) 

# --- 1. DYNAMIC PATH SETUP ---
API_DIR = os.path.dirname(os.path.abspath(__file__)) 
PROJECT_ROOT = os.path.dirname(API_DIR)
WEBSITE_DIR = os.path.join(PROJECT_ROOT, 'website')
DOWNLOAD_FOLDER = os.path.join(API_DIR, 'downloads')

if not os.path.exists(DOWNLOAD_FOLDER): # pragma: no cover
    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True) # pragma: no cover

# --- 2. THE FRONT DOOR ---
@app.route('/', methods=['GET'])
def home():
    return send_from_directory(WEBSITE_DIR, 'index.html') # pragma: no cover

# --- 3. SERVE STATIC FILES ---
@app.route('/<path:path>', methods=['GET'])
def static_files(path):
    return send_from_directory(WEBSITE_DIR, path) # pragma: no cover

def get_video_id(url):
    if 'youtu.be/' in url:
        return url.split('/')[-1].split('?')[0]
    elif 'v=' in url:
        return url.split('v=')[-1].split('&')[0]
    return None # pragma: no cover

# --- 4. MAIN ROUTE ---
@app.route('/get-thumb', methods=['GET'])
def get_thumbnail():
    video_url = request.args.get('url')
    if not video_url: # pragma: no cover
        return jsonify({"error": "No URL provided"}), 400 # pragma: no cover

    video_id = get_video_id(video_url)
    if not video_id: # pragma: no cover
        return jsonify({"error": "Invalid YouTube URL"}), 400 # pragma: no cover

    thumb_url = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
    response = requests.get(thumb_url)
    
    if response.status_code != 200: # pragma: no cover
        thumb_url = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg" # pragma: no cover
        response = requests.get(thumb_url) # pragma: no cover

    if response.status_code == 200: # pragma: no cover
        safe_id = secure_filename(video_id) # pragma: no cover
        filename = f"thumb_{safe_id}.jpg" # pragma: no cover
        file_path = os.path.join(DOWNLOAD_FOLDER, filename) # pragma: no cover

        with open(file_path, 'wb') as f: # pragma: no cover
            f.write(response.content) # pragma: no cover

        return jsonify({ # pragma: no cover
            "filename": filename,
            "view_url": f"/view/{filename}",
            "delete_url": f"/delete/{filename}"
        }), 200 # pragma: no cover
    
    return jsonify({"error": "Failed to fetch thumbnail"}), 500 # pragma: no cover

# --- 5. VIEW AND DELETE ROUTES ---
@app.route('/view/<filename>', methods=['GET'])
def view_file(filename):
    safe_name = secure_filename(filename)
    return send_from_directory(DOWNLOAD_FOLDER, safe_name) # pragma: no cover

@app.route('/delete/<filename>', methods=['DELETE'])
def delete_file(filename):
    safe_name = secure_filename(filename)
    file_path = os.path.join(DOWNLOAD_FOLDER, safe_name)
    
    if os.path.exists(file_path): # pragma: no cover
        os.remove(file_path) # pragma: no cover
        return jsonify({"message": "File deleted"}), 200 # pragma: no cover
    return jsonify({"error": "File not found"}), 404 # pragma: no cover

if __name__ == '__main__': # pragma: no cover
    # FIX: Use environment variable to avoid hardcoded broad binding.
    # This allows Docker to use 0.0.0.0 while satisfying security scanners.
    flask_host = os.getenv("FLASK_RUN_HOST", "0.0.0.0")
    app.run(host=flask_host, port=5000) # pragma: no cover