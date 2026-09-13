<!-- zhc-i18n 源: README.md 基线: 55556d611cf2892b 时间: 2026-09-13 -->

# zhc — Programe en Cangjie en su lengua materna

Language / Langue / Sprache / Idioma / 언어 / 言語 / Язык：[中文](../../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · **Español** · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

**zhc** es un marco de enseñanza en lengua materna para el lenguaje de
programación Cangjie: transpila código fuente dialectal (por ejemplo
chino `.zc`, coreano `.kc`, español `.sc`) a Cangjie estándar y traduce los
diagnósticos del compilador a mensajes de aprendizaje en el idioma elegido
(código de error → tabla de mensajes → localización de tipos → ejemplos de
corrección). El dialecto se selecciona con la variable de entorno `ZHCLANG`
(por defecto `zh`); todo lo dirige un **paquete de idioma**.

## Inicio rápido (unos 10 minutos)

**1. Instale el SDK de Cangjie** (única dependencia externa): descargue la
versión **1.0.5** de cangjie-lang.cn/download, descomprima y ejecute el
`envsetup.sh` incluido para que `cjc` y `cjpm` queden en el `PATH`.
Verificación:

```bash
cjc --version    # Cangjie Compiler: 1.0.5 (cjnative)
```

**2. Compile zhc** (sin red, sin dependencias de terceros):

```bash
cd zhc
cjpm build       # produce target/release/bin/main
```

**3. Ejecute su primer programa** (el ejemplo en dialecto español incluido):

```bash
export ZHC_LANG_PACKS=$PWD        # desde la raíz del repositorio: zhc/
zhc run examples/es-hello.sc
# ✅ Compilation OK: replaced 7 dialect identifier(s).
# ¡Hola, España!
# Número: 42
```

## Escriba en su propio idioma

Funciona cualquier idioma con paquete en `zhc/lang-packs/<código>/` — se
incluyen `zh`/`en` (nivel completo), `ru`/`ja`/`ko`/`fr`/`es`/`de` (nivel
estándar) y `ar` (demo RTL). Por ejemplo, español (`ZHCLANG=es`, extensión `.sc`):

```sc
principal() {
    defina saludo: Cadena = "Cangjie"
    mostrar("¡Hola, ${saludo}!")
}
```

Ejecución: `ZHCLANG=es zhc run hello.sc`. El dialecto alemán funciona igual
(`Haupt/Lege/Zeige`, extensión `.dc`).

## Traducciones de bibliotecas de terceros

Los mapeos de API de bibliotecas viven en el repositorio de traducciones
compartido, no en su árbol de fuentes — descargue solo el idioma y la
biblioteca que necesite:

```bash
zhc share list                     # explorar el registro compartido
zhc share fetch csv4cj --lang es   # descargar un mapeo en su idioma
zhc share publish mi_mapeo.toml    # compartir su propia traducción
```

Los mapeos descargados pasan sumas de verificación y controles de calidad
(formato, nombres oficiales, colisiones con palabras reservadas) antes de
instalarse en `~/.zhc/lang-packs/<idioma>/crates/`. Si falta traducción hay
repliegue elegante al chino; su programa funciona en cualquier caso.

## Terminología (uso uniforme en toda la documentación en español)

| Español | En código/documentos | Notas |
|---|---|---|
| dialecto | `.zc` `.sc` `.dc` … | Cangjie escrito en lengua materna |
| paquete de idioma | `lang-packs/<código>/` | tablas de palabras clave/alias + diagnósticos + textos de interfaz |
| mapeo | `<idioma>/crates/<lib>.toml` | nombre nativo = nombre oficial de la API |
| transpilación | `zhc run` / `zhc check` | dialecto → Cangjie estándar |
| registro compartido | `zhc share …` | registro centralizado de traducciones |
| línea base | `zh@<suma>` | huella de sincronización del original en chino |

## Para saber más

- Tutorial (canónico, en chino): [Programar Cangjie en chino — el manual canónico](../../../docs/中文仓颉程序设计/README.md)
- Paquetes de idioma y cómo contribuir: [desarrollo de paquetes de idioma](../../../docs/语言包开发.md)
- Alcance de localización y mecanismo de sincronización: [docs/i18n/README.md](../README.md)
- Guía del tutorial en español: [Introducción al tutorial (lección 0)](tutorial-00.md)
- Diagnóstico: ejecute `zhc doctor` — autocomprobación del entorno en seis puntos (compilador, build, paquetes de idioma, directorio escribible, fuente compartida, cjlint) con sugerencias de corrección localizadas.
