#!/usr/bin/env python3
"""Prepare the game's sounds: fetch the licensed originals, cut, level and encode them.

    python3 tools/prepare-sounds.py            # fetch (cached), cut, level, encode, write LICENSES.md
    python3 tools/prepare-sounds.py --check    # no encoding: every manifest entry resolves, every
                                               # output has a source, LICENSES.md is current

Inputs:  shared/assets/sounds/sources.toml   (where each original comes from, and each clip's cut)
         shared/data/sounds.toml             (the runtime manifest: event id -> files; checked only)
Outputs: shared/assets/sounds/<dir>/<name>.m4a  AAC-LC in MPEG-4, for iOS (AVAudioFile / AVAudioEngine)
         shared/assets/sounds/<dir>/<name>.ogg  Vorbis in Ogg, for Android (SoundPool / MediaExtractor)
         shared/assets/sounds/LICENSES.md       generated from sources.toml, never edited by hand

Originals are cached in shared/assets/sounds/.originals/ (git-ignored) and pinned by sha256: a
changed upstream file fails loud instead of silently changing a sound.

Needs Python 3.11+ (tomllib), ffmpeg and ffprobe (with the native `aac` encoder) and oggenc
(vorbis-tools) on PATH, or FFMPEG / FFPROBE / OGGENC set to their paths. macOS: `brew install ffmpeg
vorbis-tools`. Deterministic for a given toolchain: bit-exact MPEG-4, a fixed Ogg serial number.
"""
from __future__ import annotations

import array
import hashlib
import math
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOUNDS = ROOT / "shared/assets/sounds"
SOURCES = SOUNDS / "sources.toml"
MANIFEST = ROOT / "shared/data/sounds.toml"
CACHE = SOUNDS / ".originals"
LICENSES = SOUNDS / "LICENSES.md"

SR = 44100
FORMATS = ("m4a", "ogg")
AAC_KBPS = {1: 96, 2: 128}
VORBIS_QUALITY = "3"          # ~80 kbit/s mono, ~112 kbit/s stereo
LEAD_THRESHOLD_DB = -40.0     # leading silence: below this, relative to the clip's peak
TAIL_THRESHOLD_DB = -54.0     # trailing silence: likewise
FADE_IN_S = 0.002


def die(msg: str) -> None:
    sys.exit(f"prepare-sounds: {msg}")


def tool(name: str, env: str) -> str:
    path = os.environ.get(env) or shutil.which(name)
    if not path:
        die(f"{name} not found — install it (macOS: brew install {'vorbis-tools' if name == 'oggenc' else 'ffmpeg'}) "
            f"or set {env} to its path")
    return path


# ------------------------------------------------------------------------------------ declarations

def load_sources() -> dict:
    with open(SOURCES, "rb") as f:
        d = tomllib.load(f)
    for key in ("class", "source", "clip"):
        if key not in d:
            die(f"{SOURCES.relative_to(ROOT)}: no [{key}] declared")
    for sid, s in d["source"].items():
        for k in ("title", "author", "page", "url", "licence", "licence_url", "sha256"):
            if k not in s:
                die(f"{SOURCES.relative_to(ROOT)}: source.{sid} has no `{k}`")
        if s["licence"] != "CC0 1.0" and "attribution" not in s:
            die(f"source.{sid}: licence {s['licence']!r} is not CC0 — a CC-BY source must carry its exact "
                "`attribution` line (and nothing non-commercial or share-alike is allowed at all)")
    seen = set()
    for c in d["clip"]:
        for k in ("out", "parts", "class", "note"):
            if k not in c:
                die(f"{SOURCES.relative_to(ROOT)}: clip {c.get('out', '?')} has no `{k}`")
        if c["out"] in seen:
            die(f"clip {c['out']} is declared twice")
        seen.add(c["out"])
        if c["class"] not in d["class"]:
            die(f"clip {c['out']}: class {c['class']!r} is not declared under [class]")
        for p in c["parts"]:
            if p[0] not in d["source"]:
                die(f"clip {c['out']}: source {p[0]!r} is not declared")
    return d


