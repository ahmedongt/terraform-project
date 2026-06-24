import os
import re
import requests
import boto3
from botocore.exceptions import ClientError
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.utils import secure_filename

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": ["https://ytthumbnail.site", "http://localhost"]}}) 

S3_BUCKET = os.getenv("AWS_S3_BUCKET", "kali-web-lab-ahmed-12345")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

s3_client = boto3.client('s3', region_name=AWS_REGION)
sts_client = boto3.client('sts', region_name=AWS_REGION)

def get_aws_account_id():
    return sts_client.get_caller_identity()["Account"]

def get_video_id(url):
    pattern = r'(?:v=|\/)([0-9A-Za-z_-]{11}).*'
    match = re.search(pattern, url)
    return match.group(1) if match else None

@app.route('/get-thumb', methods=['GET'])
def get_thumbnail():
    video_url = request.args.get('url')
    video_id = get_video_id(video_url)
    if not video_id: return jsonify({"error": "Invalid URL"}), 400 

    filename = f"thumb_{secure_filename(video_id)}.jpg"
    account_id = get_aws_account_id() # Define account_id here

    try:
        s3_client.head_object(Bucket=S3_BUCKET, Key=filename, ExpectedBucketOwner=account_id)
    except ClientError:
        thumb_url = f"https://img.youtube.com/vi/{video_id}/maxresdefault.jpg"
        response = requests.get(thumb_url, timeout=10)
        if response.status_code != 200:
            thumb_url = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            response = requests.get(thumb_url, timeout=10)
        
        s3_client.put_object(
            Bucket=S3_BUCKET, Key=filename, Body=response.content, 
            ContentType='image/jpeg', ExpectedBucketOwner=account_id
        )

    # Generate Presigned URL for browser access
    url = s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': S3_BUCKET, 'Key': filename},
        ExpiresIn=3600
    )
    return jsonify({"url": url}), 200

@app.route('/delete', methods=['GET'])
def delete_file():
    filename = request.args.get('file')
    if not filename: return jsonify({"error": "No file"}), 400
    try:
        s3_client.delete_object(
            Bucket=S3_BUCKET, Key=secure_filename(filename),
            ExpectedBucketOwner=get_aws_account_id()
        )
        return jsonify({"message": "Deleted"}), 200
    except ClientError:
        return jsonify({"error": "Delete failed"}), 500

if __name__ == '__main__': 
    app.run(host="127.0.0.1", port=5000)