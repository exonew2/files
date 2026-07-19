#!/usr/bin/env python3

import os, sys, stat, time, json, errno, logging, signal, threading, re
import subprocess, urllib.request, urllib.error, http.client, socket
from datetime import datetime

log = logging.getLogger("lsfs-fuse")

try:
    from fuse import FUSE, Operations, LoggingMixIn, FuseOSError
except ImportError:
    log.error("fusepy not installed. Install: pip install fusepy")
    sys.exit(1)

MOUNTPOINT = "/mnt/lsfs"
COLLECTION = "apps"
MODEL = "nomic-embed-text"
EMBED_DIM = 768
COSINE_THRESHOLD = 0.5
CACHE_TTL = 30
RECENT_DAYS = 7
QDRANT_SOCKET = "/tmp/lsfs.sock"
QDRANT_TCP = "http://localhost:6333"
OLLAMA_URL = "http://localhost:11434/api/embeddings"
SEARCH_LIMIT = 20
RERANK_KEEP = 5

EXT_WEIGHTS = {
    '.py': 1.2, '.sh': 1.2, '.js': 1.2, '.ts': 1.2, '.rs': 1.2, '.go': 1.2,
    '.md': 1.1, '.txt': 1.1, '.rst': 1.1,
    '.yaml': 1.15, '.yml': 1.15, '.json': 1.15, '.toml': 1.15, '.env': 1.15,
    '.jpg': 0.6, '.png': 0.6, '.mp4': 0.6,
    '.gitignore': 0.5, '.dockerignore': 0.5,
}

_cross_encoder = None

def _get_reranker():
    global _cross_encoder
    if _cross_encoder is None:
        try:
            from sentence_transformers import CrossEncoder
            _cross_encoder = CrossEncoder(
                "cross-encoder/ms-marco-MiniLM-L-6-v2", device="cpu"
            )
        except Exception:
            _cross_encoder = False
    return _cross_encoder if _cross_encoder is not False else None

def _qdrant(method, path, data=None, timeout=3):
    api_path = f"/collections/{COLLECTION}/{path.lstrip('/')}"
    body = json.dumps(data).encode() if data is not None else None
    headers = {"Content-Type": "application/json"}
    if os.path.exists(QDRANT_SOCKET):
        try:
            conn = http.client.HTTPConnection("localhost", timeout=timeout)
            conn.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            conn.sock.settimeout(timeout)
            conn.sock.connect(QDRANT_SOCKET)
            conn.request(method, api_path, body=body, headers=headers)
            resp = conn.getresponse()
            result = json.loads(resp.read())
            conn.close()
            return result
        except Exception:
            pass
    url = f"{QDRANT_TCP}{api_path}"
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {}
        return None
    except Exception:
        return None

def _embed(text, retries=1):
    text
    payload = json.dumps({
        "model": MODEL, "prompt": prefixed[:2048], "keep_alive": -1
    }).encode()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                OLLAMA_URL, data=payload,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=5) as r:
                return json.loads(r.read()).get("embedding")
        except Exception:
            if attempt < retries - 1:
                time.sleep(1)
    return None

_RELATIVE_TIME_RE = re.compile(r'\b(last|within|past|since)\s+(\d+)\s*(h|hr|hour|hours|d|day|days|m|min|minute|minutes|s|sec|second|seconds)\b', re.IGNORECASE)

def _parse_relative_time(query):
    now = time.time()
    def _replace(m):
        amount = int(m.group(2))
        unit = m.group(3).lower()[0]
        if unit in ('h',):
            ts = now - amount * 3600
        elif unit in ('d',):
            ts = now - amount * 86400
        elif unit in ('m',):
            ts = now - amount * 60
        else:
            ts = now - amount
        return f" after:{time.strftime('%Y-%m-%d', time.gmtime(ts))}"
    return _RELATIVE_TIME_RE.sub(_replace, query)

