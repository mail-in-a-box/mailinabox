#!/usr/bin/python3
#
# This is a tool Josh uses on his box serving mailinabox.email to parse the nginx
# access log to see how many people are installing Mail-in-a-Box each day, by
# looking at accesses to the bootstrap.sh script.

import re, glob, gzip, os.path, json
import dateutil.parser

outfn = "/home/user-data/www/mailinabox.email/install-stats.json"

# Make a unique list of (date, ip address) pairs so we don't double-count
# accesses that are for the same install.
accesses = set()

# Scan the current and rotated access logs.
for fn in glob.glob("/var/log/nginx/access.log*"):
	# Gunzip if necessary.
	if fn.endswith(".gz"):
		f = gzip.open(fn)
	else:
		f = open(fn, "rb")

	# Loop through the lines in the access log.
	with f:
		for line in f:
			# Find lines that are GETs on /bootstrap.sh by either curl or wget.
			m = re.match(rb"(?P<ip>\S+) - - \[(?P<date>.*?)\] \"GET /bootstrap.sh HTTP/.*\" 200 \d+ .* \"(?:curl|wget)", line, re.I)
			if m:
				date, time = m.group("date").decode("ascii").split(":", 1)
				date = dateutil.parser.parse(date).date().isoformat()
				ip = m.group("ip").decode("ascii")
				accesses.add( (date, ip) )

# Aggregate by date.
by_date = { }
for date, ip in accesses:
	by_date[date] = by_date.get(date, 0) + 1

# Since logs are rotated, store the statistics permanently in a JSON file.
# Load in the stats from an existing file.
if os.path.exists(outfn):
	existing_data = json.load(open(outfn))
	for date, count in existing_data:
		if date not in by_date:
			by_date[date] = count

# Turn into a list rather than a dict structure to make it ordered.
by_date = sorted(by_date.items())

# Pop the last one because today's stats are incomplete.
by_date.pop(-1)

# Write out.
with open(outfn, "w") as f:
	json.dump(by_date, f, sort_keys=True, indent=True)
