# -*- coding: utf-8 -*-
"""生成 zhc/lang-packs/zh/errors.toml 全集（诊断码 644 条 + 消息翻译 12 条）。

数据来源：
  - 官方 DiagKind 全集：自 cjc 1.0.5 二进制 strings 提取（644 条，见 FULL_KINDS）
  - 中文翻译：tools/diag_translations.py + tools/diag_translations2.py
  - 精翻条目（CURATED）：人工打磨的 14 条（模板含 {q0} 引号提取 + 教学提示 + 修复示例）
  - 自动条目：模板 = 「中文翻译{q0?}」（{q0?} 可选动态值：从官方消息提取关键名/类型，
    有值显示为反引号包裹，无值纯翻译——全中文输出，无英文残留，见设计 §13.1 第 47 条）

用法：python3 tools/gen_full_errors.py [--lang zh|ru] [--out 路径]
  - zh（默认）：全集式——翻译表与官方 DiagKind 全集必须一一对应（缺失/多余均报错）；
  - ru：增量式——只收录 tools/diag_translations_ru.py 已翻译的码（建议 E3），
    缺翻译的码运行时走优雅回退，不硬报错；
  - --out：输出到指定路径（供验收防漂移 diff，不指定则写语言包目录）。
"""
import argparse
import json
import sys

from diag_translations import SEMA
from diag_translations2 import PARSE, LEX, CHIR
from diag_translations_ru import RU, MSG_RU
from diag_translations_ja import JA, MSG_JA
from diag_translations_de import DE, MSG_DE
from diag_translations_es import ES, MSG_ES
from diag_translations_fr import FR, MSG_FR
from diag_translations_ko import KO, MSG_KO

