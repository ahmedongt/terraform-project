import io
import os
from flask import Flask, request, send_file, jsonify, send_from_directory
from flask_cors import CORS
import requests

app = Flask(__name__)
CORS(app)

# --- 1. DYNAMIC PATH SETUP ---
# This finds exactly where your app.py is located
API_DIR = os.path.dirname(os.path.abspath(__file__)) 
# This finds the 'website' folder in your main project directory
PROJECT_ROOT = os.path.dirname(API_DIR)
WEBSITE_DIR = os.path.join(PROJECT_ROOT, 'website')
# This puts the downloads inside the api folder
DOWNLOAD_FOLDER = os.path.join(API_DIR, 'downloads')

if not os.path.exists(DOWNLOAD_FOLDER):
    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True)

# --- 2. THE FRONT DOOR (Serve index.html) ---
@app.route('/')
def home():
    return send_from_directory(WEBSITE_DIR, 'index.html')

# --- 3. SERVE CSS/JS/IMAGES ---
@app.route('/<path:path>')
def static_files(path):
    return send_from_directory(WEBSITE_DIR, path)

def get_video_id(url):
    if 'youtu.be/' in url:
        return url.split('/')[-1].split('?')[0]
    elif 'v=' in url:
        return url.split('v=')[-1].split('&')[0]
    return None

# --- 4. MAIN ROUTE: GRAB AND SAVE THUMBNAIL ---
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

        with open(file_path, 'wb') as f:
            f.write(response.content)

        return jsonify({
            "filename": filename,
            "view_url": f"/view/{filename}",
            "delete_url": f"/delete/{filename}"
        }), 200
    
    return jsonify({"error": "Failed to fetch thumbnail"}), 500

# --- 5. VIEW AND DELETE ROUTES ---
@app.route('/view/<filename>')
def view_file(filename):
    return send_from_directory(DOWNLOAD_FOLDER, filename)

@app.route('/delete/<filename>', methods=['DELETE', 'GET'])
def delete_file(filename):
    file_path = os.path.join(DOWNLOAD_FOLDER, filename)
    if os.path.exists(file_path):
        os.remove(file_path)
        return jsonify({"message": "File deleted"}), 200
    return jsonify({"error": "File not found"}), 404

if __name__ == '__main__':
    # host='0.0.0.0' allows access from your browser to the WSL/Linux side
    app.run(host='0.0.0.0', port=5000, debug=True)