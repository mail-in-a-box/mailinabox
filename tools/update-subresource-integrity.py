#!/usr/bin/python3
# Updates subresource integrity attributes in management/templates/index.html
# to prevent CDN-hosted resources from being used as an attack vector. Run this
# after updating the Bootstrap and jQuery <link> and <script> to compute the
# appropriate hash and insert it into the template.

import re, urllib.request, hashlib, base64

fn = "management/templates/index.html"

with open(fn, 'r') as f:
	content = f.read()

def make_integrity(url):
	resource = urllib.request.urlopen(url).read()
	return "sha256-" + base64.b64encode(hashlib.sha256(resource).digest()).decode('ascii')

content = re.sub(
	r'<(link rel="stylesheet" href|script src)="(.*?)" integrity="(.*?)"',
	lambda m : '<' + m.group(1) + '="' + m.group(2) + '" integrity="' + make_integrity(m.group(2)) + '"',
	content)

with open(fn, 'w') as f:
	f.write(content)
