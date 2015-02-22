#!/bin/bash

exec 1>&2

test -f /etc/default/postfix && . /etc/default/postfix

command_directory=`postconf -h command_directory`
daemon_directory=`$command_directory/postconf -h daemon_directory`
# make consistency check
$command_directory/postfix check 2>&1
# run Postfix
exec $daemon_directory/master 2>&1