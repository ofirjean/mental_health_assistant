from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from flask_pymongo import PyMongo
from flask_login import (
    LoginManager, UserMixin, login_user, login_required, logout_user, current_user
)
from flask_wtf import FlaskForm, CSRFProtect
from flask_wtf.csrf import CSRFError
from wtforms import StringField, PasswordField, IntegerField, TextAreaField, BooleanField, SelectMultipleField
from wtforms.validators import DataRequired, Length, NumberRange
from jinja2 import TemplateNotFound

import google.generativeai as genai
import os
import re
import logging
from datetime import datetime, timedelta
from dotenv import load_dotenv
from werkzeug.security import generate_password_hash, check_password_hash
from bson.objectid import ObjectId

# -----------------------
# Env & logging
# -----------------------
load_dotenv()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# -----------------------
# Flask app & config
# -----------------------
app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-change-me')

# Use default when MONGO_URI is unset or empty
mongo_uri = os.getenv('MONGO_URI') or 'mongodb://mongo:27017/mental_health_db'
app.config['MONGO_URI'] = mongo_uri

# CSRF settings
app.config['WTF_CSRF_TIME_LIMIT'] = None  # disable CSRF expiry during dev

# -----------------------
# Extensions
# -----------------------
mongo = PyMongo(app)
csrf = CSRFProtect(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'
login_manager.login_message = 'Please log in to access this page.'

# -----------------------
# Gemini config (primary & only)
# -----------------------
# Accept GOOGLE_API_KEY or GEMINI_API_KEY (either works)
GEMINI_API_KEY = os.getenv('GEMINI_API_KEY') or os.getenv('GOOGLE_API_KEY')
GEMINI_MODEL = os.getenv('GEMINI_MODEL', 'gemini-1.5-flash')

if GEMINI_API_KEY:
    try:
        genai.configure(api_key=GEMINI_API_KEY)
        logger.info("Gemini configured | model=%s | key present: %s", GEMINI_MODEL, True)
    except Exception as e:
        logger.error("Gemini configure error: %s: %s", type(e).__name__, e)
else:
    logger.warning("GEMINI_API_KEY/GOOGLE_API_KEY not set")

# -----------------------
# Forms
# -----------------------
class RegistrationForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired(), Length(min=3, max=20)])
    password = PasswordField('Password', validators=[DataRequired(), Length(min=6)])

class LoginForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    password = PasswordField('Password', validators=[DataRequired()])

class ProfileForm(FlaskForm):
    age = IntegerField('Age', validators=[NumberRange(min=13, max=120)])
    mental_health_goals = TextAreaField('Mental Health Goals (one per line)')
    stress_level = SelectMultipleField(
        'Stress Level',
        choices=[('low', 'Low'), ('medium', 'Medium'), ('high', 'High')],
        validators=[DataRequired()]
    )
    therapy_preference = BooleanField('I attend therapy or counseling')
    meditation_preference = BooleanField('I practice meditation')

class QuestionForm(FlaskForm):
    question = TextAreaField('Your Question', validators=[DataRequired(), Length(min=10, max=1000)])

# -----------------------
# User model
# -----------------------
class User(UserMixin):
    def __init__(self, user_id, username):
        self.id = user_id
        self.username = username

@login_manager.user_loader
def user_loader(user_id):
    try:
        user = mongo.db.users.find_one({"_id": ObjectId(user_id)})
        if user:
            return User(str(user["_id"]), user["username"])
    except Exception as e:
        logger.error(f"Error loading user: {e}")
    return None

# -----------------------
# Helpers
# -----------------------
def validate_password(password: str):
    if len(password) < 8:
        return False, "Password must be at least 8 characters long"
    if not re.search(r"[A-Za-z]", password):
        return False, "Password must contain at least one letter"
    if not re.search(r"[0-9]", password):
        return False, "Password must contain at least one number"
    return True, "Password is valid"

def rate_limit_check(user_id, limit=10, window=3600):
    """Allow up to `limit` questions per `window` seconds."""
    try:
        window_start = datetime.utcnow() - timedelta(seconds=window)
        count = mongo.db.qa_history.count_documents({
            'user_id': user_id,
            'timestamp': {'$gte': window_start}
        })
        return count < limit
    except Exception as e:
        logger.error(f"Rate limit check error: {e}")
        # If counting fails, don't block user
        return True

def sanitize_input(text: str):
    if not text:
        return ""
    return re.sub(r'[<>"\']', '', text).strip()

