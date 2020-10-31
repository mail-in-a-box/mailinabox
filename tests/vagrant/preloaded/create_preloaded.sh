#!/bin/bash

vagrant destroy -f
rm -f prepcode.txt

vagrant up preloaded-ubuntu-bionic64
upcode=$?
prepcode=$(cat "./prepcode.txt")
rm -f prepcode.txt
echo ""
echo "VAGRANT UP RETURNED $upcode"
echo "PREPVM RETURNED $prepcode"

if [ "$prepcode" != "0" -o $upcode -ne 0 ]; then
    echo "FAILED!!!!!!!!"
    vagrant destroy -f
    exit 1
fi

vagrant halt
vagrant package
rm -f preloaded.box
mv package.box preloaded-ubuntu-bionic64.box

vagrant destroy -f
