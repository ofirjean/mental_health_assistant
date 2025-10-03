import pytest
import sys
import os

# Add the app directory to Python path so we can import the main app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app import app, validate_password, sanitize_input


@pytest.fixture
def client():
    """Create a test client for the Flask application."""
    app.config['TESTING'] = True
    app.config['WTF_CSRF_ENABLED'] = False  # Disable CSRF for testing
    
    with app.test_client() as client:
        yield client


class TestBasicRoutes:
    """Test basic application routes."""
    
    def test_index_page(self, client):
        """Test the homepage loads."""
        response = client.get('/')
        assert response.status_code == 200
    
    def test_register_page_loads(self, client):
        """Test registration page loads."""
        response = client.get('/register')
        assert response.status_code == 200
        assert b'Username' in response.data
    
    def test_login_page_loads(self, client):
        """Test login page loads."""
        response = client.get('/login')
        assert response.status_code == 200
        assert b'Username' in response.data
    
    def test_dashboard_requires_login(self, client):
        """Test dashboard redirects when not logged in."""
        response = client.get('/dashboard')
        assert response.status_code == 302  # Redirect to login
    
    def test_profile_requires_login(self, client):
        """Test profile page requires login."""
        response = client.get('/profile')
        assert response.status_code == 302  # Redirect to login
    
    def test_ask_requires_login(self, client):
        """Test ask page requires login."""
        response = client.get('/ask')
        assert response.status_code == 302  # Redirect to login


class TestHealthEndpoints:
    """Test health check endpoints."""
    
    def test_healthz(self, client):
        """Test health check endpoint."""
        response = client.get('/healthz')
        assert response.status_code == 200
        assert response.json['status'] == 'ok'


class TestUtilityFunctions:
    """Test utility functions."""
    
    def test_validate_password_valid(self):
        """Test valid password."""
        is_valid, message = validate_password('ValidPass123')
        assert is_valid is True
    
    def test_validate_password_too_short(self):
        """Test short password."""
        is_valid, message = validate_password('short')
        assert is_valid is False
        assert "8 characters" in message
    
    def test_validate_password_no_letter(self):
        """Test password without letters."""
        is_valid, message = validate_password('12345678')
        assert is_valid is False
        assert "letter" in message
    
    def test_validate_password_no_number(self):
        """Test password without numbers."""
        is_valid, message = validate_password('onlyletters')
        assert is_valid is False
        assert "number" in message
    
    def test_sanitize_input_basic(self):
        """Test input sanitization removes dangerous characters."""
        result = sanitize_input("Hello<script>World")
        assert "<script>" not in result
        assert "HelloscriptWorld" in result
    
    def test_sanitize_input_removes_quotes(self):
        """Test sanitize removes quotes and other dangerous chars."""
        result = sanitize_input('Test"quote\'single<tag>')
        # Based on your sanitize function: removes <>"'
        assert '"' not in result
        assert "'" not in result
        assert '<' not in result
        assert '>' not in result
        assert 'Testquotesingle' in result or 'Testquote' in result
    
    def test_sanitize_input_empty(self):
        """Test sanitize handles empty input."""
        assert sanitize_input("") == ""
        assert sanitize_input(None) == ""


class TestFormValidation:
    """Test basic form validation."""
    
    def test_register_form_empty_fields(self, client):
        """Test registration form with empty fields."""
        response = client.post('/register', data={})
        assert response.status_code == 200
        # Should stay on registration page (not redirect)
    
    def test_login_form_empty_fields(self, client):
        """Test login form with empty fields."""
        response = client.post('/login', data={})
        assert response.status_code == 200
        # Should stay on login page (not redirect)


class TestErrorPages:
    """Test error handling."""
    
    def test_404_page(self, client):
        """Test 404 error page."""
        response = client.get('/this-page-does-not-exist')
        assert response.status_code == 404


if __name__ == '__main__':
    pytest.main(['-v', __file__])