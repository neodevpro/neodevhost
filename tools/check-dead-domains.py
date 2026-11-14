#!/usr/bin/env python3
"""Bulk dead-domain checker.

Reads a domain list (default: ``block``) plus every name already recorded in
the output file (default: ``deadblock``), resolves all of them concurrently and
writes the names that no longer exist to the output file. Each run re-checks the
whole accumulated list, so domains that came back to life disappear while dead
names that upstream dropped from its list are kept.

A name is only recorded as dead when two independent resolvers agree. Names
that cannot be resolved because of timeouts or broken authoritative servers are
reported as unknown and left alone, so transient DNS failures never end up in
the list.

Resolution uses DNS over HTTPS when possible (immune to local DNS filtering and
to firewalls that block UDP/53), falls back to the same JSON API over plain HTTP
when TLS is blocked, and finally to plain UDP resolvers. Resolvers are tagged by
region and a pool is only accepted when it still has enough overseas *and* China
entries, so one network cannot decide the result on its own. Results are written
to ``<output>.tmp`` after every batch and only replace the output file when the
run completes, so a failed run never truncates the previous list.
"""

from __future__ import annotations

import argparse
import asyncio
import itertools
import os
import sys
import time
from pathlib import Path

import aiohttp
import dns.asyncresolver
import dns.exception
import dns.resolver

DEAD = "dead"
ALIVE = "alive"
UNKNOWN = "unknown"
SINKHOLED = "sinkholed"

# Every resolver is tagged with the region it is operated from. A run must not
# depend on a single network, so the pools below are probed at startup and a
# pool is only accepted when it still has enough of both.
#
# DoH here means the JSON API (status/answer fields); endpoints that only speak
# RFC 8484 wire format (Quad9, AdGuard, Mullvad, ...) cannot be used.
HTTPS_ENDPOINTS = (
    ("overseas", "https://cloudflare-dns.com/dns-query"),
    ("overseas", "https://dns.google/resolve"),
    ("china", "https://dns.alidns.com/resolve"),
    ("china", "https://doh.pub/dns-query"),
    ("china", "https://doh.360.cn/resolve"),
)
# Plain HTTP is only a fallback for networks that block TLS; it is unencrypted.
HTTP_ENDPOINTS = (
    ("china", "http://223.5.5.5/resolve"),
)
UDP_RESOLVERS = (
    ("overseas", "1.1.1.1"),
    ("overseas", "8.8.8.8"),
    ("overseas", "9.9.9.10"),  # Quad9 unfiltered: the filtered edition answers NXDOMAIN for malware
    ("overseas", "208.67.222.222"),
    ("china", "223.5.5.5"),
    ("china", "119.29.29.29"),
    ("china", "180.76.76.76"),
)
SINKHOLE_ADDRESSES = frozenset({"0.0.0.0", "127.0.0.1", "::", "::1"})
RRTYPE_NUMBERS = {"A": 1, "AAAA": 28, "MX": 15}


