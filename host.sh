host=/home/peter/Desktop/host/hosts.txt
whitelist=/home/peter/Desktop/host/whitelist.txt

echo " "
echo "Clean..."
rm $host
rm $whitelist

echo " "
echo "Merge AD list..."
wait
while read i;do curl -s "$i">>$host&&echo "$i"||echo "fail";done<<EOF
https://raw.githubusercontent.com/E7KMbb/AD-hosts/master/system/etc/hosts
https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts
https://raw.githubusercontent.com/jdlingyu/ad-wars/master/hosts
https://raw.githubusercontent.com/Goooler/1024_hosts/master/hosts
https://hosts.nfz.moe/full/hosts
https://raw.githubusercontent.com/rentianyu/Ad-set-hosts/master/xiaobeita/hosts
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://mirror1.malwaredomains.com/files/justdomains 
https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt
https://hblock.molinero.xyz/hosts
http://winhelp2002.mvps.org/hosts.txt
https://raw.githubusercontent.com/yous/YousList/master/hosts.txt
https://adaway.org/hosts.txt
https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext
https://raw.githubusercontent.com/bongochong/CombinedPrivacyBlockLists/master/newhosts-final.hosts
EOF

echo " "
echo "Merge Whitelist..."
wait
while read g;do curl -s "$g">>$whitelist&&echo "$g"||echo "fail";done<<EOF
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt
https://raw.githubusercontent.com/VeleSila/yhosts/master/whitelist.txt
https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/whitelist/master/domains.list
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt
EOF

echo " "
echo "Geanera AD host file..."
wait
sed -i '/^#/'d $host
sed -i '/^\(127\|0\|::\)/!d;s/0.0.0.0/127.0.0.1/g;/ip6-/d;/localhost/d;s/#.*//g;s/\s\{2,\}//g' $host

echo " "
echo "Geanera whitelist..."
wait
sed -i '/^#/'d $whitelist
sed -i 's/127.0.0.1 //' $whitelist
sed -i "s/http:\/\///" $whitelist
sed -i "s/https:\/\///" $whitelist
sed -i 's/pp助手淘宝登录授权拉起//' $whitelist
sed -i 's/只要有这一条，//' $whitelist
sed -i 's/，腾讯视频网页下一集按钮灰色，也不能选集播放//' $whitelist
sed -i 's/会导致腾讯动漫安卓版的逗比商城白屏//' $whitelist
sed -i '/^$/d' $whitelist
sort -n $whitelist | uniq 


echo " "
echo "Done!"

