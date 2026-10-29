#!/usr/bin/env python3
"""LobsterDeck API - read-only aggregation for Reports / Files / Agent memory.

Single-file, stdlib only. Sits beside existing services and never mutates
their data, except the documented reports token map.
"""
from __future__ import annotations

import hmac
import json
import os
import re
import secrets
import subprocess
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

HOME = Path("/vol1/1000/home/LiGuiyu")
REPORTS_DIR = Path("/vol1/1000/Docker/Reports/site/reports")
REPORTS_SITE = Path("/vol1/1000/Docker/Reports/site")
TOKENS_MAP = Path("/vol1/1000/Docker/Reports/nginx/tokens.map")
INBOX = HOME / "file-inbox"
LC_REPO = HOME / "LobsterContext"

STATE_DIR = Path(os.environ.get("LOBSTERDECK_STATE", "/vol1/1000/Docker/LobsterDeck"))
STATE_DIR.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get("LOBSTERDECK_PORT", "3320"))
APP_VERSION = "1.0.0"


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def load_token() -> str:
    env = os.environ.get("LOBSTERDECK_TOKEN", "").strip()
    if env:
        return env
    f = STATE_DIR / "token.txt"
    if f.exists():
        return f.read_text(encoding="utf-8").strip()
    tok = secrets.token_urlsafe(32)
    f.write_text(tok + "\n", encoding="utf-8")
    f.chmod(0o600)
    return tok


API_TOKEN = load_token()


def authed(handler) -> bool:
    h = handler.headers.get("Authorization", "")
    if not h.startswith("Bearer "):
        return False
    return hmac.compare_digest(h[7:].strip(), API_TOKEN)


def read_json(handler) -> dict:
    n = int(handler.headers.get("Content-Length", 0) or 0)
    if n <= 0:
        return {}
    return json.loads(handler.rfile.read(n) or b"{}")


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")


def human_size(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{int(n)} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0
    return f"{n:.1f} GB"


# reports -------------------------------------------------------------------
def parse_tokens() -> dict:
    out = {}
    if not TOKENS_MAP.exists():
        return out
    for line in TOKENS_MAP.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^"(/reports/([^"]+\.html))"\s+"([0-9a-f]+)";', line.strip())
        if m:
            out[m.group(2)] = m.group(3)
    return out


def write_tokens(mapping: dict) -> None:
    header = ('# shared report token map (URI -> token)\n'
              '# format: "/reports/xxx.html" "token";\n'
              '# remove a line to revoke; then: docker exec reports nginx -s reload\n')
    lines = [header]
    for name in sorted(mapping):
        lines.append(f'"/reports/{name}" "{mapping[name]}";\n')
    tmp = TOKENS_MAP.with_suffix(".tmp")
    tmp.write_text("".join(lines), encoding="utf-8")
    os.chmod(tmp, 0o664)
    os.replace(tmp, TOKENS_MAP)
    try:
        subprocess.run(["docker", "exec", "reports", "nginx", "-s", "reload"],
                       check=False, capture_output=True, timeout=20)
    except Exception:
        pass


def title_of(p: Path) -> str:
    try:
        head = p.read_text(encoding="utf-8", errors="ignore")[:20000]
        m = re.search(r"<title>(.*?)</title>", head, re.S | re.I)
        if m:
            t = re.sub(r"<[^>]+>", "", m.group(1)).strip()
            if t:
                return t
    except Exception:
        pass
    return p.stem


def reports_list() -> list:
    tokens = parse_tokens()
    items = []
    for f in REPORTS_DIR.glob("*.html"):
        if f.name in ("index.html", "all-index.html") or f.name.endswith(".body.html"):
            continue
        st = f.stat()
        m = re.match(r"(\d{4}-\d{2}-\d{2})", f.name)
        items.append({
            "id": f.name,
            "title": title_of(f),
            "date": m.group(1) if m else iso(st.st_mtime)[:10],
            "modified": iso(st.st_mtime),
            "size": st.st_size,
            "shared": f.name in tokens,
        })
    items.sort(key=lambda x: (x["date"], x["modified"]), reverse=True)
    return items


def report_html(name: str) -> str:
    p = REPORTS_DIR / name
    html = p.read_text(encoding="utf-8", errors="ignore")
    # keep each report's own look; only rebase root-relative assets onto our proxy
    html = re.sub(r'(src|href)="/', r'\1="../', html)
    return html


def safe_report_name(name: str):
    if re.fullmatch(r"[A-Za-z0-9._-]+\.html", name or "") and (REPORTS_DIR / name).exists():
        return name
    return None


# files ---------------------------------------------------------------------
IGNORE = {".DS_Store", ".desktop.ini", "Thumbs.db"}
STATE_FILE = STATE_DIR / "files_state.json"


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"initialized": False, "files": {}}