# 官方 DiagKind 全集（cjc 1.0.5 二进制提取，每行 20 个）
FULL_KINDS = """
chir_annotation_not_applicable chir_arithmetic_operator_overflow chir_cannot_assign_initialized_let_variable chir_class_uninitialized_field chir_dce_unreachable chir_dce_unreachable_block chir_dce_unreachable_block_in_expression chir_dce_unreachable_expression chir_dce_unreachable_expression_hint chir_dce_unreachable_function chir_dce_unreachable_if chir_dce_unreachable_return chir_dce_unreachable_statement chir_dce_unused_expression chir_dce_unused_function chir_dce_unused_function_main chir_dce_unused_operator chir_dce_unused_variable chir_diag_begin chir_diag_end
chir_divisor_is_zero chir_eval_support chir_file_might_circular_dependency chir_idx_out_of_bounds chir_illegal_usage_of_member chir_illegal_usage_of_super_member chir_sancov_illegal_usage_of_level chir_sancov_illegal_usage_of_pc_table chir_shift_length_overflow chir_step_non_zero_range chir_typecast_overflow chir_unreachable_pattern chir_used_before_initialization chir_var_might_circular_dependency lex_cannot_start_with_digit lex_characters_overflow lex_diag_begin lex_diag_end lex_expected_back_quote lex_expected_character
lex_expected_character_in_char_literal lex_expected_digit lex_expected_exponent_part lex_expected_identifier lex_expected_identifier_after_dollar lex_expected_left_bracket lex_expected_letter_after_underscore lex_expected_quote_in_raw_string lex_expected_right_bracket lex_expected_right_bracket_or_hexadecimal lex_fchar lex_float lex_float128 lex_illegal_float_suffix lex_illegal_integer_suffix lex_illegal_non_decimal_float lex_illegal_uni_character_literal lex_illegal_unicode lex_multiline_string_start_from_newline lex_too_many_digits
lex_unexpected_decimal_point lex_unexpected_digit lex_unexpected_exponent_part lex_unknown_start_of_token lex_unknown_suffix lex_unrecognized_char_in_binary_string lex_unrecognized_escape lex_unrecognized_symbol lex_unsecure_unicode lex_unterminated_block_comment lex_unterminated_char_literal lex_unterminated_interpolation lex_unterminated_multi_line_string lex_unterminated_raw_string lex_unterminated_single_line_string parse_abstract_func_must_have_return_type parse_all_parameters_must_be_named parse_cannot_have_assi_in_init parse_cannot_operator_a_tuple parse_case_body_cannot_be_empty
parse_chained_none_associative parse_conflict_modifier parse_const_expected_initializer parse_decl_cannot_inherit_their_self parse_deprecated_argument_duplication parse_deprecated_arguments_must_be_lit_const_expr parse_deprecated_empty_string_argument parse_deprecated_invalid_target parse_deprecated_unknown_argument parse_deprecated_wrong_argument parse_diag_begin parse_diag_end parse_diag_error parse_diag_warning parse_duplicated_annotation parse_duplicated_attr_value parse_duplicated_get_or_set parse_duplicated_intrinsic_function parse_duplicated_item parse_duplicated_step_op
parse_duplicate_modifier parse_duplicate_type_parameter_name parse_empty_attribute parse_empty_string_interpolation parse_expected_arrow_in_func_type parse_expected_assignment parse_expected_backarrow_in_let_cond parse_expected_case parse_expected_catch_or_finally_in_try parse_expected_ccd_in_lambda parse_expected_character parse_expected_character_after parse_expected_colon_in_catch_pattern parse_expected_decl parse_expected_dot_lparen parse_expected_double_arrow_in_case parse_expected_double_arrow_in_lambda parse_expected_expression parse_expected_expr_or_decl_in parse_expected_get_or_set_in_prop
parse_expected_identifier_lp parse_expected_if_let_andand parse_expected_import parse_expected_in_forin_expression parse_expected_left_angle_after parse_expected_left_brace parse_expected_left_paren parse_expected_left_paren_after parse_expected_literal parse_expected_lsquare_after parse_expected_lt_brace parse_expected_lt_paren parse_expected_macro_decl_define_in_macro_package parse_expected_macro_decl_in_macro_package parse_expected_module_name parse_expected_name parse_expected_no_arguments_in_spawn parse_expected_no_modifier parse_expected_no_newline_after parse_expected_one_of_identifier_or_pattern
parse_expected_one_of_type_or_initializer parse_expected_operator_or_end parse_expected_parameter_rp parse_expected_paren_or_brace_after_try parse_expected_parentheses parse_expected_pattern parse_expected_public_before_macro_decl parse_expected_right_delimiter parse_expected_static_for_const_member_var parse_expected_type parse_expected_type_argument parse_expected_type_or_init_in_pattern parse_expected_where_brace parse_expected_while_in_do_while parse_expected_wildcard_or_exception_pattern parse_expect_escape_dollar_token parse_expect_integer_literal_varray parse_finalizer_can_not_accept_any_parameter parse_foreign_func_must_declare_return_type parse_foreign_func_should_not_be_generic
parse_foreign_function_with_body parse_getter_setter_cannot_be_generic parse_ifavailable_arg_no_name parse_ifavailable_not_lambda parse_illegal_declaration_pattern parse_illegal_function_name parse_illegal_macro_expand_attr_args parse_illegal_macro_expand_input_args parse_illegal_macro_expand_input_args_without_paren parse_illegal_macro_expand_input_without_paren_in_paramlist parse_illegal_modifier_in_scope parse_illegal_or_pattern parse_importing_by_package_name_is_not_supported parse_intrinsic_function_cannot_have_body parse_intrinsic_function_must_be_toplevel parse_invalid_incre_expr parse_invalid_left_hand_expr parse_invalid_overloaded_operator parse_invalid_quote_dollar_expr parse_invalid_step_op
parse_invalid_super_declaration parse_invalid_unicode_scalar parse_macro_call_illegal_with_builtin parse_macro_define_conflicted_with_builtin parse_macro_expected_right_parameter_nums parse_macro_illegal_named_param parse_macro_illegal_param_type parse_macro_illegal_ret_type parse_macro_unexpected_empty_parameter parse_member_parameter_after_regular parse_missing_body parse_named_parameter_after_unnamed parse_newline_not_allowed_between_quest_and_type parse_newline_not_allowed_between_spawn_and_argument parse_nl_warning parse_only_tuple_and_func_type_allow_type_parameter_name parse_package_as_all parse_package_name_has_backtick parse_package_name_length_overflow parse_query
parse_query_diag_begin parse_query_diag_end parse_query_expected_hash_id_compare_operator parse_query_expected_logic_symbol parse_query_expected_position_compare_operator parse_query_expected_query_symbol parse_query_hashid_illegal_fieldid parse_query_hashid_illegal_file_hash parse_query_invalid_query_value parse_query_position_comma_required parse_query_position_illegal_column_num parse_query_position_illegal_file_id parse_query_position_illegal_line_num parse_redefined_resource_name parse_redundant_arrow_after_func_type parse_redundant_modifier parse_selector_or_match_expression_body parse_setter_can_only_accept_one_parameter parse_setter_must_contain_one_parameter parse_static_init_can_not_accept_any_parameter
parse_this_type_not_allow parse_trailing_closure_only_follow_name parse_tuple_pattern_expected_more_field parse_type_pattern_in_let_cond parse_unexpected_anno_on parse_unexpected_colon_in_range parse_unexpected_const_modifier_on_variable parse_unexpected_declaration_in_scope parse_unexpected_expected_found parse_unexpected_lambda_expr_in_toplevel parse_unexpected_line_break parse_unexpected_newline_between_at_and_mc parse_unexpected_overflow_annotation parse_unexpected_tuple_decl_type parse_unexpected_type_in parse_unexpected_where parse_unknown_enum_constructor parse_unmatched_right_delimiter parse_unrecognized_attr_in_anno parse_unrecognized_expression_in_when
parse_unrecognized_token_after_macro_node parse_unsafe_will_be_ignored parse_variable_length_parameter_can_not_be_first parse_variable_length_parameter_must_in_the_end parse_variable_length_parameter_only_in_the_foreign_function parse_var_must_be_initialized parse_varray_type_args_mismatch parse_varray_type_parameter parse_varray_with_paren parse_wildcard_can_not_be_used_as_member_name sema_abstract_class_can_not_be_instantiated sema_abstract_method_cannot_be_accessed_directly sema_accessibility sema_accessibility_with_main_hint sema_ambiguous_arg_type sema_ambiguous_constructor_match sema_ambiguous_expo_right_operand_type sema_ambiguous_func_ref sema_ambiguous_match sema_ambiguous_match_primitive_extend
sema_ambiguous_use sema_annotation_arg_target sema_annotation_arg_target_array_lit sema_annotation_calling_conv_not_support sema_annotation_custom_place sema_annotation_error_arg_num sema_annotation_error_arg_range sema_annotation_error_object sema_annotation_invalid_args_type sema_annotation_no_const_init sema_annotation_non_public sema_apilevel_missing_arg sema_apilevel_multi_anno sema_apilevel_multi_diff_syscap sema_apilevel_ref_higher sema_apilevel_syscap_error sema_apilevel_syscap_warning sema_arithmetical_op_overflow sema_array_element_type_error sema_array_expression_param_type_error
sema_array_expression_type_error sema_array_first_arg_cannot_be_named sema_array_second_arg_cannot_be_named sema_array_second_wrong_named_arg sema_array_single_element_type_error sema_array_size_type_error sema_array_too_much_argument sema_assignment_of_member_variable_cannot_use_this_or_super sema_br sema_builtin_index_in_bound sema_builtin_invalid_index sema_cannot_assign_to_immutable sema_cannot_assign_to_subscript sema_cannot_convert_literal sema_cannot_currying sema_cannot_define_var_in_const_funciton sema_cannot_have_default_param sema_cannot_have_parameter sema_cannot_inherit_sealed sema_cannot_instantiated_by_incomplete_type
sema_cannot_modify_var sema_cannot_override sema_cannot_ref_to_pkg_name sema_capture_before_initialization sema_capture_has_shadow_variable sema_capture_this_or_instance_field_in_func sema_cffi_cannot_have_type_param sema_cfunc_cannot_capture_this sema_cfunc_cannot_capture_var sema_cfunc_cannot_have_named_args sema_cfunc_cannot_have_unit_args sema_cfunc_ctor_must_be_cpointer sema_cfunc_too_many_arguments sema_cfunc_type sema_cfunc_var_cannot_have_var_param sema_class_const_init_with_var sema_class_inherit_non_class_nor_interface sema_class_need_abstract_modifier_or_func_need_impl sema_class_uninitialized_field sema_conflict_with_sub_package
sema_core_object_not_found_when_no_prelude sema_cstruct_cannot_autobox sema_cstruct_cannot_have_unit_fields sema_cstruct_cannot_impl_interfaces sema_c_type_cannot_extend_interface sema_c_type_cannot_implement_interface sema_deprecated_error sema_deprecated_warning sema_deprecation_override_error sema_deprecation_override_warning sema_deprecation_redef_error sema_deprecation_redef_warning sema_deprecation_weakening sema_diag_begin sema_diag_end sema_diag_report_error_message sema_diag_report_note_message sema_different_or_pattern sema_div_zero sema_duplicated_item_in_enum
sema_enum_constructor_type_not_match sema_enum_constructor_with_param_must_have_args sema_enum_pattern_func_cty_error sema_enum_pattern_func_param_cty_error sema_enum_pattern_param_size_error sema_exceed_float_literal_range sema_exceed_num_value_range sema_except_catch_type_error sema_expand_macro_redefinition sema_expect_const sema_export_extend_depend_non_export_extend sema_export_same_private_decl sema_expr_in_forin_must_has_iterator sema_extend_check_sequence_cannot_decide sema_extend_duplicate_interface sema_extend_function_cannot_overridden sema_extend_generic_must_be_used sema_extend_illegal_member sema_extend_member_cannot_shadow sema_extend_not_interface
sema_extend_use_super sema_fail_flow_expr_operand_has_named_param sema_finalizer_forbidden_in_class sema_float_literal_too_large sema_float_literal_too_small sema_flow_expressions_use_this_or_super sema_forbid_generic_constructor sema_forbid_generic_finalizer sema_forbid_generic_nonstatic_method sema_forin_pattern_must_be_irrefutable sema_found_candidate_decl sema_found_possible_candidate_decl sema_func_capture_var_cannot_assign sema_func_capture_var_cannot_expr sema_func_capture_var_cannot_param sema_func_capture_var_cannot_return sema_func_capture_var_not_ctype sema_func_no_override_or_redefine_modifier sema_generic_ambiguous_method_match_in_upper_bounds sema_generic_argument_no_match sema_generic_constraint_not_looser
sema_generic_func_without_type_arg sema_generic_infinite_instantiation sema_generic_in_operator_overload sema_generic_instantiation_causes_ambiguous_functions sema_generic_member_type_argument_different sema_generic_no_member_match_in_upper_bounds sema_generic_no_method_match_in_upper_bounds sema_generic_param_directly_recursive sema_generic_param_exist_in_class_irrelevant_upperbound_recursively sema_generics_type_variable_not_defined sema_generic_type_argument_not_match_constraint sema_generic_type_inconsistent sema_generic_type_without_type_argument sema_global_var_used_before_initialization sema_ifavailable_arg_no_name sema_ifavailable_arg_not_literal sema_ifavailable_level_limit sema_ifavailable_unknow_arg_name sema_ignore_open sema_illegal_access_inner_classlike
sema_illegal_access_interface_field sema_illegal_access_non_static_member sema_illegal_capture_this sema_illegal_cpointer_generic_type sema_illegal_ctype_generic_argument sema_illegal_ctype_member sema_illegal_extended_type sema_illegal_member_of_cstruct sema_illegal_member_used_in_open_constructor sema_illegal_multi_inheritance sema_illegal_place_of_calling_this_or_super sema_illegal_place_of_calling_this_primary_constructor sema_illegal_scope_use_of_annotation sema_illegal_super_alone sema_illegal_this_in_interface sema_illegal_this_outside_struct_constructor sema_illegal_usage_of_member sema_illegal_usage_of_super_member sema_illegal_use_of_annotation sema_immutable_access_mutable_func
sema_immutable_function_cannot_access_mutable_function sema_immutable_property_with_setter sema_immutable_type_extend_assignment_index_operator sema_immutable_type_illegal_property sema_import_not_in_current_module sema_incompatible_expo_target_type sema_incompatible_func_body_and_return_type sema_incompatible_mut_modifier_between_struct_and_interface sema_inherit_abstract_class_static_unimplement_func sema_inheritance_cycle sema_inheritance_non_ref_type sema_inherit_duplicate_interface sema_inherit_member_kind_inconsistent sema_inherit_member_type_inconsistent sema_inherit_not_return_this sema_inherit_super_member_kind_inconsistent sema_inherit_thread_context_invalid sema_inherit_thread_context_not_open sema_inout_can_only_used_in_cfunc_calling sema_inout_mismatch
sema_inout_modify_cstring_or_zerosized sema_inout_modify_heap_variable sema_inout_modify_non_ctype sema_inout_must_be_var_variable sema_instance_func_cannot_be_used_in_finalizer sema_interface_call_with_unimplemented_call sema_interface_can_not_be_instantiated sema_interface_inherit_non_interface sema_interface_is_not_extendable sema_interface_is_not_implementable sema_interface_is_not_inheritable sema_interface_member_must_be_implemented sema_interface_member_must_be_implemented_in_struct sema_interpolation_in_const_pattern sema_invalid_access_control sema_invalid_access_function sema_invalid_assignment_to_this_expr sema_invalid_binary_expr sema_invalid_called_object sema_invalid_cfunc_arg_type
sema_invalid_cfunc_return_type sema_invalid_coalescing sema_invalid_constructor_in_enum sema_invalid_enum_member_access sema_invalid_field_expose_access sema_invalid_file_hash sema_invalid_intrinsic_decl sema_invalid_loop_control sema_invalid_member_visibility_in_class sema_invalid_mut_modifier_extend_of_struct sema_invalid_named_arguments sema_invalid_node_after_check sema_invalid_override_member_in_class sema_invalid_override_or_redefine_member_in_interface sema_invalid_position_of_this_type sema_invalid_return sema_invalid_return_in_static_init sema_invalid_return_value_type sema_invalid_string_implementation sema_invalid_subscript_assign_parameter
sema_invalid_subscript_assign_parameter_num sema_invalid_subscript_assign_return sema_invalid_subscript_expr sema_invalid_this_call_outside_ctor sema_invalid_tokens_implementation sema_invalid_tuple_field_ctype sema_invalid_type_param_of_enum_member_access sema_invalid_unary_expr sema_invalid_unary_expr_note sema_invalid_unary_expr_with_target sema_match_case_has_no_type sema_match_case_must_have_default sema_member_not_imported sema_member_variable_can_not_shadow sema_mismatched_type_for_pattern_in_vardecl sema_mismatched_types sema_mismatched_types_because sema_mismatched_types_multiple_assign sema_missing_entry sema_missing_func_body
sema_missing_overridden_func sema_missing_redefined_func sema_mock_disabled sema_mock_doesnt_support_mocking sema_mock_frozen_required sema_mock_not_in_test_mode sema_mock_unsupported_type sema_mock_wrong_static_decl sema_mod_zero sema_multiple_class_upperbounds sema_multiple_constructor_in_enum sema_multiple_named_argument sema_multiple_primary_constructors sema_native_var_error sema_need_member_implementation sema_need_named_argument sema_negative_shift_count sema_no_const_init sema_no_core_object sema_no_match_constructor
sema_no_match_function_declaration_for_call sema_no_match_function_declaration_for_ref sema_no_match_operator_function_call sema_non_abstract_class_cannot_be_sealed sema_nonexhuastive_patterns sema_non_generic_function_with_type_argument sema_non_inheritable_super_class sema_no_non_param_constructor_in_super_class sema_not_a_type sema_not_found_from_generic_upper_bounds sema_not_member_of sema_not_overload_in_match sema_numeric_convert_must_be_numeric sema_object_cannot_access_static_member sema_only_cfunc_can_use_annotation sema_only_literal_support sema_operator_overload_built_in_binary_operator sema_operator_overload_built_in_unary_operator sema_operator_overload_can_not_has_default_param sema_operator_overload_invalid_num_parameter
sema_optional_chain_non_optional sema_overload_conflicts sema_p sema_package_internal_decl_obtain_illegal sema_package_name_conflict sema_parameters_and_arguments_mismatch sema_param_miss_match sema_param_named_mismatched sema_pattern_can_not_be_assigned sema_pattern_literal_expected sema_pattern_not_match sema_pointer_single_element_type_error sema_pointer_too_much_argument sema_pointer_unknow_generic_type sema_previous_decl sema_privated_abstract_func_in_class sema_property_have_same_declaration_in_inherit_immut sema_property_have_same_declaration_in_inherit_mut sema_property_must_have_accessors sema_property_must_implement_both
sema_property_override_implement_type_diff sema_range_step_not_int64 sema_recursive_constructor_call sema_redefinition sema_redefinition_entry sema_redef_modify_static_func sema_ref_not_be_type sema_release_all sema_return_type_incompatible sema_return_type_invariance sema_return_unit sema_shift_count_overflow sema_spawn_arg_invalid sema_spawn_arg_no_effect sema_static_and_non_static_member_cannot_have_same_name sema_static_function_cannot_access_non_static_member sema_static_function_overload_conflicts sema_static_members_cannot_call_members sema_static_variable_cannot_access_non_static_member sema_static_variable_use_generic_parameter
sema_step_non_zero_range sema_subscript_get_set_not_supported sema_subscript_set_not_supported sema_superclass_must_be_placed_at_first sema_super_use_error_inside_non_class sema_symbol_not_collected sema_this_or_super_not_allowed_to_initialize_non_static_member sema_this_or_super_not_allowed_to_initialize_static_member sema_this_super_use_error_outside_class sema_throw_expr_with_wrong_type sema_trailing_lambda_cannot_used_for_non_function sema_tuple_cmp_not_supported sema_tuple_element_cmp_not_bool sema_tuple_pattern_not_match sema_tuple_pattern_with_correct_size_expected sema_typealias_cycle sema_typealias_external_refer_internal sema_type_cannot_extend_imported_interface sema_type_implement_non_interface sema_type_incompatible
sema_type_must_toplevel sema_type_uninitialized_static_field sema_unable_to_infer_decl sema_unable_to_infer_expr sema_unable_to_infer_generic_func sema_unable_to_infer_return_type sema_undeclared_identifier sema_undeclared_type_name sema_undefined_variable sema_unexpected_param_for_entry sema_unexpected_return_type_for_entry sema_unexpected_wrapper sema_unit_cannot_as_cfunc_arg sema_unknown_named_argument sema_unordered_arguments sema_unqualified_left_value_assigned sema_unreachable_pattern sema_unsafe_func_can_only_be_called sema_unsafe_function_invoke_failed sema_unsupport_named_argument
sema_unsupport_operator sema_unused_import sema_upper_bound_must_be_class_or_interface sema_used_before_initialization sema_use_expr_without_import sema_use_func_capture_var_alone sema_useless_exception_type sema_use_mutable_func_alone sema_use_super_in_interface sema_use_this_as_an_expression_in_func sema_v sema_value_type_recursive sema_var_in_or_condition sema_var_in_or_pattern sema_varray_args_number_mismatch sema_varray_arg_type_with_reftype sema_varray_in_cfunc sema_varray_size_match sema_varray_subscript_num sema_weak_visibility
sema_which_constraint_not_match sema_wrong_forin_guard sema_wrong_number_of_arguments
""".split()

