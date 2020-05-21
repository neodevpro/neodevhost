#!/bin/bash
host=./hosts.txt
whitelist=./whitelist.txt
title=./title.txt
readme=./README.md 

echo " "
echo "Clean..."
if [ -f $host ]; then
    rm -rf ./hosts.txt
fi
if [ -f $whitelist ]; then 
    rm -rf ./whitelist.txt
fi

echo " "
echo "Merge AD list..."
while read i;do curl -s "$i">>$host&&echo "$i"||echo "fail";done<<EOF
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
while read g;do curl -s "$g">>$whitelist&&echo "$g"||echo "fail";done<<EOF
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt
https://raw.githubusercontent.com/VeleSila/yhosts/master/whitelist.txt
https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/whitelist/master/domains.list
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt
https://raw.githubusercontent.com/neodevpro/neodevhost/master/customwhitelist.txt
EOF

echo " "
echo "Geanera AD host file..."
sed -i '/^#/'d $host
sed -i '/</d' $host
sed -i '/>/d' $host
sed -i '/::/d' $host
sed -i '/。/d' $host
sed -i '/:/d' $host
sed -i '/#/d' $host
sed -i '/ö/d' $host
sed -i '/ä/d' $host
sed -i '/^\(127\|0\|::\)/!d;s/0.0.0.0/127.0.0.1/g;/ip6-/d;/localhost/d;s/#.*//g;s/\s\{2,\}//g' $host
sed '/^.\{,13\}$/d' -i $host
sort -d -i $host | uniq

echo " "
echo "Geanera whitelist..."
sed -i '/</d' $whitelist
sed -i '/>/d' $whitelist
sed -i '/::/d' $whitelist
sed -i '/。/d' $whitelist
sed -i '/:/d' $whitelist
sed -i '/#/d' $whitelist
sed -i 's/127.0.0.1 //' $whitelist
sed -i "s/http:\/\///" $whitelist
sed -i "s/https:\/\///" $whitelist
sed -i 's/pp助手淘宝登录授权拉起//' $whitelist
sed -i 's/只要有这一条，//' $whitelist
sed -i 's/，腾讯视频网页下一集按钮灰色，也不能选集播放//' $whitelist
sed -i 's/会导致腾讯动漫安卓版的逗比商城白屏//' $whitelist
sed -i 's/ to use them in an forum.//' $whitelist
sed -i 's/imgbb is a free service for uploading and sharing pictures.//' $whitelist
sed -i '/REG ^/d' $whitelist
sed -i '/RZD /d' $whitelist
sed -i '/address=\/.bcebos.com\/0.0.0.0 baidu maps /d' $whitelist
sed -i '/ALL ./d' $whitelist
sed -e "s/^[ \t]*//g" -e "s/[ \t]*$//g" -e "s/\r//g" -e "/^$/d" -e 's/^/127.0.0.1 &/g' $whitelist
sed -i '/^$/d' $whitelist
sed '/^.\{,3\}$/d' -i $whitelist
sort -d -i $whitelist | uniq

echo | sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' $host
echo | sed -i '11c# Number of domains:  '$(wc -l ./hosts.txt)' ' $host    

echo | sed -i '14cTotal ad / tracking block list 屏蔽追踪广告总数: '$(wc -l ./hosts.txt)' ' $readme  
echo | sed -i '16cTotal whitelist list 白名单总数: '$(wc -l ./whitelist.txt)' ' $readme  
echo | sed -i '18cUpdate 更新时间: '$(date "+%Y-%m-%d")'' $readme 

echo " "
echo "Adding Title and SYNC data..."
cp $title $title.1
cat $host >>$title.1
rm -rf $host
mv $title.1 $host


echo " "
echo "Done!"