def save_state(state: dict) -> None:
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, STATE_FILE)


def rel_safe(rel: str) -> Path:
    p = (INBOX / unquote(rel or "")).resolve()
    if not str(p).startswith(str(INBOX.resolve())):
        raise ValueError("bad path")
    return p


def walk_files(limit: int = 4000) -> list:
    out = []
    for p in INBOX.rglob("*"):
        if len(out) >= limit:
            break
        try:
            if p.name in IGNORE or p.name.startswith("."):
                continue
            if not p.is_file():
                continue
            st = p.stat()
            out.append({"path": str(p.relative_to(INBOX)), "name": p.name,
                        "size": st.st_size, "size_h": human_size(st.st_size),
                        "mtime": st.st_mtime})
        except Exception:
            continue
    return out


def scan_state() -> dict:
    st = load_state()
    first = not st.get("initialized")
    known = st.setdefault("files", {})
    t = time.time()
    for item in walk_files():
        key = item["path"]
        rec = known.get(key)
        if rec is None:
            rec = {"first_seen": t, "mtime": item["mtime"], "size": item["size"]}
            known[key] = rec
            item["new"] = not first
        else:
            item["new"] = False
            if rec.get("mtime") != item["mtime"] or rec.get("size") != item["size"]:
                item["changed"] = True
                rec["mtime"] = item["mtime"]
                rec["size"] = item["size"]
        rec["last_seen"] = t
    st["initialized"] = True
    st["updated_at"] = now_iso()
    save_state(st)
    return {"items": walk_files(), "state": st}


def files_recent(limit: int = 20) -> list:
    scanned = scan_state()
    st = scanned["state"]
    items = []
    for item in scanned["items"]:
        rec = st["files"].get(item["path"], {})
        item["first_seen"] = rec.get("first_seen")
        items.append(item)
    items.sort(key=lambda x: x["mtime"], reverse=True)
    return items[:limit]


def files_list(rel: str) -> dict:
    target = rel_safe(rel)
    if not target.exists() or not target.is_dir():
        raise FileNotFoundError(rel)
    dirs, files = [], []
    for p in sorted(target.iterdir(), key=lambda x: x.name.lower()):
        if p.name in IGNORE or p.name.startswith("."):
            continue
        try:
            st = p.stat()
        except Exception:
            continue
        item = {"name": p.name, "path": str(p.relative_to(INBOX)), "is_dir": p.is_dir(),
                "size": 0 if p.is_dir() else st.st_size,
                "size_h": "" if p.is_dir() else human_size(st.st_size),
                "mtime": iso(st.st_mtime)}
        (dirs if p.is_dir() else files).append(item)
    return {"path": rel, "dirs": dirs, "files": files}


# agents --------------------------------------------------------------------
AGENT_LABELS = {
    "OpenClaw": "OpenClaw", "ClaudeCode": "Claude Code", "GitHubCopilot": "GitHub Copilot",
    "Qoder": "Qoder", "KimiCode": "Kimi Code", "ZCode": "Z Code",
    "DeepSeekHarness": "DeepSeek Harness", "WorkBuddy": "WorkBuddy", "Reasonix": "Reasonix",
    "Pi": "Pi", "OpenCode": "OpenCode", "Cursor": "Cursor", "Antigravity": "Antigravity",
    "Codex": "Codex", "Gemini": "Gemini",
}


def git(*args, timeout: int = 30) -> str:
    p = subprocess.run(["git", "-C", str(LC_REPO), *args], capture_output=True,
                       text=True, timeout=timeout)
    return p.stdout


def agent_of(files: list):
    counts = {}
    for f in files:
        m = re.match(r"Memory/([^/]+)/", f)
        if m:
            counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    return max(counts, key=counts.get) if counts else None


def commits(limit: int = 60, path: str = "Memory") -> list:
    raw = git("log", f"-{limit}", "--date=iso-strict",
              "--pretty=format:@@@%H%x1f%an%x1f%ad%x1f%s", "--name-only", "--", path)
    out = []
    for block in raw.split("@@@"):
        block = block.strip("\n")
        if not block:
            continue
        lines = block.splitlines()
        head = lines[0].split("\x1f")
        if len(head) < 4:
            continue
        files = [l.strip() for l in lines[1:] if l.strip()]
        out.append({"sha": head[0], "author": head[1], "date": head[2],
                    "subject": head[3], "files": files, "agent": agent_of(files)})
    return out


def _age_days(s: str) -> float:
    try:
        return max(0.0, (time.time() - datetime.fromisoformat(s).timestamp()) / 86400.0)
    except Exception:
        return 9999


