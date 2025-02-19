#!/bin/bash


# Clean up old files
echo "\nClean..."
rm -f host lite_host lite_adblocker adblocker lite_dnsmasq.conf dnsmasq.conf deadallow deadblock checkblock checkallow \
      smartdns.conf lite_smartdns.conf domain lite_domain clash lite_clash allow


# Merge allowlist
echo "\nMerge allow..."
> tmpallow
for url in $(cat allowlist); do
    wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> tmpallow
done

sed -i -e '/#/d' \
       -e '/^$/d' \
       -e '/^REG /d' \
       -e '/RZD/d' \
       -e 's/ALL .//g' \
       -e 's/[[:space:]]//g' tmpallow

sort -u tmpallow > allow
rm -f tmpallow


# Check for dead allowlist entries
echo "\nCheck Dead Allow..."
wget --no-check-certificate -t 1 -T 10 -q -O deadallow https://raw.githubusercontent.com/neodevpro/dead-allow/master/deadallow
sort allow deadallow | uniq -u > tmpallow && mv tmpallow allow


# Merge blocklist
echo "\nMerge block..."
> tmpblock
for url in $(cat blocklist); do
    wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> tmpblock
done

sed -i -e '/#/d' \
       -e '/@/d' \
       -e '/*/d' \
       -e '/127.0.0.1 localhost.localdomain/d' \
       -e '/fe80::1%lo0 localhost/d' \
       -e '/127.0.0.1 localhost/d' \
       -e '/127.0.0.1 local/d' \
       -e '/::1 ip6-localhost/d' \
       -e '/localhost/d' \
       -e '/ip6-local/d' \
       -e '/ip6-all/d' \
       -e '/ip6-mcastprefix/d' \
       -e '/broadcasthost/d' \
       -e '/ip6-loopback/d' \
       -e '/0.0.0.0 0.0.0.0/d' \
       -e 's/0.0.0.0 //' \
       -e 's/127.0.0.1 //' \
       -e '/:/d' \
       -e '/!/d' \
       -e '/|/d' \
       -e '/^$/d' \
       -e 's/[[:space:]]//g' tmpblock

sort -u tmpblock > block
rm -f tmpblock



# Check format

echo "\nCheck format..."
sed -E -e '/^[^[:space:]]+\.[^[:space:]]+$/!d' allow
sed -E -e '/^[^[:space:]]+\.[^[:space:]]+$/!d' block

domain_name_regex="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}(:[0-9]+)?([/?].*)?$"

while read line; do
  if [[ $line =~ $domain_name_regex ]]; then
    echo "$line" >> cleanallow
  fi
done < allow

while read line; do
  if [[ $line =~ $domain_name_regex ]]; then
    echo "$line" >> cleanblock
  fi
done < block


# Check for dead blocklist entries
echo "\nCheck Dead Block..."
rm -rf allow block
mv cleanallow allow
mv cleanblock block
cp block checkblock lite_block
wget --no-check-certificate -t 1 -T 10 -q https://raw.githubusercontent.com/FusionPlmH/dead-block/master/deadblock
sort lite_block deadblock | uniq -u > tmplite_block && mv tmplite_block lite_block
rm -f tmplite_block 

# Generate final lite host list
echo "\nMerge Combine..."
generate_host_list() {
    local blocklist=$1
    local output=$2

    sort -n "$blocklist" allow allow | uniq -u > tmp && mv tmp tmp"$output"
    sort -u tmp"$output" > "$output"
    sed -i '/^$/d' "$output"
    sed -i 's/[[:space:]]//g' "$output"
    rm -f tmp"$output"
}

# Generate both host lists
generate_host_list "block" "host"
generate_host_list "lite_block" "lite_host"



# Generate different format lists
echo "\nAdding Compatibility..."

cp host adblocker dnsmasq.conf smartdns.conf domain
cp lite_host lite_adblocker lite_dnsmasq.conf lite_smartdns.conf lite_domain

