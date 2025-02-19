#!/bin/bash

tmp_allow=$(mktemp)
tmp_block=$(mktemp)

# Clean up old files
echo "Clean..."
rm -f host adblocker dnsmasq.conf smartdns.conf domain clash allow block

# Merge allowlist
echo "Merging allowlist..."
while read -r url; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue
    wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> "$tmp_allow"
done < allowlist

sed -i -e '/#/d' -e 's/[[:space:]]//g' "$tmp_allow"
sort -u "$tmp_allow" > allow


# Merge blocklist
echo "Merging blocklist..."
while read -r url; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue
    wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> "$tmp_block"
done < blocklist

sed -i -e '/#/d' -e '/@/d' -e '/^$/d' -e 's/[[:space:]]//g' "$tmp_block"
sed -i '/^\(127\.0\.0\.1 localhost\|127\.0\.0\.1 localhost\.localdomain\|127\.0\.0\.1 local\|255\.255\.255\.255 broadcasthost\|::1 localhost\|::1 ip6-localhost\|::1 ip6-loopback\|fe80::1%lo0 localhost\|ff00::0 ip6-localnet\|ff00::0 ip6-mcastprefix\|ff02::1 ip6-allnodes\|ff02::2 ip6-allrouters\|ff02::3 ip6-allhosts\|0\.0\.0\.0 0\.0\.0\.0\)$/d' "$tmp_block"

sort -u "$tmp_block" > block


# Check format
echo "Check format..."
sed -E -e '/^[^[:space:]]+\.[^[:space:]]+$/!d' allow
sed -E -e '/^[^[:space:]]+\.[^[:space:]]+$/!d' block

domain_regex="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}(:[0-9]+)?([/?].*)?$"

grep -E "$domain_regex" allow > cleanallow
grep -E "$domain_regex" block > cleanblock

mv cleanallow allow
mv cleanblock block


# Generate final lite host list
echo "Merge Combine..."
sort -u block allow > host
sed -i '/^$/d' host
sed -i s/[[:space:]]//g host



# Create lists
tee adblocker dnsmasq.conf smartdns.conf domain clash block < host >/dev/null

# Update Date and block list number
sed -i "9c# Last update: $(date '+%Y-%m-%d')" title
sed -i "11c# Number of domains: $(wc -l < block)" title

# Add Head to all list
for file in host adblocker dnsmasq.conf smartdns.conf domain clash
do
  cat title "$file" > temp.file && mv temp.file "$file"
  rm -f temp.file
done


# Edit adblocker
sed -i -e '14,$s/^/||&/' -e '14,$s/$/&^/' adblocker

# Edit host
sed -i -e '14,$s/^/0.0.0.0  &/' host

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
sed -i "24cUpdate 更新时间: $(date '+%Y-%m-%d')" README.md
sed -i "48cNumber of Domain 域名数目： $(wc -l < block)" README.md

echo " "
echo "Done!"

# Cleanup
rm -f "$tmp_allow" "$tmp_block"
