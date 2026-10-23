#!/bin/bash
# Called by the IMAPSieve report-spam sieve script when a user
# moves or copies a message into the Spam folder.
exec /usr/bin/sa-learn --spam
