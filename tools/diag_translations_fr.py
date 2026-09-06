# -*- coding: utf-8 -*-
"""Traductions de diagnostic en français (table incrémentale, recommandation E3 : chaîne
de génération paramétrée).

Pour tools/gen_full_errors.py --lang fr, qui génère zhc/lang-packs/fr/errors.toml.
Les entrées sont isomorphes à CURATED en zh : {DiagKind: (modèle de message, conseil
pédagogique, exemple de réparation)}.

Incrémental : seuls les codes **traduits** figurent (depuis 2026-09-06 : Top-50 des
erreurs fréquentes de débutants). Les codes non traduits dégradent élégamment à
l'exécution (texte original du compilateur officiel, pas de panique) ; la table peut
donc s'étendre à tout moment et se régénérer avec `--lang fr`.
Les exemples de réparation utilisent des mots du dialecte fr (soit=let / variable=var /
si=if / sinon=else / afficher=println / principal=main / Entier=Int64 / Chaine=String /
Booleen=Bool / Reel=Float64 / Tableau=Array / Option=Option / PasDeValeur=None, voir les
listes de mots sous lang-packs/fr/).
"""

FR = {
    "sema_mismatched_types": (
        "Les types ne correspondent pas",
        "Vérifiez les types des deux côtés de la déclaration et de l'affectation. Si une "
        "conversion est nécessaire, utilisez `comme` (as) — Cangjie ne convertit pas les "
        "types automatiquement.",
        "variable entier : Entier = 1\n"
        "variable texte : Chaine = \"1\"\n"
        "// les deux côtés doivent avoir le même type",
    ),
    "package_search_error": (
        "Paquet `{q0}` introuvable",
        "Vérifiez la déclaration de dépendances dans cjpm.toml ou exécutez l'installation "
        "du paquet.",
        "",
    ),
    "chir_dce_unused_variable": (
        "La variable `{q0}` n'est jamais utilisée",
        "Les déclarations inutilisées génèrent un avertissement du compilateur. Supprimez-la "
        "ou cherchez une faute de frappe (p. ex. une autre variable nommée par erreur).",
        "soit inutilisee : Chaine = \"bonjour\"\n"
        "// option 1 : supprimer la ligne\n"
        "// option 2 : l'utiliser\n"
        "afficher(inutilisee)",
    ),
    "lex_unrecognized_escape": (
        "Séquence d'échappement inconnue `{q0}`",
        "La séquence `\\q` n'est pas prise en charge. Cangjie connaît `\\n` (saut de ligne), "
        "`\\t` (tabulation), `\\\\`, `\\\"`, `\\uXXXX` (Unicode), etc.",
        "afficher(\"première ligne\\nseconde ligne\")  // \\n est le saut de ligne",
    ),
    "parse_expected_character": (
        "Attendu : `{q0}`",
        "Syntaxe incomplète : vérifiez s'il manque une parenthèse, un point-virgule ou un "
        "mot clé sur cette ligne.",
        "",
    ),
    "parse_expected_right_delimiter": (
        "Délimiteur `{q0}` non fermé",
        "Les parenthèses doivent se fermer par paires : vérifiez l'imbrication — à chaque "
        "`(`/`[`/`{` correspond une `)`/`]`/`}`.",
        "si (a > 0) {\n    afficher(a)\n}  // à chaque `{` correspond une `}`",
    ),
    "sema_cannot_assign_to_immutable": (
        "Affectation à une valeur immuable impossible",
        "Une liaison `soit` est immuable une fois créée. Pour réaffecter, utilisez `variable`.",
        "soit x = 1\n// x = 2  // erreur : soit est immuable\nvariable y = 1\ny = 2  // correct",
    ),
    "sema_exceed_num_value_range": (
        "Le nombre `{q0}` dépasse l'intervalle du type `{q1}`",
        "Le littéral sort de l'intervalle du type cible : prenez un type plus grand ou "
        "calculez la valeur à l'exécution.",
        "",
    ),
    "sema_generic_type_without_type_argument": (
        "Type générique sans paramètre de type",
        "Les types génériques exigent un paramètre de type : `Tableau<Entier>`, "
        "`Option<Chaine>`, etc.",
        "soit liste : Tableau<Entier> = Tableau<Entier>()\nsoit valeur : Option<Chaine> = PasDeValeur",
    ),
    "sema_missing_entry": (
        "Point d'entrée `{q0}` manquant",
        "Un programme exécutable nécessite `principal()` : une seule fois par projet ; "
        "paramètres et type de retour par défaut.",
        "principal() {\n    afficher(\"Bonjour, Cangjie !\")\n}",
    ),
    "sema_redefinition": (
        "Déclaration dupliquée `{q0}`",
        "Un nom ne peut être déclaré qu'une fois dans la même portée : cherchez les doublons "
        "ou les conflits avec des identifiants importés (renommez ou supprimez la "
        "déclaration superflue).",
        "",
    ),
    "sema_undeclared_identifier": (
        "Identifiant non déclaré `{q0}`",
        "Un nom indéfini a été utilisé : vérifiez l'orthographe ; les variables doivent être "
        "déclarées avant usage ; les noms d'un bloc `{}` ne sont visibles qu'à l'intérieur.",
        "principal() {\n    soit nom = \"Cangjie\"\n    afficher(nom)  // déclarer d'abord, utiliser ensuite\n}",
    ),
    "sema_undeclared_type_name": (
        "Nom de type non déclaré `{q0}`",
        "Un type doit être déclaré ou importé : vérifiez l'orthographe ; définissez vos "
        "types avant ; les types de la bibliothèque standard exigent l'import du module.",
        "",
    ),
    "sema_wrong_number_of_arguments": (
        "Le nombre d'arguments de l'appel ne correspond pas : `{q0}`",
        "Le nombre d'arguments doit correspondre à la liste des paramètres : comptez-les à "
        "l'appel — manquants et excédentaires sont des erreurs.",
        "",
    ),
    "chir_annotation_not_applicable": (
        "Annotation inapplicable ici{q0?}",
        "Échec de la vérification statique : cherchez les problèmes cachés "
        "(inutilisé, inaccessible, débordement, non initialisé).",
        "",
    ),
    "chir_arithmetic_operator_overflow": (
        "Débordement dans l'opération arithmétique{q0?}",
        "Échec de la vérification statique : le débordement est déjà détectable avant "
        "l'exécution. Prenez un type plus grand ou vérifiez les valeurs.",
        "",
    ),
    "chir_cannot_assign_initialized_let_variable": (
        "Affectation à une variable soit déjà initialisée impossible{q0?}",
        "Échec de la vérification statique : `soit` n'admet pas de réaffectation — utilisez "
        "`variable`.",
        "",
    ),
    "chir_class_uninitialized_field": (
        "Champ de classe non initialisé{q0?}",
        "Échec de la vérification statique : les champs d'une classe doivent être "
        "initialisés dans le constructeur (initialiser) ou à la déclaration.",
        "",
    ),
    "chir_dce_unused_expression": (
        "Expression inutilisée{q0?}",
        "Échec de la vérification statique : la valeur de l'expression n'est utilisée nulle "
        "part — affectez-la ou supprimez-la.",
        "",
    ),
    "chir_dce_unused_function": (
        "Fonction inutilisée{q0?}",
        "Échec de la vérification statique : la fonction n'est jamais appelée. Supprimez-la "
        "ou conservez-la comme partie de l'API publique.",
        "",
    ),
    "chir_dce_unused_function_main": (
        "Fonction inutilisée (point d'entrée){q0?}",
        "Échec de la vérification statique : le point d'entrée est marqué comme inutilisé — "
        "vérifiez que `principal()` n'apparaît qu'une fois dans le projet.",
        "",
    ),
    "chir_dce_unused_operator": (
        "Opération inutilisée{q0?}",
        "Échec de la vérification statique : le résultat de l'opération n'est utilisé nulle part.",
        "",
    ),
    "chir_divisor_is_zero": (
        "Division par zéro{q0?}",
        "Échec de la vérification statique : division par une constante sûrement nulle. "
        "Vérifiez le diviseur avant de diviser.",
        "si (d != 0) {\n    afficher(a / d)\n}",
    ),
    "chir_file_might_circular_dependency": (
        "Dépendance circulaire de fichiers possible{q0?}",
        "Échec de la vérification statique : les fichiers dépendent les uns des autres en "
        "anneau — restructurez les imports et cassez le cycle.",
        "",
    ),
    "chir_idx_out_of_bounds": (
        "Index hors limites{q0?}",
        "Échec de la vérification statique : l'index est sûrement hors de la collection. "
        "Vérifiez les limites avant d'accéder.",
        "",
    ),
    "chir_illegal_usage_of_member": (
        "Usage illégal d'un membre{q0?}",
        "Échec de la vérification statique : ce membre ne peut pas être utilisé dans ce "
        "contexte (visibilité ou récepteur inadaptés).",
        "",
    ),
    "chir_illegal_usage_of_super_member": (
        "Usage illégal d'un membre de la superclasse{q0?}",
        "Échec de la vérification statique : le membre de la classe parente ne peut pas être "
        "invoqué ici (non redéfini ou privé).",
        "",
    ),
    "chir_shift_length_overflow": (
        "Décalage en débordement{q0?}",
        "Échec de la vérification statique : la longueur de décalage dépasse la largeur en "
        "bits de l'opérande.",
        "",
    ),
    "chir_step_non_zero_range": (
        "Le pas de l'intervalle doit être non nul{q0?}",
        "Échec de la vérification statique : un pas nul produirait une boucle infinie. "
        "Utilisez un pas non nul.",
        "",
    ),
    "chir_typecast_overflow": (
        "Débordement à la conversion de type{q0?}",
        "Échec de la vérification statique : la conversion perd des données de façon "
        "démontrable. Prenez un type plus grand ou vérifiez la valeur.",
        "",
    ),
    "chir_unreachable_pattern": (
        "Motif inaccessible{q0?}",
        "Échec de la vérification statique : un motif antérieur couvre déjà ce cas — "
        "réorganisez ou supprimez.",
        "",
    ),
    "chir_used_before_initialization": (
        "Usage avant initialisation{q0?}",
        "Échec de la vérification statique : la variable est lue avant d'avoir reçu une "
        "valeur. Initialisez à la déclaration ou réorganisez le code.",
        "",
    ),
    "chir_var_might_circular_dependency": (
        "Dépendance circulaire de variables possible{q0?}",
        "Échec de la vérification statique : l'initialiseur de la variable se réfère à "
        "elle-même, directement ou indirectement.",
        "",
    ),
    "lex_cannot_start_with_digit": (
        "L'identifiant ne peut pas commencer par un chiffre{q0?}",
        "Les identifiants commencent par une lettre ou un tiret bas ; les chiffres ne sont "
        "autorisés qu'à partir du deuxième caractère.",
        "soit valeur2 = 2   // correct\n// soit 2valeur = 2  // erreur : ne pas commencer par un chiffre",
    ),
    "lex_characters_overflow": (
        "Nombre de caractères dépassé{q0?}",
        "Échec de la vérification lexicale : le littéral dépasse la longueur maximale.",
        "",
    ),
    "lex_expected_back_quote": (
        "Accent grave attendu{q0?}",
        "Échec de la vérification lexicale : les identifiants bruts se mettent entre accents "
        "graves — ajoutez l'accent `` ` `` fermant.",
        "",
    ),
    "lex_expected_character": (
        "Caractère attendu{q0?}",
        "Échec de la vérification lexicale : à cette position le compilateur attend un "
        "caractère précis.",
        "",
    ),
    "lex_expected_character_in_char_literal": (
        "Caractère attendu dans le littéral de caractère{q0?}",
        "Échec de la vérification lexicale : un littéral de caractère (r'x') contient "
        "exactement un caractère entre les guillemets.",
        "soit c = r'A'  // exactement un caractère",
    ),
    "lex_expected_digit": (
        "Chiffre attendu{q0?}",
        "Échec de la vérification lexicale : un chiffre est requis ici (littéral numérique "
        "ou séquence d'échappement).",
        "",
    ),
    "lex_expected_exponent_part": (
        "Exposant attendu{q0?}",
        "Échec de la vérification lexicale : après `e` dans un littéral flottant doit venir "
        "l'exposant (p. ex. 1e3, 1.5e-2).",
        "",
    ),
    "lex_expected_identifier": (
        "Identifiant attendu{q0?}",
        "Échec de la vérification lexicale : un nom était attendu ici — vérifiez s'il manque "
        "un nom de variable/paramètre ou si un mot réservé a été utilisé.",
        "",
    ),
    "lex_expected_identifier_after_dollar": (
        "Identifiant attendu après le dollar{q0?}",
        "Échec de la vérification lexicale : après `$` doit venir un identifiant.",
        "",
    ),
    "lex_expected_left_bracket": (
        "Crochet ouvrant attendu{q0?}",
        "Échec de la vérification lexicale : `[` attendu ici (littéral de tableau ou accès "
        "par index).",
        "",
    ),
    "lex_expected_letter_after_underscore": (
        "Lettre attendue après le tiret bas{q0?}",
        "Échec de la vérification lexicale : un identifiant ne peut pas être uniquement un "
        "tiret bas sans lettres.",
        "",
    ),
    "lex_expected_quote_in_raw_string": (
        "Guillemet attendu dans la chaîne brute{q0?}",
        "Échec de la vérification lexicale : à la chaîne brute (p. ex. `#\"...\"#`) il "
        "manque le guillemet fermant comme délimiteur.",
        "",
    ),
    "lex_expected_right_bracket": (
        "Crochet fermant attendu{q0?}",
        "Échec de la vérification lexicale : `[` doit se fermer avec `]`.",
        "",
    ),
    "lex_expected_right_bracket_or_hexadecimal": (
        "Crochet fermant ou chiffres hexadécimaux attendus{q0?}",
        "Échec de la vérification lexicale : la séquence d'échappement `\\u` exige 1 à 6 "
        "chiffres hexadécimaux et un `]` fermant — p. ex. `\\u{4e2d}`.",
        "",
    ),
    "lex_fchar": (
        "Erreur dans le littéral de caractère{q0?}",
        "Échec de la vérification lexicale : vérifiez la syntaxe du littéral de caractère "
        "(r'x', séquences d'échappement, exactement un caractère).",
        "",
    ),
    "lex_float": (
        "Erreur dans le littéral flottant{q0?}",
        "Échec de la vérification lexicale : vérifiez la syntaxe du littéral flottant — "
        "chiffres, point, exposant (p. ex. 1.5, 1e3).",
        "soit a = 1.5      // correct\nsoit b = 1e3      // correct\n// soit c = 1.    // erreur : des chiffres sont requis après le point",
    ),
    "lex_float128": (
        "Erreur dans le littéral float128{q0?}",
        "Échec de la vérification lexicale : vérifiez la syntaxe du littéral Float128 "
        "(suffixe et chiffres).",
        "",
    ),
}

