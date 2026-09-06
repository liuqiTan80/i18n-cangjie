# -*- coding: utf-8 -*-
"""Deutsche Diagnoseübersetzungen (Inkrementaltabelle, Empfehlung E3: parametrisierte Generierungskette).

Für tools/gen_full_errors.py --lang de zur Erzeugung von zhc/lang-packs/de/errors.toml.
Einträge sind isomorph zu CURATED in zh: {DiagKind: (Nachrichten-Vorlage, Lehrhinweis, Reparaturbeispiel)}.

Inkremental freundlich: nur die **übersetzten** Codes werden aufgenommen (seit 2026-09-06:
Top-50 der häufigen Anfängerfehler) — Codes ohne Übersetzung fallen zur Laufzeit elegant zurück
(Originaltext des offiziellen Compilers, kein Absturz), die Tabelle lässt sich also jederzeit
erweitern und mit `--lang de` neu generieren.
Reparaturbeispiele nutzen de-Dialektwörter (Lege=let / Variable=var / Falls=if / Zeige=println /
Haupt=main / Ganzzahl=Int64 / Zeichenkette=String, siehe Wortlisten unter lang-packs/de/).
"""

DE = {
    "sema_mismatched_types": (
        "Typen stimmen nicht überein",
        "Prüfen Sie die Typen auf beiden Seiten von Deklaration und Zuweisung. Falls eine "
        "Umwandlung nötig ist, verwenden Sie `Als` (as) — Cangjie konvertiert Typen nicht automatisch.",
        "Variable ganze: Ganzzahl = 1\n"
        "Variable text: Zeichenkette = \"1\"\n"
        "// beide Seiten müssen denselben Typ haben",
    ),
    "package_search_error": (
        "Paket `{q0}` nicht gefunden",
        "Prüfen Sie die Abhängigkeitsdeklaration in cjpm.toml oder führen Sie die Paketinstallation aus.",
        "",
    ),
    "chir_dce_unused_variable": (
        "Variable `{q0}` wird nie verwendet",
        "Unbenutzte Deklarationen erzeugen eine Compiler-Warnung. Löschen Sie sie oder prüfen Sie "
        "auf Tippfehler (z. B. wurde versehentlich eine andere Variable benannt).",
        "Lege unbenutzt: Zeichenkette = \"hallo\"\n"
        "// Variante 1: Zeile löschen\n"
        "// Variante 2: sie verwenden\n"
        "Zeige(unbenutzt)",
    ),
    "lex_unrecognized_escape": (
        "Unbekannte Escape-Sequenz `{q0}`",
        "Die Sequenz `\\q` wird nicht unterstützt. Cangjie kennt `\\n` (Zeilenumbruch), `\\t` "
        "(Tabulator), `\\\\`, `\\\"`, `\\uXXXX` (Unicode) usw.",
        "Zeige(\"erste Zeile\\nzweite Zeile\")  // \\n ist der Zeilenumbruch",
    ),
    "parse_expected_character": (
        "Erwartet: `{q0}`",
        "Unvollständige Syntax: prüfen Sie, ob in dieser Zeile Klammern, Semikolon oder ein "
        "Schlüsselwort fehlen.",
        "",
    ),
    "parse_expected_right_delimiter": (
        "Nicht geschlossenes Begrenzungszeichen `{q0}`",
        "Klammern müssen paarweise geschlossen werden: prüfen Sie die Verschachtelung — zu jeder "
        "`(`/`[`/`{` gehört eine `)`/`]`/`}`.",
        "Falls (a > 0) {\n    Zeige(a)\n}  // zu jedem `{` gehört ein `}`",
    ),
    "sema_cannot_assign_to_immutable": (
        "Zuweisung an einen unveränderlichen Wert nicht möglich",
        "Eine `Lege`-Bindung ist nach der Erstellung unveränderlich. Zum Neuzuweisen "
        "verwenden Sie `Variable`.",
        "Lege x = 1\n// x = 2  // Fehler: Lege ist unveränderlich\nVariable y = 1\ny = 2  // korrekt",
    ),
    "sema_exceed_num_value_range": (
        "Zahl `{q0}` überschreitet den Wertebereich von Typ `{q1}`",
        "Das Literal liegt außerhalb des Bereichs des Zieltyps: nehmen Sie einen größeren Typ "
        "oder berechnen Sie den Wert zur Laufzeit.",
        "",
    ),
    "sema_generic_type_without_type_argument": (
        "Generischer Typ ohne Typparameter",
        "Generische Typen erfordern einen Typparameter: `Liste<Ganzzahl>`, `Option<Zeichenkette>` usw.",
        "Lege liste: Liste<Ganzzahl> = Liste<Ganzzahl>()\nLege wert: Option<Zeichenkette> = KeinWert",
    ),
    "sema_missing_entry": (
        "Programmeinstieg fehlt `{q0}`",
        "Ein ausführbares Programm benötigt `Haupt()`: genau einmal pro Projekt, Parameter und "
        "Rückgabetyp bleiben beim Standard.",
        "Haupt() {\n    Zeige(\"Hallo, Cangjie!\")\n}",
    ),
    "sema_redefinition": (
        "Mehrfachdeklaration `{q0}`",
        "Ein Name darf in derselben Sichtbarkeit nur einmal deklariert werden: prüfen Sie Duplikate "
        "oder Konflikte mit importierten Bezeichnern (umbenennen oder überflüssige Deklaration entfernen).",
        "",
    ),
    "sema_undeclared_identifier": (
        "Nicht deklarierter Bezeichner `{q0}`",
        "Ein undefinierter Name wurde verwendet: prüfen Sie die Schreibweise; Variablen müssen vor "
        "der Nutzung deklariert werden; Namen aus einem Block `{}` sind nur innerhalb sichtbar.",
        "Haupt() {\n    Lege name = \"Cangjie\"\n    Zeige(name)  // erst deklarieren, dann nutzen\n}",
    ),
    "sema_undeclared_type_name": (
        "Nicht deklarierter Typname `{q0}`",
        "Ein Typ muss deklariert oder importiert sein: prüfen Sie die Schreibweise; eigene Typen "
        "vorher definieren; Standardbibliothekstypen benötigen den Modulimport.",
        "",
    ),
    "sema_wrong_number_of_arguments": (
        "Anzahl der Argumente im Aufruf passt nicht: `{q0}`",
        "Die Anzahl der Argumente muss zur Parameterliste passen: zählen Sie die Argumente an der "
        "Aufrufstelle — fehlende und überzählige sind gleichermaßen Fehler.",
        "",
    ),
    "chir_annotation_not_applicable": (
        "Annotation hier nicht anwendbar{q0?}",
        "Statische Prüfung nicht bestanden: suchen Sie nach versteckten Problemen "
        "(unbenutzt, unerreichbar, Überlauf, ohne Initialisierung).",
        "",
    ),
    "chir_arithmetic_operator_overflow": (
        "Überlauf in arithmetischer Operation{q0?}",
        "Statische Prüfung nicht bestanden: der Überlauf ist schon vor der Ausführung erkennbar. "
        "Nehmen Sie einen größeren Typ oder prüfen Sie die Werte.",
        "",
    ),
    "chir_cannot_assign_initialized_let_variable": (
        "Zuweisung an bereits initialisierte Lege-Variable nicht möglich{q0?}",
        "Statische Prüfung nicht bestanden: `Lege` lässt keine Neuzuweisung zu — verwenden Sie `Variable`.",
        "",
    ),
    "chir_class_uninitialized_field": (
        "Klassenfeld nicht initialisiert{q0?}",
        "Statische Prüfung nicht bestanden: Felder einer Klasse müssen im Konstruktor (init) "
        "oder bei der Deklaration initialisiert werden.",
        "",
    ),
    "chir_dce_unused_expression": (
        "Unbenutzter Ausdruck{q0?}",
        "Statische Prüfung nicht bestanden: der Wert des Ausdrucks wird nirgends verwendet — "
        "zuweisen oder löschen.",
        "",
    ),
    "chir_dce_unused_function": (
        "Unbenutzte Funktion{q0?}",
        "Statische Prüfung nicht bestanden: die Funktion wird nie aufgerufen. Löschen Sie sie "
        "oder behalten Sie sie als Teil der öffentlichen API.",
        "",
    ),
    "chir_dce_unused_function_main": (
        "Unbenutzte Funktion (Einstiegspunkt){q0?}",
        "Statische Prüfung nicht bestanden: der Einstiegspunkt ist als unbenutzt markiert — "
        "prüfen Sie, dass `Haupt()` im Projekt genau einmal vorkommt.",
        "",
    ),
    "chir_dce_unused_operator": (
        "Unbenutzte Operation{q0?}",
        "Statische Prüfung nicht bestanden: das Ergebnis der Operation wird nirgends verwendet.",
        "",
    ),
    "chir_divisor_is_zero": (
        "Division durch null{q0?}",
        "Statische Prüfung nicht bestanden: Division durch eine sicher nullwertige Konstante. "
        "Prüfen Sie den Divisor vor der Division.",
        "Falls (d != 0) {\n    Zeige(a / d)\n}",
    ),
    "chir_file_might_circular_dependency": (
        "Mögliche zirkuläre Dateiabhängigkeit{q0?}",
        "Statische Prüfung nicht bestanden: Dateien hängen ringförmig voneinander ab — "
        "strukturieren Sie die Imports um und durchbrechen Sie den Zyklus.",
        "",
    ),
    "chir_idx_out_of_bounds": (
        "Index außerhalb der Grenzen{q0?}",
        "Statische Prüfung nicht bestanden: der Index liegt sicher außerhalb der Sammlung. "
        "Prüfen Sie die Grenzen vor dem Zugriff.",
        "",
    ),
    "chir_illegal_usage_of_member": (
        "Unzulässige Verwendung eines Members{q0?}",
        "Statische Prüfung nicht bestanden: dieses Member kann in diesem Kontext nicht "
        "verwendet werden (Sichtbarkeit oder Empfänger passt nicht).",
        "",
    ),
    "chir_illegal_usage_of_super_member": (
        "Unzulässige Verwendung eines Super-Members{q0?}",
        "Statische Prüfung nicht bestanden: das Member der Elternklasse kann hier nicht "
        "aufgerufen werden (nicht überschrieben oder privat).",
        "",
    ),
    "chir_shift_length_overflow": (
        "Schubweite überläuft{q0?}",
        "Statische Prüfung nicht bestanden: die Schubweite überschreitet die Bitbreite des Operanden.",
        "",
    ),
    "chir_step_non_zero_range": (
        "Schrittweite des Bereichs muss ungleich null sein{q0?}",
        "Statische Prüfung nicht bestanden: Schrittweite null ergäbe eine Endlosschleife. "
        "Verwenden Sie eine von null verschiedene Schrittweite.",
        "",
    ),
    "chir_typecast_overflow": (
        "Überlauf bei der Typumwandlung{q0?}",
        "Statische Prüfung nicht bestanden: die Umwandlung verliert nachweislich Daten. "
        "Nehmen Sie einen größeren Typ oder prüfen Sie den Wert.",
        "",
    ),
    "chir_unreachable_pattern": (
        "Unerreichbares Muster{q0?}",
        "Statische Prüfung nicht bestanden: ein vorheriges Muster deckt diesen Fall bereits ab — "
        "umstellen oder entfernen.",
        "",
    ),
    "chir_used_before_initialization": (
        "Verwendung vor der Initialisierung{q0?}",
        "Statische Prüfung nicht bestanden: die Variable wird vor ihrer Zuweisung gelesen. "
        "Bei der Deklaration initialisieren oder den Code umstellen.",
        "",
    ),
    "chir_var_might_circular_dependency": (
        "Mögliche zirkuläre Variablenabhängigkeit{q0?}",
        "Statische Prüfung nicht bestanden: der Initialisierer der Variablen verweist direkt "
        "oder indirekt auf sie selbst.",
        "",
    ),
    "lex_cannot_start_with_digit": (
        "Bezeichner darf nicht mit einer Ziffer beginnen{q0?}",
        "Bezeichner beginnen mit einem Buchstaben oder Unterstrich — Ziffern sind erst ab dem "
        "zweiten Zeichen erlaubt.",
        "Lege wert2 = 2   // korrekt\n// Lege 2wert = 2  // Fehler: nicht mit Ziffer beginnen",
    ),
    "lex_characters_overflow": (
        "Zeichenzahl überschritten{q0?}",
        "Lexikalische Prüfung nicht bestanden: das Literal überschreitet die maximale Länge.",
        "",
    ),
    "lex_expected_back_quote": (
        "Rückwärtiger Akzent erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: rohe Bezeichner werden in Rückwärtsakzente "
        "gesetzt — fügen Sie das schließende `` ` `` hinzu.",
        "",
    ),
    "lex_expected_character": (
        "Zeichen erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: an dieser Position erwartet der Compiler ein "
        "bestimmtes Zeichen.",
        "",
    ),
    "lex_expected_character_in_char_literal": (
        "Im Zeichenliteral wird ein Zeichen erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: ein Zeichenliteral (r'x') enthält genau ein "
        "Zeichen zwischen den Anführungszeichen.",
        "Lege c = r'A'  // genau ein Zeichen",
    ),
    "lex_expected_digit": (
        "Ziffer erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: hier ist eine Ziffer nötig (Zahlenliteral oder "
        "Escape-Sequenz).",
        "",
    ),
    "lex_expected_exponent_part": (
        "Exponent erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: nach `e` in einem Gleitkommaliteral muss der "
        "Exponent folgen (z. B. 1e3, 1.5e-2).",
        "",
    ),
    "lex_expected_identifier": (
        "Bezeichner erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: hier wurde ein Name erwartet — prüfen Sie, ob ein "
        "Variablen-/Parametername fehlt oder ein reserviertes Wort verwendet wurde.",
        "",
    ),
    "lex_expected_identifier_after_dollar": (
        "Nach dem Dollarzeichen wird ein Bezeichner erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: auf `$` muss ein Bezeichner folgen.",
        "",
    ),
    "lex_expected_left_bracket": (
        "Öffnende eckige Klammer erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: hier wird `[` erwartet (Array-Literal oder "
        "Indexzugriff).",
        "",
    ),
    "lex_expected_letter_after_underscore": (
        "Nach dem Unterstrich wird ein Buchstabe erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: ein Bezeichner darf nicht nur aus einem "
        "Unterstrich ohne Buchstaben bestehen.",
        "",
    ),
    "lex_expected_quote_in_raw_string": (
        "In der rohen Zeichenkette wird ein Anführungszeichen erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: die rohe Zeichenkette (z. B. `#\"...\"#`) hat kein "
        "schließendes Anführungszeichen als Begrenzer.",
        "",
    ),
    "lex_expected_right_bracket": (
        "Schließende eckige Klammer erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: `[` muss mit `]` geschlossen werden.",
        "",
    ),
    "lex_expected_right_bracket_or_hexadecimal": (
        "Schließende Klammer oder Hexadezimalziffern erwartet{q0?}",
        "Lexikalische Prüfung nicht bestanden: die Escape-Sequenz `\\u` verlangt 1-6 "
        "Hexadezimalziffern und ein schließendes `]` — z. B. `\\u{4e2d}`.",
        "",
    ),
    "lex_fchar": (
        "Fehler im Zeichenliteral{q0?}",
        "Lexikalische Prüfung nicht bestanden: prüfen Sie die Syntax des Zeichenliterals "
        "(r'x', Escape-Sequenzen, genau ein Zeichen).",
        "",
    ),
    "lex_float": (
        "Fehler im Gleitkommaliteral{q0?}",
        "Lexikalische Prüfung nicht bestanden: prüfen Sie die Syntax des Gleitkommaliterals — "
        "Ziffern, Punkt, Exponent (z. B. 1.5, 1e3).",
        "Lege a = 1.5      // korrekt\nLege b = 1e3      // korrekt\n// Lege c = 1.    // Fehler: nach dem Punkt braucht es Ziffern",
    ),
    "lex_float128": (
        "Fehler im float128-Literal{q0?}",
        "Lexikalische Prüfung nicht bestanden: prüfen Sie die Syntax des Float128-Literals "
        "(Suffix und Ziffern).",
        "",
    ),
}

