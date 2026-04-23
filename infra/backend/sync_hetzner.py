#!/usr/bin/env python3
"""Hetzner Cloud → sqlite sync.

Pulls servers and snapshots. Tiny — Hetzner API is clean and we don't
need to track much state per server (status + spec + IPs).
"""

from __future__ import annotations

import json
import logging
import pathlib
import sqlite3
import time
import urllib.request
from typing import Optional

log = logging.getLogger("opspocket-hetzner-sync")

DB_PATH = pathlib.Path("/var/lib/opspocket/tenants.db")
HETZNER_TOKEN_FILE = pathlib.Path("/etc/opspocket/hetzner-token")
HETZNER_BASE = "https://api.hetzner.cloud/v1"


def _key() -> Optional[str]:
    try:
        return HETZNER_TOKEN_FILE.read_text().strip() or None
    except Exception:
        return None


def _get(key: str, path: str) -> dict:
    req = urllib.request.Request(
        HETZNER_BASE + path,
        headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH), timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def _tenant_id_for_server(conn: sqlite3.Connection, server_id: int) -> Optional[str]:
    row = conn.execute(
        "SELECT id FROM tenants WHERE hetzner_server_id=? LIMIT 1",
        (server_id,),
    ).fetchone()
    return row["id"] if row else None


def sync_servers() -> int:
    key = _key()
    if not key:
        raise RuntimeError("hetzner token not readable")
    now = int(time.time())
    n = 0
    conn = _db()
    try:
        page = _get(key, "/servers")
        for s in page.get("servers", []):
            st = s.get("server_type", {})
            ipv4 = s.get("public_net", {}).get("ipv4") or {}
            ipv6 = s.get("public_net", {}).get("ipv6") or {}
            dc = s.get("datacenter", {}).get("name")
            created = s.get("created")
            # Parse RFC3339 to unix
            created_ts = None
            if created:
                try:
                    from datetime import datetime
                    # Handle Z suffix
                    if created.endswith("Z"):
                        created = created[:-1] + "+00:00"
                    created_ts = int(datetime.fromisoformat(created).timestamp())
                except Exception:
                    pass
            tid = _tenant_id_for_server(conn, s["id"])
            conn.execute(
                """
                INSERT INTO hetzner_servers
                  (id, tenant_id, name, status, server_type, vcpus, memory_gb,
                   disk_gb, datacenter, ipv4, ipv6, created_at, synced_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                  tenant_id=excluded.tenant_id, name=excluded.name,
                  status=excluded.status, server_type=excluded.server_type,
                  vcpus=excluded.vcpus, memory_gb=excluded.memory_gb,
                  disk_gb=excluded.disk_gb, datacenter=excluded.datacenter,
                  ipv4=excluded.ipv4, ipv6=excluded.ipv6,
                  synced_at=excluded.synced_at
                """,
                (
                    s["id"], tid, s.get("name"), s.get("status"),
                    st.get("name"), st.get("cores"),
                    st.get("memory"), st.get("disk"),
                    dc,
                    ipv4.get("ip"),
                    ipv6.get("ip"),
                    created_ts, now,
                ),
            )
            n += 1
        conn.commit()
    finally:
        conn.close()
    log.info("hetzner server sync: %d", n)
    return n


def sync_snapshots() -> int:
    key = _key()
    if not key:
        raise RuntimeError("hetzner token not readable")
    now = int(time.time())
    n = 0
    conn = _db()
    try:
        page = _get(key, "/images?type=snapshot&per_page=50")
        for s in page.get("images", []):
            created_ts = None
            created = s.get("created")
            if created:
                try:
                    from datetime import datetime
                    if created.endswith("Z"):
                        created = created[:-1] + "+00:00"
                    created_ts = int(datetime.fromisoformat(created).timestamp())
                except Exception:
                    pass
            conn.execute(
                """
                INSERT INTO hetzner_snapshots
                  (id, server_id, server_name, description, image_size_gb,
                   created_at, synced_at)
                VALUES (?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                  description=excluded.description,
                  image_size_gb=excluded.image_size_gb,
                  synced_at=excluded.synced_at
                """,
                (
                    s["id"],
                    (s.get("created_from") or {}).get("id"),
                    (s.get("created_from") or {}).get("name"),
                    s.get("description"),
                    s.get("image_size"),
                    created_ts, now,
                ),
            )
            n += 1
        conn.commit()
    finally:
        conn.close()
    log.info("hetzner snapshot sync: %d", n)
    return n


