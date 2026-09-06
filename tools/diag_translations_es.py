# -*- coding: utf-8 -*-
"""Traducciones de diagnóstico al español (tabla incremental, recomendación E3: cadena de
generación parametrizada).

Para tools/gen_full_errors.py --lang es, que genera zhc/lang-packs/es/errors.toml.
Las entradas son isomorfas a CURATED en zh: {DiagKind: (plantilla de mensaje, consejo
didáctico, ejemplo de reparación)}.

Amigable con el incremento: solo entran los códigos **traducidos** (desde 2026-09-06:
Top-50 de errores frecuentes de principiantes). Los códigos sin traducir degradan con
elegancia en tiempo de ejecución (texto original del compilador oficial, sin pánico), así
que la tabla puede ampliarse en cualquier momento y regenerarse con `--lang es`.
Los ejemplos de reparación usan palabras del dialecto es (defina=let / variable=var /
si=if / sino=else / mostrar=println / principal=main / Entero=Int64 / Cadena=String /
Logico=Bool / Real=Float64 / Arreglo=Array / Opcion=Option / SinValor=None, ver listas de
palabras en lang-packs/es/).
"""

ES = {
    "sema_mismatched_types": (
        "Los tipos no coinciden",
        "Revisa los tipos de ambos lados de la declaración y de la asignación. Si hace falta "
        "una conversión, usa `como` (as): Cangjie no convierte tipos automáticamente.",
        "variable entero: Entero = 1\n"
        "variable texto: Cadena = \"1\"\n"
        "// ambos lados deben tener el mismo tipo",
    ),
    "package_search_error": (
        "Paquete `{q0}` no encontrado",
        "Revisa la declaración de dependencias en cjpm.toml o ejecuta la instalación del paquete.",
        "",
    ),
    "chir_dce_unused_variable": (
        "La variable `{q0}` nunca se usa",
        "Las declaraciones sin uso generan una advertencia del compilador. Bórrala o revisa "
        "si hay un error tipográfico (p. ej. sin querer nombraste otra variable).",
        "defina sinUso: Cadena = \"hola\"\n"
        "// opción 1: borrar la línea\n"
        "// opción 2: usarla\n"
        "mostrar(sinUso)",
    ),
    "lex_unrecognized_escape": (
        "Secuencia de escape desconocida `{q0}`",
        "La secuencia `\\q` no se admite. Cangjie conoce `\\n` (salto de línea), `\\t` "
        "(tabulador), `\\\\`, `\\\"`, `\\uXXXX` (Unicode), etc.",
        "mostrar(\"primera línea\\nsegunda línea\")  // \\n es el salto de línea",
    ),
    "parse_expected_character": (
        "Se esperaba: `{q0}`",
        "Sintaxis incompleta: revisa si en esta línea falta un paréntesis, un punto y coma o "
        "una palabra clave.",
        "",
    ),
    "parse_expected_right_delimiter": (
        "Delimitador `{q0}` sin cerrar",
        "Los paréntesis deben cerrarse por pares: revisa el anidamiento — a cada `(`/`[`/`{` "
        "le corresponde un `)`/`]`/`}`.",
        "si (a > 0) {\n    mostrar(a)\n}  // a cada `{` le corresponde un `}`",
    ),
    "sema_cannot_assign_to_immutable": (
        "No se puede asignar a un valor inmutable",
        "Un enlace `defina` es inmutable una vez creado. Para reasignar usa `variable`.",
        "defina x = 1\n// x = 2  // error: defina es inmutable\nvariable y = 1\ny = 2  // correcto",
    ),
    "sema_exceed_num_value_range": (
        "El número `{q0}` se sale del rango del tipo `{q1}`",
        "El literal queda fuera del rango del tipo destino: usa un tipo mayor o calcula el "
        "valor en tiempo de ejecución.",
        "",
    ),
    "sema_generic_type_without_type_argument": (
        "Tipo genérico sin parámetro de tipo",
        "Los tipos genéricos exigen un parámetro de tipo: `Arreglo<Entero>`, `Opcion<Cadena>`, etc.",
        "defina lista: Arreglo<Entero> = Arreglo<Entero>()\ndefina valor: Opcion<Cadena> = SinValor",
    ),
    "sema_missing_entry": (
        "Falta el punto de entrada `{q0}`",
        "Un programa ejecutable necesita `principal()`: exactamente una vez por proyecto; "
        "parámetros y tipo de retorno se quedan por defecto.",
        "principal() {\n    mostrar(\"¡Hola, Cangjie!\")\n}",
    ),
    "sema_redefinition": (
        "Declaración duplicada `{q0}`",
        "Un nombre solo puede declararse una vez en el mismo ámbito: revisa duplicados o "
        "conflictos con identificadores importados (renombra o elimina la declaración sobrante).",
        "",
    ),
    "sema_undeclared_identifier": (
        "Identificador no declarado `{q0}`",
        "Se usó un nombre indefinido: revisa la ortografía; las variables deben declararse "
        "antes de usarse; los nombres de un bloque `{}` solo son visibles dentro de él.",
        "principal() {\n    defina nombre = \"Cangjie\"\n    mostrar(nombre)  // primero declarar, luego usar\n}",
    ),
    "sema_undeclared_type_name": (
        "Nombre de tipo no declarado `{q0}`",
        "Un tipo debe estar declarado o importado: revisa la ortografía; define antes tus "
        "propios tipos; los tipos de la biblioteca estándar necesitan el import del módulo.",
        "",
    ),
    "sema_wrong_number_of_arguments": (
        "El número de argumentos de la llamada no coincide: `{q0}`",
        "El número de argumentos debe coincidir con la lista de parámetros: cuéntalos en la "
        "llamada — tanto los que faltan como los que sobran son errores.",
        "",
    ),
    "chir_annotation_not_applicable": (
        "La anotación no se puede aplicar aquí{q0?}",
        "No pasó la comprobación estática: busca problemas ocultos "
        "(sin usar, inalcanzable, desbordamiento, sin inicializar).",
        "",
    ),
    "chir_arithmetic_operator_overflow": (
        "Desbordamiento en la operación aritmética{q0?}",
        "No pasó la comprobación estática: el desbordamiento ya se detecta antes de ejecutar. "
        "Usa un tipo mayor o revisa los valores.",
        "",
    ),
    "chir_cannot_assign_initialized_let_variable": (
        "No se puede asignar a una variable defina ya inicializada{q0?}",
        "No pasó la comprobación estática: `defina` no admite reasignación — usa `variable`.",
        "",
    ),
    "chir_class_uninitialized_field": (
        "Campo de clase sin inicializar{q0?}",
        "No pasó la comprobación estática: los campos de una clase deben inicializarse en el "
        "constructor (inicializar) o en la declaración.",
        "",
    ),
    "chir_dce_unused_expression": (
        "Expresión sin usar{q0?}",
        "No pasó la comprobación estática: el valor de la expresión no se usa en ninguna "
        "parte — asígnalo o bórralo.",
        "",
    ),
    "chir_dce_unused_function": (
        "Función sin usar{q0?}",
        "No pasó la comprobación estática: nunca se llama a la función. Bórrala o consérvala "
        "como parte de la API pública.",
        "",
    ),
    "chir_dce_unused_function_main": (
        "Función sin usar (punto de entrada){q0?}",
        "No pasó la comprobación estática: el punto de entrada está marcado como sin usar — "
        "revisa que `principal()` aparezca exactamente una vez en el proyecto.",
        "",
    ),
    "chir_dce_unused_operator": (
        "Operación sin usar{q0?}",
        "No pasó la comprobación estática: el resultado de la operación no se usa en ninguna parte.",
        "",
    ),
    "chir_divisor_is_zero": (
        "División entre cero{q0?}",
        "No pasó la comprobación estática: división por una constante que con seguridad es cero. "
        "Revisa el divisor antes de dividir.",
        "si (d != 0) {\n    mostrar(a / d)\n}",
    ),
    "chir_file_might_circular_dependency": (
        "Posible dependencia circular de archivos{q0?}",
        "No pasó la comprobación estática: los archivos dependen unos de otros en anillo — "
        "reestructura los imports y rompe el ciclo.",
        "",
    ),
    "chir_idx_out_of_bounds": (
        "Índice fuera de límites{q0?}",
        "No pasó la comprobación estática: el índice queda con seguridad fuera de la colección. "
        "Revisa los límites antes de acceder.",
        "",
    ),
    "chir_illegal_usage_of_member": (
        "Uso no permitido de un miembro{q0?}",
        "No pasó la comprobación estática: este miembro no se puede usar en ese contexto "
        "(no coincide la visibilidad o el receptor).",
        "",
    ),
    "chir_illegal_usage_of_super_member": (
        "Uso no permitido de un miembro de la superclase{q0?}",
        "No pasó la comprobación estática: el miembro de la clase padre no se puede invocar "
        "aquí (no está sobrescrito o es privado).",
        "",
    ),
    "chir_shift_length_overflow": (
        "El desplazamiento se desborda{q0?}",
        "No pasó la comprobación estática: la cantidad de desplazamiento supera el ancho en "
        "bits del operando.",
        "",
    ),
    "chir_step_non_zero_range": (
        "El paso del rango debe ser distinto de cero{q0?}",
        "No pasó la comprobación estática: un paso cero produciría un bucle infinito. "
        "Usa un paso distinto de cero.",
        "",
    ),
    "chir_typecast_overflow": (
        "Desbordamiento en la conversión de tipo{q0?}",
        "No pasó la comprobación estática: la conversión pierde datos de forma demostrable. "
        "Usa un tipo mayor o revisa el valor.",
        "",
    ),
    "chir_unreachable_pattern": (
        "Patrón inalcanzable{q0?}",
        "No pasó la comprobación estática: un patrón anterior ya cubre este caso — "
        "reordénalo o elimínalo.",
        "",
    ),
    "chir_used_before_initialization": (
        "Uso antes de la inicialización{q0?}",
        "No pasó la comprobación estática: la variable se lee antes de asignarle un valor. "
        "Inicialízala en la declaración o reordena el código.",
        "",
    ),
    "chir_var_might_circular_dependency": (
        "Posible dependencia circular de variables{q0?}",
        "No pasó la comprobación estática: el inicializador de la variable se refiere a ella "
        "misma, directa o indirectamente.",
        "",
    ),
    "lex_cannot_start_with_digit": (
        "El identificador no puede empezar por un dígito{q0?}",
        "Los identificadores empiezan con una letra o un guion bajo; los dígitos solo se "
        "permiten a partir del segundo carácter.",
        "defina valor2 = 2   // correcto\n// defina 2valor = 2  // error: no puede empezar por dígito",
    ),
    "lex_characters_overflow": (
        "Se superó la cantidad de caracteres{q0?}",
        "No pasó la comprobación léxica: el literal supera la longitud máxima.",
        "",
    ),
    "lex_expected_back_quote": (
        "Se esperaba un acento grave{q0?}",
        "No pasó la comprobación léxica: los identificadores crudos van entre acentos graves — "
        "añade el `` ` `` de cierre.",
        "",
    ),
    "lex_expected_character": (
        "Se esperaba un carácter{q0?}",
        "No pasó la comprobación léxica: en esta posición el compilador espera un carácter "
        "concreto.",
        "",
    ),
    "lex_expected_character_in_char_literal": (
        "Se esperaba un carácter en el literal de carácter{q0?}",
        "No pasó la comprobación léxica: un literal de carácter (r'x') contiene exactamente "
        "un carácter entre las comillas.",
        "defina c = r'A'  // exactamente un carácter",
    ),
    "lex_expected_digit": (
        "Se esperaba un dígito{q0?}",
        "No pasó la comprobación léxica: aquí se necesita un dígito (literal numérico o "
        "secuencia de escape).",
        "",
    ),
    "lex_expected_exponent_part": (
        "Se esperaba el exponente{q0?}",
        "No pasó la comprobación léxica: tras `e` en un literal de coma flotante debe venir "
        "el exponente (p. ej. 1e3, 1.5e-2).",
        "",
    ),
    "lex_expected_identifier": (
        "Se esperaba un identificador{q0?}",
        "No pasó la comprobación léxica: aquí se esperaba un nombre — revisa si falta un "
        "nombre de variable/parámetro o si se usó una palabra reservada.",
        "",
    ),
    "lex_expected_identifier_after_dollar": (
        "Tras el signo $ se esperaba un identificador{q0?}",
        "No pasó la comprobación léxica: después de `$` debe venir un identificador.",
        "",
    ),
    "lex_expected_left_bracket": (
        "Se esperaba el corchete de apertura{q0?}",
        "No pasó la comprobación léxica: aquí se espera `[` (literal de arreglo o acceso "
        "por índice).",
        "",
    ),
    "lex_expected_letter_after_underscore": (
        "Tras el guion bajo se esperaba una letra{q0?}",
        "No pasó la comprobación léxica: un identificador no puede constar solo de un guion "
        "bajo sin letras.",
        "",
    ),
    "lex_expected_quote_in_raw_string": (
        "Se esperaba una comilla en la cadena cruda{q0?}",
        "No pasó la comprobación léxica: a la cadena cruda (p. ej. `#\"...\"#`) le falta la "
        "comilla de cierre como delimitador.",
        "",
    ),
    "lex_expected_right_bracket": (
        "Se esperaba el corchete de cierre{q0?}",
        "No pasó la comprobación léxica: `[` debe cerrarse con `]`.",
        "",
    ),
    "lex_expected_right_bracket_or_hexadecimal": (
        "Se esperaba el corchete de cierre o dígitos hexadecimales{q0?}",
        "No pasó la comprobación léxica: la secuencia de escape `\\u` exige de 1 a 6 dígitos "
        "hexadecimales y un `]` de cierre — p. ej. `\\u{4e2d}`.",
        "",
    ),
    "lex_fchar": (
        "Error en el literal de carácter{q0?}",
        "No pasó la comprobación léxica: revisa la sintaxis del literal de carácter "
        "(r'x', secuencias de escape, exactamente un carácter).",
        "",
    ),
    "lex_float": (
        "Error en el literal de coma flotante{q0?}",
        "No pasó la comprobación léxica: revisa la sintaxis del literal de coma flotante — "
        "dígitos, punto, exponente (p. ej. 1.5, 1e3).",
        "defina a = 1.5      // correcto\ndefina b = 1e3      // correcto\n// defina c = 1.    // error: tras el punto hacen falta dígitos",
    ),
    "lex_float128": (
        "Error en el literal float128{q0?}",
        "No pasó la comprobación léxica: revisa la sintaxis del literal Float128 "
        "(sufijo y dígitos).",
        "",
    ),
}
