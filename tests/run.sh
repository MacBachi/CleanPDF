#!/bin/zsh
# End-to-end test suite for CleanPDF.
#
# Builds the release binary, then exercises the sanitizer, the risk analyzer
# and the sandboxed worker against crafted PDFs and asserts on the results.
# Needs only what ships with macOS + Xcode (zsh, Python 3 stdlib, swift,
# sips, sandbox-exec), so it runs locally and in CI without extra deps.
#
# Exit code 0 = all tests passed.
set -euo pipefail
cd "$(dirname "$0")/.."

# CLEANPDF_BIN tests a prebuilt binary (e.g. the one inside a release
# artifact) instead of building from source.
BIN="${CLEANPDF_BIN:-.build/release/CleanPDF}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { print -P "%F{green}  ✓%f $1"; pass=$((pass+1)) }
bad()  { print -P "%F{red}  ✗%f $1"; fail=$((fail+1)) }

if [[ -n "${CLEANPDF_BIN:-}" ]]; then
    print -P "%F{cyan}==>%f Testing prebuilt binary $BIN ($(uname -m))"
    [[ -x "$BIN" ]] || { print -u2 "not executable: $BIN"; exit 2 }
else
    print -P "%F{cyan}==>%f Building release binary"
    swift build -c release >/dev/null
fi

print -P "%F{cyan}==>%f Preparing fixtures in $WORK"
python3 tests/make_evil_pdf.py "$WORK/evil.pdf"          >/dev/null
python3 tests/make_binary_stream_pdf.py "$WORK/binfp.pdf" >/dev/null
python3 tests/make_huge_page_pdf.py "$WORK/huge.pdf"      >/dev/null
python3 tests/make_jbig2_pdf.py "$WORK/jbig2.pdf"         >/dev/null
python3 tests/make_jpx_pdf.py "$WORK/jpx.pdf"             >/dev/null
python3 tests/make_slow_page_pdf.py "$WORK/slow.pdf" 2000 >/dev/null
python3 tests/make_slow_page_pdf.py "$WORK/slowbig.pdf" 400 14400 >/dev/null
swift tests/make_rich_pdf.swift "$WORK/rich.pdf"   >/dev/null 2>&1
# Compiled with optimisation: the pixel comparison is too slow interpreted.
swiftc -O tests/check_render_parity.swift -o "$WORK/parity" 2>/dev/null

# --- Test 1: hostile PDF scores critical, lists the threats ---------------
print -P "%F{cyan}==>%f Risk analysis"
scan_evil="$("$BIN" --scan "$WORK/evil.pdf" || true)"
grep -q "RISIKO 100/100" <<<"$scan_evil" && ok "hostile PDF -> score 100" || bad "hostile PDF score"
grep -q "JavaScript-Aktion" <<<"$scan_evil" && ok "JavaScript reported" || bad "JavaScript not reported"
grep -q "evil-canary.example.com" <<<"$scan_evil" && ok "canary URL surfaced" || bad "canary URL missing"
grep -q "payload.sh" <<<"$scan_evil" && ok "attachment name surfaced" || bad "attachment name missing"

# --- Test 2: binary stream false-positive must NOT trigger ----------------
scan_fp="$("$BIN" --scan "$WORK/binfp.pdf" || true)"
grep -q "RISIKO 0/100" <<<"$scan_fp" && ok "binary /JS in stream -> score 0 (no false positive)" \
    || bad "false positive on binary stream data"

# --- Test 3: sanitize produces a clean, verified output -------------------
print -P "%F{cyan}==>%f Sanitization"
out="$("$BIN" "$WORK/evil.pdf" 2>/dev/null || true)"
grep -q "Ausgabe geprüft" <<<"$out" && ok "output self-verification passed" || bad "output verification"
grep -q "HINWEIS" <<<"$out" && bad "normal page reported as downscaled" || ok "normal page rendered at full dpi"
safe="$WORK/evil (safe).pdf"
[[ -f "$safe" ]] && ok "output file created" || bad "no output file"

# --- Test 4: independent deep scan of the sanitized file ------------------
python3 tests/verify_clean.py "$safe" >/dev/null && ok "deep marker scan: sanitized file is clean" \
    || bad "sanitized file still contains active-content markers"

