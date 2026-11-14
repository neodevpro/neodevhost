# Write every published format in one pass over the domain list.
#
#   host            Pi-hole / AdAway / hBlock   0.0.0.0  <domain>
#   adblocker       uBlock / AdGuard            ||<domain>^
#   dnsmasq.conf    dnsmasq                      address=/<domain>/0.0.0.0
#   smartdns.conf   SmartDNS                     address /<domain>/#
#   domain          plain domain list
#   clash           Clash rule-provider          payload: + "  - '<domain>'"

BEGIN {
  quote = sprintf("%c", 39)

  while ((getline line < title_file) > 0) {
    print line > (out_dir "/host")
    print line > (out_dir "/adblocker")
    print line > (out_dir "/dnsmasq.conf")
    print line > (out_dir "/smartdns.conf")
    print line > (out_dir "/domain")
    print line > (out_dir "/clash")
  }
  close(title_file)
  print "payload:" > (out_dir "/clash")
}

{
  print "0.0.0.0  " $0           > (out_dir "/host")
  print "||" $0 "^"              > (out_dir "/adblocker")
  print "address=/" $0 "/0.0.0.0" > (out_dir "/dnsmasq.conf")
  print "address /" $0 "/#"       > (out_dir "/smartdns.conf")
  print $0                        > (out_dir "/domain")
  print "  - " quote $0 quote     > (out_dir "/clash")
}

END {
  close(out_dir "/host")
  close(out_dir "/adblocker")
  close(out_dir "/dnsmasq.conf")
  close(out_dir "/smartdns.conf")
  close(out_dir "/domain")
  close(out_dir "/clash")
}
