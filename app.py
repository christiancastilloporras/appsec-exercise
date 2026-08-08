from flask import Flask, render_template, request, redirect, url_for, session, jsonify, abort
from pymongo import MongoClient
from werkzeug.security import generate_password_hash, check_password_hash
import os
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-prod')

# MongoDB connection with retry logic
MONGO_URI = os.environ.get('MONGO_URI', 'mongodb://mongo:27017/admin-app')
max_retries = 3
client = None
db = None

for attempt in range(max_retries):
    try:
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        # Test the connection
        client.admin.command('ping')
        db = client['admin-app']
        print(f"✅ MongoDB connected on attempt {attempt + 1}")
        break
    except Exception as e:
        print(f"❌ MongoDB connection attempt {attempt + 1} failed: {e}")
        if attempt < max_retries - 1:
            import time
            time.sleep(5 * (attempt + 1))

if db:
    users = db['users']
    contacts = db['contacts']
else:
    users = None
    contacts = None

@app.route('/')
def index():
    if 'user' not in session:
        return redirect(url_for('login'))
    if contacts:
        try:
            all_contacts = list(contacts.find({'user': session['user']}))
        except Exception:
            all_contacts = []
        return render_template('dashboard.html', username=session['user'], contacts=all_contacts)
    return render_template('dashboard.html', username=session['user'], contacts=[])

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        if users:
            try:
                user = users.find_one({'username': username})
                if user and check_password_hash(user['password'], password):
                    session['user'] = username
                    return redirect(url_for('index'))
                return render_template('login.html', error='Invalid credentials')
            except Exception:
                pass
        return render_template('login.html', error='Database not available')
    return render_template('login.html')

@app.route('/health')
@app.route('/debug')
def health():
    if db:
        return jsonify({'status': 'healthy', 'db': 'connected'})
    return jsonify({'status': 'degraded', 'db': 'disconnected'}), 503

@app.route('/api/status')
def status():
    db_status = 'connected' if db else 'disconnected'
    return jsonify({'status': 'running', 'db_connected': db is not None, 'contacts_enabled': db is not None})

@app.route('/contacts/create', methods=['POST'])
def create_contact():
    if 'user' not in session:
        abort(403)
    if not contacts:
        abort(503)
    contact = {
        'user': session['user'],
        'name': request.form.get('name', ''),
        'email': request.form.get('email', ''),
        'phone': request.form.get('phone', ''),
        'company': request.form.get('company', ''),
        'created_at': datetime.utcnow()
    }
    contacts.insert_one(contact)
    return redirect(url_for('index'))

@app.route('/contacts/delete/<contact_id>', methods=['POST'])
def delete_contact(contact_id):
    if 'user' not in session:
        abort(403)
    if not contacts:
        abort(503)
    contacts.delete_one({'user': session['user'], 'created_at': contact_id})
    return redirect(url_for('index'))

@app.route('/api/contacts', methods=['GET'])
def list_contacts():
    if 'user' not in session:
        abort(403)
    if not contacts:
        abort(503)
    all_contacts = list(contacts.find({'user': session['user']}, {'_id': 0, 'user': 0, 'created_at': 0}))
    return jsonify({'contacts': all_contacts})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)