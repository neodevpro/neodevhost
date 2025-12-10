#!/bin/bash

# Clean up old files
echo "Clean..."
rm -f host adblocker dnsmasq.conf smartdns.conf domain clash allow block public_suffix_list.dat


# Pre-Fetch TLD list and Public Suffix List
TLD_LIST=$(wget -qO- "https://data.iana.org/TLD/tlds-alpha-by-domain.txt" | tail -n +2 | tr '[:upper:]' '[:lower:]')
PSL_URL="https://publicsuffix.org/list/public_suffix_list.dat"
wget -qO public_suffix_list.dat "$PSL_URL"
PSL_LIST=$(grep -vE '^//|^$' public_suffix_list.dat | tr -d '\r')

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



# Reserved/blocked domains (RFC 2606)
RESERVED_DOMAINS="example.com example.net example.org test localhost invalid local"

# Enhanced domain validation with IDN (punycode) and PSL support
echo "Validating domain format (RFC, IDN, PSL, reserved)..."

# Convert IDN to punycode if 'idn' is available, else pass through
idn_convert() {
  if command -v idn >/dev/null 2>&1; then
    idn --quiet || cat
  else
    cat
  fi
}

# Comprehensive domain regex (RFC 1035/1123/5890, punycode, Unicode)
domain_name_regex="^((xn--)?[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\.)+([a-zA-Z]{2,}|xn--[a-zA-Z0-9]+)$"


# Validate against PSL (match domain's public suffix, read PSL from file)
validate_psl() {
  awk -v psl_file="public_suffix_list.dat" '
    BEGIN {
      while ((getline line < psl_file) > 0) {
        if (line ~ /^\/\// || line ~ /^$/) continue;
        psl[tolower(line)] = 1;
      }
      close(psl_file);
    }
    {
      split($0, labels, ".");
      for (i = 2; i <= length(labels); i++) {
        suffix = "";
        for (j = i; j <= length(labels); j++) {
          suffix = suffix ((suffix=="")?"":".") labels[j];
        }
        if (psl[tolower(suffix)]) { print $0; break; }
      }
    }'
}

# Filter reserved/blocked domains
filter_reserved_blocked() {
  grep -vE "$(echo $RESERVED_DOMAINS | sed 's/ /|/g')"
}

# Remove lines with invalid characters, consecutive dots, leading/trailing dots, overly long domains/labels
filter_domains() {
  awk '
    length($0)<=253 &&
    $0 !~ /[^a-zA-Z0-9.-]/ &&
    $0 !~ /\.\./ &&
    $0 !~ /^\.|\.$/ &&
    $0 !~ /\.local$|\.localhost$|\.invalid$|\.test$/ &&
    $0 !~ /\.[0-9]+$/ {
      split($0, labels, ".");
      valid=1;
      for(i in labels) {
        # Empty label
        if(labels[i]=="") {valid=0; break}
        # Label length
        if(length(labels[i])>63) {valid=0; break}
        # Leading/trailing hyphen
        if(labels[i] ~ /^-/ || labels[i] ~ /-$/) {valid=0; break}
        # Consecutive hyphens in 3rd/4th position (reserved for IDN)
        if(length(labels[i])>=4 && substr(labels[i],3,2)=="--" && i!=length(labels)) {valid=0; break}
        # Non-ASCII after punycode conversion
        if(labels[i] ~ /[^a-zA-Z0-9-]/) {valid=0; break}
      }
      # Numeric-only TLD
      if(labels[length(labels)] ~ /^[0-9]+$/) {valid=0}
      if(valid) print $0;
    }'
}

# Apply all checks: IDN, lowercase, remove trailing dot, regex, domain filter, reserved/blocked, PSL
normalize_domains() {
  awk '{
    d=tolower($0);
    sub(/\.$/, "", d);
    print d;
  }'
}

idn_convert < "allow" | \
normalize_domains | \
grep -E "$domain_name_regex" | \
filter_domains | \
filter_reserved_blocked | \
validate_psl > "clean_allow"

idn_convert < "block" | \
normalize_domains | \
grep -E "$domain_name_regex" | \
filter_domains | \
filter_reserved_blocked | \
validate_psl > "clean_block"

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
sed -i -e '14,$s/^/address \/' -e '14,$s/$/\/#/' smartdns.conf
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
