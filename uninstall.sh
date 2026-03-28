echo -e "Removing(Need some time)..." 
pihole -w -d $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null
echo -e "Update Gravity..."
pihole -g
echo -e "Done!"
