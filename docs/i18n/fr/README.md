<!-- zhc-i18n 源: README.md 基线: 55556d611cf2892b 时间: 2026-09-13 -->

# zhc — Programmer en Cangjie dans sa langue maternelle

Language / Language / Langue / Sprache / Idioma / 언어 / 言語 / Язык：[中文](../../../README.md) · [English](../en/README.md) · **Français** · [Deutsch](../de/README.md) · [Español](../es/README.md) · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

**zhc** est un cadre de programmation pédagogique pour le langage Cangjie :
il transpile un code source dialectal (par ex. chinois `.zc`, coréen `.kc`,
français `.fc`) vers le Cangjie standard, puis retraduit les diagnostics du
compilateur en messages pédagogiques dans la langue choisie (code d'erreur →
table de messages → localisation des types → exemples de correction). Le
dialecte se choisit avec la variable d'environnement `ZHCLANG` (défaut `zh`) ;
tout est piloté par un **paquet de langue**.

## Démarrage rapide (environ 10 minutes)

**1. Installer le SDK Cangjie** (seule dépendance externe) : téléchargez la
version **1.0.5** sur cangjie-lang.cn/download, décompressez puis lancez le
script `envsetup.sh` fourni afin que `cjc` et `cjpm` soient dans le `PATH`.
Vérification :

```bash
cjc --version    # Cangjie Compiler: 1.0.5 (cjnative)
```

**2. Compiler zhc** (sans réseau, aucune dépendance tierce) :

```bash
cd zhc
cjpm build       # produit target/release/bin/main
```

**3. Exécuter un premier programme** (l'exemple du dialecte français fourni) :

```bash
export ZHC_LANG_PACKS=$PWD        # à la racine du dépôt : zhc/
zhc run examples/fr-hello.fc
# ✅ Compilation OK: replaced 7 dialect identifier(s).
# Bonjour, France !
# Nombre : 42
```

## Écrire dans sa propre langue

Toute langue disposant d'un paquet sous `zhc/lang-packs/<code>/` fonctionne —
`zh`/`en` (niveau complet), `ru`/`ja`/`ko`/`fr`/`es`/`de` (niveau standard) et `ar` (démo RTL) sont inclus. Par
exemple le français (`ZHCLANG=fr`, extension `.fc`) :

```fc
principal() {
    soit message: Chaine = "Cangjie"
    afficher("Bonjour, ${message}!")
}
```

Exécution : `ZHCLANG=fr zhc run hello.fc`. Le dialecte coréen fonctionne de
la même manière (`메인/두다/문자열/출력`, extension `.kc`).

## Traductions des bibliothèques tierces

Les mappages d'API des bibliothèques vivent dans le dépôt de partage central,
pas dans votre arborescence source — ne téléchargez que la langue et la
bibliothèque dont vous avez besoin :

```bash
zhc share list                     # parcourir le registre partagé
zhc share fetch csv4cj --lang fr   # télécharger un mappage dans votre langue
zhc share publish mon_mappage.toml # contribuer votre propre traduction
```

Les mappages téléchargés passent des contrôles (somme de vérification, format,
noms officiels, collisions avec les mots réservés) avant d'être installés dans
`~/.zhc/lang-packs/<langue>/crates/`. En cas de traduction manquante, repli
élégant sur le chinois ; votre programme fonctionne dans tous les cas.

## Terminologie (emploie uniforme dans toute la documentation française)

| Français | Dans le code/docs | Remarques |
|---|---|---|
| dialecte | `.zc` `.kc` `.fc` … | Cangjie écrit dans une langue maternelle |
| paquet de langue | `lang-packs/<code>/` | tables de mots-clés/alias + diagnostics + textes d'interface |
| mappage | `crates/<langue>/<lib>.toml` | nom natif = nom officiel de l'API |
| transpilation | `zhc run` / `zhc check` | dialecte → Cangjie standard |
| dépôt partagé | `zhc share …` | registre centralisé des traductions |
| ligne de base | `zh@<somme>` | empreinte de synchronisation de la source zh |

## Pour aller plus loin

- Tutoriel (canonique, en chinois) : [Concevoir Cangjie en chinois — le manuel canonique](../../../docs/中文仓颉程序设计/README.md)
- Paquets de langue et contribution : [développement d'un paquet de langue](../../../docs/语言包开发.md)
- Périmètre de localisation et mécanisme de synchronisation : [docs/i18n/README.md](../README.md)
- Guide du tutoriel en français : [Introduction au tutoriel (leçon 0)](tutorial-00.md)
- Dépannage : lancez `zhc doctor` — auto-vérification de l'environnement en six points (compilateur, build, paquets de langue, répertoire inscriptible, source partagée, cjlint) avec conseils de correction localisés.
