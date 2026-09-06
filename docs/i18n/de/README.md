<!-- zhc-i18n 源: README.md 基线: c7becfba4a3a10d2 时间: 2026-09-06 -->

# zhc — Programmieren Sie Cangjie in Ihrer Muttersprache

Language / Langue / Sprache / Idioma / 언어 / 言語 / Язык：[中文](../../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · **Deutsch** · [Español](../es/README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md)

**zhc** ist ein Muttersprach-Lernframework für die Programmiersprache Cangjie
(仓颉): Es transpiliert dialektalen Quellcode (z. B. Chinesisch `.zc`,
Japanisch `.jc`, Deutsch `.dc`) nach Standard-Cangjie und übersetzt die
Compiler-Diagnosen in lernfreundliche Meldungen der gewählten Sprache
(Fehlercode → Meldungstabelle → Typlokalisierung → Korrekturbeispiele). Der
Dialekt wird über die Umgebungsvariable `ZHCLANG` gewählt (Standard `zh`);
alles wird von einem **Sprachpaket** gesteuert.

## Schnellstart (ca. 10 Minuten)

**1. Cangjie-SDK installieren** (einzige externe Abhängigkeit): Version
**1.0.5** von cangjie-lang.cn/download laden, entpacken und das beiliegende
`envsetup.sh` ausführen, damit `cjc` und `cjpm` im `PATH` liegen. Prüfung:

```bash
cjc --version    # Cangjie Compiler: 1.0.5 (cjnative)
```

**2. zhc bauen** (ohne Netz, keine Drittanbieter-Abhängigkeiten):

```bash
cd zhc
cjpm build       # erzeugt target/release/bin/main
```

**3. Erstes Programm ausführen** (das beiliegende chinesische Dialekt-Beispiel):

```bash
export ZHC_LANG_PACKS=$PWD        # vom Repo-Wurzelverzeichnis: zhc/
zhc run examples/hello.zc
# ✅ 编译成功：替换方言标识符 8 处。
# 消息：你好，仓颉！
```

## In der eigenen Sprache schreiben

Jede Sprache mit Paket unter `zhc/lang-packs/<Code>/` funktioniert — `en`
(identisch = offizielles Cangjie), `ru`, `ja`, `ko`, `fr`, `es`, `de` sind
enthalten. Zum Beispiel Deutsch (`ZHCLANG=de`, Endung `.dc`):

```dc
Haupt() {
    Lege gruss: Zeichenkette = "仓颉"
    Zeige("Hallo, ${gruss}!")
}
```

Ausführung: `ZHCLANG=de zhc run hello.dc`. Der spanische Dialekt funktioniert
genauso (`principal/defina/mostrar`, Endung `.sc`).

## Übersetzungen für Drittanbieter-Bibliotheken

API-Zuordnungen von Bibliotheken leben im zentralen Übersetzungs-Repository,
nicht im Quellbaum — laden Sie nur die benötigte Sprache und Bibliothek:

```bash
zhc share list                     # gemeinsames Register durchsuchen
zhc share fetch csv4cj --lang de   # eine Zuordnung in Ihrer Sprache laden
zhc share publish meine_zuordnung.toml   # eigene Übersetzung beitragen
```

Geladene Zuordnungen durchlaufen Prüfsummen- und Qualitätskontrollen (Format,
offizielle Namen, Kollisionen mit reservierten Wörtern), bevor sie in
`~/.zhc/lang-packs/<Sprache>/crates/` installiert werden. Fehlende
Übersetzungen fallen sanft auf Chinesisch zurück; das Programm läuft in
jedem Fall.

## Terminologie (einheitlich in der gesamten deutschen Dokumentation)

| Deutsch | In Code/Doku | Anmerkung |
|---|---|---|
| Dialekt | `.zc` `.sc` `.dc` … | Cangjie in der Muttersprache geschrieben |
| Sprachpaket | `lang-packs/<Code>/` | Schlüsselwort-/Alias-Tabellen + Diagnosen + UI-Texte |
| Zuordnung | `<Sprache>/crates/<Lib>.toml` | muttersprachlicher Name = offizieller API-Name |
| Transpilation | `zhc run` / `zhc check` | Dialekt → Standard-Cangjie |
| gemeinsames Register | `zhc share …` | zentrales Übersetzungsregister |
| Basislinie | `zh@<Prüfsumme>` | Synchronisierungs-Fingerprint des chinesischen Originals |

## Weiterführendes

- Tutorial (kanonisch, chinesisch): [《中文仓颉程序设计》](../../../docs/中文仓颉程序设计/README.md)
- Sprachpakete entwickeln und beitragen: [docs/语言包开发.md](../../../docs/语言包开发.md)
- Lokalisierungsumfang und Synchronisationsmechanismus: [docs/i18n/README.md](../README.md)
- Tutorial-Leitfaden auf Deutsch: [Tutorial-Einführung (Lektion 0)](tutorial-00.md)
- Fehlerdiagnose: `zhc doctor` — Sechs-Punkte-Umgebungsprüfung (Compiler, Build-Tool, Sprachpakete, beschreibbares Verzeichnis, Freigabequelle, cjlint) mit lokalisierten Lösungshinweisen.