def _parse_filters(query):
    query = _parse_relative_time(query)
    filters = {"must": []}
    tokens = query.split()
    clean = []
    for t in tokens:
        if ':' in t:
            k, v = t.split(':', 1)
            k = k.lower()
            if k == 'ext':
                filters["must"].append({"key": "ext", "match": {"value": v if v.startswith('.') else '.' + v}})
                continue
            elif k == 'type':
                filters["must"].append({"key": "type", "match": {"value": v}})
                continue
            elif k == 'name':
                filters["must"].append({"key": "name", "match": {"value": v}})
                continue
            elif k == 'before':
                try:
                    from datetime import datetime
                    filters["must"].append({"key": "mtime", "range": {"lt": datetime.strptime(v, "%Y-%m-%d").timestamp()}})
                except ValueError:
                    clean.append(t)
                continue
            elif k == 'after':
                try:
                    from datetime import datetime
                    filters["must"].append({"key": "mtime", "range": {"gt": datetime.strptime(v, "%Y-%m-%d").timestamp()}})
                except ValueError:
                    clean.append(t)
                continue
        clean.append(t)
    q = ' '.join(clean)
    return q, filters if filters["must"] else None

def _weight(path):
    name = os.path.basename(path)
    ext = os.path.splitext(path)[1].lower()
    return EXT_WEIGHTS.get(name) or EXT_WEIGHTS.get(ext) or 1.0

def _temporal_decay(path, score):
    try:
        mtime = os.path.getmtime(path)
        age = max(0, min(1, (time.time() - mtime) / 31536000))
        return score * (1 - 0.3 * age)
    except Exception:
        return score * 0.9

def _read_chunk_text(filepath, chunk_label):
    try:
        ext = os.path.splitext(filepath)[1].lower()
        if ext == ".py" and chunk_label and ":" in chunk_label:
            import ast
            kind, name = chunk_label.split(":", 1)
            with open(filepath, "r", errors="replace") as f:
                source = f.read()
            tree = ast.parse(source)
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    if node.name == name:
                        lines = source.split('\n')[node.lineno - 1:node.end_lineno]
                        return '\n'.join(lines)[:2048]
                elif isinstance(node, ast.ClassDef):
                    if node.name == name:
                        lines = source.split('\n')[node.lineno - 1:node.end_lineno]
                        return '\n'.join(lines)[:2048]
        with open(filepath, "r", errors="replace") as f:
            return f.read(2048)
    except Exception:
        return ""

def _rerank(query, candidates):
    reranker = _get_reranker()
    if reranker is None or not candidates:
        return candidates
    texts = []
    for c in candidates:
        ct = _read_chunk_text(c["path"], c.get("chunk_label", ""))
        texts.append(ct if ct else c["name"])
    pairs = [(query, t[:512]) for t in texts]
    try:
        scores = reranker.predict(pairs)
        for i, c in enumerate(candidates):
            c["score"] = float(scores[i])
    except Exception:
        pass
    candidates.sort(key=lambda x: x["score"], reverse=True)
    return candidates[:RERANK_KEEP]


