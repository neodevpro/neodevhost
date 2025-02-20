#!/bin/bash

# Clean up old files
echo "Clean..."
rm -f host adblocker dnsmasq.conf smartdns.conf domain clash allow block

# Merge list
echo "Merge list..."
process_list() {
    local input_list=$1
    local output_file=$2
    local tmp_file="tmp_$output_file"
    
    echo "Merging $output_file..."
    while read -r url; do
        [[ -z "$url" || "$url" =~ ^# ]] && continue  # Skip empty lines and comments
        wget --no-check-certificate -t 1 -T 10 -q -O - "$url" >> "$tmp_file"
    done < "$input_list"
    
    sed -i -E \
            -e '/#/d' \
            -e '/:/d' \
            -e 's/127.0.0.1 //g' \
            -e 's/0.0.0.0 //g' \
            -e '/^[^[:space:]]+\.[^[:space:]]+$/!d' \
            -e '/^$/d' \
            -e 's/[[:space:]]//g'  "$tmp_file"
    
    sort -u "$tmp_file" > "$output_file"
    rm -f "$tmp_file"
}

process_list "allowlist" "allow"
process_list "blocklist" "block"

# Check format
echo "Checking format..."
domain_name_regex="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$"

validate_format() {
    local input_file=$1
    local output_file="clean_$input_file"
    grep -E "^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$" "$input_file" > "$output_file"
    mv "$output_file" "$input_file"
}

validate_format "allow"
validate_format "block"

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
done

# Adjust Rule format
sed -i -e '14,$s/^/||&/' -e '14,$s/$/&^/' adblocker
sed -i -e '14,$s/^/0.0.0.0  &/' host
sed -i -e '14,$s/^/address=\//' -e '14,$s/$/\/0.0.0.0/' dnsmasq.conf
sed -i -e '14,$s/^/address \//' -e '14,$s/$/\/#/' smartdns.conf
sed -i -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" clash

# Update README with statistics
echo "Adding Title and SYNC data..."
sed -i "14cTotal ad / tracking block list 屏蔽追踪广告总数: $(wc -l < block)" README.md  
sed -i "16cTotal allowlist list 允许名单总数: $(wc -l < allow)" README.md 
sed -i "24cUpdate 更新时间: $(date '+%Y-%m-%d')" README.md
sed -i "48cNumber of Domain 域名数目： $(wc -l < block)" README.md
echo "Done!"
