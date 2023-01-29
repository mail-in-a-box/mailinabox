#!/usr/bin/python3
#
# This is a tool Josh uses on his box serving mailinabox.email to parse the nginx
# access log to see how many people are installing Mail-in-a-Box each day, by
# looking at accesses to the bootstrap.sh script (which is currently at the URL
# .../setup.sh).

import re, glob, gzip, os.path, json
import dateutil.parser

outfn = "/home/user-data/www/mailinabox.email/install-stats.json"

# Make a unique list of (date, ip address) pairs so we don't double-count
# accesses that are for the same install.
accesses = set()

# Scan the current and rotated access logs.
for fn in glob.glob("/var/log/nginx/access.log*"):
	# Gunzip if necessary.
	# Loop through the lines in the access log.
	with (gzip.open if fn.endswith(".gz") else open)(fn, "rb") as f:
		for line in f:
			# Find lines that are GETs on the bootstrap script by either curl or wget.
			# (Note that we purposely skip ...?ping=1 requests which is the admin panel querying us for updates.)
			# (Also, the URL changed in January 2016, but we'll accept both.)
			m = re.match(rb"(?P<ip>\S+) - - \[(?P<date>.*?)\] \"GET /(bootstrap.sh|setup.sh) HTTP/.*\" 200 \d+ .* \"(?:curl|wget)", line, re.I)
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
	with open(outfn, "r") as f:
		existing_data = json.load(f)
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
