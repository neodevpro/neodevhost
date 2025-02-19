#!/bin/bash


# Clean up old files
echo "Clean..."
rm -f host lite_host lite_adblocker adblocker lite_dnsmasq.conf dnsmasq.conf checkblock checkallow smartdns.conf lite_smartdns.conf domain lite_domain clash lite_clash allow


# Merge allowlist
echo "Merge allow..."
for url in `cat allowlist` ; do
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


# Merge blocklist
echo "Merge block..."
for url in `cat blocklist` ; do
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
echo "Adding Compatibility..."

tee adblocker dnsmasq.conf smartdns.conf domain < host >/dev/null
tee lite_adblocker lite_dnsmasq.conf lite_smartdns.conf lite_domain < lite_host >/dev/null


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

# Generate Clash rules
echo "Adding Clash support..."
sed -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" domain >> clash
sed -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" lite_domain >> lite_clash

# Update README with statistics
echo "Adding Title and SYNC data..."

sed -i "14cTotal ad / tracking block list 屏蔽追踪广告总数: $(wc -l < block)" README.md  
sed -i "16cTotal allowlist list 允许名单总数: $(wc -l < allow)" README.md 
sed -i "18cTotal combine list 结合总数： $(wc -l < host)" README.md
sed -i "20cTotal deadblock list 失效屏蔽广告域名： $(wc -l < deadblock)" README.md
sed -i "22cTotal deadallow list 失效允许广告域名： $(wc -l < deadallow)" README.md
sed -i "24cUpdate 更新时间: $(date '+%Y-%m-%d')" README.md
sed -i "54cNumber of Domain 域名数目： $(wc -l < domain)" README.md
sed -i "64cNumber of Domain 域名数目： $(wc -l < lite_domain)" README.md

echo " "
echo "Done!"
