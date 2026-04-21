#!/bin/bash
# Called by the IMAPSieve report-ham sieve script when a user
# moves or copies a message out of the Spam folder (except to Trash).
exec /usr/bin/sa-learn --ham