# --- Test 5: sanitized output re-scores as unremarkable -------------------
rescan="$("$BIN" --scan "$safe" || true)"
grep -q "RISIKO 0/100" <<<"$rescan" && ok "sanitized output -> score 0" || bad "sanitized output not score 0"

# --- Test 6: page geometry preserved (no shrink-to-center regression) -----
print -P "%F{cyan}==>%f Rendering geometry"
geom_ok=$(swift tests/check_geometry.swift "$WORK/evil.pdf" "$safe" 2>/dev/null | tail -1)
[[ "$geom_ok" == "GEOMETRY_OK" ]] && ok "page size & content box preserved" || bad "geometry mismatch ($geom_ok)"

# --- Test 7: render budget caps memory on oversized pages ----------------
print -P "%F{cyan}==>%f Render budget"
huge_out="$( { /usr/bin/time -l "$BIN" "$WORK/huge.pdf" ; } 2>&1 || true)"
rss=$(awk '/maximum resident set size/ {print $1}' <<<"$huge_out")
grep -q "Ausgabe geprüft" <<<"$huge_out" && ok "oversized page sanitized" || bad "oversized page failed"
grep -q "reduzierter Auflösung" <<<"$huge_out" && ok "downscale reported" || bad "downscale not reported"
# Unbudgeted this needs ~2 GB; the 50 MP budget stays well under 1 GB.
(( rss > 0 && rss < 1000000000 )) && ok "peak memory $((rss / 1048576)) MB (< 1 GB)" \
    || bad "peak memory ${rss:-?} bytes"
size_ok=$(swift tests/check_geometry.swift --size "$WORK/huge (safe).pdf" 2>/dev/null | tail -1)
[[ "$size_ok" == "14400x14400" ]] && ok "page size kept at 14400x14400 pt" || bad "page size changed ($size_ok)"

# --- Test 8: JBIG2 image data is reported, but not scored -----------------
print -P "%F{cyan}==>%f JBIG2 detection"
scan_jb="$("$BIN" --scan "$WORK/jbig2.pdf")" && jb_exit=0 || jb_exit=$?
grep -q "Bilddaten im JBIG2-Format" <<<"$scan_jb" && ok "JBIG2 image data reported" || bad "JBIG2 not reported"
grep -q "Seiten: 1, 2$" <<<"$scan_jb" && ok "direct and form-nested images found, Flate image ignored" \
    || bad "wrong JBIG2 pages: $(grep Seiten <<<"$scan_jb")"
[[ $jb_exit -eq 0 ]] && grep -q "RISIKO 0/100" <<<"$scan_jb" && ok "informational only (score 0, exit 0)" \
    || bad "JBIG2 changed the score or exit code"
jb_out="$("$BIN" "$WORK/jbig2.pdf" 2>/dev/null || true)"
grep -q "Ausgabe geprüft" <<<"$jb_out" && ok "undecodable JBIG2 data does not stop sanitization" \
    || bad "sanitizing broken JBIG2 failed"

# --- Test 9: the worker sandbox really blocks what it must ----------------
print -P "%F{cyan}==>%f Sandbox isolation"
echo "secret" > "$WORK/secret.txt"
# Control: the same operations must work *outside* the sandbox here, or a
# "blocked" result below would prove nothing.
control="$(python3 -I - "$WORK/secret.txt" "$WORK" <<'PY'
import os, socket, subprocess, sys
def attempt(name, fn):
    try:
        fn(); print(f"{name}: possible")
    except PermissionError:
        print(f"{name}: unavailable")
    except OSError:
        print(f"{name}: possible")   # e.g. ECONNREFUSED: the attempt was made
attempt("read-user-file", lambda: open(sys.argv[1]).read())
attempt("write-file", lambda: open(os.path.join(sys.argv[2], "control.txt"), "w").write("x"))
attempt("network-connect", lambda: socket.create_connection(("127.0.0.1", 9), timeout=2))
attempt("spawn-process", lambda: subprocess.run(["/usr/bin/true"], check=True))
try:
    socket.getaddrinfo("example.com", 80); print("dns-lookup: possible")
except OSError:
    print("dns-lookup: unavailable")