def agents_overview() -> list:
    cs = commits(200)
    by = {}
    for c in cs:
        a = c["agent"]
        if not a:
            continue
        d = by.setdefault(a, {"agent": a, "label": AGENT_LABELS.get(a, a),
                              "commits": 0, "last": c["date"], "files": set(), "recent": []})
        d["commits"] += 1
        d["files"].update(c["files"])
        if len(d["recent"]) < 3:
            d["recent"].append({"sha": c["sha"], "subject": c["subject"], "date": c["date"]})
    out = []
    for d in by.values():
        d["files"] = len(d["files"])
        d["commits_30d"] = sum(1 for c in cs if c["agent"] == d["agent"] and _age_days(c["date"]) <= 30)
        out.append(d)
    out.sort(key=lambda x: x["last"], reverse=True)
    return out


def commit_detail(sha: str) -> dict:
    if not re.fullmatch(r"[0-9a-f]{7,40}", sha or ""):
        raise ValueError("bad sha")
    meta = git("show", "-s", "--date=iso-strict",
               "--pretty=format:%H%x1f%an%x1f%ae%x1f%ad%x1f%s%x1f%b", sha)
    parts = meta.split("\x1f")
    patch = git("show", "--format=", "--no-color", sha, "--", "Memory", timeout=60)
    if len(patch) > 60000:
        patch = patch[:60000] + "\n... (truncated)"
    return {"sha": parts[0] if parts else sha,
            "author": parts[1] if len(parts) > 1 else "",
            "email": parts[2] if len(parts) > 2 else "",
            "date": parts[3] if len(parts) > 3 else "",
            "subject": parts[4] if len(parts) > 4 else "",
            "body": parts[5] if len(parts) > 5 else "",
            "patch": patch}


# home layout ---------------------------------------------------------------
DEFAULT_LAYOUT = {
    "version": 1, "generated_by": "lobster", "updated_at": None,
    "modules": [
        {"id": "hero", "kind": "hero", "size": "hero", "title": "你好，桂鱼",
         "subtitle": "你的 AI 空间，都在这里。", "accent": "orange"},
        {"id": "recent-reports", "kind": "list", "size": "large", "title": "最新报告",
         "subtitle": "深度调研与每日简报", "source": "reports", "limit": 3},
        {"id": "new-files", "kind": "list", "size": "large", "title": "新到的文件",
         "subtitle": "来自文件站的最新变化", "source": "files", "limit": 4},
        {"id": "agents", "kind": "agents", "size": "large", "title": "Agent 在忙什么",
         "subtitle": "记忆库最近的变化", "source": "agents", "limit": 3},
        {"id": "quick", "kind": "actions", "size": "medium", "title": "快捷入口",
         "items": [
             {"title": "报告台", "subtitle": "reports.liguiyu.com",
              "url": "https://reports.liguiyu.com", "icon": "doc.text"},
             {"title": "文件站", "subtitle": "file.liguiyu.com",
              "url": "https://file.liguiyu.com/fs", "icon": "folder"},
         ]},
    ],
}
LAYOUT_FILE = STATE_DIR / "home.json"


def load_layout() -> dict:
    if LAYOUT_FILE.exists():
        try:
            return json.loads(LAYOUT_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    save_layout(DEFAULT_LAYOUT)
    return dict(DEFAULT_LAYOUT)


def save_layout(layout: dict) -> None:
    layout = dict(layout)
    layout["updated_at"] = now_iso()
    tmp = LAYOUT_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, LAYOUT_FILE)


def resolve_module(m: dict) -> dict:
    out = dict(m)
    kind = m.get("kind", "list")
    limit = int(m.get("limit", 4))
    src = m.get("source")
    if kind == "list" and src == "reports":
        out["items"] = [{"title": r["title"], "subtitle": r["date"], "id": r["id"],
                         "shared": r["shared"]} for r in reports_list()[:limit]]
    elif kind == "list" and src == "files":
        prefix = m.get("prefix")
        pool = files_recent(400) if prefix else files_recent(limit)
        if prefix:
            pool = [f for f in pool if f["path"].startswith(prefix)][:limit]
        out["items"] = [{"title": f["name"],
                         "subtitle": f"{f['size_h']} · " + iso(f["mtime"])[:16].replace("T", " "),
                         "path": f["path"], "new": f.get("new", False)}
                        for f in pool]
    elif kind == "agents":
        out["items"] = [{"title": a["label"],
                         "subtitle": a["last"][:16].replace("T", " "),
                         "detail": f"{a['commits_30d']} 次更新", "agent": a["agent"]}
                        for a in agents_overview()[:limit]]
    return out


def overview() -> dict:
    layout = load_layout()
    rs = reports_list()
    fl = files_recent(3)
    ag = agents_overview()
    return {"generated_at": now_iso(),
            "layout_updated_at": layout.get("updated_at"),
            "generated_by": layout.get("generated_by", "lobster"),
            "stats": {"reports": len(rs), "files": len(fl), "agents": len(ag)},
            "modules": [resolve_module(m) for m in layout.get("modules", [])]}


