/*

- to make using this easier we should do intelligent abbreviations of commands so you don't have to type the long form all the time.
- while also supporting regex, there should also be deciated commands for listing out thigns that match a file extension or have a substring that matches
because that's one of the biggest annoyances in regex is that simple or intermediate level of requests just make you have to go and open up regex 101 again.


*/
#load "dispatch.jai";

#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#if OS == .WINDOWS {
    kernel32 :: #system_library "kernel32";
    MoveFileA :: (lpExistingFileName: *u8, lpNewFileName: *u8) -> s32 #foreign kernel32;
    CreateDirectoryA :: (lpPathName: *u8, lpSecurityAttributes: *void) -> s32 #foreign kernel32;
} else {
    libc :: #system_library "libc";
    c_rename :: (oldpath: *u8, newpath: *u8) -> s32 #foreign libc "rename";
    c_mkdir  :: (pathname: *u8, mode: u32) -> s32 #foreign libc "mkdir";
}


current_file_selection : [..] string;
current_directory      : string;


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
    "go_up_directory",
    "go_down_directory",
    "print_help",
    "list_available_functions",
    "interactive",
    "quit"
];



change_directory :: (new_dir : string) {
    if new_dir.count == 0 {
        print("ERROR: No directory specified.\n");
        return;
    }

    if current_directory.count > 0 {
        free(current_directory);
    }

    dir := new_dir;

    // strip trailing slash if present (unless it's the root "/")
    if dir.count > 1 && (dir[dir.count-1] == #char "/" || dir[dir.count-1] == #char "\\") {
        dir.count -= 1;
    }

    // determine if path is absolute or relative
    is_absolute := false;

    #if OS == .WINDOWS {
        // absolute if starts with drive letter like "c:\" or "c:/"
        if dir.count >= 3 && dir[1] == #char ":" && (dir[2] == #char "\\" || dir[2] == #char "/") {
            is_absolute = true;
        }
        // also handle unc paths like "\\server\share"
        if dir.count >= 2 && dir[0] == #char "\\" && dir[1] == #char "\\" {
            is_absolute = true;
        }
    } else {
        // on unix, absolute paths start with "/"
        if dir.count >= 1 && dir[0] == #char "/" {
            is_absolute = true;
        }
    }

    resolved_path : string;

    if is_absolute {
        resolved_path = dir;
    } else {
        // relative path: join with current_directory
        if current_directory.count > 0 {
            resolved_path = tprint("%/%", current_directory, dir);
        } else {
            // no current directory set; treat as-is (could be relative to cwd)
            resolved_path = dir;
        }
    }

    if !file_exists(resolved_path) {
        print("ERROR: Directory '%' does not exist.\n", resolved_path);
        // still set it so the user can see what was attempted
        current_directory = copy_string(resolved_path);
        return;
    }

    current_directory = copy_string(resolved_path);
    print("Changed directory to '%'\n", current_directory);
}

go_up_directory :: () {
    if current_directory.count == 0 {
        print("ERROR: No current directory set. Use change_directory first.\n");
        return;
    }

    // find the last path separator to determine the parent directory
    last_sep := -1;
    for i : 0..current_directory.count-1 {
        c := current_directory[i];
        if c == #char "/" || c == #char "\\" {
            last_sep = i;
        }
    }

    if last_sep < 0 {
        print("ERROR: Already at the top-level relative path '%'. Cannot go up.\n", current_directory);
        return;
    }

    // handle root directory cases
    #if OS == .WINDOWS {
        // don't go above "c:\" (last_sep would be 2 for "c:\something")
        if last_sep <= 2 && current_directory.count >= 3 && current_directory[1] == #char ":" {
            parent : string;
            parent.data  = current_directory.data;
            parent.count = 3; // e.g. "C:\"
            if parent == current_directory {
                print("ERROR: Already at root '%'. Cannot go up.\n", current_directory);
                return;
            }
            // go to root
            old := current_directory;
            current_directory = copy_string(parent);
            free(old);
            print("Changed directory to '%'\n", current_directory);
            return;
        }
    } else {
        // don't go above "/"
        if last_sep == 0 {
            if current_directory.count == 1 {
                print("ERROR: Already at root '/'. Cannot go up.\n");
                return;
            }
            // go to root "/"
            old := current_directory;
            current_directory = copy_string("/");
            free(old);
            print("Changed directory to '%'\n", current_directory);
            return;
        }
    }

    parent : string;
    parent.data  = current_directory.data;
    parent.count = last_sep;

    old := current_directory;
    current_directory = copy_string(parent);
    free(old);

    print("Changed directory to '%'\n", current_directory);
}

go_down_directory :: (subdir_name : string) {
    if current_directory.count == 0 {
        print("ERROR: No current directory set. Use change_directory first.\n");
        return;
    }

    if subdir_name.count == 0 {
        // list available subdirectories so the user can pick one
        print("Available subdirectories:\n");
        dirs := list_directories();
        for dirs free(it);
        array_free(dirs);
        return;
    }

    new_path := tprint("%/%", current_directory, subdir_name);

    if !file_exists(new_path) {
        print("ERROR: Subdirectory '%' does not exist in '%'.\n", subdir_name, current_directory);
        return;
    }

    old := current_directory;
    current_directory = copy_string(new_path);
    free(old);

    print("Changed directory to '%'\n", current_directory);
}