class LSFS(LoggingMixIn, Operations):
    def __init__(self, mountpoint):
        self.mountpoint = mountpoint
        self.running = True
        self.lock = threading.RLock()

        self.search_query = ""
        self.search_results = ""

        self._names = {}
        self._names_ts = 0.0
        self._recents = []
        self._recents_ts = 0.0
        self._query_cache = {}
        self._query_cache_ts = {}

        signal.signal(signal.SIGTERM, self._signal)
        signal.signal(signal.SIGINT, self._signal)

    def _signal(self, signum, frame):
        log.info("Received signal %d, shutting down", signum)
        self.running = False
        sys.exit(0)

    def _scroll_all(self):
        result = _qdrant("POST", "points/scroll", {
            "limit": 10000, "with_payload": True
        })
        if result:
            return result.get("result", {}).get("points", [])
        return []

    @property
    def names(self):
        with self.lock:
            if time.time() - self._names_ts < CACHE_TTL and self._names:
                return self._names
        result = {}
        for pt in self._scroll_all():
            p = pt.get("payload", {})
            path = p.get("path", "")
            name = p.get("name", "")
            if path and name and os.path.exists(path):
                result.setdefault(name, []).append(path)
        with self.lock:
            self._names = result
            self._names_ts = time.time()
        return result

    @property
    def recents(self):
        with self.lock:
            if time.time() - self._recents_ts < CACHE_TTL and self._recents:
                return self._recents
        cutoff = time.time() - RECENT_DAYS * 86400
        files = []
        seen = set()
        for pt in self._scroll_all():
            p = pt.get("payload", {})
            path = p.get("path", "")
            if not path or path in seen:
                continue
            seen.add(path)
            try:
                mtime = os.path.getmtime(path)
                if mtime >= cutoff:
                    name = p.get("name", os.path.basename(path))
                    files.append((mtime, path, name))
            except OSError:
                continue
        files.sort(key=lambda x: x[0], reverse=True)
        with self.lock:
            self._recents = files
            self._recents_ts = time.time()
        return files

    def _search(self, query):
        with self.lock:
            ts = self._query_cache_ts.get(query, 0)
            if time.time() - ts < CACHE_TTL and query in self._query_cache:
                return self._query_cache[query]
        clean_query, qf = _parse_filters(query)
        embedding = _embed(clean_query)
        if not embedding:
            results = []
        else:
            payload = {
                "vector": embedding, "limit": SEARCH_LIMIT, "with_payload": True
            }
            if qf:
                payload["filter"] = qf
            result = _qdrant("POST", "points/search", payload)
            candidates = []
            seen = set()
            now = time.time()
            if result:
                for hit in result.get("result", []):
                    score = hit.get("score", 0)
                    if score < COSINE_THRESHOLD:
                        continue
                    p = hit.get("payload", {})
                    path = p.get("path", "")
                    if not path or path in seen:
                        continue
                    seen.add(path)
                    if os.path.exists(path):
                        candidates.append({
                            "path": path,
                            "name": p.get("name", os.path.basename(path)),
                            "chunk_label": p.get("chunk", ""),
                            "score": score,
                        })
            results = _rerank(clean_query, candidates)
            for r in results:
                mtime = r.get("mtime")
                if mtime is None:
                    try:
                        mtime = os.path.getmtime(r["path"])
                    except OSError:
                        mtime = now
                adj = r["score"] * (1 - 0.3 * max(0, min(1, (now - mtime) / 31536000)))
                adj *= _weight(r["path"])
                r["score"] = adj
            results.sort(key=lambda r: r['score'], reverse=True)
        with self.lock:
            self._query_cache[query] = results
            self._query_cache_ts[query] = time.time()
        return results

    def _status(self):
        info = _qdrant("GET", "", timeout=1)
        points = info.get("result", {}).get("points_count", 0) if info else 0
        return json.dumps({
            "mountpoint": self.mountpoint,
            "collection": COLLECTION,
            "model": MODEL,
            "points": points,
            "threshold": COSINE_THRESHOLD,
            "rerank": RERANK_KEEP,
            "cached_queries": len(self._query_cache),
            "time": time.strftime("%Y-%m-%d %H:%M:%S"),
        }, indent=2) + "\n"

    def _recent_label(self, mtime, path, name):
        ts = datetime.fromtimestamp(mtime).strftime("%Y%m%d_%H%M%S")
        return f"{ts}_{name}"

    def _parts(self, path):
        return [p for p in path.split('/') if p]

    def _dstat(self):
        t = time.time()
        u, g = os.getuid(), os.getgid()
        return {
            'st_mode': stat.S_IFDIR | 0o755, 'st_nlink': 2,
            'st_size': 0, 'st_uid': u, 'st_gid': g,
            'st_atime': t, 'st_mtime': t, 'st_ctime': t,
        }

    def _fstat(self, size, mode=0o644):
        t = time.time()
        u, g = os.getuid(), os.getgid()
        return {
            'st_mode': stat.S_IFREG | mode, 'st_nlink': 1,
            'st_size': size, 'st_uid': u, 'st_gid': g,
            'st_atime': t, 'st_mtime': t, 'st_ctime': t,
        }

    def _lstat(self, target):
        t = time.time()
        u, g = os.getuid(), os.getgid()
        return {
            'st_mode': stat.S_IFLNK | 0o777, 'st_nlink': 1,
            'st_size': len(target.encode()), 'st_uid': u, 'st_gid': g,
            'st_atime': t, 'st_mtime': t, 'st_ctime': t,
        }

    def getattr(self, path, fh=None):
        parts = self._parts(path)

        if not parts:
            return self._dstat()

        if len(parts) == 1:
            if parts[0] in ('by-name', 'by-content', 'by-tag', 'recent', 'context', '.lsfs'):
                return self._dstat()
            raise FuseOSError(errno.ENOENT)

        if parts[0] == '.lsfs' and len(parts) == 2:
            if parts[1] == 'search':
                return self._fstat(len(self.search_results))
            if parts[1] == 'index':
                return self._fstat(0, 0o622)
            if parts[1] == 'status':
                d = self._status()
                return self._fstat(len(d), 0o444)
            raise FuseOSError(errno.ENOENT)

        if len(parts) == 2 and parts[0] == 'by-name':
            names = self.names
            if parts[1] in names:
                return self._lstat(names[parts[1]][0])
            raise FuseOSError(errno.ENOENT)

        if len(parts) == 2 and parts[0] in ('by-content', 'by-tag'):
            return self._dstat()

        if len(parts) == 3 and parts[0] in ('by-content', 'by-tag'):
            query, res_name = parts[1], parts[2]
            results = self._search(query)
            for r in results:
                n = r['name']
                if n == res_name or res_name.startswith(n + '.'):
                    return self._lstat(r['path'])
            raise FuseOSError(errno.ENOENT)

        if len(parts) == 2 and parts[0] == 'recent':
            for mtime, path_, name in self.recents:
                if self._recent_label(mtime, path_, name) == parts[1]:
                    return self._lstat(path_)
            raise FuseOSError(errno.ENOENT)

        if parts[0] == 'context':
            home = os.path.expanduser("~")
            target = os.path.join(home, *parts[1:])
            if os.path.lexists(target):
                if os.path.isdir(target):
                    return self._dstat()
                return self._lstat(target)
            raise FuseOSError(errno.ENOENT)

        raise FuseOSError(errno.ENOENT)

    def readdir(self, path, fh):
        parts = self._parts(path)

        if not parts:
            return ['.', '..', 'by-name', 'by-content', 'by-tag',
                    'recent', 'context', '.lsfs']

        if len(parts) == 1:
            if parts[0] == 'by-name':
                return ['.', '..'] + sorted(self.names.keys())
            if parts[0] == 'by-content':
                return ['.', '..'] + sorted(self._query_cache.keys())
            if parts[0] == 'by-tag':
                return ['.', '..']
            if parts[0] == 'recent':
                entries = [self._recent_label(m, p, n) for m, p, n in self.recents]
                return ['.', '..'] + entries
            if parts[0] == 'context':
                home = os.path.expanduser("~")
                try:
                    items = sorted(os.listdir(home))
                    return ['.', '..'] + items
                except OSError:
                    return ['.', '..']
            if parts[0] == '.lsfs':
                return ['.', '..', 'search', 'index', 'status']
            raise FuseOSError(errno.ENOENT)

        if len(parts) == 2 and parts[0] in ('by-content', 'by-tag'):
            query = parts[1]
            results = self._search(query)
            entries = []
            seen = {}
            for r in results:
                n = r['name']
                if n not in seen:
                    seen[n] = 0
                    entries.append(n)
                else:
                    seen[n] += 1
                    entries.append(f"{n}.{seen[n]}")
            return ['.', '..'] + entries

        if len(parts) >= 1 and parts[0] == 'context':
            home = os.path.expanduser("~")
            target = os.path.join(home, *parts[1:])
            if os.path.isdir(target):
                try:
                    items = sorted(os.listdir(target))
                    return ['.', '..'] + items
                except OSError:
                    return ['.', '..']
            return ['.', '..']

        raise FuseOSError(errno.ENOENT)

    def readlink(self, path):
        parts = self._parts(path)

        if len(parts) == 2 and parts[0] == 'by-name':
            names = self.names
            if parts[1] in names:
                return names[parts[1]][0]
            raise FuseOSError(errno.ENOENT)

        if len(parts) == 3 and parts[0] in ('by-content', 'by-tag'):
            query, res_name = parts[1], parts[2]
            results = self._search(query)
            for r in results:
                n = r['name']
                if n == res_name or res_name.startswith(n + '.'):
                    return r['path']
            raise FuseOSError(errno.ENOENT)

        if len(parts) == 2 and parts[0] == 'recent':
            for mtime, path_, name in self.recents:
                if self._recent_label(mtime, path_, name) == parts[1]:
                    return path_
            raise FuseOSError(errno.ENOENT)

        if parts[0] == 'context':
            home = os.path.expanduser("~")
            return os.path.join(home, *parts[1:])

        raise FuseOSError(errno.ENOENT)

    def read(self, path, size, offset, fh):
        parts = self._parts(path)

        if parts and parts[0] == '.lsfs':
            if parts[-1] == 'search':
                data = self.search_results
                return data[offset:offset + size].encode()
            if parts[-1] == 'status':
                data = self._status()
                return data[offset:offset + size].encode()

        raise FuseOSError(errno.ENOENT)

    def write(self, path, data, offset, fh):
        parts = self._parts(path)
        if not parts or parts[0] != '.lsfs':
            raise FuseOSError(errno.EACCES)

        text = data.decode('utf-8', errors='replace').strip()

        if parts[-1] == 'search':
            self.search_query = text
            threading.Thread(target=self._run_search, daemon=True).start()
            return len(data)

        if parts[-1] == 'index':
            threading.Thread(target=self._run_index, args=(text,), daemon=True).start()
            return len(data)

        raise FuseOSError(errno.EACCES)

    def _run_search(self):
        query = self.search_query
        if not query:
            return
        try:
            results = self._search(query)
            if not results:
                self.search_results = f"# No results for '{query}'\n"
            else:
                lines = [
                    f"{r['path']}\t{r['name']}\t{r.get('chunk_label', '')}\t{r['score']:.3f}"
                    for r in results
                ]
                self.search_results = "\n".join(lines) + "\n"
        except Exception as e:
            self.search_results = f"# Error: {e}\n"

    def _run_index(self, path):
        path = path.strip()
        if not path:
            return
        try:
            subprocess.run(
                [sys.executable, "/usr/lib/lsfs/lsfs_query.py", "--index", path],
                timeout=120, capture_output=True
            )
        except Exception:
            pass

    def truncate(self, path, length, fh=None):
        parts = self._parts(path)
        if parts and parts[0] == '.lsfs' and parts[-1] == 'search':
            self.search_results = ""
            return 0
        raise FuseOSError(errno.EACCES)

    def open(self, path, flags):
        return 0

    def release(self, path, fh):
        pass


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )

    mountpoint = sys.argv[1] if len(sys.argv) > 1 else MOUNTPOINT
    log.info("Mounting LSFS at %s", mountpoint)

    os.makedirs(mountpoint, exist_ok=True)

    try:
        FUSE(
            LSFS(mountpoint),
            mountpoint,
            foreground=True,
            allow_other=True,
            ro=False,
        )
    except RuntimeError as e:
        log.error("Mount failed: %s", e)
        log.error("Ensure fusepy is installed and /etc/fuse.conf has user_allow_other")
        sys.exit(1)


if __name__ == "__main__":
    main()
