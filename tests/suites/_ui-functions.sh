#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

run_browser_test() {
    local assert=false
    if [ "$1" = "assert" ]; then
        assert=true
        shift
    fi
    local path="$1" # relative to suites directory. eg "roundcube/mytest.py"
    shift;  # remaining arguments are passed to the test
    
    record "[launching ui test $path $*]"
    record "PYTHONPATH=$UI_TESTS_PYTHONPATH"
    record "BROWSER_TESTS_VERBOSITY=${UI_TESTS_VERBOSITY:-1}"
    record "BROWSER_TESTS_OUTPUT_PATH=${TEST_OF}_ui"
    
    local output
    output=$(
        export PYTHONPATH="$UI_TESTS_PYTHONPATH";
        export BROWSER_TESTS_VERBOSITY=${UI_TESTS_VERBOSITY:-1};
        export BROWSER_TESTS_OUTPUT_PATH="${TEST_OF}_ui";
        python3 suites/$path "$@" 2>&1
          )
    local code=$?
    record "RESULT: $code"
    record "OUTPUT:"; record "$output"
    if [ $code -ne 0 ] && $assert; then
        test_failure "ui test failed: $(python_error "$output")"
    fi
    return $code
}


assert_browser_test() {
    run_browser_test "assert" "$@"
    return $?
}
