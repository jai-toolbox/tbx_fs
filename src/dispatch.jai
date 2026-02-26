#import "Basic";
#import "String";
#import "Hash_Table";

#load "abbreviations.jai";


should_quit := false;

print_help :: () -> string {
    help := #string DONE
Usage: eval_dispatch [expression]

If no expression is given, starts in interactive mode.

Examples:
    eval_dispatch print_help()
    eval_dispatch list_available_functions()
    eval_dispatch add(3, 5)
    eval_dispatch "add(do_thing())"
    eval_dispatch "mul(int.[1, 2, 3, 4])"
    eval_dispatch "mul(gen_numbers(4))"
    eval_dispatch "greet(World)"
    eval_dispatch interactive()

Supports nested calls and multi-return spreading:
    do_thing() returns two ints, so add(do_thing()) works.
    Arguments that are function calls are evaluated first,
    and multi-return values are spread into the parent args.

Abbreviations:
    Each function has a unique short abbreviation.
    Use list_available_functions() to see abbreviations.
    e.g. if add -> a, mul -> m, then m(a(3,5),4) works.

Use list_available_functions() to see all available functions.
DONE;
    return help;
}

list_available_functions :: () -> string {
    builder: String_Builder;
    append(*builder, "Available functions:\n\n");

    // first pass: find the longest abbreviation for alignment
    max_abbr_len := 0;
    for dispatch_signatures {
        name := it_index;
        abbr, found := table_find(*name_to_abbreviation, name);
        if found && !equal(abbr, name) {
            if abbr.count > max_abbr_len  max_abbr_len = abbr.count;
        } else {
            if name.count > max_abbr_len  max_abbr_len = name.count;
        }
    }

    // second pass: print with aligned colons
    for dispatch_signatures {
        name := it_index;
        sig  := it;
        abbr, found := table_find(*name_to_abbreviation, name);
        label := ifx found && !equal(abbr, name) then abbr else name;
        padding := max_abbr_len - label.count;

        append(*builder, "  ");
        append(*builder, label);
        for 0..padding-1  append(*builder, " ");
        append(*builder, " : ");
        append(*builder, sig);
        append(*builder, "\n");
    }

    return builder_to_string(*builder);
}

interactive :: () -> string {
    print("Entering interactive mode. Type quit() or q() to exit.\n\n");

    while !should_quit {
        print(">> ");
        input := read_line();
        if input.count == 0 continue;

        trimmed := trim(input);
        if trimmed.count == 0 continue;

        result, ok := call(trimmed);
        if ok {
            if !should_quit {
                print("%\n\n", result);
            }
        } else {
            if !should_quit {
                print("Failed to evaluate: %\n\n", trimmed);
            }
        }
    }

    return "Goodbye!";
}

quit :: () -> string {
    should_quit = true;
    return "Goodbye!";
}


read_line :: () -> string {
    builder: String_Builder;

    while true {
        buffer: [1] u8;
        bytes_read := crt_read(0, buffer.data, 1);
        if bytes_read <= 0 break;

        c := buffer[0];
        if c == #char "\n" break;
        if c == #char "\r" continue;

        append(*builder, c);
    }

    return builder_to_string(*builder);
}

// todo rename crt_read to something more generic
#if OS == .WINDOWS {
    crt :: #system_library "msvcrt";
    crt_read :: (fd: s32, buffer: *u8, count: u32) -> s32 #foreign crt "_read";
} else {
    libc_io :: #system_library "libc";
    crt_read :: (fd: s32, buffer: *u8, count: u64) -> s64 #foreign libc_io "read";
}


