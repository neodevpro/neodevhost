![Logo](https://raw.githubusercontent.com/neodevpro/neodevhost/master/logo.png)

# NEO DEV HOST

**强大、友善、持续更新的去广告 Hosts 列表**<br/>
**Powerful, friendly and always up-to-date ad blocking hosts**

[![Build Status](https://img.shields.io/github/actions/workflow/status/neodevpro/neodevhost/Auto%20Update.yml)](https://github.com/neodevpro/neodevhost/actions)
[![Last commit](https://img.shields.io/github/last-commit/neodevpro/neodevhost.svg)](https://github.com/neodevpro/neodevhost/commit/master)
[![License](https://img.shields.io/github/license/neodevpro/neodevhost.svg)](https://github.com/neodevpro/neodevhost/blob/master/LICENSE)

```
Total ad / tracking block list 屏蔽追踪广告总数: 221277

Total allowlist list 允许名单总数: 114143

Total upstream-non-accessable list 上游无法访问域名总数: 32981

Update 更新时间: 2026-11-14
```

每天 UTC 08:00 自动构建，经校验后才发布。<br/>
Rebuilt and validated every day at 08:00 UTC by GitHub Actions.

## 目录 TOC

- [特性 Features](#特性-features)
- [下载 Download](#下载-download)
- [使用 Usage](#使用-usage)
- [Pi-hole 安装与卸载](#pi-hole-安装与卸载)
- [数据规则 Data rules](#数据规则-data-rules)
- [构建与开发 Build](#构建与开发-build)
- [上游源 Sources](#上游源-sources)
- [许可 License](#许可-license)

## 特性 Features

- **七种格式 · Seven formats**：host / Adblock / dnsmasq / SmartDNS / 纯域名 / Clash / sing-box（含 .srs），同一份数据一次生成。<br/>One build, seven formats including sing-box.
- **只保留真实域名 · Valid domains only**：逐个校验 RFC 标签规则、punycode、IANA TLD 与 Public Suffix List。<br/>Every entry is checked against RFC label rules, punycode, IANA TLDs and the PSL.
- **白名单不会吞掉整片网络 · No namespace wipe-out**：允许条目只覆盖自身及子域，`com.br`、`cloudfront.net` 这类条目绝不会放行整段命名空间。<br/>Allow entries cover only themselves and their subdomains, never a whole namespace.
- **自有名单优先 · Your list wins**：`ownblocklist` 的条目即使被上游白名单覆盖也会保留，冲突写进构建日志。<br/>Entries in `ownblocklist` survive upstream allowlists; conflicts are reported.
- **可复现 · Reproducible**：全部产物在临时目录生成、校验齐全后才发布，构建失败不会留下半成品。<br/>Outputs are built in a temp dir and published only once every file is complete.

## 下载 Download

Number of Domain 域名数目： 221277

| Format 格式 | 适用于 Works with | 下载 Raw | 国内加速 China mirror |
|---|---|:---:|:---:|
| Host | Pi-hole, AdAway, hBlock, AdGuard Home | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/host) | [link](https://neodev.team/host) |
| Adblocker | uBlock Origin, AdGuard / AdGuard Home | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/adblocker) | [link](https://neodev.team/adblocker) |
| Dnsmasq | dnsmasq, OpenWrt | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/dnsmasq.conf) | [link](https://neodev.team/dnsmasq.conf) |
| SmartDNS | SmartDNS | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/smartdns.conf) | [link](https://neodev.team/smartdns.conf) |
| Domain | 纯域名 / plain domains | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/domain) | [link](https://neodev.team/domain) |
| Clash | Clash / Mihomo rule-provider | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/clash) | [link](https://neodev.team/clash) |
| sing-box JSON | sing-box 1.8+ 源码 rule-set | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/singbox.json) | [link](https://neodev.team/singbox.json) |
| sing-box SRS | sing-box 1.8+ 二进制 rule-set | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/singbox.srs) | [link](https://neodev.team/singbox.srs) |
| Allowlist | Pi-hole / AdGuard 白名单 allowlist | [link](https://raw.githubusercontent.com/neodevpro/neodevhost/master/allow) | [link](https://neodev.team/allow) |

各格式长这样 / What each format looks like:

```
host            0.0.0.0  example.com
adblocker       ||example.com^
dnsmasq.conf    address=/example.com/0.0.0.0
smartdns.conf   address /example.com/#
domain          example.com
clash             - 'example.com'      # 位于 payload: 之下
singbox.json    {"version": 1, "rules": [{"domain_suffix": ["example.com"]}]}
```

> **Clash**：`clash` 是 rule-provider 格式（`behavior: domain`），请从 `rule-providers` 引用，不要粘贴进 `rules:`。<br/>
> **Clash**: the file is a `behavior: domain` rule-provider. Reference it from `rule-providers`; it does nothing inside `rules:`.

**sing-box 用法 / Usage**（`domain_suffix` 自动包含子域 / matches subdomains too）:

```json
{
  "route": {
    "rule_set": [
      {
        "type": "remote",
        "tag": "neodevhost",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/neodevpro/neodevhost/master/singbox.srs",
        "download_detour": "direct"
      }
    ],
    "rules": [{ "rule_set": "neodevhost", "action": "reject" }]
  }
}
```

国内加速可把 `url` 换成 `https://neodev.team/singbox.srs`。<br/>Use the China mirror URL above if GitHub is slow.

源码格式 / source format（`singbox.json`）适合自行编译：

```bash
sing-box rule-set compile --output singbox.srs singbox.json
```

## 使用 Usage

1. 下载文件，或复制上表中的链接。<br/>Download a file or copy a link from the table above.
2. 把 `host` 加入你的拦截器；建议同时导入 `allow` 白名单以减少误杀。<br/>Add `host` to your blocker; importing `allow` as well keeps false positives low.
3. 在应用里刷新数据源。<br/>Refresh the list inside the app.

| 平台 Platform | 做法 How |
|---|---|
| Pi-hole | Settings → Adlists 填入 `host` 链接，然后执行 `pihole -g`<br/>Settings → Adlists, add the `host` URL, then run `pihole -g` |
| AdGuard Home | Filters → DNS blocklists → 添加 `host` 链接<br/>Filters → DNS blocklists → add the `host` URL |
| AdAway (Android) | 添加 host 源 `https://neodev.team/host`<br/>Add the host source |
| dnsmasq / OpenWrt | 下载 `dnsmasq.conf` 放进 `/etc/dnsmasq.d/` 并重启<br/>Drop `dnsmasq.conf` into `/etc/dnsmasq.d/` and restart |
| SmartDNS | 下载 `smartdns.conf`，用 `conf-file` 引入<br/>Reference it with `conf-file` |
| uBlock Origin | 自定义规则列表填 `adblocker` 链接<br/>Add the `adblocker` URL as a custom filter list |
| Clash / Mihomo | `rule-providers` 指向 `clash`，`behavior: domain`<br/>Point a `rule-providers` entry at `clash` |

## Pi-hole 安装与卸载

### 安装 Install

1. 登录 Pi-hole 后台。<br/>Log in to the Pi-hole admin page.
2. 打开 Adlists / Lists 页面（v5: Group Management → Adlists；v6: Lists），把 `host` 链接填入 Address。<br/>Open the Adlists / Lists page and paste the `host` URL.
3. 在终端执行下面的命令。<br/>Run the following in a terminal:

```bash
sudo -i
curl -fsSL https://raw.githubusercontent.com/neodevpro/neodevhost/master/install.sh | bash
pihole -g
```

`install.sh` 会分块导入 `allow` 白名单（v5 用 `pihole -w`，v6 用 `pihole allow`），约几分钟。<br/>
`install.sh` imports the `allow` list in chunks (v5: `pihole -w`, v6: `pihole allow`); it takes a few minutes.

> 自建镜像可用 `NEODEV_ALLOWLIST_URL=https://你的镜像/allow` 覆盖下载地址。<br/>
> Point it at your own mirror with `NEODEV_ALLOWLIST_URL`.

### 卸载 Uninstall

1. 在 Adlists 里点红色垃圾桶删除对应条目。<br/>Remove the adlist with the red trash icon.
2. 在终端执行 / In a terminal:

```bash
sudo -i
curl -fsSL https://raw.githubusercontent.com/neodevpro/neodevhost/master/uninstall.sh | bash
```

只移除**本列表包含的**域名，不会动你自己添加的白名单。<br/>
It removes only the domains from this list and leaves your own allow entries untouched.

## 数据规则 Data rules

流程 / Pipeline：`上游下载 fetch → 格式归一 extract → 合法性校验 validate → 去冗余 reduce → 扣除白名单/过期 exclude → 成品检查 checks → 发布 publish`

| 规则 Rule | 说明 Description |
|---|---|
| 格式归一 Format | 支持 plain / hosts / dnsmasq / Adblock `\|\|x^` / `@@` 例外 / URL 列表<br/>Accepts plain, hosts, dnsmasq, Adblock and URL lists |
| 元素隐藏 Cosmetic | `example.com##.banner` 被丢弃：它不携带 DNS 信息，误用会屏蔽整站<br/>Cosmetic rules are dropped; they carry no DNS information |
| 域名合法性 Validity | RFC 标签规则、punycode `xn--`、IANA TLD、Public Suffix List 四重校验<br/>RFC labels, punycode, IANA TLDs and the PSL |
| 公共后缀 Suffixes | 允许名单中本身就是公共后缀的条目被丢弃；屏蔽名单中出现 ICANN 公共后缀（`com.br`）视为数据错误<br/>Bare suffixes are dropped from allowlists; ICANN suffixes in blocklists are treated as data errors |
| 白名单语义 Allowlist | 允许条目只覆盖自身及子域，且不得高于目标域名的注册域<br/>An allow entry covers itself and subdomains, never above the registrable domain |
| 自有名单 Own lists | `ownallowlist` 计入白名单；`ownblocklist` 优先级最高，被覆盖时会加回并告警<br/>`ownblocklist` always wins and conflicts are reported |
| 品牌豁免 Brand ignore | `allowignore` 中的品牌，其上游白名单条目被忽略（默认 29 个广告品牌）<br/>Upstream entries for brands in `allowignore` are ignored (29 ad brands by default) |
| 过期域名 Dead domains | 每次构建用 `tools/check-dead-domains.py` 实测解析，双解析器确认后才判定为死域并剔除<br/>Every build resolves the list (DoH → HTTP → UDP) and drops names two resolvers agree are dead |
| 成品检查 Checks | 不比较历史大小（上游增删来源属正常波动）；仅在参考数据残缺（PSL/TLD 下载不完整）、产物为空，或单轮死域超过存活数一半（解析器被劫持）时中止<br/>Sizes are never compared across runs; the build aborts on truncated reference data, empty output, or a run where dead domains outnumber live ones (hijacked resolvers) |

## 构建与开发 Build

```bash
bash host.sh                       # 构建并发布 / build and publish
bash host.sh --dry-run             # 只构建不发布 / build only, keep the work dir
bash host.sh --no-dead-check       # 跳过存活检测 / skip the liveness check
bash tests/run.sh                  # 阶段单测，不联网 / stage unit tests, offline
bash tests/audit.sh                # 逐源审计 + 成品校验 / per-source audit (needs network)
```

只依赖 `bash` + `curl`（或 `wget`）；`singbox.srs` 由 `sing-box` 编译，未安装时跳过该文件。<br/>
Requires `bash` plus `curl` (or `wget`); `singbox.srs` is compiled with `sing-box` and skipped when it is missing.

```
host.sh                     入口 / entry: fetch → validate → merge → dead check → render → publish
lib/psl.awk                 Public Suffix List 通用函数 / shared PSL helpers
lib/extract.awk             任意格式 → 候选主机名 / any format → candidate hosts
lib/validate.awk            候选 → 合法域名 / candidates → valid domains
lib/ignore.awk              按 allowignore 忽略上游条目 / drop ignored allow entries
lib/reduce.awk              去掉被父域覆盖的冗余条目 / drop redundant subdomains
lib/exclude.awk             扣除白名单（PSL 感知）/ PSL-aware allowlist exclusions
lib/deadblock.awk           精确剔除已判定死亡的域名 / exact dead-domain subtraction
lib/render.awk              一次遍历生成七种格式 / render all seven formats
tests/run.sh                21 项阶段单测 / 21 stage tests
tests/audit.sh              逐源统计与成品不变量 / per-source stats + invariants
tools/check-dead-domains.py 域名存活检测（DoH/HTTP/UDP）/ domain liveness checker
allowlist blocklist         上游源 URL / upstream source URLs
ownallowlist ownblocklist   自有名单，改完即生效 / local lists, effective immediately
allowignore                 上游白名单"不得放行"的品牌 / brands upstream may not whitelist
```

| 环境变量 Variable | 默认 Default | 作用 Purpose |
|---|:---:|---|
| `NEODEV_MIN_PSL_RULES` | 5000 | PSL 规则数下限<br/>Minimum PSL rules expected |
| `NEODEV_MIN_TLDS` | 1000 | IANA TLD 数量下限<br/>Minimum IANA TLDs expected |
| `KEEP_WORK_DIR` | 0 | 设为 1 保留临时目录<br/>Keep the temporary build directory |
| `SING_BOX_BIN` | auto | `sing-box` 可执行文件路径，用于编译 `.srs`<br/>Path to the `sing-box` binary used to compile `.srs` |
| `CHECK_CONCURRENCY` | 400 | 存活检测并发数，CI 用 1000<br/>Liveness-check concurrency (CI uses 1000) |
| `CHECK_STRICT_RESOLVERS` | 0 | 解析器数量不达标时直接失败（CI 开启）<br/>Fail when a resolver pool is below the required mix (CI) |
| `CHECK_MIN_OVERSEAS` / `CHECK_MIN_CHINA` | 2 / 2 | 每个池至少要有的海外 / 国内解析器数<br/>Minimum overseas / China resolvers per pool |
| `NEODEV_CHECK_LIMIT` | 空 | 只检测前 N 个域名（调试用）<br/>Check only the first N domains (debugging) |

CI（`.github/workflows/Auto Update.yml`）：安装 `idn2`、`sing-box` v1.14.4 与 Python 依赖（`dnspython`、`aiohttp`）→ shellcheck → 单测 → 构建（含存活检测）→ 提交。<br/>
CI runs: install `idn2`, `sing-box` and the Python deps → shellcheck → unit tests → build (including the liveness sweep) → commit. 可在 Actions 页面勾选 `dry_run` 只构建不提交 / tick `dry_run` to build without publishing.

## 上游源 Sources

### 屏蔽源 Blocklists

| Source | Link |
|---|---|
| Anti-ad | [link](https://github.com/privacy-protection-tools/anti-AD) |
| 217heidai | [link](https://github.com/217heidai/adblockfilters) |
| StevenBlack | [link](https://github.com/StevenBlack/hosts) |

### 允许源 Allowlists

以下即仓库内 `allowlist` 的全部 URL。<br/>
These are exactly the URLs listed in `allowlist`.

| Source | Link |
|---|---|
| AnudeepND | [link](https://github.com/anudeepND/whitelist) |
| Ultimate-Hosts-Blacklist | [link](https://github.com/Ultimate-Hosts-Blacklist/whitelist) |
| Energized Protection | [link](https://github.com/EnergizedProtection/unblock) |
| 217heidai | [link](https://github.com/217heidai/adblockfilters) |
| blahdns | [link](https://github.com/fun-ed/blahdns) |
| HaGeZi DNS Blocklists | [link](https://github.com/hagezi/dns-blocklists) |
| AdAway White List | [link](https://github.com/lingeringsound/10007_auto) |
| GoodnessJSON Pi-hole Whitelist | [link](https://github.com/GoodnessJSON/PiHole-Whitelist) |
| Pi-hole VeryHighWL | [link](https://github.com/rahilpathan/pihole-whitelist) |
| freekers whitelist | [link](https://github.com/freekers/whitelist) |
| China CDN Domain Whitelist | [link](https://github.com/mawenjian/china-cdn-domain-whitelist) |
| Discord official domains | [link](https://github.com/Dogino/Discord-Phishing-URLs) |
| notracking whitelist | [link](https://github.com/notracking/hosts-blocklists-scripts) |
| URL shorteners | [link](https://github.com/boutetnico/url-shorteners) |

> 上游白名单常包含厂商根域（`google.com`、`doubleclick.net`），这些条目由 `allowignore` 过滤，否则整片广告子域将永远无法屏蔽。<br/>
> Upstream whitelists contain vendor root domains; `allowignore` drops them so their ad hosts can still be blocked.

### 过期域名 Dead domains

`deadblock` 不再从外部仓库下载，而是每次构建由本仓库的 `tools/check-dead-domains.py` 现场检测：

- 输入：本轮候选列表 + 上一版 `deadblock`（这样上游删掉的死域仍会复检，复活的会被移出）
- 解析器池：**3 海外 + 3 国内**（Cloudflare、Google、DoH.sb ｜ AliDNS、DNSPod、360）。启动时逐个探活，不达 `CHECK_MIN_*` 就失败
- 兜底链路：DNS over HTTPS → 明文 HTTP → UDP；明文只有阿里一家（其余厂商一律 301 到 HTTPS），所以该池只要求国内数量
- 判定标准：**两个独立解析器都确认**才算死亡，两次查询按区域交替（先海外再国内）；超时/SERVFAIL 记为 unknown，绝不写入
- 结果先写 `<file>.tmp`，跑完才原子替换，中途失败不会污染上一版

```bash
python3 tools/check-dead-domains.py --input block --output deadblock
python3 tools/check-dead-domains.py --limit 500 --dry-run      # 抽样调试
python3 tools/check-dead-domains.py --transport udp --resolvers 127.0.0.1:53
```

依赖 `python3` + `dnspython` + `aiohttp`；CI 会自动安装。本地缺依赖或加 `--no-dead-check` 时，
直接复用仓库里已有的 `deadblock`（不会因为环境缺失把列表改坏）。

The list is now measured in-house on every build instead of being downloaded; without
python or its dependencies the previous `deadblock` is reused unchanged.

Resolver pools are `3 overseas` (Cloudflare, Google, DoH.sb) + `3 China` (AliDNS, DNSPod,
360), probed at startup. The fallback order is DoH → plaintext HTTP → UDP; plaintext JSON
DoH only exists at Aliyun today, so that pool is China-only by nature. A name is dropped
only when two resolvers from different regions agree it is dead.

## 许可 License

[LICENSE](https://github.com/neodevpro/neodevhost/blob/master/LICENSE)

数据归各上游项目所有，本项目只做合并、校验与格式转换，请同时遵守上游许可。<br/>
Data belongs to the upstream projects above; this repository only merges, validates and reformats.
