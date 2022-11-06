#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# This is a status_checks management hook for the logwatch setup mod.
#
# It adds logwatch output to status checks. In most circumstances it
# will cause a "status checks change notice" email to be sent every
# day when daily_tasks.sh runs status checks around 3 am.
#
# The hook is enabled by placing the file in directory
# LOCAL_MODS_DIR/managment_hooks_d.
#

import os, time
import logging
from utils import shell

log = logging.getLogger(__name__)

def do_hook(hook_name, hook_data, mods_env):
    if hook_name != 'status_checks':
        # we only care about hooking status_checks
        log.debug('hook - ignoring hook %s', hook_name)
        return False
    
    if hook_data['op'] != 'output_changes_end':
        # we only want to append for --show-changes
        log.debug('hook - ignoring hook op %s:%s', hook_name, hook_data['op'])
        return False

    output = hook_data['output']
    
    if not os.path.exists("/usr/sbin/logwatch"):
        output.print_error("logwatch is not installed")
        return True

    # determine scope and period of the logwatch log file scan
    since_mtime = hook_data['since'] if 'since' in hook_data else 0
    if since_mtime <= 0:
        since = 'since 24 hours ago for that hour'
        since_desc = 'since 24 hours ago'
    else:
        local_str = time.strftime(
            "%Y-%m-%d %H:%M:%S",
            time.localtime(since_mtime)
        )
        since = 'since %s for that second' % local_str
        since_desc = 'since %s' % local_str

    # run logwatch
    report = shell(
        'check_output',
        [
            '/usr/sbin/logwatch',
            '--range', since,
            '--output', 'stdout',
            '--format', 'text',
            '--service', 'all',
            '--service', '-zz-disk_space',
            '--service', '-zz-network',
            '--service', '-zz-sys',
        ],
        capture_stderr=True,
        trap=False
    )

    # defer outputting the heading text because if there is no
    # logwatch output we care about, we don't want any output at all
    # (which could avoid a status check email)
    heading_done = False    
    def try_output_heading():
        nonlocal heading_done
        if heading_done: return
        output.add_heading('System Log Watch (%s)' % since_desc);
        heading_done=True

    in_summary = False  # true if we're currently processing the logwatch summary text, which is the text output by logwatch that is surrounded by lines containing hashes. we ignore the summary text
    blank_line_count = 1 # keep track of the count of adjacent blank lines
    output_info = False # true if we've called output.print_info at least once
    
    for line in report.split('\n'):
        line = line.strip();
        if line == '':
            blank_line_count += 1
            if blank_line_count == 1 and output_info:
                output.print_line('')
        
        elif line.startswith('##'):
            in_summary = '## Logwatch' in line
                
        elif line.startswith('--'):
            if ' Begin --' in line:
                start = line.find(' ')
                end = line.rfind(' Begin --')
                try_output_heading()
                output.print_info("%s" % line[start+1:end])
                output_info = True
                blank_line_count = 0
                
        else:
            if not in_summary:
                try_output_heading()
                output.print_line(line)
                blank_line_count = 0
    
    return True