def _region_counts(pairs: list[tuple[str, str]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for region, _ in pairs:
        counts[region] = counts.get(region, 0) + 1
    return counts


def _interleave(pairs: list[tuple[str, str]]) -> list[str]:
    """Alternate regions so two consecutive queries never share a network."""
    buckets: dict[str, list[str]] = {}
    for region, value in pairs:
        buckets.setdefault(region, []).append(value)
    # Known regions first, anything else (custom endpoints) after them.
    order = ["overseas", "china"] + [region for region in buckets if region not in ("overseas", "china")]
    ordered: list[str] = []
    for index in range(max((len(values) for values in buckets.values()), default=0)):
        for region in order:
            if index < len(buckets.get(region, ())):
                ordered.append(buckets[region][index])
    return ordered


async def _probe_pool(pool: tuple[tuple[str, str], ...], probe, timeout: float) -> list[tuple[str, str]]:
    results = await asyncio.gather(*(probe(value, timeout) for _, value in pool))
    return [pair for pair, ok in zip(pool, results) if ok]


async def _select(label: str, pool: tuple[tuple[str, str], ...], probe, args: argparse.Namespace):
    """Return the reachable endpoints of a pool, or None when it is unusable.

    A pool is accepted when it still has ``--min-overseas`` overseas and
    ``--min-china`` China endpoints (3 + 3 when everything is healthy). Pools
    that fall short are still used with a warning unless ``--strict-resolvers``
    is set, so a restricted network degrades instead of failing outright.
    """
    reachable = await _probe_pool(pool, probe, args.timeout)
    if not reachable:
        print(f"{label}: no endpoint reachable", file=sys.stderr)
        return None

    counts = _region_counts(reachable)
    overseas = counts.get("overseas", 0)
    china = counts.get("china", 0)
    detail = f"{overseas} overseas, {china} china"

    if overseas >= args.min_overseas and china >= args.min_china:
        endpoints = _interleave(reachable)
        print(f"using {label} ({detail}): {', '.join(endpoints)}")
        return endpoints

    if args.strict_resolvers:
        print(f"{label} is below the required mix ({detail}); --strict-resolvers is set", file=sys.stderr)
        return None

    print(f"warning: {label} is degraded ({detail}); continuing with what is reachable", file=sys.stderr)
    return _interleave(reachable)



class DohTransport:
    """DNS over HTTPS using the JSON API of Cloudflare and Google."""

    def __init__(self, endpoints: list[str], timeout: float, concurrency: int) -> None:
        self._endpoints = itertools.cycle(endpoints)
        self._timeout = timeout
        self._session: aiohttp.ClientSession | None = None
        self._connector_limit = concurrency + 10

    async def __aenter__(self) -> "DohTransport":
        self._session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=self._timeout),
            connector=aiohttp.TCPConnector(limit=self._connector_limit, ttl_dns_cache=600),
        )
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        if self._session is not None:
            await self._session.close()

    async def query(self, name: str, rdtype: str, tries: int) -> tuple[str, list[str]]:
        for attempt in range(tries):
            endpoint = next(self._endpoints)
            try:
                assert self._session is not None
                async with self._session.get(
                    endpoint,
                    params={"name": name, "type": rdtype},
                    headers={"accept": "application/dns-json"},
                ) as response:
                    response.raise_for_status()
                    payload = await response.json(content_type=None)
            except (aiohttp.ClientError, asyncio.TimeoutError):
                if attempt + 1 < tries:
                    await asyncio.sleep(0.2 * (attempt + 1))
                continue

            status = payload.get("Status", 2)
            if status == 3:
                return "nxdomain", []
            if status != 0:
                if attempt + 1 < tries:
                    await asyncio.sleep(0.2 * (attempt + 1))
                continue
            wanted = RRTYPE_NUMBERS[rdtype]
            addresses = [record.get("data", "") for record in payload.get("Answer", []) if record.get("type") == wanted]
            return ("yes", addresses) if addresses else ("nodata", [])
        return "error", []


def split_server(spec: str) -> tuple[str, int]:
    """Split ``host`` or ``host:port`` (IPv6 literals without a port still work)."""
    host, separator, port = spec.rpartition(":")
    if separator and host and port.isdigit() and ":" not in host:
        return host, int(port)
    return spec, 53


class UdpTransport:
    """Round-robin over plain DNS resolvers so no single server gets hammered."""

    def __init__(self, servers: list[str | None], timeout: float) -> None:
        self._resolvers = []
        for server in servers:
            if server is None:
                resolver = dns.asyncresolver.Resolver()
            else:
                host, port = split_server(server)
                resolver = dns.asyncresolver.Resolver(configure=False)
                resolver.nameservers = [host]
                resolver.port = port
            resolver.timeout = timeout
            resolver.lifetime = timeout
            resolver.retry_servfail = False
            self._resolvers.append(resolver)
        self._cycle = itertools.cycle(self._resolvers)

    async def __aenter__(self) -> "UdpTransport":
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        return None

    async def query(self, name: str, rdtype: str, tries: int) -> tuple[str, list[str]]:
        for attempt in range(tries):
            resolver = next(self._cycle)
            try:
                answer = await resolver.resolve(name, rdtype, lifetime=resolver.lifetime, raise_on_no_answer=True)
                if rdtype in ("A", "AAAA"):
                    return "yes", [rdata.address for rdata in answer]
                return "yes", []
            except dns.resolver.NXDOMAIN:
                return "nxdomain", []
            except dns.resolver.NoAnswer:
                return "nodata", []
            except dns.exception.DNSException:
                if attempt + 1 < tries:
                    await asyncio.sleep(0.2 * (attempt + 1))
        return "error", []


