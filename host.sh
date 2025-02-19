#!/bin/bash

# Clean up old files
echo "Clean..."
rm -f host adblocker dnsmasq.conf smartdns.conf domain clash allow block

# Merge list
merge_list() {
    local input_file=$1
    local output_file=$2
    local temp_file=$(mktemp)

    echo "Merging $input_file into $output_file..."
    while read -r url; do
        [[ -z "$url" || "$url" =~ ^# ]] && continue
        wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> "$temp_file"
    done < "$input_file"

    # Cleanup
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "$temp_file" | sort -u > "$output_file"
    sed -i -e '/#/d' -e 's/[[:space:]]//g' "$output_file"
    rm -f "$temp_file"
}

# Handle allowlist & blocklist
merge_list allowlist allow
merge_list blocklist block


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
