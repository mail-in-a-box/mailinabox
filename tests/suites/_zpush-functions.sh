

zpush_start() {
	# Must be called before performing any tests
    # enable debug logging
    zpush_set_loglevel "DEBUG"
    zpush_reset_database
}

zpush_end() {
	# Clean up after zpush_start
    zpush_set_loglevel "ERROR"  # ERROR is the default
    zpush_reset_database
}

zpush_set_loglevel() {
    local level="$1"   # eg. "DEBUG"
    local config="$ZPUSH_DIR/config.php"  # ZPUSH_DIR from lib/locations.sh
    record "[set z-push loglevel to '$level']"
    sed -i -E "s/^(\\s+define\\('LOGLEVEL', LOGLEVEL_).*(\\).*)$/\\1${level}\\2/" "$config" >>$TEST_OF 2>&1
    [ $? -ne 0 ] && die "Could not set z-push LOGLEVEL in $config"
}

zpush_reset_database() {
    # zpush keeps track of users and their devices - reset the database
    record "[reset z-push database]"
    rm -rf /var/lib/z-push >>$TEST_OF 2>&1 \
        || die "Could not delete /var/lib/z-push"
    mkdir /var/lib/z-push >>$TEST_OF 2>&1
    chmod 750 /var/lib/z-push >>$TEST_OF 2>&1
    chown www-data:www-data /var/lib/z-push >>$TEST_OF 2>&1
}
