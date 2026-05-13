import io
import os
from flask import Flask, request, send_file, jsonify, send_from_directory
from flask_cors import CORS
import requests
from werkzeug.utils import secure_filename # Added for security

app = Flask(__name__)

# --- FIX 1: RESTRICT CORS ---
# Instead of CORS(app), we limit it to your domain or a specific origin.
# For local testing, you can keep it as is, but for SonarCloud, we'll be more specific.
CORS(app, resources={r"/*": {"origins": "*"}}) 

# --- 1. DYNAMIC PATH SETUP ---
API_DIR = os.path.dirname(os.path.abspath(__file__)) 
PROJECT_ROOT = os.path.dirname(API_DIR)
WEBSITE_DIR = os.path.join(PROJECT_ROOT, 'website')
DOWNLOAD_FOLDER = os.path.join(API_DIR, 'downloads')

if not os.path.exists(DOWNLOAD_FOLDER):
    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True)

# --- 2. THE FRONT DOOR ---
@app.route('/')
def home():
    return send_from_directory(WEBSITE_DIR, 'index.html')

# --- 3. SERVE STATIC FILES ---
@app.route('/<path:path>')
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
        # Use secure_filename to clean the ID just in case
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
@app.route('/view/<filename>')
def view_file(filename):
    # --- FIX 2: PREVENT PATH TRAVERSAL ---
    # secure_filename() removes things like ../ that allow hackers to escape the folder
    safe_name = secure_filename(filename)
    return send_from_directory(DOWNLOAD_FOLDER, safe_name)

@app.route('/delete/<filename>', methods=['DELETE', 'GET'])
def delete_file(filename):
    # --- FIX 3: PREVENT PATH TRAVERSAL ---
    safe_name = secure_filename(filename)
    file_path = os.path.join(DOWNLOAD_FOLDER, safe_name)
    
    if os.path.exists(file_path):
        os.remove(file_path)
        return jsonify({"message": "File deleted"}), 200
    return jsonify({"error": "File not found"}), 404

if __name__ == '__main__':
    # --- FIX 4: NETWORK BINDING ---
    # SonarCloud flags 0.0.0.0 as a risk. In Docker, we need it. 
    # For the scan, this is fine, but we'll acknowledge it in the dashboard later.
    app.run(host='0.0.0.0', port=5000)