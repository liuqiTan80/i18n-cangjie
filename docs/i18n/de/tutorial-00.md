<!-- zhc-i18n 源: docs/中文仓颉程序设计/README.md 基线: e414394a92c0d230 时间: 2026-09-04 -->

# Tutorial-Einführung — Lektion 0 (Deutsch)

Navigation：[Tutorial-Original (zh)](../../中文仓颉程序设计/README.md) · [English](../en/README.md) · [Français](../fr/README.md) · **Deutsch** · [Español](../es/README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md)

Das kanonische Tutorial **《中文仓颉程序设计》** ist ein systematischer Kurs im
Handbuch-Stil: **3 Bände, 20 Kapitel + 3 Anhänge + Lösungsheft**, mit **über
150 Codeblöcken, alle gegen das offizielle `cjc 1.0.5` verifiziert**. Diese
Seite ist Ihre Lektion 0 auf Deutsch; der kanonische Text ist chinesisch —
lesen Sie beides parallel oder starten Sie mit den Dialekt-Beispielen unten.

## Die drei Bände

| Band | Für Sie, wenn… | Inhalt |
|---|---|---|
| Band 1 Erste Schritte | völliger Anfänger | Einrichtung, erstes Programm, Variablen, Zahlen, Bedingungen, Schleifen, Funktionen |
| Band 2 Kern und Ausbau | systematische Grammatik | Funktionen, Typsystem, Zeichenketten, Sammlungen, OOP, Aufzählungen, Fehlerbehandlung, Generics und Makros |
| Band 3 Handwerk und Denken | qualitätsbewusste Entwickler | Entwurfsdenken, Algorithmen und Datenstrukturen, Software-Engineering, Abschlussprojekt |

## Lektion 1: Ihr erstes Programm

Schreiben Sie es im deutschen Dialekt:

```dc
Haupt() {
    Lege gruss: Zeichenkette = "Hallo, 仓颉!"
    Zeige(gruss)
}
```

Speichern als `hello.dc`, dann `ZHCLANG=de zhc run hello.dc`. Jeder Dialekt
wird exakt in diesen Standardcode transpiliert — der chinesische Dialekt
schreibt zum Beispiel `main` als `主函数`, `let` als `让`, `println` als
`打印行`. Verfügbare Dialekte: `en`/`ru`/`ja`/`ko`/`fr`/`es`/`de`.

## Wo nachschlagen (Kurzreferenz)

- Bei null starten → Band 1, Kapitel 01–07 (je ca. 10–20 Min., mit Übungen)
- Systematische Grammatik → Band 2, Kapitel 08–15 (Definition → Syntax → Beispiel → Hinweise)
- Qualität und Ingenieurskunst → Band 3, Kapitel 16–19
- Schlüsselwörter/Standardbibliothek, Fehler entziffern → Anhänge A/B/C

Kanonisches Tutorial öffnen: [docs/中文仓颉程序设计/README.md](../../中文仓颉程序设计/README.md)
