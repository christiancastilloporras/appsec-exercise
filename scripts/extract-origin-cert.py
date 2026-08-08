#!/usr/bin/env python3
import sys, json

data = json.load(sys.stdin)
open('/tmp/origin-cert.pem', 'w').write(data['result']['certificate'])
open('/tmp/origin-key.pem', 'w').write(data['result']['private_key'])
print('Certificate and private key saved')
