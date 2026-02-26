#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";

Search_Result :: struct {
    file_path:   string;
    line_number: int;
    line_text:   string;
}

is_binary_file :: (contents: string) -> bool {
    // check the first 512 bytes (or less) for null bytes or high concentration of non-printable characters
    check_length := min(contents.count, 512);
    null_count := 0;
    non_printable_count := 0;

    for i : 0..check_length - 1 {
        c := contents[i];
        if c == 0 {
            null_count += 1;
        }
        if c != #char "\t" && c != #char "\n" && c != #char "\r" && (c < 32 || c > 126) {
            non_printable_count += 1;
        }
    }

    if null_count > 0  return true;
    if check_length > 0 && non_printable_count * 100 / check_length > 10  return true;

    return false;
}

search_recursively_for_file_contents :: (pattern: string, root_path: string) -> [..] Search_Result {
    results: [..] Search_Result;

    Context :: struct {
        pattern: string;
        results: *[..] Search_Result;
    }

    ctx: Context;
    ctx.pattern = pattern;
    ctx.results = *results;

    visitor :: (info: *File_Visit_Info, ctx: *Context) {
        if info.is_directory  return;

        contents, success := read_entire_file(info.full_name);
        if !success  return;

        if is_binary_file(contents) {
            free(contents);
            return;
        }

        line_number := 1;
        remaining := contents;

        while remaining.count > 0 {
            index := find_index_from_left(remaining, "\n");

            line: string;
            if index >= 0 {
                line = slice(remaining, 0, index);
            } else {
                line = remaining;
            }

            if contains(line, ctx.pattern) {
                result: Search_Result;
                result.file_path   = copy_string(info.full_name);
                result.line_number = line_number;
                result.line_text   = copy_string(trim(line));
                array_add(ctx.results, result);
            }

            if index >= 0 {
                remaining = advance(remaining, index + 1);
            } else {
                break;
            }

            line_number += 1;
        }

        free(contents);
    }

    visit_files(root_path, recursive = true, *ctx, visitor);

    return results;
}

format_result :: (result: Search_Result) -> string {
    return tprint("%:%:%", result.file_path, result.line_number, result.line_text);
}

