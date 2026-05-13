import pytest
from app import app

def test_home():
    # This simple test hits the home route and counts as 'coverage'
    tester = app.test_client()
    response = tester.get('/')
    assert response.status_code == 200