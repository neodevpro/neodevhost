echo -e "Removing(Need some time)..."
sed -i '/##NEO DEV HOST/d' /etc/pihole/adlists.list  
sed -i '/https://raw.githubusercontent.com/neodevpro/neodevhost/master/hosts.txt/d' /etc/pihole/adlists.list  
pihole -w -d $(cat /etc/pihole/whitelist.txt | xargs) > /dev/null
echo -e "Update Gravity..."
pihole -g
echo -e "Done!"