list_files :: () -> [..] string {
    results : [..] string;

    if current_directory.count == 0 {
        print("ERROR: No current directory set. Use change_directory first.\n");
        return results;
    }

    visitor :: (info: *File_Visit_Info, results: *[..] string) {
        array_add(results, copy_string(info.full_name));
    }

    visit_files(current_directory, false, *results, visitor, visit_directories = false);

    print("Files in '%' (% found):\n", current_directory, results.count);
    for results {
        print("  [%] %\n", it_index, it);
    }

    return results;
}

list_directories :: () -> [..] string {
    results : [..] string;

    if current_directory.count == 0 {
        print("ERROR: No current directory set. Use change_directory first.\n");
        return results;
    }

    visitor :: (info: *File_Visit_Info, results: *[..] string) {
        if info.is_directory {
            array_add(results, copy_string(info.full_name));
        }
    }

    visit_files(current_directory, false, *results, visitor, visit_directories = true, visit_files = false);

    print("Directories in '%' (% found):\n", current_directory, results.count);
    for results {
        print("  [%] %\n", it_index, it);
    }

    return results;
}

add_all_files_in_directory_to_selection :: () {
    if current_directory.count == 0 {
        print("ERROR: No current directory set. Use change_directory first.\n");
        return;
    }

    files := list_files();
    defer {
        for files free(it);
        array_free(files);
    }

    for files {
        array_add(*current_file_selection, copy_string(it));
    }

    print("Added % files from '%' to selection.\n", files.count, current_directory);
}

filter_selection_by_extension :: (extension : string) {
    ext := extension;
    if ext.count > 0 && ext[0] != #char "." {
        ext = tprint(".%", ext);
    }

    i := 0;
    while i < current_file_selection.count {
        file := current_file_selection[i];

        if !ends_with(file, ext) {
            free(file);
            array_ordered_remove_by_index(*current_file_selection, i);
        } else {
            i += 1;
        }
    }

    print("Filtered selection to '*%' (% files remain).\n", ext, current_file_selection.count);
}


create_directory :: (dir_name : string) -> bool {
    path : string;
    if current_directory.count > 0 {
        path = tprint("%/%", current_directory, dir_name);
    } else {
        path = dir_name;
    }

    if file_exists(path) {
        print("ERROR: '%' already exists.\n", path);
        return false;
    }

    path_c := temp_c_string(path);

    #if OS == .WINDOWS {
        result := CreateDirectoryA(path_c, null);
        if result == 0 {
            print("ERROR: Failed to create directory '%'\n", path);
            return false;
        }
    } else {
        result := c_mkdir(path_c, 0x1ED);  // 0x1ED == octal 755 == decimal 493
        if result != 0 {
            print("ERROR: Failed to create directory '%'\n", path);
            return false;
        }
    }

    print("Created directory '%'\n", path);
    return true;
}

create_file :: (file_name : string) -> bool {
    path : string;
    if current_directory.count > 0 {
        path = tprint("%/%", current_directory, file_name);
    } else {
        path = file_name;
    }

    if file_exists(path) {
        print("ERROR: '%' already exists.\n", path);
        return false;
    }

    success := write_entire_file(path, "");
    if !success {
        print("ERROR: Failed to create file '%'\n", path);
        return false;
    }

    print("Created file '%'\n", path);
    return true;
}


print_current_file_selection :: () {
    if current_file_selection.count == 0 {
        print("No files selected.\n");
        return;
    }

    print("Current file selection (% files):\n", current_file_selection.count);
    for current_file_selection {
        print("  [%] %\n", it_index, it);
    }
}

clear_current_file_selection :: () {
    for current_file_selection {
        free(it);
    }
    array_reset(*current_file_selection);
}

select_files :: (files : [] string) {
    clear_current_file_selection();
    add_files_to_selection(files);
}

add_files_to_selection :: (files : [] string) {
    for files {
        array_add(*current_file_selection, copy_string(it));
    }
}

rename_file_on_disk :: (old_path : string, new_path : string) -> bool {
    old_c := temp_c_string(old_path);
    new_c := temp_c_string(new_path);

    #if OS == .WINDOWS {
        result := MoveFileA(old_c, new_c);
        return result != 0;
    } else {
        result := c_rename(old_c, new_c);
        return result == 0;
    }
}

build_new_path :: (file_path : string, new_extension : string) -> string {
    dot_index := -1;
    for i : 0..file_path.count-1 {
        if file_path[i] == #char "." {
            dot_index = i;
        }
    }

    base : string;
    if dot_index >= 0 {
        base.data  = file_path.data;
        base.count = dot_index;
    } else {
        base = file_path;
    }

    ext := new_extension;
    if ext.count > 0 && ext[0] == #char "." {
        ext.data  += 1;
        ext.count -= 1;
    }

    return tprint("%.%", base, ext);
}

change_extension_of_file :: (file_path : string, new_extension : string) -> new_path: string, success: bool {
    new_path := build_new_path(file_path, new_extension);

    if new_path == file_path {
        return copy_string(new_path), true;
    }

    ok := rename_file_on_disk(file_path, new_path);
    if !ok {
        print("ERROR: Failed to rename '%' -> '%'\n", file_path, new_path);
        return "", false;
    }

    return copy_string(new_path), true;
}

change_extension_of_all_selected_files :: (new_extension : string) {
    for * current_file_selection {
        old_path := <<it;
        new_path, success := change_extension_of_file(old_path, new_extension);

        if success {
            <<it = new_path;
            free(old_path);
        } else {
            print("  Skipping '%' due to rename failure.\n", old_path);
        }
    }
}
