#!/bin/sh
if [ -f ./hosts.txt ]; then
    rm ./hosts.txt
fi
if [ -f ./whitelist.txt ]; then
    rm ./whitelist.txt
fi
