# Drop domains that the liveness checker recorded as not resolving.
#
# The deadlist is read first (FNR == NR), the domain list second:
#   awk -f deadblock.awk deadblock host.domains
#
# Matching is exact on purpose: a live subdomain must stay blocked even when its
# parent no longer resolves.

FNR == NR { dead[$0] = 1; next }
!($0 in dead)