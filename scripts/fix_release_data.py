#!/usr/bin/env python3
import yaml

# Read the file
with open('.github/workflows/app-deploy.yml', 'r') as f:
    content = f.read()

# Find the RELEASE_DATA line and replace it
# The issue is that *** secrets.GITHUB_TOKEN }} becomes *** in display but file has actual content
# Let's check what's really in the file

# Find the line with RELEASE_DATA
lines = content.split('\n')
for i, line in enumerate(lines):
    if 'RELEASE_DATA=' in line and 'tag_name' in line:
        # Check what's actually in the line
        print(f"Line {i+1} raw repr: {repr(line)}")
        print(f"Line {i+1} has backslash before quote: {chr(92)+chr(34) in line}")
        
        # Build new line WITHOUT backslashes
        # Use single quotes in bash, JSON with regular double quotes (no backslash escaping)
        # In YAML run: | block, we need valid bash
        # Option: use echo with -e and escaped quotes, or use python
        new_line = '        RELEASE_DATA=$(python3 -c \'import json; print(json.dumps({"tag_name":"tf-state","name":"Terraform State","body":"TF State file for wiz-exercise","target_commitish":"main","draft":False,"prerelease":False}))\')'
        lines[i] = new_line
        print(f"New line: {repr(new_line)}")
        break

# Write back
with open('.github/workflows/app-deploy.yml', 'w') as f:
    f.write('\n'.join(lines))

print("Done")
