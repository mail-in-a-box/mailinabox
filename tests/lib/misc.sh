#
# misc helpful functions
#
# requirements:
#   system packages: [ python3 ]


array_contains() {
	local searchfor="$1"
	shift
	local item
	for item; do
		[ "$item" == "$searchfor" ] && return 0
	done
	return 1
}

is_true() {
    # empty string is not true
    if [ "$1" == "true" \
              -o "$1" == "TRUE" \
              -o "$1" == "True" \
              -o "$1" == "yes" \
              -o "$1" == "YES" \
              -o "$1" == "Yes" \
              -o "$1" == "1" ]
    then
        return 0
    else
        return 1
    fi
}

is_false() {
    if is_true $@; then return 1; fi
    return 0
}

email_localpart() {
    local addr="$1"
    awk -F@ '{print $1}' <<<"$addr"
}

email_domainpart() {
    local addr="$1"
    awk -F@ '{print $2}' <<<"$addr"
}


generate_uuid() {
	local uuid
	uuid=$(python3 -c "import uuid; print(uuid.uuid4())")
	[ $? -ne 0 ] && die "Unable to generate a uuid"
	echo "$uuid"
}

generate_qa_password() {
    echo "Test1234."
}

sha1() {
	local txt="$1"
	python3 -c "import hashlib; m=hashlib.sha1(); m.update(bytearray(r'''$txt''','utf-8')); print(m.hexdigest());" || die "Unable to generate sha1 hash"
}

