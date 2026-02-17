OUTPUT_EXECUTABLE_NAME := "eval_dispatch";

#run {
    set_build_options_dc(.{do_output = false});

    args := get_build_options().compile_time_command_line;

    target_x64     := array_find(args, "-x64");
    target_arm     := array_find(args, "-arm64");

    cpu_target := CPU;
    os_target  := OS;
    if target_x64  cpu_target = .X64;
    if target_arm  cpu_target = .ARM64;

    log("Compiling for % %", os_target, cpu_target);

    build_output_directory := "bin";
    make_directory_if_it_does_not_exist(build_output_directory, recursive = true);

    w := compiler_create_workspace("Target workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.cpu_target = cpu_target;
    options.os_target  = os_target;
    options.output_executable_name = OUTPUT_EXECUTABLE_NAME;
    if target_arm {
        options.backend = .LLVM;
        options.llvm_options.target_system_features = "+lse";
    }

    options.output_path = tprint("%/", build_output_directory);

    import_path: [..] string;
    array_add(*import_path, ..options.import_path);
    array_add(*import_path, "src/");
    options.import_path = import_path;

    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("src/main.jai", w);


    // DISPATCH_NAMES :: string.["add", "mul", "greet", "gen_numbers", "do_thing", "print_help", "list_available_functions", "interactive", "quit"];

    DISPATCH_NAMES :: string.[
        "print_current_file_selection",
        "clear_current_file_selection",
        "select_files",
        "add_files_to_selection",
        "change_extension_of_file",
        "change_extension_of_all_selected_files",
        "change_directory",
        "list_files",
        "list_directories",
        "add_all_files_in_directory_to_selection",
        "filter_selection_by_extension",
        "create_directory",
        "create_file",
        "print_help",
        "list_available_functions",
        "interactive",
        "quit"
    ];

    Dispatch_Entry :: struct {
        name: string;
        arg_names: [..] string;
        arg_type_names: [..] string;
        return_type_names: [..] string;
    }

    entries: [..] Dispatch_Entry;
    emitted := false;

    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .TYPECHECKED;
                if emitted continue;

                tc := cast(*Message_Typechecked) message;

                for tc.procedure_headers {
                    header := it.expression;
                    if !header continue;

                    name := header.name;
                    if name.count == 0 continue;

                    found_in_whitelist := false;
                    for DISPATCH_NAMES {
                        if name == it { found_in_whitelist = true; break; }
                    }
                    if !found_in_whitelist continue;

                    already := false;
                    for entries {
                        if it.name == name { already = true; break; }
                    }
                    if already continue;

                    arg_count := header.arguments.count;
                    return_count := header.returns.count;

                    arg_names: [..] string;
                    arg_type_names: [..] string;
                    all_supported := true;

                    for arg: header.arguments {
                        ti: *Type_Info = null;
                        if arg.type_inst {
                            ti = arg.type_inst.result;
                        }
                        if !ti && arg.type {
                            ti = arg.type;
                        }

                        if !ti {
                            all_supported = false;
                            break;
                        }

                        type_name, ok := type_info_to_name(ti);
                        if !ok {
                            all_supported = false;
                            break;
                        }
                        array_add(*arg_type_names, copy_string(type_name));
                        array_add(*arg_names, copy_string(arg.name));
                    }

                    if !all_supported continue;

                    return_type_names: [..] string;

                    for ret: header.returns {
                        ret_ti: *Type_Info = null;
                        if ret.type_inst  ret_ti = ret.type_inst.result;
                        if !ret_ti && ret.type  ret_ti = ret.type;

                        if ret_ti {
                            rtn, ret_ok := type_info_to_name(ret_ti);
                            if !ret_ok { all_supported = false; break; }
                            array_add(*return_type_names, copy_string(rtn));
                        } else {
                            all_supported = false;
                            break;
                        }
                    }

                    if !all_supported continue;

                    entry: Dispatch_Entry;
                    entry.name = copy_string(name);
                    entry.arg_names = arg_names;
                    entry.arg_type_names = arg_type_names;
                    entry.return_type_names = return_type_names;
                    array_add(*entries, entry);

                    print("[metaprogram] Found dispatchable function: %\n", name);
                }

                if !emitted && entries.count == DISPATCH_NAMES.count {
                    emitted = true;

                    generated_code: String_Builder;
                    init_registrations: String_Builder;

                    for entry: entries {
                        ename := entry.name;
                        arg_count := entry.arg_type_names.count;
                        ret_count := entry.return_type_names.count;

                        // generate dispatch wrapper
                        append(*generated_code, tprint("__dispatch_% :: (args: [] string) -> (string, bool) {\n", ename));
                        append(*generated_code, tprint("    if args.count != %  return \"\", false;\n", arg_count));

                        for arg_idx: 0..arg_count-1 {
                            type_name := entry.arg_type_names[arg_idx];
                            append(*generated_code, tprint(
                                "    arg%_parsed := from_string(%, args[%]);\n",
                                arg_idx, type_name, arg_idx
                            ));
                            append(*generated_code, tprint(
                                "    if !arg%_parsed.ok  return \"\", false;\n",
                                arg_idx
                            ));
                        }

                        if ret_count == 0 {
                            append(*generated_code, tprint("    %(", ename));
                        } else if ret_count == 1 {
                            append(*generated_code, tprint("    __r0 := %(", ename));
                        } else {
                            append(*generated_code, "    ");
                            for r_idx: 0..ret_count-1 {
                                if r_idx > 0  append(*generated_code, ", ");
                                append(*generated_code, tprint("__r%", r_idx));
                            }
                            append(*generated_code, tprint(" := %(", ename));
                        }

                        for arg_idx: 0..arg_count-1 {
                            if arg_idx > 0  append(*generated_code, ", ");
                            append(*generated_code, tprint("arg%_parsed.value", arg_idx));
                        }
                        append(*generated_code, ");\n");

                        if ret_count == 0 {
                            append(*generated_code, "    return \"\", true;\n");
                        } else if ret_count == 1 {
                            append(*generated_code, "    return value_to_string(__r0), true;\n");
                        } else {
                            // multiple returns: build comma-separated string
                            append(*generated_code, "    __multi_sb: String_Builder;\n");
                            for r_idx: 0..ret_count-1 {
                                if r_idx > 0 {
                                    append(*generated_code, "    append(*__multi_sb, \", \");\n");
                                }
                                append(*generated_code, tprint("    append(*__multi_sb, value_to_string(__r%));\n", r_idx));
                            }
                            append(*generated_code, "    return builder_to_string(*__multi_sb), true;\n");
                        }

                        append(*generated_code, "}\n\n");

                        // build signature string
                        sig: String_Builder;
                        append(*sig, tprint("%(", ename));
                        for arg_idx: 0..arg_count-1 {
                            if arg_idx > 0  append(*sig, ", ");
                            append(*sig, tprint("%: %", entry.arg_names[arg_idx], entry.arg_type_names[arg_idx]));
                        }
                        append(*sig, ")");
                        if ret_count > 0 {
                            append(*sig, " -> ");
                            for r_idx: 0..ret_count-1 {
                                if r_idx > 0  append(*sig, ", ");
                                append(*sig, entry.return_type_names[r_idx]);
                            }
                        }
                        sig_str := builder_to_string(*sig);

                        append(*init_registrations, tprint(
                            "    table_add(*dispatch_table, \"%\", __dispatch_%);\n",
                            ename, ename
                        ));
                        append(*init_registrations, tprint(
                            "    table_add(*dispatch_signatures, \"%\", \"%\");\n",
                            ename, sig_str
                        ));
                    }

                    init_str := builder_to_string(*init_registrations);
                    gen_str  := builder_to_string(*generated_code);

                    full: String_Builder;
                    append(*full, gen_str);
                    append(*full, "__register_dispatchers :: () {\n");
                    append(*full, init_str);
                    append(*full, "}\n");

                    full_generated := builder_to_string(*full);

                    print("--- Generated dispatch code ---\n%\n------\n", full_generated);
                    add_build_string(full_generated, w);
                }

            case .ERROR;
                exit(1);

            case .COMPLETE;
                break;
        }
    }

    compiler_end_intercept(w);
};

type_info_to_name :: (info: *Type_Info) -> string, bool {
    if !info return "", false;

    if info.type == {
        case .INTEGER;
            int_info := cast(*Type_Info_Integer) info;
            if int_info.signed {
                if info.runtime_size == {
                    case 1; return "s8", true;
                    case 2; return "s16", true;
                    case 4; return "s32", true;
                    case 8; return "s64", true;
                }
            } else {
                if info.runtime_size == {
                    case 1; return "u8", true;
                    case 2; return "u16", true;
                    case 4; return "u32", true;
                    case 8; return "u64", true;
                }
            }
        case .FLOAT;
            if info.runtime_size == {
                case 4; return "float32", true;
                case 8; return "float64", true;
            }
        case .BOOL;
            return "bool", true;
        case .STRING;
            return "string", true;
        case .ARRAY;
            arr_info := cast(*Type_Info_Array) info;
            elem_name, elem_ok := type_info_to_name(arr_info.element_type);
            if elem_ok {
                return tprint("[] %", elem_name), true;
            }
    }

    return "", false;
}

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";
#import "Hash_Table";