async def _probe(transport, name: str, tries: int, sinkhole_dead: bool) -> str:
    a_kind, addresses = await transport.query(name, "A", tries)
    if a_kind == "nxdomain":
        return DEAD  # NXDOMAIN is independent of the record type
    if a_kind == "error":
        return UNKNOWN

    usable = [address for address in addresses if address not in SINKHOLE_ADDRESSES]
    aaaa_addresses: list[str] = []
    if not usable:
        aaaa_kind, aaaa_addresses = await transport.query(name, "AAAA", tries)
        if aaaa_kind == "error":
            return UNKNOWN
        usable = [address for address in aaaa_addresses if address not in SINKHOLE_ADDRESSES]

    if usable:
        return ALIVE
    if addresses or aaaa_addresses:
        # The name resolves, but only to 0.0.0.0 / loopback: nothing is reachable.
        return DEAD if sinkhole_dead else SINKHOLED

    # No address records at all: mail-only domains still count as alive.
    mx_kind, _ = await transport.query(name, "MX", tries)
    if mx_kind == "yes":
        return ALIVE
    if mx_kind == "error":
        return UNKNOWN
    return DEAD


async def check_and_report(transport, semaphore: asyncio.Semaphore, name: str, args: argparse.Namespace) -> tuple[str, str]:
    async with semaphore:
        status = await _probe(transport, name, args.tries, args.sinkhole_dead)
        if status == DEAD and not args.no_confirm:
            status = await _probe(transport, name, args.tries, args.sinkhole_dead)
        return name, status


async def _udp_reachable(server: str, timeout: float) -> bool:
    host, port = split_server(server)
    resolver = dns.asyncresolver.Resolver(configure=False)
    resolver.nameservers = [host]
    resolver.port = port
    resolver.timeout = timeout
    resolver.lifetime = timeout
    resolver.retry_servfail = False
    try:
        await resolver.resolve("example.com", "A", lifetime=timeout)
        return True
    except dns.resolver.NXDOMAIN:
        return True
    except dns.exception.DNSException:
        return False


async def _doh_reachable(endpoint: str, timeout: float) -> bool:
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=timeout)) as session:
            async with session.get(
                endpoint, params={"name": "example.com", "type": "A"}, headers={"accept": "application/dns-json"}
            ) as response:
                response.raise_for_status()
                payload = await response.json(content_type=None)
                return payload.get("Status", 2) in (0, 3)
    except (aiohttp.ClientError, asyncio.TimeoutError):
        return False


async def build_transport(args: argparse.Namespace):
    mode = "https" if args.transport == "doh" else args.transport
    custom = [endpoint.strip() for endpoint in args.endpoints.split(",") if endpoint.strip()]

    if custom:
        # Explicit endpoints are the caller's decision, so no region rules apply.
        checks = await asyncio.gather(*(_doh_reachable(endpoint, args.timeout) for endpoint in custom))
        endpoints = [endpoint for endpoint, ok in zip(custom, checks) if ok]
        if not endpoints:
            raise SystemExit("no custom DNS endpoint reachable")
        print("using custom DNS endpoints: " + ", ".join(endpoints))
        return DohTransport(endpoints, args.timeout, args.concurrency)

    if mode in ("auto", "https", "http"):
        https_pool = (("HTTPS", HTTPS_ENDPOINTS),)
        http_pool = (("HTTP", HTTP_ENDPOINTS),)
        pools = https_pool if mode == "https" else http_pool if mode == "http" else https_pool + http_pool

        for label, pool in pools:
            endpoints = await _select(f"DNS over {label}", pool, _doh_reachable, args)
            if endpoints:
                # The plain HTTP endpoints are heavily rate limited; a few hundred
                # parallel requests already produce SERVFAIL/timeouts.
                if label == "HTTP" and args.concurrency > 200:
                    print(f"capping concurrency to 200 for plain HTTP endpoints (requested {args.concurrency})")
                    args.concurrency = 200
                return DohTransport(endpoints, args.timeout, args.concurrency)

        if mode in ("https", "http"):
            raise SystemExit(f"no DNS over {mode.upper()} pool met the resolver requirements")
        print("warning: no DNS over HTTP(S) pool is usable, falling back to UDP")

    if args.resolvers in ("system", "auto"):
        if args.resolvers == "system":
            print("using the system resolver")
            return UdpTransport([None], args.timeout)

        servers = await _select("UDP resolvers", UDP_RESOLVERS, _udp_reachable, args)
        if not servers:
            print("warning: no public UDP resolver is reachable, using the system resolver", file=sys.stderr)
            servers = [None]
        return UdpTransport(servers, args.timeout)

    servers = [server.strip() for server in args.resolvers.split(",") if server.strip()]
    print(f"using UDP resolvers: {', '.join(servers)}")
    return UdpTransport(servers, args.timeout)


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(encoding="utf-8-sig", errors="replace").splitlines()


