#!/bin/bash

# Clean up old files
echo "Clean..."
rm -f host adblocker dnsmasq.conf smartdns.conf domain clash allow block

# Pre-Fetch TLD list
TLD_LIST=$(wget -qO- "https://data.iana.org/TLD/tlds-alpha-by-domain.txt" | tail -n +2 | tr '[:upper:]' '[:lower:]')

# Merge list
process_list() {
    local input_list=$1 output_file=$2 tmp_file="tmp_$output_file"
    echo "Merging $output_file..."
    grep -v '^#' "$input_list" | xargs -P 5 -I {} wget --no-check-certificate -t 1 -T 10 -q -O - "{}" > "$tmp_file"
    sed -i -E '/^[[:space:]]*#/d; /:/d; s/[0-9\.]+[[:space:]]+//g; /^[^[:space:]]+\.[^[:space:]]+$/!d' "$tmp_file"
    TLD_LIST=$(wget -qO- "https://data.iana.org/TLD/tlds-alpha-by-domain.txt" | tail -n +2 | tr '[:upper:]' '[:lower:]')
    awk -F. -v tlds="$TLD_LIST" 'BEGIN {split(tlds, arr, "\n"); for (i in arr) validTLD[arr[i]] = 1} 
    {if (validTLD[tolower($NF)]) print}' "$tmp_file" | sort -u > "$output_file"
    rm -f tmp_
}

# Run allowlist and blocklist processing concurrently
process_list "allowlist" "allow" &
process_list "blocklist" "block" &
wait


# Check format
echo "Validating domain format..."
domain_name_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"
grep -E "$domain_name_regex" "allow" > "clean_allow" && mv "clean_allow" "allow"
grep -E "$domain_name_regex" "block" > "clean_block" && mv "clean_block" "block"

# Generate final lite host list
echo "Merge Combine..."
sort -n block allow allow deadblock deadblock | uniq -u > tmp && mv tmp tmphost
sort -u tmphost > host
sed -i '/^$/d' host
sed -i s/[[:space:]]//g host
rm -f tmphost

# Create lists
tee adblocker dnsmasq.conf smartdns.conf domain clash block < host >/dev/null

# Update Date and block list number
sed -i "9c# Last update: $(date '+%Y-%m-%d')" title
sed -i "11c# Number of domains: $(wc -l < block)" title

# Add Head to all list
for file in host adblocker dnsmasq.conf smartdns.conf domain clash
do
  ( cat title "$file" > temp.file && mv temp.file "$file" ) &
done
wait

# Adjust Rule format
( sed -i -e '14,$s/^/||&/' -e '14,$s/$/&^/' adblocker ) &
( sed -i -e '14,$s/^/0.0.0.0  &/' host ) &
( sed -i -e '14,$s/^/address=\//' -e '14,$s/$/\/0.0.0.0/' dnsmasq.conf ) &
( sed -i -e '14,$s/^/address \//' -e '14,$s/$/\/#/' smartdns.conf ) &
( sed -i -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" clash ) &
wait

# Update README with statistics
echo "Adding Title and SYNC data..."
sed -i "14cTotal ad / tracking block list 屏蔽追踪广告总数: $(wc -l < block)" README.md
sed -i "16cTotal allowlist list 允许名单总数: $(wc -l < allow)" README.md
sed -i "24cUpdate 更新时间: $(date '+%Y-%m-%d')" README.md
sed -i "44cNumber of Domain 域名数目： $(wc -l < block)" README.md

echo "Done!"