# ── Fallback-Nachrichtentabelle (Empfehlung E4): Schlüssel = offizieller Meldungstext
# (isomorph zu MESSAGES in zh; Schlüssel werden nicht übersetzt — Abgleich gegen cjc-Texte).
MSG_DE = [
    ("expected '", "Erwartet: `{q0}`, erhalten: `{q1}`", "Die Typen beider Seiten stimmen nicht überein: prüfen Sie den deklarierten Typ und den tatsächlichen Typ des Ausdrucks."),
    ("can not find package '", "Paket `{q0}` nicht gefunden", "Der Importpfad existiert nicht: prüfen Sie die Schreibweise oder ob die Bibliothek installiert ist."),
    ("~ is immutable", "Variable `{q0}` ist eine unveränderliche Bindung", "Eine `Lege`-Bindung (let) kann nicht geändert werden; verwenden Sie bei Bedarf `Variable` (var)."),
    ("~ is never used", "`{q0}` wird nie verwendet", "Entfernen Sie die ungenutzte Deklaration oder prüfen Sie die Schreibweise."),
    ("not found in", "In `{q0}` wurde `{q1}` nicht gefunden", "Prüfen Sie, ob Name und zugehöriges Modul korrekt geschrieben sind."),
    ("missing argument", "Anzahl der Argumente im Aufruf passt nicht: `{q0}`", "Die Anzahl der tatsächlichen Argumente muss der der Parameter entsprechen: fehlende wie überzählige Argumente führen zu Fehlern."),
    ("unclosed delimiter", "Nicht geschlossenes Begrenzungszeichen `{q0}`", "Runde, eckige und geschweifte Klammern müssen paarweise geschlossen werden: prüfen Sie Verschachtelung und Einrückung."),
    ("redefinition of", "Mehrfachdeklaration `{q0}`", "Innerhalb desselben Gültigkeitsbereichs darf ein Name nur einmal deklariert werden: benennen Sie um oder entfernen Sie die überflüssige Deklaration."),
    ("undeclared type name", "Nicht deklarierter Typname `{q0}`", "Ein Typ muss deklariert oder importiert sein: prüfen Sie Schreibweise und Import."),
    ("generic type should be used", "Generischer Typ ohne Typparameter{q0?}", "Bei generischen Typen (z. B. `Feld`) müssen Typparameter angegeben werden."),
    ("unrecognized escape", "Unbekannte Escape-Sequenz `{q0}`", "Cangjie unterstützt `\\n`, `\\t`, `\\\\`, `\\uXXXX` usw.; `\\q` und Ähnliches sind nicht erlaubt."),
    ("~ is missing", "`{q0}` fehlt", "Ein erforderlicher Name oder Einstieg fehlt: Programmeinstieg ist `Haupt()`."),
    ("unused variable", "Unbenutzte Variable", "Entfernen Sie die ungenutzte Deklaration oder prüfen Sie auf Tippfehler."),
    ("unused import", "Unbenutzter Import", "Entfernen Sie den ungenutzten Import oder stellen Sie sicher, dass er tatsächlich verwendet wird."),
    ("unused function", "Unbenutzte Funktion", "Entfernen Sie die ungenutzte Funktion oder prüfen Sie die Schreibweise an der Aufrufstelle."),
    ("this warning can be suppressed by setting the compiler option",
     "Diese Warnung kann über die Compiler-Option `{q0}` unterdrückt werden",
     "Behalten Sie die Warnung oder korrigieren Sie den Code gemäß Hinweis; Compiler-Optionen sind das letzte Mittel."),
    ("this error can be suppressed by setting the compiler option",
     "Dieser Fehler kann über die Compiler-Option `{q0}` unterdrückt werden",
     "Korrigieren Sie den Code gemäß Hinweis, um den Fehler zu beheben; Compiler-Optionen nur als letztes Mittel."),
    ("following constraints for type variable", "Beschränkungen für Typparameter `{q0}` nicht lösbar", "Prüfen Sie, ob die Typparameter des generischen Typs die deklarierten Beschränkungen erfüllen."),
    ("constraint '", "Beschränkung `{q0}` könnte stammen aus", "Hinweis bei fehlgeschlagener Generik-Inferenz: gleichen Sie den tatsächlichen Typ der Argumente an der Aufrufstelle ab."),
    ("may come from", "Könnte stammen aus `{q0}`", "Hinweis bei fehlgeschlagener Generik-Inferenz: prüfen Sie die Typannotationen der beteiligten Deklarationen."),
]
