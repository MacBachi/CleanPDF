#!/bin/zsh
# End-to-end test suite for CleanPDF.
#
# Builds the release binary, then exercises the sanitizer and the risk
# analyzer against crafted PDFs and asserts on the results. Pure shell +
# Python 3 (stdlib only), so it runs locally and in CI without extra deps.
#
# Exit code 0 = all tests passed.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=".build/release/CleanPDF"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { print -P "%F{green}  ✓%f $1"; pass=$((pass+1)) }
bad()  { print -P "%F{red}  ✗%f $1"; fail=$((fail+1)) }

print -P "%F{cyan}==>%f Building release binary"
swift build -c release >/dev/null

print -P "%F{cyan}==>%f Preparing fixtures in $WORK"
python3 tests/make_evil_pdf.py "$WORK/evil.pdf"          >/dev/null
python3 tests/make_binary_stream_pdf.py "$WORK/binfp.pdf" >/dev/null

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

print ""
print -P "%F{cyan}==>%f $pass passed, $fail failed"
[[ $fail -eq 0 ]]