# 精翻条目：DiagKind -> (消息模板, 教学提示, 修复示例)
CURATED = {
    "sema_mismatched_types": (
        "类型不匹配",
        "检查声明与赋值两侧类型是否一致。需要转换时使用 `作为`，仓颉不会自动做类型转换。",
        "可变 整数变量: 整数 = 1\n可变 文本变量: 字符串 = \"1\"\n// 声明与赋值两侧类型必须一致",
    ),
    "chir_dce_unused_variable": (
        "变量 `{q0}` 从未被使用",
        "未使用的声明会被编译器警告。删除它，或确认是否拼写错误（比如把名字写成了别的变量）。",
        "可变 未使用的变量: 字符串 = \"hi\"\n// 方案一：删除该行\n// 方案二：使用它\n打印行(未使用的变量)",
    ),
    "parse_expected_character": (
        "缺少 `{q0}`",
        "语法不完整：检查这一行的括号、分号或关键字是否漏写。每行语句以分号 `;` 或换行结尾。",
        "函数 甲() {\n    打印行(1)  // 语句以分号或换行结尾\n}",
    ),
    "sema_cannot_assign_to_immutable": (
        "不能给不可变值赋值",
        "`让` 绑定一旦创建就不可修改。需要修改时把 `让` 改成 `可变`。",
        "让 计数器: 整数 = 1\n// 修改值前，把 让 改为 可变：\n可变 计数器: 整数 = 1\n计数器 = 2",
    ),
    "package_search_error": (
        "找不到包 `{q0}`",
        "导入的模块不存在。先确认标准库包名（如 `标准集合`/`数学`），再检查是否安装了对应用户库。",
        "导入 标准集合.{向量}\n导入 标准库.{打印行}\n// 确认导入的路径在标准库或已安装的库中",
    ),
    "sema_undeclared_identifier": (
        "未声明的标识符 `{q0}`",
        "使用了未定义的名称：检查拼写；变量需先声明后使用；块作用域（`{}`）内声明的名字仅块内可见。",
        "函数 主() {\n    可变 总数: 整数 = 1\n    打印行(总数)  // 先声明，再使用\n}",
    ),
    "sema_undeclared_type_name": (
        "未声明的类型名 `{q0}`",
        "类型必须已声明或已导入：检查类型名拼写；自建类型需先定义；标准库类型需导入对应模块（如 `标准集合`）。",
        "导入 标准集合.{向量}\n类 我的类型 {}\n函数 甲() {\n    让 变量: 我的类型 = 我的类型()\n    让 列表: 向量<整数> = 向量<整数>()\n}",
    ),
    "sema_redefinition": (
        "重复声明 `{q0}`",
        "同一作用域内名字只能声明一次：检查是否有重复定义，或与导入的标识符冲突（改名或去掉多余声明）。",
        "让 变量 = 1\n// 让 变量 = 2  // 重复声明报错，改名：\n可变 变量2 = 2",
    ),
    "sema_generic_type_without_type_argument": (
        "泛型类型缺少类型参数",
        "泛型类型（如 `向量`/`哈希映射`/`选项`）使用时必须给出类型参数：`向量<整数>`、`选项<字符串>`。",
        "让 列表: 向量<整数> = 向量<整数>()\n让 可能值: 选项<字符串> = 无值",
    ),
    "sema_exceed_num_value_range": (
        "数字 `{q0}` 超出类型 `{q1}` 的取值范围",
        "字面量数值超出目标类型的取值范围：改用更大的类型（如 `整数` 超出时用 `无符号整数`），或改为运行时计算。",
        "让 大数: 无符号整数 = 9223372036854775808",
    ),
    "parse_expected_right_delimiter": (
        "未闭合的分隔符 `{q0}`",
        "括号/方括号/花括号必须成对闭合：检查嵌套与缩进，每打开一个 `(`/`[`/`{` 都要有对应的 `)`/`]`/`}`。",
        "函数 甲() {\n    打印行(1)\n}  // 括号成对",
    ),
    "lex_unrecognized_escape": (
        "无法识别的转义 `{q0}`",
        "字符串转义序列不支持 `\\q`：仓颉支持 `\\n`（换行）、`\\t`（制表）、`\\\\`、`\\\"`、`\\uXXXX`（Unicode）等。",
        "打印行(\"第一行\\n第二行\")  // 换行用 \\n",
    ),
    "sema_missing_entry": (
        "缺少程序入口 `{q0}`",
        "可执行程序必须提供入口 `主函数()`：每个工程有且只有一个 `主函数()`，参数与返回类型保持默认。",
        "主函数() {\n    打印行(\"你好，仓颉！\")\n}",
    ),
    "sema_wrong_number_of_arguments": (
        "调用参数数量不匹配：`{q0}`",
        "实参个数必须与形参个数一致：数一数调用处的参数，缺失或多余都会报错。",
        "函数 甲(参数: 整数) {}\n甲(1)  // 实参 1 个，形参 1 个，匹配",
    ),
}