parse_array_literal :: ($ElemType: Type, s: string) -> [..] ElemType, bool {
    result: [..] ElemType;

    dot_bracket := find_index_from_left(s, ".[");
    if dot_bracket < 0  return result, false;

    close_bracket := find_index_from_right(s, cast(u8) #char "]");
    if close_bracket < 0  return result, false;

    inner := slice(s, dot_bracket + 2, close_bracket - dot_bracket - 2);
    inner = trim(inner);

    if inner.count == 0  return result, true;

    parts := split(inner, ",");
    for parts {
        elem_str := trim(it);
        parsed := from_string(ElemType, elem_str);
        if !parsed.ok {
            array_free(result);
            result.count = 0;
            return result, false;
        }
        array_add(*result, parsed.value);
    }

    return result, true;
}

format_array_literal :: (val: [] $ElemType, type_prefix: string) -> string {
    builder: String_Builder;
    append(*builder, tprint("%.[", type_prefix));
    for val {
        if it_index > 0  append(*builder, ", ");
        append(*builder, tprint("%", it));
    }
    append(*builder, "]");
    return builder_to_string(*builder);
}


split_call_args :: (s: string) -> [..] string {
    args: [..] string;
    bracket_depth := 0;
    paren_depth := 0;
    start := 0;

    for i: 0..s.count-1 {
        c := s[i];
        if c == #char "["  bracket_depth += 1;
        if c == #char "]"  bracket_depth -= 1;
        if c == #char "("  paren_depth += 1;
        if c == #char ")"  paren_depth -= 1;
        if c == #char "," && bracket_depth == 0 && paren_depth == 0 {
            array_add(*args, trim(slice(s, start, i - start)));
            start = i + 1;
        }
    }
    remainder := trim(slice(s, start, s.count - start));
    if remainder.count > 0 {
        array_add(*args, remainder);
    }

    return args;
}


is_function_call :: (s: string) -> bool {
    trimmed := trim(s);
    if trimmed.count == 0 return false;

    if trimmed[trimmed.count - 1] != #char ")" return false;

    paren_pos := find_index_from_left(trimmed, cast(u8) #char "(");
    if paren_pos <= 0 return false;

    name_part := slice(trimmed, 0, paren_pos);

    if find_index_from_left(trimmed, ".[") >= 0 return false;

    for i: 0..name_part.count-1 {
        c := name_part[i];
        if !((c >= #char "a" && c <= #char "z") ||
             (c >= #char "A" && c <= #char "Z") ||
             (c >= #char "0" && c <= #char "9") ||
             c == #char "_") {
            return false;
        }
    }

    return true;
}

resolve_arg :: (arg: string) -> [..] string, bool {
    results: [..] string;
    trimmed := trim(arg);

    if is_function_call(trimmed) {
        result, ok := call(trimmed);
        if !ok return results, false;

        parts := split_call_args(result);
        for parts {
            array_add(*results, it);
        }
        return results, true;
    }

    array_add(*results, trimmed);
    return results, true;
}


FromStringResult :: struct(T: Type) {
    value: T;
    ok: bool;
}

from_string :: ($T: Type, s: string) -> FromStringResult(T) {
    result: FromStringResult(T);

    #if T == int {
        val, ok, _ := string_to_int(s);
        result.value = val;
        result.ok = ok;
    } else #if T == s64 {
        val, ok, _ := string_to_int(s);
        result.value = val;
        result.ok = ok;
    } else #if T == s32 {
        val, ok, _ := string_to_int(s);
        result.value = cast(s32) val;
        result.ok = ok;
    } else #if T == float64 {
        val, ok, _ := string_to_float64(s);
        result.value = val;
        result.ok = ok;
    } else #if T == float32 {
        val, ok, _ := string_to_float(s);
        result.value = val;
        result.ok = ok;
    } else #if T == string {
        result.value = s;
        result.ok = true;
    } else #if T == bool {
        if s == "true"  { result.value = true;  result.ok = true; }
        else if s == "false" { result.value = false; result.ok = true; }
    } else #if T == [] s64 {
        arr, ok := parse_array_literal(s64, s);
        result.value = arr;
        result.ok = ok;
    } else #if T == [] s32 {
        arr, ok := parse_array_literal(s32, s);
        result.value = arr;
        result.ok = ok;
    } else #if T == [] float32 {
        arr, ok := parse_array_literal(float32, s);
        result.value = arr;
        result.ok = ok;
    } else #if T == [] float64 {
        arr, ok := parse_array_literal(float64, s);
        result.value = arr;
        result.ok = ok;
    } else #if T == [] string {
        arr, ok := parse_array_literal(string, s);
        result.value = arr;
        result.ok = ok;
    } else {
        result.ok = false;
    }

    return result;
}

