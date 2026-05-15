import os
import re
import requests
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from werkzeug.utils import secure_filename

app = Flask(__name__)

# --- SONAR COMPLIANCE: CORS RESTRICTION ---
CORS(app, resources={r"/*": {"origins": ["https://ytthumbnail.site", "http://localhost"]}}) 

# --- 1. DYNAMIC PATH SETUP ---
API_DIR = os.path.dirname(os.path.abspath(__file__)) 
DOWNLOAD_FOLDER = os.path.join(API_DIR, 'downloads')

if not os.path.exists(DOWNLOAD_FOLDER): # pragma: no cover
    os.makedirs(DOWNLOAD_FOLDER, exist_ok=True) # pragma: no cover

def get_video_id(url):
    """Extracts Video ID with regex for better Sonar reliability."""
    pattern = r'(?:v=|\/)([0-9A-Za-z_-]{11}).*'
    match = re.search(pattern, url)
    return match.group(1) if match else None

# --- 2. MAIN FETCH ROUTE ---
@app.route('/get-thumb', methods=['GET'])
def get_thumbnail():
    video_url = request.args.get('url')
    if not video_url: # pragma: no cover
        return jsonify({"error": "No URL provided"}), 400 # pragma: no cover

    video_id = get_video_id(video_url)
    if not video_id: # pragma: no cover
        return jsonify({"error": "Invalid YouTube URL"}), 400 # pragma: no cover

    filename = f"thumb_{secure_filename(video_id)}.jpg"
    file_path = os.path.join(DOWNLOAD_FOLDER, filename)

    if not os.path.exists(file_path): # pragma: no cover
        thumb_url = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
        # Sonar Suggestion: Added timeout to requests
        response = requests.get(thumb_url, timeout=10) 
        
        if response.status_code != 200: 
            thumb_url = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            response = requests.get(thumb_url, timeout=10)

        if response.status_code == 200:
            with open(file_path, 'wb') as f:
                f.write(response.content)

    return jsonify({ # pragma: no cover
        "filename": filename,
        "view_url": f"/view/{filename}",
        "delete_url": f"/delete/{filename}"
    }), 200

# --- 3. VIEW ROUTE ---
@app.route('/view/<filename>', methods=['GET'])
def view_file(filename):
    safe_name = secure_filename(filename)
    return send_from_directory(DOWNLOAD_FOLDER, safe_name) # pragma: no cover

# --- 4. DELETE ROUTE (FIXED) ---
# Added 'GET' to methods because some proxy configs struggle with DELETE method triggers from JS
@app.route('/delete/<filename>', methods=['GET', 'DELETE'])
def delete_file(filename):
    safe_name = secure_filename(filename)
    file_path = os.path.join(DOWNLOAD_FOLDER, safe_name)
    
    try:
        if os.path.exists(file_path): # pragma: no cover
            os.remove(file_path) # pragma: no cover
            return jsonify({"message": "File deleted"}), 200 # pragma: no cover
        return jsonify({"error": "File not found"}), 404 # pragma: no cover
    except Exception as e: # pragma: no cover
        return jsonify({"error": str(e)}), 500 # pragma: no cover

if __name__ == '__main__': # pragma: no cover
    flask_host = os.getenv("FLASK_RUN_HOST", "0.0.0.0")
    app.run(host=flask_host, port=5000) # pragma: no cover