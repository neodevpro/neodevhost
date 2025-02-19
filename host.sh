#!/bin/bash


# Clean up old files
echo "Clean..."
rm -f host adblocker dnsmasq.conf smartdns.conf domain clash allow block

# Merge allowlist
echo "Merge allow..."
while read -r url; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue  # Skip empty lines and comments
    wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> tmpallow
done < allowlist

sed -i -e '/#/d' \
       -e '/^$/d' \
       -e '/^REG /d' \
       -e '/RZD/d' \
       -e 's/ALL .//g' \
       -e 's/[[:space:]]//g' tmpallow

sort -u tmpallow > allow
rm -f tmpallow


# Merge blocklist
echo "Merge block..."
while read -r url; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue  # Skip empty lines and comments
    wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> tmpblock
done < blocklist

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
echo "Check format..."
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

mv cleanallow allow
mv cleanblock block


# Generate final lite host list
echo "Merge Combine..."
sort -n block allow allow | uniq -u > tmp && mv tmp tmphost
sort -u tmphost > host
sed -i '/^$/d' host
sed -i s/[[:space:]]//g host
rm -f tmphost


# Create lists
tee adblocker dnsmasq.conf smartdns.conf domain clash block < host >/dev/null

# Update Date and block list number
sed -i "9cLast update: $(date '+%Y-%m-%d')" title
sed -i "11cNumber of domains: $(wc -l < block)" title

# Add Head to all list
for file in host adblocker dnsmasq.conf smartdns.conf domain clash
do
  cat title "$file" > temp.file && mv temp.file "$file"
  rm -f temp.file
done


# Edit adblocker
sed -i -e '14,$s/^/||&/' -e '14,$s/$/&^/' adblocker

# Edit host
sed -i '14,$s/^/0.0.0.0  &/' host

# Edit dnsmasq.conf
sed -i -e '14,$s/^/address=\//' -e '14,$s/$/\/0.0.0.0/' dnsmasq.conf

# Edit smartdns.conf
sed -i -e '14,$s/^/address=\//' -e '14,$s/$/\/#/' smartdns.conf

# Generate Clash rules
sed -i -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" clash


# Update README with statistics
echo "Adding Title and SYNC data..."

sed -i "14cTotal ad / tracking block list 屏蔽追踪广告总数: $(wc -l < block)" README.md  
sed -i "16cTotal allowlist list 允许名单总数: $(wc -l < allow)" README.md 
sed -i "18cTotal combine list 结合总数： $(wc -l < host)" README.md
sed -i "24cUpdate 更新时间: $(date '+%Y-%m-%d')" README.md
sed -i "50cNumber of Domain 域名数目： $(wc -l < domain)" README.md

echo " "
echo "Done!"
