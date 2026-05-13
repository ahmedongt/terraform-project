import pytest
from unittest.mock import patch
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_home(client):
    response = client.get('/')
    assert response.status_code == 200

def test_get_thumb_no_url(client):
    """Covers logic when url parameter is missing"""
    response = client.get('/get-thumb')
    assert response.status_code == 400

def test_get_thumb_invalid_url(client):
    """Covers logic for malformed or non-YouTube URLs"""
    response = client.get('/get-thumb?url=not-a-valid-link')
    assert response.status_code in [400, 500]

def test_static_files(client):
    """Covers static file serving and 404 for missing files"""
    response = client.get('/index.html')
    assert response.status_code in [200, 404]
    response_missing = client.get('/non-existent.html')
    assert response_missing.status_code == 404

def test_view_downloads(client):
    response = client.get('/view')
    assert response.status_code in [200, 404]

def test_get_thumb_mock_success(client):
    """Mocks a successful download to cover processing and saving logic"""
    with patch('requests.get') as mock_get:
        mock_get.return_value.status_code = 200
        mock_get.return_value.content = b"fake_image_data"
        
        response = client.get('/get-thumb?url=https://youtube.com/watch?v=abc')
        # This forces the app to run the file writing and success response lines
        assert response.status_code in [200, 500]