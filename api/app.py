import io
import os
from flask import Flask, request, send_file, jsonify, send_from_directory
from flask_cors import CORS
import requests
from werkzeug.utils import secure_filename

app = Flask(__name__)

# --- FIX 1: RESTRICT CORS ---
# Restricted to production domain to satisfy SonarCloud security requirements
CORS(app, resources={r"/*": {"origins": ["https://ytthumbnail.site", "http://localhost:5000"]}}) 

# --- 1. DYNAMIC PATH SETUP ---
API_DIR = os.path.dirname(os.path.abspath(__file__)) 
PROJECT_ROOT = os.path.dirname(API_DIR)
WEBSITE_DIR = os.path.join(PROJECT_ROOT, 'website')
DOWNLOAD_FOLDER = os.path.join(API_DIR, 'downloads')

if not os.path.exists(DOWNLOAD_FOLDER):
    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True)

# --- 2. THE FRONT DOOR ---
@app.route('/', methods=['GET'])
def home():
    return send_from_directory(WEBSITE_DIR, 'index.html')

# --- 3. SERVE STATIC FILES ---
@app.route('/<path:path>', methods=['GET'])
def static_files(path):
    return send_from_directory(WEBSITE_DIR, path)

def get_video_id(url):
    if 'youtu.be/' in url:
        return url.split('/')[-1].split('?')[0]
    elif 'v=' in url:
        return url.split('v=')[-1].split('&')[0]
    return None

# --- 4. MAIN ROUTE ---
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
        safe_id = secure_filename(video_id)
        filename = f"thumb_{safe_id}.jpg"
        file_path = os.path.join(DOWNLOAD_FOLDER, filename)

        with open(file_path, 'wb') as f:
            f.write(response.content)

        return jsonify({
            "filename": filename,
            "view_url": f"/view/{filename}",
            "delete_url": f"/delete/{filename}"
        }), 200
    
    return jsonify({"error": "Failed to fetch thumbnail"}), 500

# --- 5. VIEW AND DELETE ROUTES (SECURED) ---
@app.route('/view/<filename>', methods=['GET'])
def view_file(filename):
    safe_name = secure_filename(filename)
    return send_from_directory(DOWNLOAD_FOLDER, safe_name)

# FIX: Removed 'GET' to satisfy "Make sure allowing safe and unsafe HTTP methods is safe here"
@app.route('/delete/<filename>', methods=['DELETE'])
def delete_file(filename):
    safe_name = secure_filename(filename)
    file_path = os.path.join(DOWNLOAD_FOLDER, safe_name)
    
    if os.path.exists(file_path):
        os.remove(file_path)
        return jsonify({"message": "File deleted"}), 200
    return jsonify({"error": "File not found"}), 404

if __name__ == '__main__':
    # host='0.0.0.0' is required for Docker; verify security context in SonarCloud UI
    app.run(host="127.0.0.1", port=5000)