value_to_string :: (val: $T) -> string {
    #if T == [] s64 {
        return format_array_literal(val, "int");
    } else #if T == [] s32 {
        return format_array_literal(val, "s32");
    } else #if T == [] float32 {
        return format_array_literal(val, "float32");
    } else #if T == [] float64 {
        return format_array_literal(val, "float64");
    } else #if T == [] string {
        return format_array_literal(val, "string");
    } else {
        return tprint("%", val);
    }
}


DispatchFn :: #type (args: [] string) -> (string, bool);

dispatch_table:      Table(string, DispatchFn);
dispatch_signatures: Table(string, string);

abbreviation_to_name: Table(string, string);  // abbr -> full_name
name_to_abbreviation: Table(string, string);  // full_name -> abbr


// build abbreviation tables from all currently registered function names.
build_abbreviation_tables :: () {
    names: [..] string;
    defer array_free(names);

    for dispatch_table {
        array_add(*names, it_index);
    }

    if names.count == 0 return;

    abbr_result := min_abbreviations(names);
    if !abbr_result.success {
        print("Warning: could not compute unique abbreviations for all functions.\n");
        return;
    }
    defer array_free(abbr_result.abbreviations);

    for i: 0..names.count-1 {
        abbr := copy_string(abbr_result.abbreviations[i]);
        name := copy_string(names[i]);
        table_set(*name_to_abbreviation, name, abbr);
        table_set(*abbreviation_to_name, abbr, name);
    }
}

// expand a function name: if it's an abbreviation, return the full name.
// if it's already a full name, return it as-is.
expand_function_name :: (name: string) -> string {
    // check if it's already a registered full name
    _, found_direct := table_find(*dispatch_table, name);
    if found_direct return name;

    // check if it's an abbreviation
    full_name, found_abbr := table_find(*abbreviation_to_name, name);
    if found_abbr return full_name;

    return name;
}


call :: (expression: string) -> string, bool {
    paren_pos := find_index_from_left(expression, cast(u8) #char "(");
    if paren_pos < 0 return "", false;

    close_paren := find_index_from_right(expression, cast(u8) #char ")");
    if close_paren < 0 return "", false;

    func_name := trim(slice(expression, 0, paren_pos));
    args_str := trim(slice(expression, paren_pos + 1, close_paren - paren_pos - 1));

    func_name = expand_function_name(func_name);

    raw_args := split_call_args(args_str);
    defer array_free(raw_args);

    resolved_args: [..] string;
    defer array_free(resolved_args);

    for raw_args {
        resolved, ok := resolve_arg(it);
        defer array_free(resolved);
        if !ok {
            print("Failed to resolve argument: '%'\n", it);
            return "", false;
        }
        for resolved {
            array_add(*resolved_args, trim(it));  // <-- ADD trim HERE
        }
    }

    fn, found := table_find(*dispatch_table, func_name);
    if !found {
        print("Unknown function: '%'\n", func_name);
        print("Use list_available_functions() to see all available functions.\n");
        return "", false;
    }

    result, ok := fn(resolved_args);
    return result, ok;
}


main :: () {
    __register_dispatchers();
    build_abbreviation_tables();

    args := get_command_line_arguments();

    if args.count < 2 {
        result, _ := call("interactive()");
        print("%\n", result);
        return;
    }

    builder: String_Builder;
    for i: 1..args.count-1 {
        if i > 1  append(*builder, " ");
        append(*builder, args[i]);
    }
    expression := builder_to_string(*builder);

    result, ok := call(expression);
    if ok {
        print("%\n", result);
    } else {
        print("Failed to evaluate: %\n", expression);
    }
}
