#!bin/bash

echo " "
echo "Clean..."
if [ -f host ]; then
    rm host
fi
if [ -f whitelist ]; then 
    rm whitelist
fi

if [ -f combine ]; then 
    rm combine
fi
if [ -f tmphost ]; then
    rm tmphost
fi
if [ -f tmpwhitelist ]; then 
    rm tmpwhitelist
fi


echo " "
echo "Merge AD list..."
while read i;do curl -s "$i">>tmphost&&echo "$i"||echo "fail";done<<EOF
https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts
https://raw.githubusercontent.com/jdlingyu/ad-wars/master/hosts
https://raw.githubusercontent.com/Goooler/1024_hosts/master/hosts
https://hosts.nfz.moe/full/hosts
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
https://mirror1.malwaredomains.com/files/justdomains 
https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt
https://hblock.molinero.xyz/hosts
http://winhelp2002.mvps.org/hosts.txt
https://raw.githubusercontent.com/yous/YousList/master/hosts.txt
https://adaway.org/hosts.txt
https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext
https://raw.githubusercontent.com/ilpl/ad-hosts/master/hosts
https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt
EOF

echo " "
echo "Merge Whitelist..."
while read g;do curl -s "$g">>tmpwhitelist&&echo "$g"||echo "fail";done<<EOF
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt
https://raw.githubusercontent.com/VeleSila/yhosts/master/whitelist.txt
https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/whitelist/master/domains.list
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt
https://raw.githubusercontent.com/raghavdua1995/DNSlock-PiHole-whitelist/master/whitelist.list
https://raw.githubusercontent.com/neodevpro/neodevhost/master/customwhitelist.txt
EOF

echo " "
echo "Geanera AD host file..."
sed -i '/</d' tmphost
sed -i '/>/d' tmphost
sed -i '/::/d' tmphost
sed -i '/。/d' tmphost
sed -i '/:/d' tmphost
sed -i '/#/d' tmphost
sed -i '/ö/d' tmphost
sed -i '/ä/d' tmphost
sed '/^.\{,3\}$/d' -i tmphost
sed -i 's/255.255.255.255 //' tmphost
sed -i '/ip6-/d' tmphost
sed -i '/localhost/d' tmphost
sed -i 's/127.0.0.1 //g' tmphost
sed -i 's/0.0.0.0 //g' tmphost
sort -n tmphost | uniq > host
rm tmphost
sed -i 's/0.0.0.0.//' host
sed -i 's/0.0.0.0//' host
sed -i 's/ //g' host
sed -i '1,1d' host
sed -i 's/^/127.0.0.1  &/' host


echo " "
echo "Geanera whitelist..."
sed -i '/</d' tmpwhitelist
sed -i '/>/d' tmpwhitelist
sed -i '/::/d' tmpwhitelist
sed -i '/。/d' tmpwhitelist
sed -i '/:/d' tmpwhitelist
sed -i '/#/d' tmpwhitelist
sed -i 's/127.0.0.1 //' tmpwhitelist
sed -i "s/http:\/\///" tmpwhitelist
sed -i "s/https:\/\///" tmpwhitelist
sed -i 's/pp助手淘宝登录授权拉起//' tmpwhitelist
sed -i 's/只要有这一条，//' tmpwhitelist
sed -i 's/，腾讯视频网页下一集按钮灰色，也不能选集播放//' tmpwhitelist
sed -i 's/会导致腾讯动漫安卓版的逗比商城白屏//' tmpwhitelist
sed -i '/address=\//d' tmpwhitelist
sed -i 's/ to use them in an forum.//' tmpwhitelist
sed -i 's/imgbb is a free service for uploading and sharing pictures.//' tmpwhitelist
sed -i '/REG ^/d' tmpwhitelist
sed -i '/RZD /d' tmpwhitelist
sed -i '/ALL ./d' tmpwhitelist
sed -i '/^$/d' tmpwhitelist
sed '/^.\{,3\}$/d' -i tmpwhitelist
sort -n tmpwhitelist | uniq > whitelist
rm tmpwhitelist

sed 's/127.0.0.1  //' host > combine


cp $host $tmphosts
sed -i 's/127.0.0.1 //' $tmphosts
sort -n $tmphosts $whitelist $whitelist | uniq -u > $combine
sed -i 's/^/127.0.0.1 &/g' $combine
sort -d -i $host | uniq
rm $tmphosts



sed -i '14cTotal ad / tracking block list 屏蔽追踪广告总数: '$(wc -l host)' ' $readme  
sed -i '16cTotal whitelist list 白名单总数: '$(wc -l whitelist)' ' $readme  
sed -i '18cTotal combine list 结合总数： '$(wc -l combine)' ' $readme 
sed -i '20cUpdate 更新时间: '$(date "+%Y-%m-%d")'' $readme 


echo " "
echo "Adding Title and SYNC data..."
cp title title.1
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.1
sed -i '11c# Number of blocked domains:  '$(wc -l host)' ' title.1   
cp title title.2
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.2
sed -i '11c# Number of blocked domains:  '$(wc -l combine)' ' title.2   
cat host >>title.1
cat combine >>title.2
rm host
rm combine
mv title.1 host
mv title.2 combine

echo " "
echo "Done!"
