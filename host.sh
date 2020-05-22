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
echo "Merge Whitelist..."
for url in `cat white` ;do
    axel -n10 -a -k -o tmpwhitelist $url
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
    sed -e "s/^[ \t]*//g" -e "s/[ \t]*$//g" -e "s/\r//g"  tmpwhitelist
    cat tmpwhitelist >> whitelist
    sort -n whitelist | uniq -u
    rm tmpwhitelist
done

echo " "
echo "Merge ADlist..."
for url in `cat black` ;do
    axel -n10 -a -k -o tmphost $url
    sed -i '/::/d' tmphost
    sed -i '/。/d' tmphost
    sed -i '/:/d' tmphost
    sed -i '/#/d' tmphost
    #sed -i '/ö/d' tmphost
    #sed -i '/ä/d' tmphost   
    sed -i 's/255.255.255.255 //' tmphost
    sed -i '/ip6-/d' tmphost
    sed -i '/localhost/d' tmphost
    sed -i 's/127.0.0.1 //g' tmphost
    sed -i 's/0.0.0.0 //g' tmphost
    sed -i 's/ //g' tmphost
    sed '/^.\{,3\}$/d' -i tmphost
    sed -i 's/#.*//g;s/\s\{2,\}//g' tmphost
    cat tmphost >> host
    sort -n host | uniq -u
    sort -n host whitelist whitelist | uniq -u > combine
    #sort -n combine | uniq
    rm tmphost
done

sed -i 's/^/127.0.0.1  &/g' host 
sed -i 's/^/127.0.0.1  &/g' combine

sed -i '14cTotal ad / tracking block list 屏蔽追踪广告总数: '$(wc -l host)' ' README.md  
sed -i '16cTotal whitelist list 白名单总数: '$(wc -l whitelist)' ' README.md 
sed -i '18cTotal combine list 结合总数： '$(wc -l combine)' ' README.md
sed -i '20cUpdate 更新时间: '$(date "+%Y-%m-%d")'' README.md


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
