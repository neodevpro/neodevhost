curl -sS https://raw.githubusercontent.com/neodevpro/neodevhost/master/whitelist.txt | sudo tee -a /etc/pihole/whitelist.txt >/dev/null
sleep 0.5
mv /etc/pihole/whitelist.txt /etc/pihole/whitelist.txt.old && cat /etc/pihole/whitelist.txt.old | sort | uniq >> /etc/pihole/whitelist.txt
wait
pihole -w -q $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null
