#!/usr/bin/env python3
"""OmaTrack — state engine and CLI.

Single writer for the plugin's state file. python3 stdlib only.

Every command prints exactly one JSON line on stdout:
  {"ok": true, ...}                exit 0
  {"ok": false, "error": "<msg>"}  exit 1

Timestamps are stored as UTC ISO-8601 with second precision. Local time is
used only for the day-granularity semantics that commands document (date-only
range bounds, manual-entry date/time, day totals).
"""

import argparse
import csv
import datetime
import fcntl
import html
import json
import os
import sys
import tempfile
import uuid

UTC = datetime.timezone.utc

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME")
    or os.path.join(os.path.expanduser("~"), ".local", "state"),
    "omarchy",
    "omatrack",
)
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOCK_FILE = os.path.join(STATE_DIR, ".lock")


class CmdError(Exception):
    """User-facing error: rendered as {"ok": false, "error": str(e)}."""


# ---------------------------------------------------------------------------
# state file plumbing
# ---------------------------------------------------------------------------

def default_state():
    return {
        "version": 1,
        "settings": {
            "currency": "EUR",
            "hourlyRate": 0,
            "invoice": {
                "companyName": "",
                "companyAddress": "",
                "taxRate": 0,
                "numberPrefix": "INV-",
                "nextNumber": 1,
                "footer": "",
            },
        },
        "clients": [],
        "projects": [],
        "entries": [],
        "active": None,
        "invoices": [],
    }


def load_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        raise CmdError("state file missing (run: init)")
    # Older state files predate the invoice records; normalize so every
    # command sees the full shape.
    state.setdefault("invoices", [])
    return state


def atomic_write(path, write_fn):
    """write_fn(file) writes the payload; path is replaced atomically."""
    path = os.path.abspath(path)
    parent = os.path.dirname(path) or "."
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp.", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            write_fn(f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def save_state(state):
    def write(f):
        json.dump(state, f, ensure_ascii=False, indent=2)
        f.write("\n")

    atomic_write(STATE_FILE, write)


