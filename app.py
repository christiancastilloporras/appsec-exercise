from flask import Flask, render_template, request, redirect, url_for, session, jsonify, abort
from pymongo import MongoClient
from werkzeug.security import generate_password_hash, check_password_hash
import os
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-prod')

# MongoDB connection
MONGO_URI = os.environ.get('MONGO_URI', 'mongodb://mongo:27017/admin-app')
client = MongoClient(MONGO_URI)
db = client['admin-app']
users = db['users']
contacts = db['contacts']

@app.route('/')
def index():
    if 'user' in session:
        all_contacts = list(contacts.find({'user': session['user']}))
        return render_template('dashboard.html', username=session['user'], contacts=all_contacts)
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        user = users.find_one({'username': username})
        if user and check_password_hash(user['password'], password):
            session['user'] = username
            return redirect(url_for('index'))
        return render_template('login.html', error='Invalid credentials')
    return render_template('login.html')

@app.route('/api/status')
def status():
    return jsonify({'status': 'running', 'db_connected': True, 'contacts_enabled': True})

@app.route('/contacts/create', methods=['POST'])
def create_contact():
    if 'user' not in session:
        abort(403)
    contact = {
        'user': session['user'],
        'name': request.form.get('name', ''),
        'email': request.form.get('email', ''),
        'phone': request.form.get('phone', ''),
        'company': request.form.get('company', ''),
        'created_at': datetime.utcnow()
    }
    result = contacts.insert_one(contact)
    return redirect(url_for('index'))

@app.route('/contacts/delete/<contact_id>', methods=['POST'])
def delete_contact(contact_id):
    if 'user' not in session:
        abort(403)
    contacts.delete_one({'_id': contact_id, 'user': session['user']})
    return redirect(url_for('index'))

@app.route('/api/contacts', methods=['GET'])
def list_contacts():
    if 'user' not in session:
        abort(403)
    all_contacts = list(contacts.find({'user': session['user']}, {'_id': 0, 'user': 0, 'created_at': 0}))
    return jsonify({'contacts': all_contacts})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)