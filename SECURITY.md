# Security Policy

## Scope and threat model

CleanPDF's job is to turn an untrusted PDF into one that contains no active
content. It does this by **rasterising** every page and building a brand-new
PDF from the resulting images — nothing from the source's object structure is
carried into the output.

**What this protects against:** JavaScript, auto-run actions, external links
and tracking canaries, embedded/attached files, forms, multimedia, signatures,
and metadata — all of it is structurally absent from the output.

**What it does not protect against:** the conversion itself parses the
untrusted file with Apple's CoreGraphics (the same engine as Preview and Quick
Look). A memory-corruption zero-day against that parser is out of scope — for
that threat model, run conversion inside a disposable VM, as
[Dangerzone](https://dangerzone.rocks) does.

## Reporting a vulnerability

If you find a way for **active content to survive sanitisation** (i.e. the
output PDF is not actually passive), that's the bug we care about most.

- Open a GitHub issue with a minimal reproducer PDF, **or**
- if you consider it sensitive, use GitHub's private
  ["Report a vulnerability"](https://github.com/MacBachi/CleanPDF/security/advisories/new)
  advisory flow.

`tests/make_evil_pdf.py` is a good template for a reproducer.

There is no bug bounty — this is a free, unfunded project — but credit will be
given in the changelog unless you prefer to stay anonymous.

## Supported versions

Only the latest release is supported. Fixes land on `main` and ship in the next
release.
