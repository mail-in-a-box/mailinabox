This directory contains scripts used to populate a MiaB installation
with known values, and then subsequently verify that MiaB continues to
operate poperly after an upgrade or setup mod change.

Each "named" populate set of scripts should contain at least two
shell scripts:

   1. <name>-populate.sh  : populates the installation
   2. <name>-verify.sh    : verifies operation after upgrade

The system-setup/* scripts run the populate script, and the test
runner's 'upgrade' test suite runs the verify script.

These scripts are run, not sourced.


Expected script output and return value:

   1. All debug output must go to stderr
   2. Result messages must be sent to stdout (a single line, preferrably)
   3. Return 0 if successfully passed verification
   4. Return non-zero if failed verification

The working directory for <name>-populate.sh is the Mail-in-a-Box root
directory.

The working directory for <name>-verify.sh is 'tests' (because the
test runner always changes the working directory there to limit
contamination of the source tree). Use MIAB_DIR and ASSETS_DIR, if
needed.