def load_manifest() -> dict:
    with open(MANIFEST, "rb") as f:
        m = tomllib.load(f)
    if "event" not in m or "category" not in m:
        die(f"{MANIFEST.relative_to(ROOT)}: needs [category.*] and [event.\"…\"] tables")
    for eid, e in m["event"].items():
        for k in ("category", "when", "gain_db", "pitch_semitones", "max_voices", "priority"):
            if k not in e:
                die(f"{MANIFEST.relative_to(ROOT)}: event {eid} has no `{k}`")
        if e["category"] not in m["category"]:
            die(f"event {eid}: category {e['category']!r} is not declared under [category]")
        if not eid.startswith(e["category"] + "."):
            die(f"event {eid}: its id must start with its category ({e['category']}.)")
        has_files = "files" in e
        has_sport = "field" in e or "ice" in e
        if has_files == has_sport:
            die(f"event {eid}: give either `files` (both sports) or both `field` and `ice`")
        if has_sport and not ("field" in e and "ice" in e):
            die(f"event {eid}: `field` and `ice` come together")
        empty = not any(e.get(k) for k in ("files", "field", "ice"))
        if empty and "todo" not in e:
            die(f"event {eid}: no files and no `todo` saying why")
    return m


def manifest_stems(m: dict) -> dict[str, list[str]]:
    out = {}
    for eid, e in m["event"].items():
        out[eid] = [s for k in ("files", "field", "ice") for s in e.get(k, [])]
    return out


# ------------------------------------------------------------------------------------------ fetch

