<!-- zhc-i18n 源: docs/中文仓颉程序设计/README.md 基线: b336d790600ad489 时间: 2026-09-06 -->

# Introduction du tutoriel — Leçon 0 (Français)

Navigation：[Tutoriel canonique (zh)](../../中文仓颉程序设计/README.md) · [English](../en/README.md) · **Français** · [Deutsch](../de/README.md) · [Español](../es/README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

Le tutoriel canonique **《中文仓颉程序设计》** est un cours méthodique en style
manuel : **3 tomes, 20 chapitres + 3 annexes + corrigés**, avec **plus de 150
blocs de code tous vérifiés contre `cjc 1.0.5` officiel**. Cette page est votre
leçon 0 en français ; le texte canonique est en chinois — lisez-les en parallèle
ou commencez par les exemples de dialecte ci-dessous.

## Les trois tomes

| Tome | Pour vous si… | Contenu |
|---|---|---|
| Tome 1 Premiers pas | débutant complet | installation, premier programme, variables, nombres, conditions, boucles, fonctions |
| Tome 2 Cœur & approfondissement | grammaire systématique | fonctions, système de types, chaînes, collections, POO, énumérations, erreurs, génériques & macros |
| Tome 3 Art & pensée | développeurs exigeants | pensée de conception, algorithmes & structures de données, génie logiciel, projet fil rouge |

## Leçon 1 : votre premier programme

Écrivez-le dans le dialecte français :

```fc
principal() {
    soit message: Chaine = "Bonjour, Cangjie !"
    afficher(message)
}
```

Enregistrez sous `hello.fc`, puis `ZHCLANG=fr zhc run hello.fc`. Chaque dialecte
se transpile vers exactement ce code standard — seuls les mots-clés et les noms
de types sont réécrits d'après la table de correspondance de votre langue.
Paquets disponibles : `en`/`ru`/`ja`/`ko`/`fr`/`es`/`de`.

## Où chercher (repères rapides)

- Départ zéro → Tome 1, chapitres 01–07 (≈10–20 min chacun, exercices inclus)
- Grammaire systématique → Tome 2, chapitres 08–15 (définition → syntaxe → exemple → remarques)
- Qualité & ingénierie → Tome 3, chapitres 16–19
- Mots-clés / bibliothèque standard, décoder les erreurs → Annexes A/B/C

Ouvrir le tutoriel canonique : [page d'accueil du tutoriel](../../中文仓颉程序设计/README.md)
