#!/bin/bash

NAME='spampd'
PROGRAM=/usr/sbin/spampd

if [ -f /etc/default/$NAME ]; then
        . /etc/default/$NAME
fi

istrue () {
    ANS=$(echo $1 | tr A-Z a-z)
    [ "$ANS" = 'yes' -o "$ANS" = 'true' -o "$ANS" = 'enable' -o "$ANS" = '1' ]
}

#
# Calculate final commandline
#
S_TAGALL=''
S_AWL=''
S_LOCALONLY=''

istrue "$TAGALL" \
&& S_TAGALL='--tagall'

istrue "$AUTOWHITELIST" \
&& S_AWL='--auto-whitelist'

istrue "$LOCALONLY" \
&& S_LOCALONLY='--L'

istrue "$LOGINET" \
&& LOGTARGET="inet" \
|| LOGTARGET="unix"

ARGS="${S_LOCALONLY} ${S_AWL} ${S_TAGALL} "

[ -n "${LISTENPORT}" ] && ARGS="${ARGS} --port=${LISTENPORT}"

[ -n "${LISTENHOST}" ] && ARGS="${ARGS} --host=${LISTENHOST}"

[ -n "${DESTPORT}" ] && ARGS="${ARGS} --relayport=${DESTPORT}"

[ -n "${DESTHOST}" ] && ARGS="${ARGS} --relayhost=${DESTHOST}"

[ -n "${PIDFILE}" ] && ARGS="${ARGS} --pid=${PIDFILE}"

[ -n "${CHILDREN}" ] && ARGS="${ARGS} --children=${CHILDREN}"

[ -n "${USERID}" ] && ARGS="${ARGS} --user=${USERID}"

[ -n "${GRPID}" ] && ARGS="${ARGS} --group=${GRPID}"

[ -n "${LOGTARGET}" ] && ARGS="${ARGS} --logsock=${LOGTARGET}"

[ -n "${ADDOPTS}" ] && ARGS="${ARGS} ${ADDOPTS}"

# Don't daemonize
ARGS="${ARGS} --nodetach"

exec $PROGRAM $ARGS 2>&1