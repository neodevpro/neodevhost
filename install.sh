echo -e "Downloading Whitelist..."
curl -sS https://raw.githubusercontent.com/neodevpro/neodevhost/master/whitelist
sleep 0.5
echo -e "Editing..."
mv ./whitelist ./whitelist.old && cat ./whitelist.old | sort | uniq >> /etc/pihole/whitelist
wait
echo -e "Patching(Need some time)..."
pihole -w -q $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null
echo -e "Upate PiHole Gravity..."
pihole -g
echo -e "Done!"