def sync_traffic() -> int:
    """Read per-server traffic counters (outgoing/ingoing + included)."""
    key = _key()
    if not key:
        raise RuntimeError("hetzner token not readable")
    now = int(time.time())
    n = 0
    conn = _db()
    try:
        page = _get(key, "/servers")
        for s in page.get("servers", []):
            conn.execute(
                """
                INSERT INTO hetzner_traffic
                  (server_id, included_bytes, outgoing_bytes, ingoing_bytes, synced_at)
                VALUES (?,?,?,?,?)
                ON CONFLICT(server_id) DO UPDATE SET
                  included_bytes=excluded.included_bytes,
                  outgoing_bytes=excluded.outgoing_bytes,
                  ingoing_bytes=excluded.ingoing_bytes,
                  synced_at=excluded.synced_at
                """,
                (
                    s["id"],
                    s.get("included_traffic"),
                    s.get("outgoing_traffic"),
                    s.get("ingoing_traffic"),
                    now,
                ),
            )
            n += 1
        conn.commit()
    finally:
        conn.close()
    return n


def sync_metrics_for(server_id: int, minutes: int = 60) -> int:
    """Pull last <minutes> of cpu + network metrics for one server.
    Call sparingly — one server at a time."""
    key = _key()
    if not key:
        raise RuntimeError("hetzner token not readable")
    from datetime import datetime, timezone, timedelta
    end = datetime.now(timezone.utc)
    start = end - timedelta(minutes=minutes)
    # Hetzner metrics types: cpu, disk, network
    params = (
        f"?type=cpu,network"
        f"&start={start.isoformat().replace('+00:00','Z')}"
        f"&end={end.isoformat().replace('+00:00','Z')}"
        f"&step=60"
    )
    try:
        data = _get(key, f"/servers/{server_id}/metrics{params}")
    except Exception as e:
        log.error("hetzner metrics fetch failed for %s: %s", server_id, e)
        return 0
    metrics = data.get("metrics", {})
    ts_values = metrics.get("time_series", {}) or {}
    cpu_points = (ts_values.get("cpu") or {}).get("values") or []
    net_in_points = (ts_values.get("network.0.bandwidth.in") or {}).get("values") or []
    net_out_points = (ts_values.get("network.0.bandwidth.out") or {}).get("values") or []

    # Each points list is [[unix_float, "value_str"], ...]
    # Build a dict keyed by timestamp.
    series = {}
    for p in cpu_points:
        ts = int(p[0]); series.setdefault(ts, {})["cpu"] = float(p[1])
    for p in net_in_points:
        ts = int(p[0]); series.setdefault(ts, {})["in"] = int(float(p[1]))
    for p in net_out_points:
        ts = int(p[0]); series.setdefault(ts, {})["out"] = int(float(p[1]))

    conn = _db()
    n = 0
    try:
        for ts, vals in series.items():
            conn.execute(
                "INSERT OR REPLACE INTO hetzner_metrics "
                "(server_id, ts, cpu_percent, net_in_bytes, net_out_bytes) "
                "VALUES (?,?,?,?,?)",
                (server_id, ts, vals.get("cpu"),
                 vals.get("in"), vals.get("out")),
            )
            n += 1
        # Prune older than 7 days
        conn.execute(
            "DELETE FROM hetzner_metrics WHERE server_id=? AND ts < ?",
            (server_id, int(time.time()) - 7 * 86400),
        )
        conn.commit()
    finally:
        conn.close()
    return n


def sync_metrics_all(minutes: int = 60) -> int:
    """Pull metrics for every server we know about."""
    conn = _db()
    try:
        ids = [r["id"] for r in conn.execute(
            "SELECT id FROM hetzner_servers"
        ).fetchall()]
    finally:
        conn.close()
    total = 0
    for sid in ids:
        total += sync_metrics_for(sid, minutes=minutes)
    return total


def sync_all() -> dict:
    return {
        "servers": sync_servers(),
        "snapshots": sync_snapshots(),
        "traffic": sync_traffic(),
        "metrics_points": sync_metrics_all(minutes=60),
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    print(sync_all())