# Edit adblocker & lite_adblocker
for file in adblocker lite_adblocker; do
    sed -i 's/^/||&/' "$file"
    sed -i 's/$/&^/' "$file"
done

# Edit host & lite_host
for file in host lite_host; do
    sed -i 's/^/0.0.0.0  &/' "$file"
done

# Edit dnsmasq.conf & lite_dnsmasq.conf
for file in dnsmasq.conf lite_dnsmasq.conf; do
    sed -i 's/^/address=\/&/' "$file"
    sed -i 's/$/&\/0.0.0.0/' "$file"
done

# Edit smartdns.conf & lite_smartdns.conf
for file in smartdns.conf lite_smartdns.conf; do
    sed -i 's/^/address=\/&/' "$file"
    sed -i 's/$/&\/#/' "$file"
done

# Update README with statistics
echo "\nAdding Title and SYNC data..."

sed -i "14cTotal ad / tracking block list 屏蔽追踪广告总数: $(wc -l < block)" README.md  
sed -i "16cTotal allowlist list 允许名单总数: $(wc -l < allow)" README.md 
sed -i "18cTotal combine list 结合总数： $(wc -l < host)" README.md
sed -i "20cTotal deadblock list 失效屏蔽广告域名： $(wc -l < deadblock)" README.md
sed -i "22cTotal deadallow list 失效允许广告域名： $(wc -l < deadallow)" README.md
sed -i "24cUpdate 更新时间: $(date '+%Y-%m-%d')" README.md
 
cp title title.2
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.2 
sed -i '11c# Number of blocked domains:  '$(wc -l host)' ' title.2  
cp title title.4
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.4 
sed -i '11c# Number of blocked domains:  '$(wc -l adblocker)' ' title.4
cp title title.6
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.6
sed -i '11c# Number of blocked domains:  '$(wc -l dnsmasq.conf)' ' title.6
cp title title.8
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.8
sed -i '11c# Number of blocked domains:  '$(wc -l smartdns.conf)' ' title.8    
cp title title.10
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.10
sed -i '11c# Number of blocked domains:  '$(wc -l domain)' ' title.10             
cp title title.12
     



cp title title.1
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.1
sed -i '11c# Number of blocked domains:  '$(wc -l lite_host)' ' title.1   
cp title title.3
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.3
sed -i '11c# Number of blocked domains:  '$(wc -l lite_adblocker)' ' title.3   
cp title title.5
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.5
sed -i '11c# Number of blocked domains:  '$(wc -l lite_dnsmasq.conf)' ' title.5  
cp title title.7
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.7
sed -i '11c# Number of blocked domains:  '$(wc -l lite_smartdns.conf)' ' title.7  
cp title title.9
sed -i '9c# Last update: '$(date "+%Y-%m-%d")'' title.9
sed -i '11c# Number of blocked domains:  '$(wc -l lite_domain)' ' title.9  
cp title title.11



cat host >>title.2
cat adblocker >>title.4
cat dnsmasq.conf >>title.6
cat smartdns.conf >>title.8
cat domain >>title.10

cat lite_host >>title.1
cat lite_adblocker >>title.3
cat lite_dnsmasq.conf >>title.5
cat lite_smartdns.conf >>title.7
cat lite_domain >>title.9


rm -f host adblocker dnsmasq.conf lite_host lite_adblocker lite_dnsmasq.conf deadallow deadblock lite_block block smartdns.conf lite_smartdns.conf doamin lite_domain

mv title.2 host
mv title.4 adblocker
mv title.6 dnsmasq.conf
mv title.8 smartdns.conf
mv title.10 domain

mv title.1 lite_host
mv title.3 lite_adblocker
mv title.5 lite_dnsmasq.conf
mv title.7 lite_smartdns.conf
mv title.9 lite_domain

# Generate Clash rules
echo "\nAdding Clash support..."
sed -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" domain >> clash
sed -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" lite_domain >> lite_clash


echo " "
echo "Done!"
