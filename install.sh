echo -e "Downloading Whitelist..."
wget -o ./whitelist https://raw.githubusercontent.com/neodevpro/neodevhost/master/whitelist
sleep 0.5
echo -e "Editing..."
sudo mv ./whitelist ./whitelist.old
sudo cat ./whitelist.old | sort | uniq >> /etc/pihole/whitelist
wait
echo -e "Patching(Need some time)..."
pihole -w -q $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null
echo -e "Upate PiHole Gravity..."
pihole -g
echo -e "Done!"