# server --------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "LobsterDeck/" + APP_VERSION

    def log_message(self, fmt, *args):
        print("[deck]", self.address_string(), fmt % args)

    def _json(self, code: int, obj) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _raw(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _guard(self) -> bool:
        if authed(self):
            return True
        self._json(401, {"error": "unauthorized"})
        return False

    def do_GET(self):
        u = urlparse(self.path)
        p, q = u.path, parse_qs(u.query)
        try:
            if p == "/api/v1/health":
                self._json(200, {"ok": True, "version": APP_VERSION, "time": now_iso()})
                return
            if not self._guard():
                return
            if p == "/api/v1/overview":
                self._json(200, overview())
            elif p == "/api/v1/home/layout":
                self._json(200, load_layout())
            elif p == "/api/v1/reports":
                self._json(200, {"items": reports_list()})
            elif p.startswith("/api/v1/reports/") and p.endswith("/html"):
                name = safe_report_name(p.split("/")[-2])
                if not name:
                    self._json(404, {"error": "not found"})
                else:
                    self._json(200, {"id": name, "html": report_html(name)})
            elif p.startswith("/api/v1/report-assets/"):
                rel = unquote(p[len("/api/v1/report-assets/"):])
                target = (REPORTS_SITE / rel).resolve()
                if not str(target).startswith(str(REPORTS_SITE.resolve())) or not target.is_file():
                    self._json(404, {"error": "not found"})
                    return
                ctype = {".css": "text/css", ".js": "application/javascript",
                         ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                         ".svg": "image/svg+xml", ".woff2": "font/woff2",
                         ".woff": "font/woff"}.get(target.suffix, "application/octet-stream")
                self._raw(200, target.read_bytes(), ctype)
            elif p == "/api/v1/reports/tokens":
                self._json(200, {"tokens": parse_tokens()})
            elif p == "/api/v1/files":
                self._json(200, files_list(q.get("path", [""])[0]))
            elif p == "/api/v1/files/recent":
                self._json(200, {"items": files_recent(int(q.get("limit", ["20"])[0]))})
            elif p == "/api/v1/files/raw":
                target = rel_safe(q.get("path", [""])[0])
                if not target.is_file():
                    self._json(404, {"error": "not found"})
                else:
                    self._raw(200, target.read_bytes(), "application/octet-stream")
            elif p == "/api/v1/agents":
                self._json(200, {"items": agents_overview()})
            elif p == "/api/v1/agents/commit":
                self._json(200, commit_detail(q.get("sha", [""])[0]))
            elif p.startswith("/api/v1/agents/") and p.endswith("/commits"):
                name = p.split("/")[-2]
                limit = int(q.get("limit", ["40"])[0])
                items = [c for c in commits(300) if c["agent"] == name][:limit]
                self._json(200, {"items": items})
            else:
                self._json(404, {"error": "not found"})
        except FileNotFoundError:
            self._json(404, {"error": "not found"})
        except ValueError as e:
            self._json(400, {"error": str(e)})
        except Exception as e:
            self._json(500, {"error": "server error", "detail": str(e)[:300]})

    def do_PUT(self):
        if not self._guard():
            return
        if urlparse(self.path).path != "/api/v1/home/layout":
            self._json(404, {"error": "not found"})
            return
        try:
            layout = read_json(self)
            if not isinstance(layout.get("modules"), list):
                raise ValueError("modules required")
            save_layout(layout)
            self._json(200, {"ok": True, "updated_at": load_layout().get("updated_at")})
        except Exception as e:
            self._json(400, {"error": str(e)[:300]})

    def do_POST(self):
        if not self._guard():
            return
        p = urlparse(self.path).path
        try:
            if p == "/api/v1/reports/tokens":
                data = read_json(self)
                name, action = data.get("file", ""), data.get("action", "")
                if not safe_report_name(name):
                    raise ValueError("bad file")
                mapping = parse_tokens()
                if action == "share":
                    mapping[name] = secrets.token_hex(12)
                elif action == "rotate":
                    if name not in mapping:
                        raise ValueError("该报告尚未共享")
                    mapping[name] = secrets.token_hex(12)
                elif action == "revoke":
                    if name not in mapping:
                        raise ValueError("该报告尚未共享")
                    mapping.pop(name, None)
                else:
                    raise ValueError("bad action")
                write_tokens(mapping)
                self._json(200, {"ok": True, "token": mapping.get(name)})
            else:
                self._json(404, {"error": "not found"})
        except Exception as e:
            self._json(400, {"error": str(e)[:300]})


def main() -> None:
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"LobsterDeck API v{APP_VERSION} on :{PORT}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