PY
)"
selftest="$("$BIN" --sandbox-selftest "$WORK/secret.txt" "$WORK" || true)"
for check in read-user-file write-file network-connect dns-lookup spawn-process; do
    if grep -q "^$check: blocked" <<<"$selftest"; then
        if grep -q "^$check: possible" <<<"$control"; then
            ok "$check blocked in sandbox (control: possible outside)"
        else
            print -P "%F{yellow}  ~%f $check blocked, but also unavailable outside the sandbox here (inconclusive)"
        fi
    else
        bad "$check NOT blocked: $(grep "^$check" <<<"$selftest")"
    fi
done
written=( "$WORK"/cleanpdf-selftest-*(N) )
(( ${#written} == 0 )) && ok "no file written by the sandboxed self-test" \
    || bad "sandboxed self-test managed to write ${written[1]}"

# --- Test 10: fail closed when the sandbox cannot be applied --------------
# A process that is already sandboxed cannot apply another profile, so a
# worker started under sandbox-exec must refuse instead of parsing unprotected.
print -P "%F{cyan}==>%f Fail closed"
cp "$WORK/evil.pdf" "$WORK/fc.pdf"
fc_out="$(sandbox-exec -p '(version 1) (allow default)' "$BIN" --no-ocr "$WORK/fc.pdf" 2>&1 || true)"
grep -q "Sandbox nicht verfügbar" <<<"$fc_out" && ok "worker refuses without its sandbox" \
    || bad "no refusal without sandbox: $fc_out"
[[ ! -e "$WORK/fc (safe).pdf" ]] && ok "no output produced without sandbox" || bad "output produced without sandbox"

# --- Test 11: output looks like the original (sandbox didn't break drawing) -
print -P "%F{cyan}==>%f Render parity"
for name in evil rich jpx; do
    [[ -e "$WORK/$name (safe).pdf" ]] || "$BIN" --no-ocr "$WORK/$name.pdf" >/dev/null 2>&1 || true
    par="$("$WORK/parity" "$WORK/$name.pdf" "$WORK/$name (safe).pdf" 2>/dev/null || true)"
    worst=$(grep -o "worst block [0-9.]*" <<<"$par" | awk '{print $3}' | sort -n | tail -1)
    [[ "$(tail -1 <<<"$par")" == "PARITY_OK" ]] && ok "$name.pdf matches original (worst block ${worst})" \
        || bad "$name.pdf differs from original: $(grep -v ' ok$' <<<"$par" | head -3)"
done

# --- Test 12: watchdog kills a worker that stalls on a page ---------------
print -P "%F{cyan}==>%f Worker watchdog"
t0=$SECONDS
slow_out="$(CLEANPDF_PAGE_TIMEOUT=2 "$BIN" --no-ocr "$WORK/slow.pdf" 2>&1 || true)"
elapsed=$((SECONDS - t0))
grep -q "Zeitüberschreitung bei Seite 2" <<<"$slow_out" && ok "page 2 timed out" || bad "no timeout: $slow_out"
(( elapsed < 20 )) && ok "aborted after ${elapsed}s (page alone takes far longer)" || bad "took ${elapsed}s"
[[ ! -e "$WORK/slow (safe).pdf" ]] && ok "partial output removed" || bad "partial output left behind"

# --- Test 13: memory ceiling ----------------------------------------------
# The watchdog samples memory twice a second, so it targets sustained growth
# (decompression bombs), not brief spikes. This page holds a ~200 MB bitmap
# while it renders for a long time, well above a 100 MB ceiling.
mem_out="$(CLEANPDF_WORKER_MEMORY_MB=100 CLEANPDF_PAGE_TIMEOUT=60 "$BIN" --no-ocr "$WORK/slowbig.pdf" 2>&1 || true)"
grep -q "Speichergrenze (100 MB) bei Seite 2" <<<"$mem_out" && ok "worker killed at memory ceiling" \
    || bad "no memory kill: $mem_out"
[[ ! -e "$WORK/slowbig (safe).pdf" ]] && ok "partial output removed after memory kill" \
    || bad "partial output left after memory kill"

print ""
print -P "%F{cyan}==>%f $pass passed, $fail failed"
[[ $fail -eq 0 ]]
