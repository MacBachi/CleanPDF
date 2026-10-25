# Security Policy

## Scope and threat model

CleanPDF's job is to turn an untrusted PDF into one that contains no active
content, without letting the untrusted file harm the machine on the way.

**Output guarantee.** Every page is rasterised and a brand-new PDF is built
from the resulting pixels; nothing from the source's object structure is
carried into the output. JavaScript, auto-run actions, external links and
tracking canaries, embedded/attached files, forms, multimedia, signatures and
metadata are structurally absent from the result.

**Isolation of the untrusted file.** The PDF is parsed, rendered and analysed
only in a worker process that has locked itself into a deny-default macOS
sandbox profile before it reads a single byte of the file:

- no network access of any kind, including DNS and localhost
- no reading user files — only macOS system files (frameworks, fonts, colour
  profiles); the PDF arrives on stdin
- no writing files, no launching processes, no IPC to system services
- a CPU-time limit, no core dumps, and it exits when its parent goes away

The worker can send back only page sizes and raw pixels. The app validates
every message (page order, finite sizes, a 50-megapixel budget, exact byte
counts; the alpha channel is ignored) and kills the worker if a page takes
longer than 120 s or it exceeds 3 GB of memory. If the sandbox cannot be
applied, the worker refuses to process the file (fail closed).

`CleanPDF --sandbox-selftest <file> <dir>` verifies on a given machine that
the sandbox actually blocks file reads, writes, network, DNS and process
launch.

**Out of scope.** An attacker who exploits the PDF engine inside the worker
*and* then escapes the macOS sandbox (for example via a kernel bug) is not
covered — that requires VM-level isolation, as
[Dangerzone](https://dangerzone.rocks) provides.

**Known dependency risk.** The sandbox is applied with `sandbox_init` and a
custom profile. Apple marks this API deprecated but still ships it, and the
profile-text form is not formally documented. CleanPDF fails closed if it
stops working, and the test suite verifies on every CI run — on Apple
silicon and Intel, oldest and newest supported macOS image — that the
sandbox is in force (each check against a control run outside it).

## Reporting a vulnerability

Bugs we care about most:

1. **Active content surviving sanitisation** (the output PDF is not passive).
2. **A way out of the worker sandbox**, or anything that lets data from the
   worker reach the app other than as validated page pixels.
3. A crash or hang in the **app** (not the worker) caused by a PDF.

Please report:

- via GitHub's private
  ["Report a vulnerability"](https://github.com/MacBachi/CleanPDF/security/advisories/new)
  flow (preferred for anything exploitable), or
- as a GitHub issue with a minimal reproducer PDF for non-sensitive problems.

`tests/make_evil_pdf.py` is a good template for a reproducer.

There is no bug bounty — this is a free, unfunded project — but credit will be
given in the changelog unless you prefer to stay anonymous.

## Supported versions

Only the latest release is supported. Fixes land on `main` and ship in the next
release.
