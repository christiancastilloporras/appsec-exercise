#!/usr/bin/env python3
with open('.github/workflows/app-deploy.yml', 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'RELEASE_DATA=' in line and ('tag_name' in line or 'python3' in line or 'jq' in line):
        # Use echo with single quotes around JSON - no backslash escaping needed
        lines[i] = '        RELEASE_DATA=$(echo \'{"tag_name":"tf-state","name":"Terraform State","body":"TF State file for wiz-exercise","target_commitish":"main","draft":false,"prerelease":false}\')\n'
        break

with open('.github/workflows/app-deploy.yml', 'w') as f:
    f.writelines(lines)

# Verify no backslashes
with open('.github/workflows/app-deploy.yml', 'rb') as f:
    data = f.read()
idx = data.find(b'RELEASE_DATA=')
segment = data[idx:idx+150]
bs = bytes([0x5c])
print(f"Raw bytes: {repr(segment)}")
print(f"Has backslash (0x5c): {bs in segment}")
