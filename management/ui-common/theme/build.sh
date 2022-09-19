#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# install bootstrap sources
#
if [ ! -e "node_modules/bootstrap" ]; then
    npm install bootstrap
    if [ $? -ne 0 ]; then
        echo "Installing bootstrap using npm failed. Is npm install on your system?"
        exit 1
    fi
fi


#
# install sass compiler
#
compiler="/usr/bin/sassc"
if [ ! -x "$compiler" ]; then
    sudo apt-get install sassc || exit 1
fi


#
# compile our theme
#
b_dir="node_modules/bootstrap/scss"

$compiler -I "$b_dir" --sourcemap --style compressed theme.scss ../ui-bootstrap.css
if [ $? -eq 0 ]; then
    echo "SUCCESS - files:"
    ls -sh ../ui-bootstrap.*
fi


