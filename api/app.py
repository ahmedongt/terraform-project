import os
import re
import requests
import boto3
from botocore.exceptions import ClientError
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from werkzeug.utils import secure_filename

app = Flask(__name__)

# --- SONAR COMPLIANCE: SECURE CORS ---
CORS(app, resources={r"/*": {"origins": ["https://ytthumbnail.site", "http://localhost"]}}) 

# --- AWS S3 CENTRALIZED STORAGE SETUP ---
S3_BUCKET = os.getenv("AWS_S3_BUCKET", "kali-web-lab-ahmed-12345")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
AWS_ACCOUNT_ID = os.getenv("AWS_ACCOUNT_ID")

s3_client = boto3.client('s3', region_name=AWS_REGION)

def get_video_id(url):
    """Extracts Video ID using optimized regex."""
    if not url: return None 
    pattern = r'(?:v=|\/)([0-9A-Za-z_-]{11}).*'
    match = re.search(pattern, url)
    if not match: return None 
    return match.group(1)

# --- 1. HEALTH CHECK ROUTES ---
@app.route('/', methods=['GET'])
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy", "message": "Backend is running"}), 200

# --- 2. MAIN FETCH ROUTE ---
@app.route('/get-thumb', methods=['GET'])
def get_thumbnail():
    video_url = request.args.get('url')
    if not video_url: 
        return jsonify({"error": "No URL provided"}), 400 

    video_id = get_video_id(video_url)
    if not video_id: 
        return jsonify({"error": "Invalid YouTube URL"}), 400 

    filename = f"thumb_{secure_filename(video_id)}.jpg"

    # Check if the thumbnail already exists in our central S3 Bucket
    try:
        s3_client.head_object(
            Bucket=S3_BUCKET, 
            Key=filename,
            ExpectedBucketOwner=AWS_ACCOUNT_ID
        )
        file_exists = True
    except ClientError as e:
        if e.response['Error']['Code'] == "404":
            file_exists = False
        else:
            return jsonify({"error": "Storage system connection error"}), 500

    # If it's not in S3, download it from YouTube and upload it directly
    if not file_exists:
        thumb_url = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
        try:
            response = requests.get(thumb_url, timeout=10) 
            if response.status_code != 200: 
                thumb_url = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
                response = requests.get(thumb_url, timeout=10)

            if response.status_code == 200:
                s3_client.put_object(
                    Bucket=S3_BUCKET,
                    Key=filename,
                    Body=response.content,
                    ContentType='image/jpeg',
                    ExpectedBucketOwner=AWS_ACCOUNT_ID
                )
            else: 
                return jsonify({"error": "Thumbnail not found on YouTube"}), 404
        except Exception: 
            return jsonify({"error": "External API error"}), 500

    return jsonify({
        "filename": filename,
        "view_url": f"/api/view/{filename}",
        "delete_url": f"/api/delete/{filename}"
    }), 200

# --- 3. VIEW ROUTE ---
@app.route('/view/<filename>', methods=['GET'])
def view_file(filename):
    safe_name = secure_filename(filename)
    try:
        s3_object = s3_client.get_object(
            Bucket=S3_BUCKET, 
            Key=safe_name,
            ExpectedBucketOwner=AWS_ACCOUNT_ID
        )
        return Response(
            s3_object['Body'].read(),
            mimetype=s3_object['ContentType']
        )
    except ClientError as e:
        if e.response['Error']['Code'] == "404":
            return jsonify({"error": "File not found"}), 404
        return jsonify({"error": "Failed to retrieve storage object"}), 500

# --- 4. DELETE ROUTE ---
@app.route('/delete/<filename>', methods=['GET', 'DELETE'])
def delete_file(filename):
    safe_name = secure_filename(filename)
    try:
        s3_client.delete_object(
            Bucket=S3_BUCKET, 
            Key=safe_name,
            ExpectedBucketOwner=AWS_ACCOUNT_ID
        )
        return jsonify({"message": "File completely removed from cloud storage"}), 200 
    except ClientError:
        return jsonify({"error": "Delete operation failed"}), 500

if __name__ == '__main__': 
    flask_host = os.getenv("FLASK_RUN_HOST", "0.0.0.0")
    app.run(host=flask_host, port=5000)