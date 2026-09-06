<!-- zhc-i18n 源: docs/中文仓颉程序设计/README.md 基线: b336d790600ad489 时间: 2026-09-06 -->

# Introducción al tutorial — Lección 0 (Español)

Navegación：[Tutorial canónico (zh)](../../中文仓颉程序设计/README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · **Español** · [한국어](../ko/README.md) · [日本語](../ja/README.md) · [Русский](../ru/README.md)

El tutorial canónico **《中文仓颉程序设计》** es un curso metódico en estilo
manual: **3 tomos, 20 capítulos + 3 apéndices + soluciones**, con **más de 150
bloques de código verificados contra `cjc 1.0.5` oficial**. Esta página es su
lección 0 en español; el texto canónico está en chino — léalos en paralelo o
comience con los ejemplos de dialecto de abajo.

## Los tres tomos

| Tomo | Para usted si… | Contenido |
|---|---|---|
| Tomo 1 Primeros pasos | principiante total | instalación, primer programa, variables, números, condiciones, bucles, funciones |
| Tomo 2 Núcleo y avance | gramática sistemática | funciones, sistema de tipos, cadenas, colecciones, POO, enumeraciones, errores, genéricos y macros |
| Tomo 3 Oficio y pensamiento | calidad e ingeniería | pensamiento de diseño, algoritmos y estructuras de datos, ingeniería de software, proyecto final |

## Lección 1: su primer programa

Escríbalo en el dialecto español:

```sc
principal() {
    defina saludo: Cadena = "¡Hola, 仓颉!"
    mostrar(saludo)
}
```

Guárdelo como `hello.sc` y ejecute `ZHCLANG=es zhc run hello.sc`. Cada dialecto
se transpila exactamente a este código estándar — por ejemplo, el dialecto
chino escribe `main` como `主函数`, `let` como `让`, `println` como `打印行`.
Dialectos disponibles: `en`/`ru`/`ja`/`ko`/`fr`/`es`/`de`.

## Dónde mirar (referencia rápida)

- Desde cero → Tomo 1, capítulos 01–07 (≈10–20 min cada uno, con ejercicios)
- Gramática sistemática → Tomo 2, capítulos 08–15 (definición → sintaxis → ejemplo → notas)
- Calidad e ingeniería → Tomo 3, capítulos 16–19
- Palabras clave/biblioteca estándar, decodificar errores → Apéndices A/B/C

Abrir el tutorial canónico: [docs/中文仓颉程序设计/README.md](../../中文仓颉程序设计/README.md)