def fetch(sid: str, s: dict) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{sid}{Path(s['url']).suffix}"
    if not path.exists():
        print(f"  fetch {sid} <- {s['url']}")
        req = urllib.request.Request(s["url"], headers={"User-Agent": "smash-hockey-prepare-sounds"})
        data = urllib.request.urlopen(req, timeout=120).read()
        tmp = path.with_suffix(path.suffix + ".part")
        tmp.write_bytes(data)
        tmp.rename(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if not s["sha256"]:
        die(f"source.{sid}: sha256 is not pinned — the file fetched from {s['url']} hashes to\n  {digest}\n"
            f"listen to it, then pin that value in {SOURCES.relative_to(ROOT)}")
    if digest != s["sha256"]:
        die(f"source.{sid}: {path.name} hashes to {digest}, pinned {s['sha256']} — upstream changed or the "
            f"download is corrupt; delete {path.relative_to(ROOT)} to refetch, and re-check the sound before re-pinning")
    return path


def original(sources: dict, sid: str, member: str | None, workdir: Path) -> Path:
    path = fetch(sid, sources["source"][sid])
    if member is None:
        return path
    with zipfile.ZipFile(path) as z:
        if member not in z.namelist():
            die(f"source.{sid}: {member!r} is not in {path.name}")
        dest = workdir / f"{sid}--{member.replace('/', '_')}"
        dest.write_bytes(z.read(member))
    return dest


# ------------------------------------------------------------------------------------------ audio

def decode(ffmpeg: str, src: Path, start: float | None, end: float | None, ch: int, highpass: float | None) -> array.array:
    cmd = [ffmpeg, "-v", "error"]
    if start is not None:
        cmd += ["-ss", f"{start:.3f}"]
    if end is not None:
        cmd += ["-to", f"{end:.3f}"]
    cmd += ["-i", str(src)]
    if highpass:
        cmd += ["-af", f"highpass=f={highpass}:poles=2"]
    cmd += ["-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    a = array.array("f")
    a.frombytes(raw)
    if not a:
        die(f"{src.name} [{start}–{end}] decoded to nothing")
    return a


def db(x: float) -> float:
    return 20 * math.log10(max(x, 1e-12))


def frames(a: array.array, ch: int) -> int:
    return len(a) // ch


def peak(a: array.array) -> float:
    return max(abs(v) for v in a)


def loudest_window(a: array.array, ch: int, win_s: float = 0.1, hop_s: float = 0.01) -> float:
    """RMS (dBFS) of the loudest 100 ms, all channels together. Short clips: the whole clip."""
    n = frames(a, ch)
    w = min(n, int(SR * win_s))
    hop = max(1, int(SR * hop_s))
    sq = [0.0] * (n + 1)          # prefix sums of per-frame mean square
    acc = 0.0
    for i in range(n):
        s = 0.0
        for c in range(ch):
            v = a[i * ch + c]
            s += v * v
        acc += s / ch
        sq[i + 1] = acc
    best = max(sq[i + w] - sq[i] for i in range(0, n - w + 1, hop))
    return db(math.sqrt(best / w))


def trim(a: array.array, ch: int) -> array.array:
    n = frames(a, ch)
    pk = peak(a)
    lead = pk * 10 ** (LEAD_THRESHOLD_DB / 20)
    tail = pk * 10 ** (TAIL_THRESHOLD_DB / 20)
    first = next(i for i in range(n) if any(abs(a[i * ch + c]) > lead for c in range(ch)))
    last = next(i for i in range(n - 1, -1, -1) if any(abs(a[i * ch + c]) > tail for c in range(ch)))
    first = max(0, first - int(SR * 0.002))
    last = min(n - 1, last + int(SR * 0.010))
    return a[first * ch:(last + 1) * ch]


def limit(a: array.array, ch: int, threshold: float, attack_s: float = 0.0005, release_s: float = 0.008) -> None:
    """Look-ahead peak limiter: no sample ends above `threshold`. The gain starts to dip `attack_s`
    before a peak (a sliding minimum, then a box average of the same length, so the gain at the peak
    is at most what the peak needs) and recovers exponentially over `release_s`."""
    from collections import deque
    n = frames(a, ch)
    need = [min(1.0, threshold / max(max(abs(a[i * ch + c]) for c in range(ch)), 1e-12)) for i in range(n)]
    A = max(1, int(SR * attack_s))
    # m[i] = min(need[i .. i + 2A])
    m = [1.0] * n
    q: deque[int] = deque()
    for j in range(n + 2 * A):
        if j < n:
            while q and need[q[-1]] >= need[j]:
                q.pop()
            q.append(j)
        i = j - 2 * A
        if i >= 0:
            while q[0] < i:
                q.popleft()
            m[i] = need[q[0]]
    # box average over [i - A, i]
    avg = [0.0] * n
    acc = 0.0
    for i in range(n):
        acc += m[i]
        if i > A:
            acc -= m[i - A - 1]
        avg[i] = acc / min(i + 1, A + 1) if i < A else acc / (A + 1)
    rel = 1 - math.exp(-1 / (SR * release_s))
    env = 1.0
    for i in range(n):
        env = min(avg[i], env + (1 - env) * rel)
        for c in range(ch):
            a[i * ch + c] *= env
    # the box average of a minimum can overshoot by rounding at the very edges: clamp what is left
    for i in range(len(a)):
        if abs(a[i]) > threshold:
            a[i] = math.copysign(threshold, a[i])


def fades(a: array.array, ch: int, fade_out: float) -> None:
    n = frames(a, ch)
    fi = min(n, int(SR * FADE_IN_S))
    for i in range(fi):
        g = i / fi
        for c in range(ch):
            a[i * ch + c] *= g
    fo = min(n, int(SR * fade_out))
    for k in range(fo):
        i = n - fo + k
        g = math.cos(0.5 * math.pi * (k + 1) / fo) ** 2      # raised-cosine to exact zero
        for c in range(ch):
            a[i * ch + c] *= g


def encode(ffmpeg: str, oggenc: str, a: array.array, ch: int, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    pcm = a.tobytes()
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "clip.wav"
        subprocess.run([ffmpeg, "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
                        "-c:a", "pcm_s16le", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(wav)],
                       input=pcm, check=True)
        subprocess.run([ffmpeg, "-v", "error", "-y", "-i", str(wav), "-map_metadata", "-1",
                        "-c:a", "aac", "-b:a", f"{AAC_KBPS[ch]}k", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        "-movflags", "+faststart", str(out.with_suffix(".m4a"))], check=True)
        subprocess.run([oggenc, "--quiet", "--serial", "1", "--discard-comments", "-q", VORBIS_QUALITY,
                        "-o", str(out.with_suffix(".ogg")), str(wav)], check=True)


def duration(ffprobe: str, path: Path) -> float:
    r = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                       capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def prepare(sources: dict) -> list[dict]:
    ffmpeg = tool("ffmpeg", "FFMPEG")
    ffprobe = tool("ffprobe", "FFPROBE")
    oggenc = tool("oggenc", "OGGENC")
    rows = []
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        for c in sources["clip"]:
            ch = 2 if c.get("stereo", False) else 1
            buf = array.array("f")
            for i, p in enumerate(c["parts"]):
                sid = p[0]
                if len(p) > 1 and isinstance(p[1], str):
                    member, times = p[1], p[2:]
                else:
                    member, times = None, p[1:]
                start = times[0] if len(times) > 0 else None
                end = times[1] if len(times) > 1 else None
                pause = times[2] if len(times) > 2 else 0.0
                if i and pause:
                    buf.extend([0.0] * int(SR * pause) * ch)
                seg = decode(ffmpeg, original(sources, sid, member, work), start, end, ch, c.get("highpass"))
                buf.extend(trim(seg, ch) if len(c["parts"]) > 1 else seg)
            buf = trim(buf, ch)
            fades(buf, ch, c.get("fade", 0.03))
            cls = sources["class"][c["class"]]
            loud = loudest_window(buf, ch)
            pk = db(peak(buf))
            shaved = 0.0
            pk0 = pk
            # shaving the peak also takes a little energy with it, so close in over a few passes
            for _ in range(6):
                if "max_crest" not in cls or pk - loud <= cls["max_crest"] + 0.25:
                    break
                room = cls["max_shave"] - (pk0 - pk)
                if room <= 0.1:
                    break
                limit(buf, ch, 10 ** ((pk - min(room, pk - loud - cls["max_crest"])) / 20))
                loud = loudest_window(buf, ch)
                pk = db(peak(buf))
                shaved = pk0 - pk
            gain = cls["target"] + c.get("offset_db", 0.0) - loud
            limited = pk + gain > cls["ceiling"]
            if limited:
                gain = cls["ceiling"] - pk
            g = 10 ** (gain / 20)
            for i in range(len(buf)):
                buf[i] *= g
            out = SOUNDS / c["out"]
            encode(ffmpeg, oggenc, buf, ch, out)
            rows.append(dict(out=c["out"], cls=c["class"], ch=ch, dur=frames(buf, ch) / SR, shaved=shaved,
                             loud=loud + gain, peak=pk + gain, limited=limited,
                             dur_m4a=duration(ffprobe, out.with_suffix(".m4a")),
                             dur_ogg=duration(ffprobe, out.with_suffix(".ogg")),
                             kb_m4a=out.with_suffix(".m4a").stat().st_size / 1024,
                             kb_ogg=out.with_suffix(".ogg").stat().st_size / 1024))
            print(f"  {c['out']}")
    return rows


# --------------------------------------------------------------------------------------- licences

def licences_md(sources: dict) -> str:
    L = ["# Sound licences",
         "",
         "Generated by `tools/prepare-sounds.py` from `sources.toml` — do not edit by hand.",
         "",
         "Every file in this directory is cut from one of the originals below. **All of them are CC0 1.0**",
         "(public domain dedication): commercial use in a paid or free-to-play app is allowed, with no",
         "attribution owed and no share-alike on the app. The credits are a courtesy. No CC-BY file is used.",
         "",
         "Each file ships twice: `.m4a` (AAC-LC, iOS) and `.ogg` (Vorbis, Android), 44.1 kHz, mono unless",
         "marked stereo. What was done to every file: cut at the times given, leading and trailing",
         "silence trimmed, a 2 ms fade-in and the listed fade-out, the sharpest transients shaved by a",
         "look-ahead peak limiter where the class caps the crest factor, levelled to its loudness class",
         "(loudest 100 ms RMS; see `sources.toml`), then encoded.",
         "",
         "Originals are fetched by the script into `.originals/` (git-ignored), pinned by sha256.",
         "Freesound originals are the site's public HQ preview of the upload (see `sources.toml`).",
         "",
         "## Originals",
         ""]
    for sid, s in sources["source"].items():
        L += [f"### `{sid}` — {s['title']}",
              "",
              f"- Author: {s['author']}",
              f"- Source: {s['page']}",
              f"- Licence: [{s['licence']}]({s['licence_url']})",
              f"- Fetched from: {s['url']}",
              f"- sha256: `{s['sha256']}`"]
        if s.get("about"):
            L.append(f"- About: {s['about']}")
        if s.get("attribution"):
            L.append(f"- **CC-BY — attribution line:** {s['attribution']}")
        L.append("")
    L += ["## Files", "",
          "| File (`.m4a` + `.ogg`) | Original | Original file | Cut (s) | Fade-out (s) | Treatment |",
          "|---|---|---|---|---|---|"]
    for c in sources["clip"]:
        origs, files, cuts = [], [], []
        for p in c["parts"]:
            sid = p[0]
            origs.append(f"`{sid}`")
            if len(p) > 1 and isinstance(p[1], str):
                files.append(p[1].split("/")[-1])
                cuts.append("whole" if len(p) == 2 else f"{p[2]:.3f}–{p[3]:.3f}")
            else:
                files.append(sources["source"][sid]["title"])
                cut = f"{p[1]:.3f}–{p[2]:.3f}"
                if len(p) > 3:
                    cut = f"+{p[3]:.2f} pause, {cut}"
                cuts.append(cut)
        treat = [c["note"], f"class {c['class']}"]
        if c.get("offset_db"):
            treat.append(f"{c['offset_db']:+.0f} dB from its class")
        if c.get("highpass"):
            treat.append(f"high-pass {c['highpass']} Hz")
        if c.get("stereo"):
            treat.append("stereo")
        uniq = lambda xs: " + ".join(dict.fromkeys(xs))
        L.append(f"| `{c['out']}` | {uniq(origs)} | {uniq(files)} | {'; '.join(cuts)} | "
                 f"{c.get('fade', 0.03):.2f} | {'; '.join(treat)} |")
    L.append("")
    return "\n".join(L)


# ------------------------------------------------------------------------------------------ check

def check(sources: dict, manifest: dict) -> list[str]:
    errs = []
    outs = {c["out"] for c in sources["clip"]}
    used = set()
    for eid, stems in manifest_stems(manifest).items():
        for s in stems:
            used.add(s)
            if s not in outs:
                errs.append(f"event {eid}: {s} is not produced by any clip in sources.toml")
            for ext in FORMATS:
                if not (SOUNDS / f"{s}.{ext}").is_file():
                    errs.append(f"event {eid}: {s}.{ext} does not exist — run tools/prepare-sounds.py")
    for o in sorted(outs - used):
        errs.append(f"clip {o} is produced but no event in {MANIFEST.relative_to(ROOT)} plays it")
    for f in sorted(SOUNDS.rglob("*")):
        if f.suffix.lstrip(".") in FORMATS and ".originals" not in f.parts:
            stem = str(f.relative_to(SOUNDS).with_suffix(""))
            if stem not in outs:
                errs.append(f"{f.relative_to(ROOT)} has no clip in sources.toml (stale file?)")
    if not LICENSES.is_file() or LICENSES.read_text() != licences_md(sources):
        errs.append(f"{LICENSES.relative_to(ROOT)} is not current — run tools/prepare-sounds.py")
    return errs


def report(rows: list[dict]) -> None:
    print(f"\n{'file':34} {'class':8} ch {'dur s':>6} {'m4a s':>6} {'ogg s':>6} {'L100 dB':>8} {'peak dB':>8} "
          f"{'shaved':>6} {'m4a KB':>7} {'ogg KB':>7}")
    for r in rows:
        print(f"{r['out']:34} {r['cls']:8} {r['ch']:2} {r['dur']:6.3f} {r['dur_m4a']:6.3f} {r['dur_ogg']:6.3f} "
              f"{r['loud']:8.1f} {r['peak']:8.1f}{'*' if r['limited'] else ' '} {r['shaved']:6.1f} {r['kb_m4a']:7.1f} {r['kb_ogg']:7.1f}")
    m4a = sum(r["kb_m4a"] for r in rows)
    ogg = sum(r["kb_ogg"] for r in rows)
    print(f"\n{len(rows)} files; .m4a {m4a:.0f} KB (iOS bundle), .ogg {ogg:.0f} KB (Android bundle), "
          f"both {m4a + ogg:.0f} KB in the repo.\n* = the peak ceiling won: quieter than its class target. "
          f"shaved = dB taken off the transient peak by the limiter (class max_crest, at most max_shave)")


def main() -> None:
    args = sys.argv[1:]
    if args not in ([], ["--check"]):
        die("usage: tools/prepare-sounds.py [--check]")
    sources = load_sources()
    manifest = load_manifest()
    if not args:
        for sid, s in sources["source"].items():
            fetch(sid, s)
        report(prepare(sources))
        LICENSES.write_text(licences_md(sources))
    errs = check(sources, manifest)
    if errs:
        die("check failed:\n  " + "\n  ".join(errs))
    n = sum(len(v) for v in manifest_stems(manifest).values())
    todo = [eid for eid, e in manifest["event"].items() if e.get("todo")]
    print(f"check: {len(manifest['event'])} events, {n} file references, all present in both formats; "
          f"LICENSES.md current. todo: {', '.join(todo) or 'none'}")


if __name__ == "__main__":
    main()
