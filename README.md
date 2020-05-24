NEODEV HOST

![Logo](https://raw.githubusercontent.com/neodevpro/neodevhost/master/logo.png)


## The Powerful Friendly Uptodate AD Blocking Hosts 最新强大而友善的去广告
   

[![Build Status](https://img.shields.io/github/workflow/status/neodevpro/neodevhost/CI/master)](https://github.com/neodevpro/neodevhost/actions?workflow=CI)<br/>
[![Last commit](https://img.shields.io/github/last-commit/neodevpro/neodevhost.svg)](https://github.com/neodevpro/neodevhost/commit/master)<br/>
[![license](https://img.shields.io/github/license/neodevpro/neodevhost.svg)](https://github.com/neodevpro/neodevhost/blob/master/LICENSE)

```
Total ad / tracking block list 屏蔽追踪广告总数: 298998

Total whitelist list 白名单总数: 2904

Total combine list 结合总数： 283173

Update 更新时间: 2020-05-24
```
## Introduction 介绍

### UPTODATE 保持最新<br/>
    Merge everyhours　每小时更新
### POWERFUL　 强大有效<br/>
    To block all ad / tracking  有效拦截广告追踪　
### FRIENDLY　友善使用<br/>
    Easy to use and welcome to report issues　简单使用欢迎回报问题
   
## Supported Platform 支持平台
```
-Windows
-Android
-Linux
-Mac OS
-Openwrt
-etc
```
### Supported adblocker 广告拦截器
```
-Pihole
-Adaway
-Adblocker/Adguard
-etc
```
## Download 下载 

### Recommend 建议下载　: AD + Whitelist [Host] 去广告+白名单　结合拦截
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/combine
```
### AD host 去广告 [hosts]
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/host
```

### Whitelist 域名白名单 [whitelist]
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/whitelist
```


### For Adblocker (Adguard)　广告拦截器　: AD 去广告
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/adblocker
```

### For Adblocker (Adguard)　广告拦截器　: Whitelist 白名单（防止拦截错误）
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/adblockerwhite
```

### For Adblocker (Adguard)　广告拦截器　: AD + Whitelist 去广告+白名单　结合拦截
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/adblockercombine
```

### Dnsmasq AD List Dnsmasq 广告拦截格式 [Dnsmasq] 
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/hosts_dnsmasq.conf
```

### Dnsmasq AD + Whitelist　List Dnsmasq　广告+白名单　结合拦截格式  [Dnsmasq] 
``` 
https://raw.githubusercontent.com/neodevpro/neodevhost/master/combinehosts_dnsmasq.conf
```
### Domain AD 普通广告域名
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/domain
```

### Domain AD + Whitelist　普通 广告+白名单　域名结合
```
https://raw.githubusercontent.com/neodevpro/neodevhost/master/domaincombine
```

## How To Use 如何使用
```
1.Download both files/copy link of files
2.Add host and whitelist file/link into adblocker
3.Update the data source in the app
```
```
1.下载两个文件/复制下载链接
2.添加文件或者下载链接到广告拦截器
3.更新数据规则
```
## Pihole Installation 安装导入教程

Import and Installation 导入和安装<br/>

1.Login to pihole website<br/>
2.Go to Groupmanagement > Adlists<br/>
3.copy the NEODEV AD host link into "Address:"<br/>
4.open terminal<br/>
5. Run the following command :<br/>
```
sudo -i
sudo curl -s https://raw.githubusercontent.com/neodevpro/neodevhost/master/install.sh | bash
pihole -g
```
6.Wait for 20 mins around  <br/>
7.Then it will import both NEODEV host and whitelist into your Pihole <br/>


Remove and Uninstall 移除和卸载<br/>

1.Login to pihole website<br/>
2.Go to Groupmanagement > Adlists<br/>
3.click the red trash can button<br/>
4.open terminal<br/>
5. Run the following command :<br/>
```
sudo -i
sudo curl -s https://raw.githubusercontent.com/neodevpro/neodevhost/master/uninstall.sh | bash
pihole -g
```
6.Wait for 20 mins around  <br/> <br/>
7.Then it will Remove and Uninstall both NEODEV host and whitelist from your Pihole <br/>

## Sources of AD-hosts data 去广告host源

>https://hblock.molinero.xyz/hosts<br/>
>https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts<br/>
>https://raw.githubusercontent.com/jdlingyu/ad-wars/master/hosts<br/>
>https://raw.githubusercontent.com/jdlingyu/ad-wars/master/sha_ad_hosts<br/>
>https://raw.githubusercontent.com/Goooler/1024_hosts/master/hosts<br/>
>https://hosts.nfz.moe/full/hosts<br/>
>https://raw.githubusercontent.com/yous/YousList/master/hosts.txt<br/>
>https://raw.githubusercontent.com/ilpl/ad-hosts/master/hosts<br/>
>https://raw.githubusercontent.com/Licolnlee/blog-cloud-storage/master/adblock.txt<br/>

## Sources of Whitelist data 域名白名单源

>https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt<br/>
>https://raw.githubusercontent.com/VeleSila/yhosts/master/whitelist.txt<br/>
>https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/whitelist/master/domains.list<br/>
>https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt<br/>
>https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt<br/>

