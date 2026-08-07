#!/usr/bin/env python3
with open('.github/workflows/app-deploy.yml', 'r') as f:
    content = f.read()

# The current line uses python3 -c which is overly complex
# Replace with a simple approach using echo and pipe to jq
# But actually the simplest fix: use a heredoc in the bash script

# Find current RELEASE_DATA line
import re
pattern = r"RELEASE_DATA=\$.*?\)"
if re.search(pattern, content):
    print("Found RELEASE_DATA with python3 approach")

# Replace with jq approach
old = "        RELEASE_DATA=$(python3 -c 'import json; print(json.dumps({\"tag_name\":\"tf-state\",\"name\":\"Terraform State\",\"body\":\"TF State file for wiz-exercise\",\"target_commitish\":\"main\",\"draft\":False,\"prerelease\":False}))')"
new = '        RELEASE_DATA=$(jq -n --arg tag "tf-state" --arg name "Terraform State" --arg body "TF State file for wiz-exercise" --arg commitish "main" '\''{"tag_name":$tag,"name":$name,"body":$body,"target_commitish":$commitish,"draft":false,"prerelease":false}'\'' )'

content = content.replace(old, new)

with open('.github/workflows/app-deploy.yml', 'w') as f:
    f.write(content)

# Verify
with open('.github/workflows/app-deploy.yml', 'rb') as f:
    data = f.read()
idx = data.find(b'RELEASE_DATA=')
print(f"New line repr: {repr(data[idx:idx+200])}")
