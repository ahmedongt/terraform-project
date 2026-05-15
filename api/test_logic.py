import pytest
from app import get_video_id

def test_valid_youtube_urls():
    # Covers the main regex logic
    assert get_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert get_video_id("https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ"

def test_invalid_urls():
    # This covers the 'return None' line which is likely missing coverage
    assert get_video_id("https://google.com") is None
    assert get_video_id("") is None

def test_edge_cases():
    # Covers extra parameters in URLs
    assert get_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s") == "dQw4w9WgXcQ"