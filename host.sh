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
    awk -F. -v tlds="$TLD_LIST" 'BEGIN {split(tlds, arr, "\n"); for (i in arr) validTLD[arr[i]] = 1} 
    {if (validTLD[tolower($NF)]) print}' "$tmp_file" | sort -u > "$output_file"
    rm -f tmp_
}

# Run allowlist and blocklist processing concurrently
process_list "allowlist" "allow"
process_list "blocklist" "block"


# Enhanced domain validation with IDN (punycode) support
echo "Validating domain format (strict, with IDN support)..."

# Load Public Suffix List (PSL) for TLD/domain validation
PSL_URL="https://publicsuffix.org/list/public_suffix_list.dat"
PSL_FILE="psl.txt"
if [ ! -f "$PSL_FILE" ]; then
  wget -qO "$PSL_FILE" "$PSL_URL"
fi

# Reserved domains (RFC 2606)
RESERVED_DOMAINS="example.com example.net example.org test localhost local invalid"

# Improved regex for domain validation (RFC-compliant, punycode, Unicode)
domain_name_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z0-9]{2,}$"

# Public Suffix List check function
is_valid_psl() {
  local domain="$1"
  local tld=$(echo "$domain" | awk -F. '{print $NF}')
  grep -q "^$tld$" "$PSL_FILE"
}

# Reserved domain check function
is_reserved_domain() {
  local domain="$1"
  for reserved in $RESERVED_DOMAINS; do
    if [[ "$domain" == *"$reserved" ]]; then
      return 0
    fi
  done
  return 1
}


# Convert IDN to punycode if 'idn' is available, else pass through
idn_convert() {
  if command -v idn >/dev/null 2>&1; then
    idn --quiet || cat
  else
    cat
  fi
}
# Remove lines with invalid characters, consecutive dots, leading/trailing dots, overly long domains/labels
filter_domains() {
  awk '
    length($0)<=253 &&
    $0 !~ /[^a-zA-Z0-9.-]/ &&
    $0 !~ /\.\./ &&
    $0 !~ /^\.|\.$/ &&
    $0 !~ /\.[0-9]+$/ {
      split($0, labels, ".");
      valid=1;
      for(i in labels) {
        if(labels[i]=="") {valid=0; break}
        if(length(labels[i])>63) {valid=0; break}
        if(labels[i] ~ /^-/ || labels[i] ~ /-$/) {valid=0; break}
        if(length(labels[i])>=4 && substr(labels[i],3,2)=="--" && i!=length(labels)) {valid=0; break}
        if(labels[i] ~ /[^a-zA-Z0-9-]/) {valid=0; break}
      }
      if(labels[length(labels)] ~ /^[0-9]+$/) {valid=0}
      if(valid) print $0;
    }'
}
}

domain_name_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"
grep -E "$domain_name_regex" "allow" | idn_convert | filter_domains > "clean_allow"
grep -E "$domain_name_regex" "block" | idn_convert | filter_domains > "clean_block"
grep -E "$domain_name_regex" "allow" | idn_convert | filter_domains | filter_reserved_and_psl > "clean_allow"
grep -E "$domain_name_regex" "block" | idn_convert | filter_domains | filter_reserved_and_psl > "clean_block"
# Remove redundant subdomains if parent domain exists
remove_redundant_subdomains() {
  awk -F. '{
    n=split($0, a, ".");
    for(i=1;i<=n;i++) {
      subd="";
      for(j=i;j<=n;j++) subd=(subd==""?a[j]:subd"."a[j]);
      if(subd!=$0) seen[subd]=1;
    }
    if(!seen[$0]) print $0;
  }' | sort -u
}

cat clean_allow | remove_redundant_subdomains > allow && rm -f clean_allow
cat clean_block | remove_redundant_subdomains > block && rm -f clean_block

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

# Reserved and PSL checks outside awk
filter_reserved_and_psl() {
  while read domain; do
    reserved=1
    for reserved_domain in $RESERVED_DOMAINS; do
      if [[ "$domain" == *"$reserved_domain" ]]; then
        reserved=0
        break
      fi
    done
    tld="${domain##*.}"
    psl_valid=0
    if grep -q "^$tld$" "$PSL_FILE"; then
      psl_valid=1
    fi
    if [[ $reserved -eq 1 && $psl_valid -eq 1 ]]; then
      echo "$domain"
    fi
  done
}
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

# Update README with statistics optimized
block_count=$(wc -l < block)
allow_count=$(wc -l < allow)
dead_count=$(wc -l < deadblock)
update_date=$(date '+%Y-%m-%d')
sed -i -e "14cTotal ad / tracking block list 屏蔽追踪广告总数: ${block_count}" \
       -e "16cTotal allowlist list 允许名单总数: ${allow_count}" \
       -e "18cTotal upstream-non-accessable list 上游无法访问域名总数: ${dead_count}" \
       -e "20cUpdate 更新时间: ${update_date}" \
       -e "46cNumber of Domain 域名数目： ${block_count}" README.md
echo "Done!"