# -----------------------
# Error handlers (safe if templates missing)
# -----------------------
@app.errorhandler(404)
def not_found_error(error):
    try:
        return render_template('errors/404.html'), 404
    except TemplateNotFound:
        # Minimal safe fallback (no url_for usage)
        return (
            "<!doctype html><html><head><meta charset='utf-8'><title>Page Not Found</title></head>"
            "<body><h1>404</h1><p>The page you requested was not found.</p><p><a href='/'>Home</a></p></body></html>",
            404,
        )

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal error: {error}")
    try:
        return render_template('errors/500.html'), 500
    except TemplateNotFound:
        return "500 Internal Server Error", 500

@app.errorhandler(CSRFError)
def handle_csrf_error(e):
    try:
        return render_template('errors/400.html', reason=e.description), 400
    except TemplateNotFound:
        return f"Bad Request (CSRF): {e.description}", 400

# -----------------------
# Health / readiness
# -----------------------
@app.get("/healthz")
def healthz():
    # Simple liveness probe (no DB access)
    return jsonify(status="ok"), 200

@app.get("/readyz")
def readyz():
    # Optional: ping DB to assert readiness
    try:
        mongo.cx.admin.command('ping')  # type: ignore[attr-defined]
        return jsonify(status="ready"), 200
    except Exception as e:
        logger.error("Readiness check failed: %s", e)
        return jsonify(status="not-ready"), 503

# -----------------------
# Routes
# -----------------------
@app.route('/')
def index():
    try:
        return render_template('index.html')
    except TemplateNotFound:
        # Safe fallback so "/" never 500s during probes or missing template
        return "Welcome to Mental Health Assistant", 200

# Alias so templates using url_for('home') don't break
@app.route('/home')
def home():
    return redirect(url_for('index'))

@app.route('/register', methods=['GET', 'POST'])
def register():
    form = RegistrationForm()
    if form.validate_on_submit():
        username = sanitize_input(form.username.data.lower())
        password = form.password.data

        is_valid, message = validate_password(password)
        if not is_valid:
            flash(message, 'error')
            return render_template('register.html', form=form)

        existing_user = mongo.db.users.find_one({'username': username})
        if existing_user:
            flash('Username already exists. Please choose a different one.', 'error')
            return render_template('register.html', form=form)

        try:
            hashed_password = generate_password_hash(password)
            user_result = mongo.db.users.insert_one({
                'username': username,
                'password': hashed_password,
                'created_at': datetime.utcnow(),
                'is_active': True
            })
            # Defaults aligned with ProfileForm
            mongo.db.user_data.insert_one({
                'user_id': str(user_result.inserted_id),
                'username': username,
                'age': None,
                'goals': [],
                'preferences': {'therapy': False, 'meditation': False},
                'stress_level': [],
                'created_at': datetime.utcnow(),
                'updated_at': datetime.utcnow()
            })
            flash('Registration successful! Please log in.', 'success')
            return redirect(url_for('login'))
        except Exception as e:
            logger.error(f"Registration error: {e}")
            flash('An error occurred during registration. Please try again.', 'error')
    return render_template('register.html', form=form)

@app.route('/login', methods=['GET', 'POST'])
def login():
    form = LoginForm()
    if form.validate_on_submit():
        username = sanitize_input(form.username.data.lower())
        password = form.password.data
        try:
            user = mongo.db.users.find_one({'username': username, 'is_active': True})
            if user and check_password_hash(user['password'], password):
                user_obj = User(str(user["_id"]), user["username"])
                login_user(user_obj)
                mongo.db.users.update_one(
                    {'_id': user["_id"]},
                    {'$set': {'last_login': datetime.utcnow()}}
                )
                next_page = request.args.get('next')
                return redirect(next_page) if next_page else redirect(url_for('dashboard'))
            else:
                flash('Invalid username or password.', 'error')
        except Exception as e:
            logger.error(f"Login error: {e}")
            flash('An error occurred during login. Please try again.', 'error')
    return render_template('login.html', form=form)

@app.route('/logout')
@login_required
def logout():
    logout_user()
    flash('You have been logged out successfully.', 'info')
    return redirect(url_for('index'))

@app.route('/dashboard')
@login_required
def dashboard():
    try:
        recent_qa = list(
            mongo.db.qa_history
            .find({'user_id': current_user.id})
            .sort('timestamp', -1)
            .limit(5)
        )
        user_data = mongo.db.user_data.find_one({'user_id': current_user.id})
        return render_template('dashboard.html', recent_qa=recent_qa, user_data=user_data)
    except Exception as e:
        logger.error(f"Dashboard error: {e}")
        flash('Error loading dashboard data.', 'error')
        return render_template('dashboard.html', recent_qa=[], user_data=None)