# 自动条目类别兜底教学提示
TIPS = {
    "sema": "语义检查未通过：核对类型、名称、作用域与修饰符是否符合语言规则。若提示中的名称不是期望的，请检查拼写与导入。",
    "parse": "语法检查未通过：检查此处的拼写、分隔符与语句结构是否完整（括号、分号、关键字）。",
    "lex": "词法检查未通过：检查此处的字符、字符串、数字与转义写法是否符合规则。",
    "chir": "静态检查未通过：检查代码中的潜在问题（未使用、不可达、溢出、未初始化等）。",
}

# 修复示例补充（建议 D1）：实战命中码（tools/diag-cases + ZHC_DIAG_STATS 聚合）
# 中，尚未进入 CURATED 精翻的自动条目 → 补「修复示例」（方言可粘贴代码）。
# 维护规则：码已在 CURATED 时把条目升级进 CURATED 而非在此重复；码不在
# 官方全集时会报错（与翻译表同级的完整性校验）。
FIX_EXAMPLES = {
    "chir_idx_out_of_bounds": (
        "让 甲 = [1, 2, 3]\n打印行(\"${甲[0]}\")    // 合法下标范围 0..甲.长度-1\n// 甲[5] 越界：下标必须在 0..长度-1 内，用 甲.长度 检查边界"
    ),
    "parse_invalid_overloaded_operator": (
        "// += 不允许直接重载；重载 + 后 a += b 自动展开为 a = a + b\n公开 运算符 函数 +(其他: 计数): 计数 { ... }\n可变 甲 = 计数(10)\n甲 += 计数(5)    // 自动展开（需可变绑定）"
    ),
    "parse_unexpected_declaration_in_scope": (
        "扩展 整数 {\n    // 扩展只能加函数/属性访问器/运算符，不能加存储字段：\n    公开 函数 加倍(): 整数 { 返回 本对象 * 2 }\n}\n// 想加状态 → 把字段定义在类型声明里，或用类组合包一层"
    ),
    "sema_invalid_binary_expr": (
        "// != 不自动取反：== 与 != 都需显式声明（或 @派生(相等) 一键生成）\n公开 运算符 函数 ==(其他: 向量): 布尔 { ... }\n公开 运算符 函数 !=(其他: 向量): 布尔 { 返回 !(本对象 == 其他) }"
    ),
}

