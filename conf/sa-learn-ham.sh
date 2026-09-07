#!/bin/bash
# Called by the IMAPSieve report-ham sieve script when a user
# moves or copies a message out of the Spam folder (except to Trash).
# author: https://github.com/yeah
#
exec /usr/bin/sa-learn --ham