@app.route('/profile', methods=['GET', 'POST'])
@login_required
def profile():
    form = ProfileForm()
    user_data = mongo.db.user_data.find_one({'user_id': current_user.id})
    if form.validate_on_submit():
        try:
            goals_list = [g.strip() for g in (form.mental_health_goals.data or "").split('\n') if g.strip()]
            update_data = {
                'age': form.age.data,
                'goals': goals_list,
                'preferences': {
                    'therapy': form.therapy_preference.data,
                    'meditation': form.meditation_preference.data
                },
                'stress_level': form.stress_level.data or [],
                'updated_at': datetime.utcnow()
            }
            mongo.db.user_data.update_one({'user_id': current_user.id}, {'$set': update_data})
            flash('Profile updated successfully!', 'success')
            return redirect(url_for('profile'))
        except Exception as e:
            logger.error(f"Profile update error: {e}")
            flash('Error updating profile. Please try again.', 'error')

    if user_data:
        form.age.data = user_data.get('age')
        form.mental_health_goals.data = '\n'.join(user_data.get('goals', []))
        form.stress_level.data = user_data.get('stress_level', [])
        prefs = user_data.get('preferences', {})
        form.therapy_preference.data = prefs.get('therapy', False)
        form.meditation_preference.data = prefs.get('meditation', False)

    return render_template('profile.html', form=form)

# -----------------------
# Ask (Gemini only)
# -----------------------
@app.route('/ask', methods=['GET', 'POST'])
@login_required
def ask():
    form = QuestionForm()
    if form.validate_on_submit():
        # Rate limit
        if not rate_limit_check(current_user.id):
            flash('You have reached the hourly limit for questions. Please try again later.', 'warning')
            return render_template('ask.html', form=form)

        question = sanitize_input(form.question.data)

        # Build user context safely
        try:
            user_data = mongo.db.user_data.find_one({'user_id': current_user.id}) or {}
        except Exception as e:
            logger.error(f"User data fetch error: {type(e).__name__} - {e}")
            user_data = {}

        parts = []
        if user_data.get('age'):
            parts.append(f"Age: {user_data['age']}.")
        goals = user_data.get('goals') or []
        if goals:
            parts.append(f"Mental Health Goals: {', '.join(goals)}.")
        stress = user_data.get('stress_level') or []
        if stress:
            parts.append(f"Stress Level: {', '.join(stress)}.")
        prefs = (user_data.get('preferences') or {})
        if prefs.get('therapy'):
            parts.append("Attends therapy or counseling.")
        if prefs.get('meditation'):
            parts.append("Practices meditation.")
        user_context = " ".join(parts) if parts else "No additional context available."

        prompt = (
            "You are a compassionate and professional mental health advisor. "
            "Provide supportive, evidence-based guidance while being empathetic and non-judgmental. "
            "Always recommend professional help for serious mental health concerns.\n\n"
            f"User context: {user_context}\n\n"
            f"Question: \"{question}\"\n\n"
            "Please provide a thoughtful, empathetic response with actionable advice. "
            "Keep your response focused and helpful, around 150-200 words."
        )

        # Ensure key present
        if not GEMINI_API_KEY:
            logger.error("Gemini request error: Missing API key")
            flash('AI is not configured (missing GOOGLE_API_KEY/GEMINI_API_KEY).', 'error')
            return render_template('ask.html', form=form)

        try:
            model = genai.GenerativeModel(GEMINI_MODEL)
            resp = model.generate_content(prompt)
            ai_answer = (getattr(resp, "text", "") or "").strip()
            if not ai_answer:
                raise ValueError("Empty response from Gemini")

            # Save Q&A
            mongo.db.qa_history.insert_one({
                'user_id': current_user.id,
                'username': current_user.username,
                'question': question,
                'answer': ai_answer,
                'timestamp': datetime.utcnow()
            })

            return render_template('response.html', question=question, answer=ai_answer)

        except Exception as e:
            logger.error("Gemini error: %s - %s", type(e).__name__, e)
            flash('AI service is currently unavailable. Please try again shortly.', 'error')
            return render_template('ask.html', form=form)

    # GET or validation errors
    return render_template('ask.html', form=form)

# -----------------------
# Entrypoint
# -----------------------
if __name__ == '__main__':
    port = int(os.getenv("PORT", "5000"))
    debug = os.getenv("FLASK_DEBUG", "0") == "1"  # default off for k8s
    app.run(host="0.0.0.0", port=port, debug=debug)
