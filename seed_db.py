#!/usr/bin/env python3
"""Seed script to create admin user in MongoDB"""
from pymongo import MongoClient
from werkzeug.security import generate_password_hash
import os

MONGO_URI = os.environ.get('MONGO_URI', 'mongodb://localhost:27017/admin-app')
client = MongoClient(MONGO_URI)
db = client['admin-app']
users = db['users']

# Create admin user if not exists
admin_user = users.find_one({'username': 'admin'})
if not admin_user:
    users.insert_one({
        'username': 'admin',
        'password': generate_password_hash('admin123')
    })
    print("Admin user created: admin / admin123")
else:
    print("Admin user already exists")

# Make MongoDB accessible without auth (vulnerable default)
print("MongoDB setup complete - no authentication required (intentionally vulnerable)")