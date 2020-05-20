echo -e "Downloading NEO DEV HOST ..."
curl -sS https://raw.githubusercontent.com/neodevpro/neodevhost/master/hosts.txt | sudo tee -a /etc/pihole/hosts.txt >/dev/null
sleep 0.5
echo -e "Editing..."
mv /etc/pihole/hosts.txt /etc/pihole/hosts.txt.old && cat /etc/pihole/hosts.txt.old | sort | uniq >> /etc/pihole/hosts.txt
sed -i 's/127.0.0.1 //' /etc/pihole/hosts.txt
sed -i '/#/d' /etc/pihole/hosts.txt
sed -i '/255.255.255.255/d' /etc/pihole/hosts.txt
sed -i '/::1/d' /etc/pihole/hosts.txt
sed -i '/ ip6-/d' /etc/pihole/hosts.txt
sed -i '/0.0.0.0/d' /etc/pihole/hosts.txt
sed -i '/fe80::/d' /etc/pihole/hosts.txt

echo -e "Patching(Need some time)..."
pihole -b $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null

echo -e "Downloading Whitelist..."
curl -sS https://raw.githubusercontent.com/neodevpro/neodevhost/master/whitelist.txt | sudo tee -a /etc/pihole/whitelist.txt >/dev/null
sleep 0.5
echo -e "Editing..."
mv /etc/pihole/whitelist.txt /etc/pihole/whitelist.txt.old && cat /etc/pihole/whitelist.txt.old | sort | uniq >> /etc/pihole/whitelist.txt
wait
echo -e "Patching(Need some time)..."
pihole -w -q $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null
echo -e "Upate PiHole Gravity..."
pihole -g
echo -e "Done!"
