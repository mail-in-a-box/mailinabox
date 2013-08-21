import sys, json, re

# Arguments:
region, version, arch, instance_type = sys.argv[1:]

# Read bytes from stdin.
dat = sys.stdin.read()

# Be flexible. The Ubuntu AMI list is invalid JSON by having a comma
# following the last element in a list.
dat = re.sub(r",(\s*)\]", r"\1]", dat)

# Parse JSON.
dat = json.loads(dat)

for item in dat["aaData"]:
	if item[0] == region and item[2] == version and item[3] == arch and item[4] == instance_type:
		ami_link = item[6]
		
		# The field comes in the form of <a href="...">ami-id</a>
		ami_link = re.sub(r"<.*?>", "", ami_link)
		
		print(ami_link)
		break
		

