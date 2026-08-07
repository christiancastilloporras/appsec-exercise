#!/usr/bin/env python3

# Fix terraform-apply-destroy.yml RELEASE_DATA line
fname = '.github/workflows/terraform-apply-destroy.yml'
with open(fname, 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'RELEASE_DATA=' in line and 'tag_name' in line:
        old_repr = repr(line)
        print(f"Old line {i+1}: {old_repr}")
        
        # Replace with echo approach
        lines[i] = '        RELEASE_DATA=$(echo \'{"tag_name":"tf-state","name":"Terraform State","body":"TF State file for wiz-exercise","target_commitish":"main","draft":false,"prerelease":false}\')\n'
        print(f"New line {i+1}: {repr(lines[i])}")
        break

with open(fname, 'w') as f:
    f.writelines(lines)

# Verify
with open(fname, 'rb') as f:
    data = f.read()
idx = data.find(b'RELEASE_DATA=')
segment = data[idx:idx+100]
bs = bytes([0x5c])
print(f"\nVerification:")
print(f"Hex: {segment.hex()}")
print(f"Has backslash: {bs in segment}")
