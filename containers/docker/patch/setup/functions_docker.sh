#!/bin/bash
function save_function() {
	local ORIG_FUNC=$(declare -f $1)
	local NEWNAME_FUNC="$2${ORIG_FUNC#$1}"
	eval "$NEWNAME_FUNC"
}

function enable_service {
	if [ -f /etc/service/$1/down ]; then
		# Runit service already exists, but is disabled with a down file. Remove it.
		rm /etc/service/$1/down
	fi
}

save_function restart_service restart_service_orig
function restart_service {
	# Make sure service is enabled
	enable_service $1

	# Call original method
	restart_service_orig $1
}