# 消息翻译键：(键, 消息模板, 教学提示)
MESSAGES = [
    ("expected '", "期望 `{q0}`，实际得到 `{q1}`", "两侧类型不一致：检查声明类型与实际表达式是否匹配。"),
    ("can not find package '", "找不到包 `{q0}`", "导入路径不存在：检查拼写，或确认库已安装。"),
    ("~ is immutable", "变量 `{q0}` 是不可变绑定", "`让` 绑定不可修改，需要修改时改为 `可变`。"),
    ("~ is never used", "`{q0}` 从未被使用", "删除未使用的声明，或检查拼写。"),
    ("not found in", "在 `{q0}` 中找不到 `{q1}`", "确认符号名与所属模块拼写正确。"),
    ("missing argument", "调用参数数量不匹配：`{q0}`", "实参个数必须与形参个数一致：缺失或多余都会报错。"),
    ("unclosed delimiter", "未闭合的分隔符 `{q0}`", "括号/方括号/花括号必须成对闭合，检查嵌套与缩进。"),
    ("redefinition of", "重复声明 `{q0}`", "同一作用域内名字只能声明一次：改名或去掉多余声明。"),
    ("undeclared type name", "未声明的类型名 `{q0}`", "类型必须已声明或已导入：检查拼写与导入。"),
    ("generic type should be used", "泛型类型缺少类型参数{q0?}", "泛型类型（如 `向量`）使用时必须给出类型参数。"),
    ("unrecognized escape", "无法识别的转义 `{q0}`", "仓颉支持 `\\n`/`\\t`/`\\\\`/`\\uXXXX` 等转义，`\\q` 之类不支持。"),
    ("~ is missing", "缺少 `{q0}`", "缺少必需的名字或入口：程序入口应为 `主函数()`。"),
    # 警告类高频键（cjc 警告 content/Notes，detail 与 ↳ 行中文化）
    ("unused variable", "未使用的变量", "删除未使用的声明，或检查拼写错误。"),
    ("unused import", "未使用的导入", "删除未使用的导入，或确认其确实被用到。"),
    ("unused function", "未使用的函数", "删除未使用的函数，或检查调用处拼写。"),
    ("this warning can be suppressed by setting the compiler option",
     "此警告可通过编译器选项 `{q0}` 关闭", "保留警告或按提示调整代码；编译器选项作为最后手段。"),
    ("this error can be suppressed by setting the compiler option",
     "此错误可通过编译器选项 `{q0}` 关闭", "按提示调整代码消除错误；编译器选项仅作最后手段。"),
    ("following constraints for type variable",
     "类型变量 `{q0}` 的约束无法求解", "检查泛型类型参数是否满足声明的约束。"),
    ("constraint '", "约束 `{q0}` 可能来自", "泛型推断失败的线索：核对类型参数在调用处的实际类型。"),
    ("may come from", "可能来自 `{q0}`", "泛型推断失败的线索：检查相关声明的类型标注。"),
]