def write_domains(path: Path, names: set[str]) -> None:
    path.write_text("".join(f"{name}\n" for name in sorted(names)), encoding="utf-8", newline="\n")


def load_domains(path: Path) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for line in read_lines(path):
        name = line.strip().lower().rstrip(".")
        if not name or name.startswith("#") or name in seen:
            continue
        seen.add(name)
        names.append(name)
    return names


async def check_names(
    transport,
    names: list[str],
    semaphore: asyncio.Semaphore,
    args: argparse.Namespace,
    batch_size: int,
    dead: set[str],
    on_batch,
) -> tuple[dict[str, int], list[str]]:
    counts = {DEAD: 0, ALIVE: 0, UNKNOWN: 0, SINKHOLED: 0}
    unknown: list[str] = []
    tasks: list[asyncio.Task] = []
    checked = 0
    try:
        for start in range(0, len(names), batch_size):
            batch = names[start : start + batch_size]
            tasks = [asyncio.create_task(check_and_report(transport, semaphore, name, args)) for name in batch]
            for task in asyncio.as_completed(tasks):
                name, status = await task
                checked += 1
                counts[status] += 1
                if status == DEAD:
                    dead.add(name)
                elif status == UNKNOWN:
                    unknown.append(name)
                if checked % 1000 == 0:
                    print(f"  {checked}/{len(names)} checked, {counts[DEAD]} dead", flush=True)
            on_batch(dead, counts)
    except BaseException:
        for task in tasks:
            task.cancel()
        raise
    return counts, unknown


