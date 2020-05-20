#!/bin/sh
if [ -f ./hosts.txt ]; then
    rm -rf ./hosts.txt
fi
if [ -f ./whitelist.txt ]; then
    rm -rf ./whitelist.txt
fi
