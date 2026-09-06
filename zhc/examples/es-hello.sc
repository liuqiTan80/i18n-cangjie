// Ejemplo de dialecto español (extensión .sc → detección automática del idioma)
// Nota: principal → main. Como en Cangjie oficial, main no lleva la palabra clave func.
principal() {
    defina nombre: Cadena = "España"
    mostrar("¡Hola, ${nombre}!")

    // Alias de tipo: Entero → Int64
    defina número: Entero = 42
    mostrar("Número: ${número}")
}
