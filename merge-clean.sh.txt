#!bin/bash

echo " "
echo "Clean..."

sort -u customallowlist > customallowlist.temp
rm -f customallowlist
mv customallowlist.temp customallowlist

sort -u customblocklist > customblocklist.temp
rm -f customblocklist
mv customblocklist.temp customblocklist

echo " "
echo "Done..."
