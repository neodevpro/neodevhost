#!/bin/bash

# 正则表达式用于验证有效域名
domain_name_regex="^[a-zA-Z0-9]+([-.][a-zA-Z0-9]+)*\.[a-zA-Z]{2,}(:[0-9]+)?([/?].*)?$"

# 清理函数：删除指定的临时文件
clean_up() {
    echo "Cleaning up old files..."
    rm -f host lite_host lite_adblocker adblocker lite_dnsmasq.conf dnsmasq.conf deadallow deadblock checkblock checkallow \
        smartdns.conf lite_smartdns.conf domain lite_domain clash lite_clash allow block lite_block
}

# 合并列表函数：处理 allowlist 和 blocklist 的合并
merge_list() {
    local list_file=$1
    local output_file=$2

    echo "Merging $list_file..."
    while IFS= read -r url; do
        wget --no-check-certificate -t 1 -T 10 -q -O - "$url"
    done < "$list_file" | sed '/#/d; /^$/d; s/[[:space:]]//g' | sort -u > "$output_file"
}

# 检查死链函数：检查 deadallow 或 deadblock 列表
check_dead_list() {
    local list_file=$1
    local dead_url=$2

    echo "Checking dead entries in $list_file..."
    wget --no-check-certificate -t 1 -T 10 -q "$dead_url" -O dead_tmp
    sort "$list_file" dead_tmp dead_tmp | uniq -u > tmp && mv tmp "$list_file"
    rm -f dead_tmp
}

# 过滤有效域名格式
filter_valid_domains() {
    local input_file=$1
    grep -E "$domain_name_regex" "$input_file" > tmp && mv tmp "$input_file"
}

# 生成输出文件
generate_output_files() {
    local host_file=$1
    local lite_file=$2

    echo "Generating output files..."
    cp "$host_file" adblocker dnsmasq.conf smartdns.conf domain
    cp "$lite_file" lite_adblocker lite_dnsmasq.conf lite_smartdns.conf lite_domain

    # adblocker 格式化
    sed -i 's/^/||&/; s/$/&^/' adblocker lite_adblocker

    # host 文件格式化为 0.0.0.0
    sed -i 's/^/0.0.0.0  &/' "$host_file" "$lite_file"

    # dnsmasq 格式化
    sed -i 's/^/address=\/&/; s/$/&\/0.0.0.0/' dnsmasq.conf lite_dnsmasq.conf

    # smartdns 格式化
    sed -i 's/^/address \/&/; s/$/&\/#/' smartdns.conf lite_smartdns.conf
}

# 更新 README 文件
update_readme() {
    echo "Updating README..."
    sed -i "
        14cTotal ad / tracking block list 屏蔽追踪广告总数: $(wc -l < block)
        16cTotal allowlist list 允许名单总数: $(wc -l < allow)
        18cTotal combine list 结合总数： $(wc -l < host)
        20cTotal deadblock list 失效屏蔽广告域名： $(wc -l < deadblock)
        22cTotal deadallow list 失效允许广告域名： $(wc -l < deadallow)
        24cUpdate 更新时间: $(date '+%Y-%m-%d')
        54cNumber of Domain 域名数目： $(wc -l < domain)
        64cNumber of Domain 域名数目： $(wc -l < lite_domain)
    " README.md
}

# 更新标题文件
update_titles() {
    local host_count=$(wc -l < host)
    local lite_count=$(wc -l < lite_host)

    echo "Updating titles..."
    for i in {1..12}; do
        sed -i "
            9c# Last update: $(date '+%Y-%m-%d')
            11c# Number of blocked domains: $([ $i -le 6 ] && echo "$lite_count" || echo "$host_count")
        " title.$i
    done
}

# 生成 Clash 支持文件
generate_clash_files() {
    echo "Adding Clash support..."
    sed -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" domain >> clash
    sed -e '14i payload:' -e "14,\$s/^/  - '/" -e "14,\$s/$/'/" lite_domain >> lite_clash
}

# 主流程
main() {
    clean_up

    # 合并 allowlist 和 blocklist
    merge_list allowlist allow
    merge_list blocklist block

    # 检查死链
    check_dead_list allow https://raw.githubusercontent.com/neodevpro/dead-allow/master/deadallow
    check_dead_list block https://raw.githubusercontent.com/FusionPlmH/dead-block/master/deadblock

    # 过滤有效域名
    filter_valid_domains allow
    filter_valid_domains block

    # 生成最终的 host 和 lite_host 文件
    sort -u block allow | uniq -u > host
    sort -u lite_block allow | uniq -u > lite_host

    # 生成各种格式的输出文件
    generate_output_files host lite_host

    # 更新 README 和标题
    update_readme
    update_titles

    # 生成 Clash 文件
    generate_clash_files

    # 清理临时文件
    clean_up

    echo "Done!"
}

# 执行主流程
main