def emit_entry(out: list, k: str, t: str, tip: str, fix: str, note: str = "") -> None:
    """写一条 ["诊断码"] 条目（三字段 + 可选前置注释），zh/ru 生成共用。"""
    if note:
        out.append(note)
    out.append(f'["诊断码"."{k}"]')
    out.append(f'"消息模板" = {json.dumps(t, ensure_ascii=False)}')
    out.append(f'"教学提示" = {json.dumps(tip, ensure_ascii=False)}')
    out.append(f'"修复示例" = {json.dumps(fix, ensure_ascii=False)}')
    out.append("")


def gen_zh(target: str) -> None:
    """zh 全集式生成（现状逻辑）：翻译表必须覆盖官方 DiagKind 全集。"""
    trans = {}
    trans.update(SEMA)
    trans.update(PARSE)
    trans.update(LEX)
    trans.update(CHIR)
    kinds = set(FULL_KINDS)
    missing = sorted(k for k in kinds if k not in trans)
    extra = sorted(k for k in trans if k not in kinds)
    if missing:
        sys.exit(f"错误：{len(missing)} 个官方 DiagKind 缺少翻译：{missing[:8]} ...")
    if extra:
        sys.exit(f"错误：{len(extra)} 个翻译不在官方全集：{extra[:8]} ...")
    curated = set(CURATED)
    auto = sorted(k for k in kinds if k not in curated)
    fix_codes = set(FIX_EXAMPLES)
    # FIX_EXAMPLES 完整性校验：码必须在官方全集（防拼写漂移），
    # 且不在 CURATED（在精翻里已带修复示例，重复会失效——应升级进 CURATED）
    bad_fix = sorted(fix_codes - kinds)
    if bad_fix:
        sys.exit(f"错误：FIX_EXAMPLES 含非官方码：{bad_fix}")
    dup_fix = sorted(fix_codes & curated)
    if dup_fix:
        sys.exit(f"错误：FIX_EXAMPLES 与 CURATED 重叠（应升级进 CURATED）：{dup_fix}")

    out = []
    out.append("# errors.toml —— 诊断翻译（设计 §7.2；全集版由 tools/gen_full_errors.py 生成）")
    out.append("#")
    out.append("# 两类条目共存：")
    out.append("#   ① [\"诊断码\"]：键 = cjc JSON 的 DiagKind 字段（1.0.5 实测全集 644 个），")
    out.append("#      第一优先级；精翻条目模板含 {q0} 引号提取；自动条目模板含 {q0?}")
    out.append("#      可选动态值（有值显示反引号包裹，无值纯翻译）；{raw} 保留兼容；")
    out.append("#      自动条目修复示例默认空——实战命中码由 FIX_EXAMPLES 补充（建议 D1）")
    out.append("#   ② [\"消息翻译\"]：键 = 官方消息原文（精确 / 最长前缀 / ~ 后缀），兜底。")
    out.append("# 每条目字段：消息模板、教学提示（💡）、修复示例（§16.9 可粘贴修复代码）。")
    out.append("# 重新生成：python3 tools/gen_full_errors.py（翻译表 tools/diag_translations*.py）")
    out.append("")

    out.append("# ① 诊断码表（官方全集 644 条 + 方言自定义；精翻在前，自动条目按前缀分组）")
    out.append('["诊断码"]')
    out.append("")
    for k in sorted(curated):
        t, tip, fix = CURATED[k]
        emit_entry(out, k, t, tip, fix, note="# 人工精翻")
    for prefix in ("chir", "lex", "parse", "sema"):
        block = [k for k in auto if k.startswith(prefix + "_")]
        if block:
            out.append(f"# ── {prefix}（{len(block)} 条自动条目：模板含 {{q0?}} 可选动态值）──")
            for k in block:
                t = f"{trans[k]}{{q0?}}"
                fix = FIX_EXAMPLES.get(k, "")
                emit_entry(out, k, t, TIPS[prefix], fix,
                           note="# 实战命中码补充修复示例（建议 D1）" if fix else "")

    out.append("# ② 消息表（兜底；键为官方消息原文，精确 → 最长前缀 → ~ 后缀）")
    out.append('["消息翻译"]')
    out.append("")
    for k, t, tip in MESSAGES:
        out.append(f'["消息翻译"."{k}"]')
        out.append(f'"消息模板" = {json.dumps(t, ensure_ascii=False)}')
        out.append(f'"教学提示" = {json.dumps(tip, ensure_ascii=False)}')
        out.append("")

    with open(target, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    extra = sorted(curated - set(kinds))
    print(f"生成 {target}：诊断码 {len(curated) + len(auto)} 条"
          f"（官方 DiagKind {len(kinds)}：精翻 {len(curated & set(kinds))} + 自动 {len(auto)}；"
          f"方言自定义 {len(extra)}：{','.join(extra)}）+ 消息翻译 {len(MESSAGES)} 条")


def gen_incremental(target: str, table: dict, code: str, msgs=None) -> None:
    """ru/ja 等增量式生成：只写 <diag_translations_<code>>.py 已翻译的码。

    与 zh 的差异：不校验官方全集（增量友好——缺翻译的码运行时走优雅回退），
    因此本函数无 missing/extra 硬报错；条目数 = 翻译表长度。
    msgs 非空时追加 ["消息翻译"] 兜底节：键 = 官方消息原文（与 zh MESSAGES
    同构，键不翻译——匹配对象是 cjc 官方消息文本），值 = 母语译文。
    """
    out = []
    out.append(f"# errors.toml —— {code} 诊断翻译（增量包，由 tools/gen_full_errors.py --lang {code} 生成）")
    out.append("#")
    out.append(f"# 只收录 tools/diag_translations_{code}.py 已翻译的码（增量友好）：")
    out.append("# 缺翻译的码运行时走优雅回退（显示官方原文，不崩溃不瞎译，见 zhc-design §16.5）。")
    out.append(f"# 逐条扩充：在 diag_translations_{code}.py 的翻译表加条目后重新生成本文件即可。")
    out.append("")
    out.append('["诊断码"]')
    out.append("")
    for k in sorted(table):
        t, tip, fix = table[k]
        emit_entry(out, k, t, tip, fix)

    if msgs:
        out.append("# 消息表（兜底；键为官方消息原文，精确 → 最长前缀 → ~ 后缀）")
        out.append('["消息翻译"]')
        out.append("")
        for k, t, tip in msgs:
            out.append(f'["消息翻译"."{k}"]')
            out.append(f'"消息模板" = {json.dumps(t, ensure_ascii=False)}')
            out.append(f'"教学提示" = {json.dumps(tip, ensure_ascii=False)}')
            out.append("")

    with open(target, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    extra = f" + 消息翻译 {len(msgs)} 条" if msgs else ""
    print(f"生成 {target}：诊断码 {len(table)} 条（增量表，全部带人工译文）{extra}")


# ── 增量语言注册表（建议 L3）：分发与 choices 自动跟随，新增语言零脚本改动 ──
# 登记方式：import 翻译表后在此加一行 `"<代码>": (翻译表, 消息表或 None)`。
INCR = {
    "ru": (RU, MSG_RU),
    "ja": (JA, MSG_JA),
    "de": (DE, MSG_DE),
    "es": (ES, MSG_ES),
    "fr": (FR, MSG_FR),
    "ko": (KO, MSG_KO),
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    langs = ["zh"] + sorted(INCR)
    ap.add_argument("--lang", default="zh", choices=langs,
                    help="zh=全集式（校验官方全集）/ 其余=增量式（只收已翻译码）")
    ap.add_argument("--out", default="", help="输出路径（默认 zhc/lang-packs/<lang>/errors.toml）")
    args = ap.parse_args()
    target = args.out or f"zhc/lang-packs/{args.lang}/errors.toml"
    if args.lang == "zh":
        gen_zh(target)
    else:
        table, msgs = INCR[args.lang]
        gen_incremental(target, table, args.lang, msgs)


if __name__ == "__main__":
    main()
