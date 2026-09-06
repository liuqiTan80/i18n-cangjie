---
name: Report a bug (English)
about: Anything that behaves unexpectedly — tool, vocabulary, tutorial, or docs
title: "[bug] Short description"
labels: bug
---

## Environment

- OS: Linux / macOS / Windows (version)
- Cangjie SDK version: (e.g. 1.0.5; `cjc --version`)
- zhc source: built from source / release package / install.sh
- zhc version: (first line of `zhc help`)

## Repro

Minimal `.zc` file (or doc location):

```cangjie
(paste code)
```

Full command and output:

```text
$ (command)
(actual output — paste the raw error text, no screenshots)
```

Expected output:

```text
(what you expected)
```

## Category (leave blank if unsure)

- [ ] Tool bug (transpile / diagnostics / lint / LSP behavior)
- [ ] Missing vocabulary (tutorial/example fails, "not recognized" errors)
- [ ] Tutorial/doc error (text/code mismatch, dead link, outdated wording)
- [ ] Other

## Notes

(Reference: `bash scripts/acceptance.sh`; before touching word tables or translations read CONTRIBUTING and docs/语言包开发.md — Chinese, use the language-pack workflows under docs/i18n/en as templates)