def acquire_lock(exclusive):
    os.makedirs(STATE_DIR, exist_ok=True)
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o644)
    fcntl.flock(fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
    return fd


def release_lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def new_id(prefix):
    return prefix + uuid.uuid4().hex[:12]


def now_iso():
    return datetime.datetime.now(UTC).isoformat(timespec="seconds")


def ensure_dirs():
    os.makedirs(STATE_DIR, exist_ok=True)


def default_invoice_dir():
    # Invoices are documents for the user, not state: they land in the
    # user's Downloads folder (the same destination as exports) unless
    # --out says otherwise.
    return os.path.expanduser("~/Downloads")


# ---------------------------------------------------------------------------
# time parsing (no `re` — strict shape checks + stdlib constructors)
# ---------------------------------------------------------------------------

def strict_date(s):
    """YYYY-MM-DD -> datetime.date, else CmdError."""
    if (
        len(s) != 10
        or s[4] != "-"
        or s[7] != "-"
        or not (s[0:4].isdigit() and s[5:7].isdigit() and s[8:10].isdigit())
    ):
        raise CmdError(f"invalid date: {s!r} (expected YYYY-MM-DD)")
    try:
        return datetime.date.fromisoformat(s)
    except ValueError:
        raise CmdError(f"invalid date: {s!r} (expected YYYY-MM-DD)")


def strict_time(s):
    """HH:MM (or HH:MM:SS) -> datetime.time, else CmdError."""
    ok = (
        len(s) == 5
        and s[2] == ":"
        and s[0:2].isdigit()
        and s[3:5].isdigit()
    ) or (
        len(s) == 8
        and s[2] == ":"
        and s[5] == ":"
        and s[0:2].isdigit()
        and s[3:5].isdigit()
        and s[6:8].isdigit()
    )
    if not ok:
        raise CmdError(f"invalid time: {s!r} (expected HH:MM)")
    try:
        return datetime.time.fromisoformat(s)
    except ValueError:
        raise CmdError(f"invalid time: {s!r} (expected HH:MM)")


def parse_iso_utc(s):
    """Full ISO-8601 timestamp -> aware UTC datetime; naive assumed UTC."""
    try:
        dt = datetime.datetime.fromisoformat(s)
    except ValueError:
        raise CmdError(f"invalid timestamp: {s!r}")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def local_range(from_s, to_s):
    """Resolve --from/--to (date-only or ISO) to inclusive UTC bounds.

    Date-only values are interpreted in local time: the from day starts at
    local 00:00:00, the to day ends at local 23:59:59.
    """
    def resolve(s, end_of_day):
        if not s:
            return None
        if (
            len(s) == 10
            and s[4] == "-"
            and s[7] == "-"
            and s[0:4].isdigit()
            and s[5:7].isdigit()
            and s[8:10].isdigit()
        ):
            try:
                d = datetime.date.fromisoformat(s)
            except ValueError:
                raise CmdError(f"invalid date: {s!r} (expected YYYY-MM-DD)")
            t = datetime.time(23, 59, 59) if end_of_day else datetime.time(0, 0, 0)
            return datetime.datetime.combine(d, t).astimezone(UTC)
        return parse_iso_utc(s)

    return resolve(from_s, False), resolve(to_s, True)


def entry_start_utc(entry):
    return parse_iso_utc(entry["start"])


def local_dt(iso):
    """ISO (stored UTC) -> aware local datetime."""
    return parse_iso_utc(iso).astimezone()


# ---------------------------------------------------------------------------
# lookups + filtering
# ---------------------------------------------------------------------------

def find_client(state, client_id):
    for c in state["clients"]:
        if c["id"] == client_id:
            return c
    raise CmdError(f"client not found: {client_id}")


def find_project(state, project_id):
    for p in state["projects"]:
        if p["id"] == project_id:
            return p
    raise CmdError(f"project not found: {project_id}")


def client_names(state):
    return {c["id"]: c["name"] for c in state["clients"]}


def project_names(state):
    return {p["id"]: p["name"] for p in state["projects"]}


def filter_entries(state, from_s, to_s, client_id, project_id, billable, search):
    lo, hi = local_range(from_s, to_s)
    cnames = client_names(state)
    pnames = project_names(state)
    needle = search.lower() if search else None
    out = []
    for e in state["entries"]:
        st = entry_start_utc(e)
        if lo is not None and st < lo:
            continue
        if hi is not None and st > hi:
            continue
        if client_id and e["clientId"] != client_id:
            continue
        if project_id and e["projectId"] != project_id:
            continue
        if billable is not None and (1 if e["billable"] else 0) != billable:
            continue
        if needle is not None:
            hay = " ".join(
                [e["description"], cnames.get(e["clientId"], ""), pnames.get(e["projectId"], "")]
            ).lower()
            if needle not in hay:
                continue
        out.append(e)
    return out


def build_view(state):
    """State minus entries + lastUsed + day totals + dayByClient + entryCount.
    `invoices` (metadata records of generated invoices) is included."""
    view = {k: state[k] for k in ("version", "settings", "clients", "projects", "invoices")}
    a = state["active"]
    if a is not None:
        # Older state files predate the pause fields; normalize so every
        # consumer (QML, IPC) sees the full shape.
        a = dict(a)
        a.setdefault("paused", False)
        a.setdefault("pausedSeconds", 0)
        a.setdefault("pauseStart", None)
    view["active"] = a
    entries = state["entries"]
    last = None
    if entries:
        latest = max(entries, key=lambda e: parse_iso_utc(e["end"]))
        last = {
            "clientId": latest["clientId"],
            "projectId": latest["projectId"],
            "description": latest["description"],
            "billable": latest["billable"],
        }
    elif state["active"] is not None:
        a = state["active"]
        last = {
            "clientId": a["clientId"],
            "projectId": a["projectId"],
            "description": a["description"],
            "billable": a["billable"],
        }
    view["lastUsed"] = last
    today = datetime.datetime.now().astimezone().date()
    day = 0
    dayb = 0
    day_by_client = {}
    for e in entries:
        if local_dt(e["start"]).date() == today:
            day += e["seconds"]
            if e["billable"]:
                dayb += e["seconds"]
            day_by_client[e["clientId"]] = day_by_client.get(e["clientId"], 0) + e["seconds"]
    view["daySeconds"] = day
    view["dayBillableSeconds"] = dayb
    view["dayByClient"] = day_by_client
    view["entryCount"] = len(entries)
    return view


def mutate(args, fn):
    """Exclusive-lock read-modify-write wrapper for mutating commands."""
    fd = acquire_lock(True)
    try:
        state = load_state()
        result = fn(state)
        save_state(state)
        return result
    finally:
        release_lock(fd)


# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------

def cmd_init(args):
    fd = acquire_lock(True)
    try:
        ensure_dirs()
        if not os.path.exists(STATE_FILE):
            save_state(default_state())
        state = load_state()
        return {"ok": True, "state": build_view(state)}
    finally:
        release_lock(fd)


def cmd_start(args):
    def fn(state):
        if state["active"] is not None:
            raise CmdError("timer already running")
        if not (args.description or "").strip():
            raise CmdError("description is required")
        c = find_client(state, args.client_id)
        p = find_project(state, args.project_id)
        if p["clientId"] != c["id"]:
            raise CmdError("project does not belong to client")
        state["active"] = {
            "id": new_id("e_"),
            "clientId": c["id"],
            "projectId": p["id"],
            "description": args.description,
            "billable": bool(args.billable),
            "start": now_iso(),
            "paused": False,
            "pausedSeconds": 0,
            "pauseStart": None,
        }
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_pause(args):
    def fn(state):
        a = state["active"]
        if a is None:
            raise CmdError("no timer running")
        if a.get("paused"):
            raise CmdError("timer is already paused")
        a["paused"] = True
        a["pauseStart"] = now_iso()
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_resume(args):
    def fn(state):
        a = state["active"]
        if a is None:
            raise CmdError("no timer running")
        if not a.get("paused"):
            raise CmdError("timer is not paused")
        seg = int((datetime.datetime.now(UTC) - parse_iso_utc(a["pauseStart"])).total_seconds())
        a["pausedSeconds"] = int(a.get("pausedSeconds") or 0) + max(0, seg)
        a["paused"] = False
        a["pauseStart"] = None
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_stop(args):
    def fn(state):
        if state["active"] is None:
            raise CmdError("no timer running")
        a = state["active"]
        end = parse_iso_utc(args.at) if args.at else datetime.datetime.now(UTC)
        start = parse_iso_utc(a["start"])
        paused = int(a.get("pausedSeconds") or 0)
        if a.get("paused") and a.get("pauseStart"):
            ps = parse_iso_utc(a["pauseStart"])
            paused += max(0, int((end - ps).total_seconds()))
        seconds = max(0, int((end - start).total_seconds()) - paused)
        state["entries"].append(
            {
                "id": a["id"],
                "clientId": a["clientId"],
                "projectId": a["projectId"],
                "description": a["description"],
                "billable": a["billable"],
                "start": a["start"],
                "end": end.isoformat(timespec="seconds"),
                "seconds": seconds,
            }
        )
        state["active"] = None
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_entries(args):
    fd = acquire_lock(False)
    try:
        state = load_state()
    finally:
        release_lock(fd)
    matched = filter_entries(
        state, args.from_date, args.to, args.client_id, args.project_id, args.billable, args.search
    )
    matched.sort(key=lambda e: e["start"], reverse=True)
    total = len(matched)
    total_seconds = sum(e["seconds"] for e in matched)
    billable_seconds = sum(e["seconds"] for e in matched if e["billable"])
    limit = max(1, min(args.limit, 500))
    offset = max(0, args.offset)
    page = matched[offset : offset + limit]
    next_offset = offset + limit if offset + limit < total else None
    return {
        "ok": True,
        "entries": page,
        "total": total,
        "totalSeconds": total_seconds,
        "billableSeconds": billable_seconds,
        "offset": offset,
        "limit": limit,
        "nextOffset": next_offset,
    }


def cmd_report(args):
    fd = acquire_lock(False)
    try:
        state = load_state()
    finally:
        release_lock(fd)
    matched = filter_entries(
        state, args.from_date, args.to, args.client_id, args.project_id, None, None
    )
    cnames = client_names(state)
    pnames = project_names(state)
    rows = {}
    for e in matched:
        if args.group_by == "day":
            key = local_dt(e["start"]).date().isoformat()
            label = key
        elif args.group_by == "client":
            key = e["clientId"]
            label = cnames.get(key, "Unknown")
        else:  # project
            key = e["projectId"]
            p = next((x for x in state["projects"] if x["id"] == key), None)
            client_label = cnames.get(p["clientId"], "?") if p else "?"
            label = f"{client_label} — {pnames.get(key, 'Unknown')}"
        row = rows.get(key)
        if row is None:
            row = rows[key] = {
                "key": key, "label": label, "seconds": 0, "billableSeconds": 0,
                "count": 0,
            }
        row["seconds"] += e["seconds"]
        row["count"] += 1
        if e["billable"]:
            row["billableSeconds"] += e["seconds"]
    out_rows = list(rows.values())
    if args.group_by == "day":
        out_rows.sort(key=lambda r: r["key"])
    else:
        out_rows.sort(key=lambda r: r["seconds"], reverse=True)
    limit = max(1, min(args.limit, 500))
    offset = max(0, args.offset)
    total = len(out_rows)
    page = out_rows[offset : offset + limit]
    return {
        "ok": True,
        "rows": page,
        "total": total,
        "offset": offset,
        "limit": limit,
        "totalSeconds": sum(r["seconds"] for r in out_rows),
        "billableSeconds": sum(r["billableSeconds"] for r in out_rows),
        "entryCount": sum(r["count"] for r in out_rows),
    }


def cmd_client_add(args):
    name = (args.name or "").strip()
    if not name:
        raise CmdError("client name must not be empty")

    def fn(state):
        for c in state["clients"]:
            if c["name"].strip().lower() == name.lower():
                raise CmdError("client already exists")
        state["clients"].append({"id": new_id("c_"), "name": name, "createdAt": now_iso()})
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_client_update(args):
    name = (args.name or "").strip()
    if not name:
        raise CmdError("client name must not be empty")

    def fn(state):
        c = find_client(state, args.id)
        for other in state["clients"]:
            if other["id"] != c["id"] and other["name"].strip().lower() == name.lower():
                raise CmdError("client already exists")
        c["name"] = name
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_client_delete(args):
    def fn(state):
        c = find_client(state, args.id)
        n_projects = sum(1 for p in state["projects"] if p["clientId"] == c["id"])
        n_entries = sum(1 for e in state["entries"] if e["clientId"] == c["id"])
        if n_projects + n_entries > 0:
            raise CmdError(
                f"client-delete blocked: {n_projects} projects, {n_entries} entries reference this client"
            )
        state["clients"] = [x for x in state["clients"] if x["id"] != c["id"]]
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_project_add(args):
    name = (args.name or "").strip()
    if not name:
        raise CmdError("project name must not be empty")

    def fn(state):
        c = find_client(state, args.client_id)
        for p in state["projects"]:
            if p["clientId"] == c["id"] and p["name"].strip().lower() == name.lower():
                raise CmdError("project already exists")
        state["projects"].append({"id": new_id("p_"), "clientId": c["id"], "name": name})
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_project_update(args):
    if args.name is not None and not (args.name or "").strip():
        raise CmdError("project name must not be empty")

    def fn(state):
        p = find_project(state, args.id)
        target_client_id = args.client_id if args.client_id is not None else p["clientId"]
        if args.client_id is not None:
            find_client(state, args.client_id)
        new_name = (args.name or "").strip() if args.name is not None else p["name"]
        for other in state["projects"]:
            if (
                other["id"] != p["id"]
                and other["clientId"] == target_client_id
                and other["name"].strip().lower() == new_name.lower()
            ):
                raise CmdError("project already exists")
        p["clientId"] = target_client_id
        p["name"] = new_name
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_project_delete(args):
    def fn(state):
        p = find_project(state, args.id)
        n_entries = sum(1 for e in state["entries"] if e["projectId"] == p["id"])
        if n_entries > 0:
            raise CmdError(f"project-delete blocked: {n_entries} entries reference this project")
        state["projects"] = [x for x in state["projects"] if x["id"] != p["id"]]
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def check_client_project(state, client_id, project_id):
    """Validate client exists, project exists and belongs to it."""
    c = find_client(state, client_id)
    p = find_project(state, project_id)
    if p["clientId"] != c["id"]:
        raise CmdError("project does not belong to client")
    return c, p


def cmd_entry_add(args):
    d = strict_date(args.start)
    t = strict_time(args.time)
    if args.minutes < 1:
        raise CmdError("minutes must be >= 1")
    start_utc = datetime.datetime.combine(d, t).astimezone(UTC)

    def fn(state):
        check_client_project(state, args.client_id, args.project_id)
        state["entries"].append(
            {
                "id": new_id("e_"),
                "clientId": args.client_id,
                "projectId": args.project_id,
                "description": args.description,
                "billable": bool(args.billable),
                "start": start_utc.isoformat(timespec="seconds"),
                "end": (start_utc + datetime.timedelta(seconds=args.minutes * 60)).isoformat(
                    timespec="seconds"
                ),
                "seconds": args.minutes * 60,
            }
        )
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_entry_update(args):
    touched = False

    def fn(state):
        nonlocal touched
        e = next((x for x in state["entries"] if x["id"] == args.id), None)
        if e is None:
            raise CmdError(f"entry not found: {args.id}")
        d = strict_date(args.start) if args.start is not None else None
        t = strict_time(args.time) if args.time is not None else None
        if d is not None or t is not None or args.minutes is not None:
            cur = local_dt(e["start"])
            new_d = d or cur.date()
            new_t = t or cur.time()
            minutes = args.minutes if args.minutes is not None else round(e["seconds"] / 60)
            if minutes < 1:
                raise CmdError("minutes must be >= 1")
            start_utc = datetime.datetime.combine(new_d, new_t).astimezone(UTC)
            e["start"] = start_utc.isoformat(timespec="seconds")
            e["seconds"] = minutes * 60
            e["end"] = (start_utc + datetime.timedelta(seconds=e["seconds"])).isoformat(
                timespec="seconds"
            )
            touched = True
        if args.client_id is not None or args.project_id is not None:
            new_client = args.client_id if args.client_id is not None else e["clientId"]
            new_project = args.project_id if args.project_id is not None else e["projectId"]
            check_client_project(state, new_client, new_project)
            e["clientId"] = new_client
            e["projectId"] = new_project
            touched = True
        if args.description is not None:
            e["description"] = args.description
            touched = True
        if args.billable is not None:
            e["billable"] = bool(args.billable)
            touched = True
        if not touched:
            raise CmdError("nothing to update")
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


def cmd_entry_delete(args):
    def fn(state):
        before = len(state["entries"])
        state["entries"] = [x for x in state["entries"] if x["id"] != args.id]
        if len(state["entries"]) == before:
            raise CmdError(f"entry not found: {args.id}")
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


# ---------------------------------------------------------------------------
# settings
# ---------------------------------------------------------------------------

INVOICE_KEYS = ("companyName", "companyAddress", "taxRate", "numberPrefix", "nextNumber", "footer")
TOP_KEYS = ("currency", "hourlyRate", "invoice")


def _validate_setting(key, value):
    if key == "currency":
        if not isinstance(value, str) or not value.strip() or len(value.strip()) > 8:
            raise CmdError(f"invalid {key}: non-empty string of max 8 chars required")
        return value.strip()
    if key in ("hourlyRate", "taxRate", "nextNumber"):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise CmdError(f"invalid {key}: number >= 0 required")
        if value < 0:
            raise CmdError(f"invalid {key}: number >= 0 required")
        if key == "nextNumber" and not isinstance(value, int):
            raise CmdError("invalid nextNumber: integer >= 0 required")
        return value
    if key in ("numberPrefix", "companyName", "companyAddress", "footer"):
        if not isinstance(value, str):
            raise CmdError(f"invalid {key}: string required")
        return value
    raise CmdError(f"unknown settings field: {key}")


def cmd_settings_set(args):
    try:
        patch = json.loads(args.json)
    except json.JSONDecodeError as e:
        raise CmdError(f"invalid --json: {e}")
    if not isinstance(patch, dict):
        raise CmdError("--json must be an object")

    def fn(state):
        settings = state["settings"]
        for key, value in patch.items():
            if key == "invoice":
                if not isinstance(value, dict):
                    raise CmdError("invalid invoice: object required")
                for k, v in value.items():
                    if k not in INVOICE_KEYS:
                        raise CmdError(f"unknown invoice field: {k}")
                    settings["invoice"][k] = _validate_setting(k, v)
            else:
                if key not in TOP_KEYS:
                    raise CmdError(f"unknown settings field: {key}")
                settings[key] = _validate_setting(key, value)
        return {"ok": True, "state": build_view(state)}

    return mutate(args, fn)


# ---------------------------------------------------------------------------
# export + invoice
# ---------------------------------------------------------------------------

def _entry_local_str(iso):
    return local_dt(iso).strftime("%Y-%m-%d %H:%M")


def _duration_str(seconds):
    """'1h 32m' / '45m' / '0m' — mirrors the service's fmtDur; a bare
    decimal-hours number (e.g. 0.89) reads as opaque in the file."""
    total_min = int(seconds) // 60
    h, m = divmod(total_min, 60)
    if h and m:
        return f"{h}h {m}m"
    if h:
        return f"{h}h"
    return f"{m}m"


def _filter_summary(from_s, to_s, client_id, project_id, billable, cnames, pnames):
    parts = []
    if from_s:
        parts.append(f"from {from_s}")
    if to_s:
        parts.append(f"to {to_s}")
    if client_id:
        parts.append(f"client {cnames.get(client_id, client_id)}")
    if project_id:
        parts.append(f"project {pnames.get(project_id, project_id)}")
    if billable is not None:
        parts.append("billable only" if billable else "non-billable only")
    return ", ".join(parts) if parts else "all entries"


def _page(title, body, mono=True):
    font = "font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;" if mono else ""
    return (
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        f"<title>{html.escape(title)}</title>\n<style>\n"
        "body { margin: 2rem; background: #fafafa; color: #1a1a1a; "
        + font
        + " font-size: 13px; }\n"
        "h1 { font-size: 18px; margin-bottom: 0.25rem; }\n"
        ".meta { color: #666; margin-bottom: 1.5rem; }\n"
        "table { border-collapse: collapse; width: 100%; }\n"
        "th, td { text-align: left; padding: 4px 10px; border-bottom: 1px solid #ddd; }\n"
        "th { background: #f0f0f0; }\n"
        ".num { text-align: right; }\n"
        ".ctr { text-align: center; }\n"
        "tfoot td { font-weight: bold; border-top: 2px solid #999; }\n"
        "</style>\n</head>\n<body>\n"
        f"<h1>{html.escape(title)}</h1>\n"
        + body
        + "\n</body>\n</html>\n"
    )


CSV_COLUMNS = [
    "Start", "End", "Client", "Project", "Description", "Billable", "Duration", "Price",
]
CENTERED_COLUMNS = frozenset(("Billable", "Duration", "Price"))


def cmd_export(args):
    fd = acquire_lock(False)
    try:
        state = load_state()
    finally:
        release_lock(fd)
    matched = filter_entries(
        state, args.from_date, args.to, args.client_id, args.project_id, args.billable, None
    )
    matched.sort(key=lambda e: e["start"])
    cnames = client_names(state)
    pnames = project_names(state)
    summary = _filter_summary(
        args.from_date, args.to, args.client_id, args.project_id, args.billable, cnames, pnames
    )
    total_seconds = sum(e["seconds"] for e in matched)
    currency = state["settings"].get("currency", "")
    rate = state["settings"].get("hourlyRate", 0)
    priced = [(e, round(e["seconds"] / 3600 * rate, 2)) for e in matched]
    total_price = round(sum(p for _, p in priced), 2)

    def rows_for_csv(f):
        w = csv.writer(f, lineterminator="\n")
        w.writerow(CSV_COLUMNS)
        for e, price in priced:
            w.writerow(
                [
                    _entry_local_str(e["start"]),
                    _entry_local_str(e["end"]),
                    cnames.get(e["clientId"], ""),
                    pnames.get(e["projectId"], ""),
                    e["description"],
                    1 if e["billable"] else 0,
                    _duration_str(e["seconds"]),
                    money(currency, price),
                ]
            )
        w.writerow(
            [
                f"total ({len(priced)} entries)",
                "",
                "",
                "",
                "",
                "",
                _duration_str(total_seconds),
                money(currency, total_price),
            ]
        )

    def rows_for_html(f):
        rows = []
        for e, price in priced:
            rows.append(
                "<tr>"
                f"<td>{html.escape(_entry_local_str(e['start']))}</td>"
                f"<td>{html.escape(_entry_local_str(e['end']))}</td>"
                f"<td>{html.escape(cnames.get(e['clientId'], ''))}</td>"
                f"<td>{html.escape(pnames.get(e['projectId'], ''))}</td>"
                f"<td>{html.escape(e['description'])}</td>"
                f"<td class=\"ctr\">{1 if e['billable'] else 0}</td>"
                f"<td class=\"ctr\">{html.escape(_duration_str(e['seconds']))}</td>"
                f"<td class=\"ctr\">{money(currency, price)}</td>"
                "</tr>"
            )
        f.write(
            _page(
                "Timesheet",
                f"<div class=\"meta\">{html.escape(summary)} · generated "
                f"{datetime.datetime.now().astimezone().isoformat(timespec='seconds')}</div>\n"
                "<table>\n<thead>\n<tr>"
                + "".join(
                    f"<th class=\"ctr\">{c}</th>" if c in CENTERED_COLUMNS else f"<th>{c}</th>"
                    for c in CSV_COLUMNS
                )
                + "</tr>\n</thead>\n<tbody>\n"
                + "\n".join(rows)
                + "\n</tbody>\n"
                "<tfoot>\n<tr>"
                f"<td colspan=\"6\">total ({len(priced)} entries)</td>"
                f"<td class=\"ctr\">{html.escape(_duration_str(total_seconds))}</td>"
                f"<td class=\"ctr\">{money(currency, total_price)}</td>"
                "</tr>\n</tfoot>\n</table>",
            )
        )

    writer = rows_for_csv if args.format == "csv" else rows_for_html
    atomic_write(args.out, writer)
    return {
        "ok": True,
        "path": os.path.abspath(args.out),
        "count": len(matched),
        "seconds": total_seconds,
    }


def money(currency, x):
    return (currency + " " if currency else "") + f"{x:,.2f}"


def cmd_invoice(args):
    if not args.from_date or not args.to:
        raise CmdError("invoice requires --from and --to")
    lo, hi = local_range(args.from_date, args.to)
    if lo > hi:
        raise CmdError("invalid range: --from is after --to")

    def fn(state):
        c = find_client(state, args.client_id)
        pnames = project_names(state)
        matched = [
            e
            for e in state["entries"]
            if e["clientId"] == c["id"]
            and e["billable"]
            and lo <= entry_start_utc(e) <= hi
        ]
        if not matched:
            raise CmdError("no billable entries in range")
        settings = state["settings"]
        currency = settings.get("currency", "")
        rate = settings.get("hourlyRate", 0)
        invoice_cfg = settings.get("invoice", {})
        tax_rate = invoice_cfg.get("taxRate", 0)
        prefix = invoice_cfg.get("numberPrefix", "INV-")
        next_number = int(invoice_cfg.get("nextNumber", 1))

        by_project = {}
        for e in matched:
            name = pnames.get(e["projectId"], "Unknown")
            by_project[name] = by_project.get(name, 0) + e["seconds"]
        lines = []
        for name in sorted(by_project):
            hours = by_project[name] / 3600
            lines.append(
                {
                    "project": name,
                    "hours": round(hours, 2),
                    "amount": round(hours * rate, 2),
                }
            )
        subtotal = round(sum(l["amount"] for l in lines), 2)
        tax = round(subtotal * tax_rate / 100, 2)
        total = round(subtotal + tax, 2)
        number = str(prefix) + str(next_number).zfill(4)
        invoice_cfg["nextNumber"] = next_number + 1

        company = html.escape(invoice_cfg.get("companyName", ""))
        address = html.escape(invoice_cfg.get("companyAddress", ""))
        today = datetime.datetime.now().astimezone().date().isoformat()
        line_rows = "\n".join(
            "<tr>"
            f"<td>Time — {html.escape(l['project'])} ({html.escape(args.from_date)} to "
            f"{html.escape(args.to)})</td>"
            f"<td class=\"num\">{l['hours']:.2f}</td>"
            f"<td class=\"num\">{money(currency, rate)}</td>"
            f"<td class=\"num\">{money(currency, l['amount'])}</td>"
            "</tr>"
            for l in lines
        )
        # The company block renders only what is configured; with neither a
        # company name nor an address set, the block is omitted entirely.
        company_html = f"<div><strong>{company}</strong></div>" if company else ""
        address_html = f"<div>{address}</div>" if address else ""
        company_block = (
            f'<div style="margin-bottom:1.5rem;">{company_html}{address_html}</div>'
            if (company_html or address_html)
            else ""
        )
        footer_html = (
            f"<p style=\"color:#666;margin-top:2rem;\">"
            f"{html.escape(invoice_cfg.get('footer', ''))}</p>"
            if invoice_cfg.get("footer")
            else ""
        )
        doc = _page(
            f"Invoice {number}",
            company_block
            + f"<div class=\"meta\">Bill To: <strong>{html.escape(c['name'])}</strong><br>"
            f"Period: {html.escape(args.from_date)} to {html.escape(args.to)}<br>"
            f"Issued: {today} &nbsp;·&nbsp; Invoice: {html.escape(number)}</div>"
            "<table>\n<thead>\n"
            "<tr><th>Description</th><th class=\"num\">Hours</th>"
            "<th class=\"num\">Rate</th><th class=\"num\">Amount</th></tr>\n</thead>\n"
            f"<tbody>\n{line_rows}\n</tbody>\n"
            "<tfoot>\n"
            f"<tr><td colspan=\"3\">subtotal</td><td class=\"num\">{money(currency, subtotal)}</td></tr>\n"
            f"<tr><td colspan=\"3\">Tax {tax_rate:g}%</td><td class=\"num\">{money(currency, tax)}</td></tr>\n"
            f"<tr><td colspan=\"3\">Total</td><td class=\"num\">{money(currency, total)}</td></tr>\n"
            "</tfoot>\n</table>"
            + footer_html,
        )
        out = args.out or os.path.join(
            default_invoice_dir(), f"{number.replace(os.sep, '_')}_{args.from_date}_{args.to}.html"
        )
        atomic_write(out, lambda f: f.write(doc))
        # Record the invoice in state (newest first) so the Invoices tab's
        # table shows it without scanning the Downloads folder.
        state["invoices"].insert(
            0,
            {
                "id": new_id("inv_"),
                "number": number,
                "clientId": c["id"],
                "client": c["name"],
                "from": args.from_date,
                "to": args.to,
                "seconds": sum(e["seconds"] for e in matched),
                "subtotal": subtotal,
                "tax": tax,
                "total": total,
                "path": os.path.abspath(out),
                "createdAt": now_iso(),
            },
        )
        return {
            "ok": True,
            "path": os.path.abspath(out),
            "number": number,
            "client": c["name"],
            "period": {"from": args.from_date, "to": args.to},
            "lines": lines,
            "subtotal": subtotal,
            "tax": tax,
            "total": total,
            "state": build_view(state),
        }

    return mutate(args, fn)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="omatrack.py", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="command", required=True)

    def add(name, fn, help_text):
        sp = sub.add_parser(name, help=help_text)
        sp.set_defaults(func=fn)
        return sp

    sp = add("init", cmd_init, "create state file + directories (idempotent)")
    sp.add_argument("--print-dir", action="store_true", help="print state dir (no-op)")
    sp = add("state", cmd_init, "reload/ensure state; print the state view")

    sp = add("start", cmd_start, "start the active timer (description is mandatory)")
    sp.add_argument("--client-id", required=True)
    sp.add_argument("--project-id", required=True)
    sp.add_argument("--description", default="")
    sp.add_argument("--billable", type=int, choices=[0, 1], default=1)

    sp = add("stop", cmd_stop, "stop the active timer (closes the entry)")
    sp.add_argument("--at", default=None, help="ISO-8601 end time override (naive = UTC)")

    sp = add("pause", cmd_pause, "pause the active timer (no time accrues while paused)")
    sp = add("resume", cmd_resume, "resume a paused timer")

    sp = add("entries", cmd_entries, "list entries (filtered, paginated, start DESC)")
    sp.add_argument("--from", dest="from_date", default=None)
    sp.add_argument("--to", default=None)
    sp.add_argument("--client-id", default=None)
    sp.add_argument("--project-id", default=None)
    sp.add_argument("--billable", type=int, choices=[0, 1], default=None)
    sp.add_argument("--search", default=None)
    sp.add_argument("--offset", type=int, default=0)
    sp.add_argument("--limit", type=int, default=50)

    sp = add("report", cmd_report, "aggregate entries")
    sp.add_argument("--group-by", required=True, choices=["day", "client", "project"])
    sp.add_argument("--from", dest="from_date", default=None)
    sp.add_argument("--to", default=None)
    sp.add_argument("--client-id", default=None)
    sp.add_argument("--project-id", default=None)
    sp.add_argument("--offset", type=int, default=0)
    sp.add_argument("--limit", type=int, default=50)

    sp = add("client-add", cmd_client_add, "add a client")
    sp.add_argument("--name", required=True)
    sp = add("client-update", cmd_client_update, "rename a client")
    sp.add_argument("--id", required=True)
    sp.add_argument("--name", required=True)
    sp = add("client-delete", cmd_client_delete, "delete an unreferenced client")
    sp.add_argument("--id", required=True)

    sp = add("project-add", cmd_project_add, "add a project")
    sp.add_argument("--client-id", required=True)
    sp.add_argument("--name", required=True)
    sp = add("project-update", cmd_project_update, "rename/move a project")
    sp.add_argument("--id", required=True)
    sp.add_argument("--name", default=None)
    sp.add_argument("--client-id", default=None)
    sp = add("project-delete", cmd_project_delete, "delete a project without entries")
    sp.add_argument("--id", required=True)

    sp = add("entry-add", cmd_entry_add, "add a manual entry (local date/time)")
    sp.add_argument("--start", required=True, help="YYYY-MM-DD")
    sp.add_argument("--time", required=True, help="HH:MM")
    sp.add_argument("--minutes", type=int, required=True)
    sp.add_argument("--client-id", required=True)
    sp.add_argument("--project-id", required=True)
    sp.add_argument("--description", default="")
    sp.add_argument("--billable", type=int, choices=[0, 1], default=1)

    sp = add("entry-update", cmd_entry_update, "update fields of an entry")
    sp.add_argument("--id", required=True)
    sp.add_argument("--start", default=None, help="YYYY-MM-DD")
    sp.add_argument("--time", default=None, help="HH:MM")
    sp.add_argument("--minutes", type=int, default=None)
    sp.add_argument("--client-id", default=None)
    sp.add_argument("--project-id", default=None)
    sp.add_argument("--description", default=None)
    sp.add_argument("--billable", type=int, choices=[0, 1], default=None)

    sp = add("entry-delete", cmd_entry_delete, "delete an entry")
    sp.add_argument("--id", required=True)

    sp = add("settings-set", cmd_settings_set, "shallow-merge settings (JSON object)")
    sp.add_argument("--json", required=True)

    sp = add("export", cmd_export, "export a filtered range to CSV or HTML")
    sp.add_argument("--format", required=True, choices=["csv", "html"])
    sp.add_argument("--out", required=True)
    sp.add_argument("--from", dest="from_date", default=None)
    sp.add_argument("--to", default=None)
    sp.add_argument("--client-id", default=None)
    sp.add_argument("--project-id", default=None)
    sp.add_argument("--billable", type=int, choices=[0, 1], default=None)

    sp = add("invoice", cmd_invoice, "generate an HTML invoice for one client + range")
    sp.add_argument("--client-id", required=True)
    sp.add_argument("--from", dest="from_date", required=True)
    sp.add_argument("--to", required=True)
    sp.add_argument("--out", default=None)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = args.func(args)
    except CmdError as e:
        sys.stdout.write(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False) + "\n")
        return 1
    except Exception as e:  # unexpected: surface, never crash silently
        sys.stdout.write(
            json.dumps(
                {"ok": False, "error": f"internal: {type(e).__name__}: {e}"},
                ensure_ascii=False,
            )
            + "\n"
        )
        return 1
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