# ── Table des messages de repli (recommandation E4) : clé = texte officiel du message
# (isomorphe à MESSAGES de zh ; la clé n'est pas traduite — comparaison avec le texte de cjc).
MSG_FR = [
    ("expected '", "Attendu : `{q0}`, obtenu : `{q1}`", "Les types des deux côtés ne correspondent pas : vérifiez le type déclaré et le type réel de l'expression."),
    ("can not find package '", "Paquet `{q0}` introuvable", "Le chemin d'importation n'existe pas : vérifiez l'orthographe ou que la bibliothèque est installée."),
    ("~ is immutable", "La variable `{q0}` est une liaison immuable", "Une liaison `soit` (let) ne peut pas être modifiée ; utilisez `variable` (var) si elle doit changer."),
    ("~ is never used", "`{q0}` n'est jamais utilisée", "Supprimez la déclaration inutilisée ou vérifiez l'orthographe."),
    ("not found in", "`{q1}` introuvable dans `{q0}`", "Vérifiez l'orthographe du nom et du module qui le contient."),
    ("missing argument", "Le nombre d'arguments de l'appel ne correspond pas : `{q0}`", "Le nombre d'arguments réels doit correspondre aux paramètres : manquants comme excédentaires provoquent une erreur."),
    ("unclosed delimiter", "Délimiteur `{q0}` non fermé", "Parenthèses, crochets et accolades doivent se fermer par paires : vérifiez l'imbrication et l'indentation."),
    ("redefinition of", "Déclaration dupliquée `{q0}`", "Dans une même portée, un nom ne se déclare qu'une fois : renommez ou supprimez la déclaration en trop."),
    ("undeclared type name", "Nom de type non déclaré `{q0}`", "Le type doit être déclaré ou importé : vérifiez l'orthographe et l'importation."),
    ("generic type should be used", "Type générique sans paramètre de type{q0?}", "À l'usage d'un type générique (p. ex. `Tableau`), le paramètre de type est obligatoire."),
    ("unrecognized escape", "Séquence d'échappement inconnue `{q0}`", "Cangjie prend en charge `\\n`, `\\t`, `\\\\`, `\\uXXXX`, etc. ; `\\q` et assimilés sont refusés."),
    ("~ is missing", "`{q0}` manquant", "Un nom ou point d'entrée obligatoire manque : le point d'entrée du programme est `principal()`."),
    ("unused variable", "Variable inutilisée", "Supprimez la déclaration inutilisée ou vérifiez l'orthographe."),
    ("unused import", "Importation inutilisée", "Supprimez l'importation inutilisée ou confirmez qu'elle sert réellement."),
    ("unused function", "Fonction inutilisée", "Supprimez la fonction inutilisée ou vérifiez l'orthographe au site d'appel."),
    ("this warning can be suppressed by setting the compiler option",
     "Cet avertissement peut être désactivé par l'option de compilation `{q0}`",
     "Conservez l'avertissement ou corrigez le code selon l'indice ; l'option du compilateur reste le dernier recours."),
    ("this error can be suppressed by setting the compiler option",
     "Cette erreur peut être désactivée par l'option de compilation `{q0}`",
     "Corrigez le code selon l'indice pour éliminer l'erreur ; l'option du compilateur n'est qu'un dernier recours."),
    ("following constraints for type variable", "Contraintes de la variable de type `{q0}` insolubles", "Vérifiez que les paramètres du type générique satisfont les contraintes déclarées."),
    ("constraint '", "La contrainte `{q0}` pourrait provenir de", "Indice en cas d'échec d'inférence générique : comparez le type réel des arguments à l'appel."),
    ("may come from", "Pourrait provenir de `{q0}`", "Indice en cas d'échec d'inférence générique : vérifiez les annotations de type des déclarations concernées."),
]