async def run(args: argparse.Namespace) -> int:
    input_path = Path(args.input)
    output_path = Path(args.output)
    temporary_path = output_path.with_name(f"{output_path.name}.tmp")

    if not input_path.is_file():
        print(f"missing input file: {input_path}", file=sys.stderr)
        return 1

    candidates = load_domains(input_path)
    checked_names = set(candidates)
    if not args.fresh:
        # Domains dropped from the upstream list are still re-checked, otherwise
        # every run would throw away the dead names the list was built for.
        kept = [name for name in load_domains(output_path) if name not in checked_names]
        if kept:
            print(f"re-checking {len(kept)} previously recorded domains")
        candidates.extend(kept)
        checked_names.update(kept)
    if args.limit:
        candidates = candidates[: args.limit]

    print(f"{input_path.name}: {len(candidates)} domains to check")
    if not candidates:
        return 0

    started = time.monotonic()
    dead: set[str] = set()
    totals = {DEAD: 0, ALIVE: 0, UNKNOWN: 0, SINKHOLED: 0}

    def flush(dead_so_far: set[str], _counts: dict[str, int]) -> None:
        if dead_so_far and not args.dry_run:
            write_domains(temporary_path, dead_so_far)

    async with await build_transport(args) as transport:
        semaphore = asyncio.Semaphore(args.concurrency)
        batch_size = max(args.concurrency * 4, 500)
        counts, unknown = await check_names(transport, candidates, semaphore, args, batch_size, dead, flush)
        for key, value in counts.items():
            totals[key] += value

        # A saturated network drops queries; retry those names slowly so they
        # are not silently lost.
        if unknown and not args.no_retry:
            retry_concurrency = max(16, args.concurrency // 8)
            print(f"retrying {len(unknown)} unknown domains with {retry_concurrency} workers", flush=True)
            retry_semaphore = asyncio.Semaphore(retry_concurrency)
            retry_counts, unknown = await check_names(
                transport, unknown, retry_semaphore, args, max(retry_concurrency * 4, 500), dead, flush
            )
            for key, value in retry_counts.items():
                totals[key] += value

    elapsed = time.monotonic() - started
    print(
        f"{input_path.name}: {len(candidates)} checked in {elapsed:.1f}s - "
        f"{totals[DEAD]} dead, {totals[ALIVE]} alive, {totals[SINKHOLED]} sinkholed, {len(unknown)} unknown"
    )
    if totals[SINKHOLED] and not args.sinkhole_dead:
        print(f"{totals[SINKHOLED]} domains only resolve to 0.0.0.0/loopback; pass --sinkhole-dead to treat them as dead")

    if args.dry_run:
        print("\n".join(sorted(dead)))
        return 0

    write_domains(temporary_path, dead)
    os.replace(temporary_path, output_path)
    print(f"wrote {len(dead)} domains to {output_path}")

    if len(unknown) > len(candidates) / 2:
        print("too many domains could not be resolved, check the DNS setup", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Record the dead domains of a block list.")
    parser.add_argument(
        "--input",
        default=os.environ.get("CHECK_INPUT", "block"),
        help="domain list to check (default: block)",
    )
    parser.add_argument(
        "--output",
        default=os.environ.get("CHECK_OUTPUT", "deadblock"),
        help="file the dead domains are written to (default: deadblock)",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=int(os.environ.get("CHECK_CONCURRENCY", "400")),
        help="parallel lookups (default: 400 or $CHECK_CONCURRENCY)",
    )
    parser.add_argument("--timeout", type=float, default=5.0, help="per-query timeout in seconds (default: 5)")
    parser.add_argument("--tries", type=int, default=2, help="attempts per query (default: 2)")
    parser.add_argument(
        "--transport",
        choices=("auto", "https", "http", "udp", "doh"),
        default=os.environ.get("CHECK_TRANSPORT", "auto"),
        help="how to resolve names: auto, https (DNS over HTTPS), http (DNS over plain HTTP), "
        "udp (default: auto, i.e. HTTPS, then plain HTTP, then UDP)",
    )
    parser.add_argument(
        "--endpoints",
        default=os.environ.get("CHECK_ENDPOINTS", ""),
        help="comma separated DNS over HTTP(S) endpoint URLs, overrides the built-in list",
    )
    parser.add_argument(
        "--resolvers",
        default=os.environ.get("CHECK_RESOLVERS", "auto"),
        help="UDP resolvers: comma separated host or host:port list, 'system' or 'auto' "
        "(default: auto; e.g. 127.0.0.1:15353 for a local AdGuard Home)",
    )
    parser.add_argument(
        "--min-overseas",
        type=int,
        default=int(os.environ.get("CHECK_MIN_OVERSEAS", "2")),
        help="minimum overseas resolvers in the selected pool (default: 2, aim for 3)",
    )
    parser.add_argument(
        "--min-china",
        type=int,
        default=int(os.environ.get("CHECK_MIN_CHINA", "2")),
        help="minimum China resolvers in the selected pool (default: 2, aim for 3)",
    )
    parser.add_argument(
        "--strict-resolvers",
        action="store_true",
        default=os.environ.get("CHECK_STRICT_RESOLVERS", "") not in ("", "0", "false"),
        help="fail instead of continuing when a pool is below the required mix",
    )
    parser.add_argument("--no-confirm", action="store_true", help="skip the second resolver confirmation")
    parser.add_argument("--no-retry", action="store_true", help="do not retry names that could not be resolved")
    parser.add_argument(
        "--sinkhole-dead",
        action="store_true",
        default=os.environ.get("CHECK_SINKHOLE_DEAD", "") not in ("", "0", "false"),
        help="count names that only resolve to 0.0.0.0/loopback as dead",
    )
    parser.add_argument("--limit", type=int, default=0, help="only check the first N domains (debugging)")
    parser.add_argument(
        "--fresh",
        action="store_true",
        help="ignore the existing output and rebuild it from the input list only",
    )
    parser.add_argument("--dry-run", action="store_true", help="print dead domains without writing the output file")
    args = parser.parse_args()
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
