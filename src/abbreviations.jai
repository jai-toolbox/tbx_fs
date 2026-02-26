#import "Basic";
#import "String";
#import "Sort";


Abbreviation_Result :: struct {
    abbreviations: [..] string;
    success: bool;
}


split_by_underscore :: (s: string) -> [..] string {
    words: [..] string;
    start := 0;
    for i: 0..s.count-1 {
        if s[i] == #char "_" {
            word := slice(s, start, i - start);
            array_add(*words, word);
            start = i + 1;
        }
    }
    if start <= s.count {
        word := slice(s, start, s.count - start);
        array_add(*words, word);
    }
    return words;
}


concat_parts :: (parts: [] string) -> string {
    total_len := 0;
    for parts  total_len += it.count;

    buf := alloc_string(total_len);
    offset := 0;
    for parts {
        memcpy(buf.data + offset, it.data, it.count);
        offset += it.count;
    }
    return buf;
}


abbreviation_matches_command :: (abbr: string, command: string) -> bool {
    words := split_by_underscore(command);
    defer array_free(words);

    if words.count == 0  return abbr.count == 0;

    Entry :: struct {
        word_idx: int;
        abbr_offset: int;
    }

    stack: [..] Entry;
    defer array_free(stack);

    initial: Entry;
    initial.word_idx = 0;
    initial.abbr_offset = 0;
    array_add(*stack, initial);

    while stack.count > 0 {
        entry := pop(*stack);

        if entry.word_idx == words.count {
            if entry.abbr_offset == abbr.count  return true;
            continue;
        }

        word := words[entry.word_idx];
        remaining_abbr := abbr.count - entry.abbr_offset;
        remaining_words := words.count - entry.word_idx;

        max_p := min(word.count, remaining_abbr - (remaining_words - 1));
        if max_p < 1  continue;

        for p: 1..max_p {
            match := true;
            for k: 0..p-1 {
                if abbr[entry.abbr_offset + k] != word[k] {
                    match = false;
                    break;
                }
            }
            if match {
                new_entry: Entry;
                new_entry.word_idx = entry.word_idx + 1;
                new_entry.abbr_offset = entry.abbr_offset + p;
                array_add(*stack, new_entry);
            }
        }
    }

    return false;
}


get_all_abbreviations :: (snake_str: string, max_len: int) -> [..] string {
    words := split_by_underscore(snake_str);
    defer array_free(words);

    results: [..] string;

    Entry :: struct {
        word_idx: int;
        prefixes: [..] string;
        remaining_len: int;
    }

    stack: [..] Entry;
    defer array_free(stack);

    initial: Entry;
    initial.word_idx = 0;
    initial.remaining_len = max_len;
    array_add(*stack, initial);

    while stack.count > 0 {
        entry := pop(*stack);

        if entry.word_idx == words.count {
            abbr := concat_parts(entry.prefixes);
            array_add(*results, abbr);
            array_free(entry.prefixes);
            continue;
        }

        word := words[entry.word_idx];
        remaining_words := words.count - entry.word_idx - 1;
        max_prefix := min(word.count, entry.remaining_len - remaining_words);

        if max_prefix < 1 {
            array_free(entry.prefixes);
            continue;
        }

        for p: 1..max_prefix {
            new_entry: Entry;
            new_entry.word_idx = entry.word_idx + 1;
            new_entry.remaining_len = entry.remaining_len - p;
            for entry.prefixes  array_add(*new_entry.prefixes, it);
            prefix := slice(word, 0, p);
            array_add(*new_entry.prefixes, prefix);
            array_add(*stack, new_entry);
        }

        array_free(entry.prefixes);
    }

    return results;
}


remove_duplicates :: (arr: *[..] string) {
    if arr.count <= 1  return;
    write := 1;
    for i: 1..arr.count-1 {
        if !equal(arr.*[i], arr.*[write-1]) {
            arr.*[write] = arr.*[i];
            write += 1;
        }
    }
    arr.count = write;
}


compare_strings_by_length_then_lex :: (a: string, b: string) -> int {
    if a.count < b.count  return -1;
    if a.count > b.count  return  1;
    min_len := a.count;
    for i: 0..min_len-1 {
        if a[i] < b[i]  return -1;
        if a[i] > b[i]  return  1;
    }
    return 0;
}


string_in_set :: (s: string, set: [] string) -> bool {
    for set  if equal(it, s)  return true;
    return false;
}


find_unique_assignment :: (strings: [] string, max_len: int) -> Abbreviation_Result {
    result: Abbreviation_Result;

    n := strings.count;
    if n == 0 {
        result.success = true;
        return result;
    }

    all_options: [..] [..] string;
    defer {
        for *all_options  array_free(it.*);
        array_free(all_options);
    }

    for i: 0..n-1 {
        raw_options := get_all_abbreviations(strings[i], max_len);

        filtered: [..] string;
        for raw_options {
            abbr := it;
            ambiguous := false;
            for j: 0..n-1 {
                if j == i  continue;
                if abbreviation_matches_command(abbr, strings[j]) {
                    ambiguous = true;
                    break;
                }
            }
            if !ambiguous {
                array_add(*filtered, abbr);
            }
        }
        array_free(raw_options);

        quick_sort(filtered, compare_strings_by_length_then_lex);
        remove_duplicates(*filtered);

        if filtered.count == 0 {
            array_free(filtered);
            result.success = false;
            return result;
        }

        array_add(*all_options, filtered);
    }

    indexed: [..] int;
    defer array_free(indexed);
    for i: 0..n-1  array_add(*indexed, i);

    for i: 1..indexed.count-1 {
        key := indexed[i];
        j := i - 1;
        while j >= 0 && all_options[indexed[j]].count > all_options[key].count {
            indexed[j+1] = indexed[j];
            j -= 1;
        }
        indexed[j+1] = key;
    }

    assignment: [..] string;
    array_resize(*assignment, n);
    for i: 0..n-1  assignment[i] = "";

    used: [..] string;
    defer array_free(used);

    backtrack :: (pos: int, indexed: [] int, all_options: [][..] string,
                  assignment: *[..] string, used: *[..] string, n: int) -> bool {
        if pos == n  return true;

        idx := indexed[pos];
        for all_options[idx] {
            abbr := it;
            if !string_in_set(abbr, used.*) {
                array_add(used, abbr);
                assignment.*[idx] = abbr;
                if backtrack(pos + 1, indexed, all_options, assignment, used, n)
                    return true;
                used.count -= 1;
                assignment.*[idx] = "";
            }
        }
        return false;
    }

    if backtrack(0, indexed, all_options, *assignment, *used, n) {
        result.success = true;
        result.abbreviations = assignment;
        return result;
    }

    array_free(assignment);
    result.success = false;
    return result;
}


min_abbreviations :: (string_list: [] string) -> Abbreviation_Result {
    result: Abbreviation_Result;

    n := string_list.count;
    if n == 0 {
        result.success = true;
        return result;
    }

    lo := 0;
    hi := 0;
    for string_list {
        words := split_by_underscore(it);
        word_count := words.count;
        total_char_len := 0;
        for words  total_char_len += it.count;
        array_free(words);

        if word_count > lo  lo = word_count;
        if total_char_len > hi  hi = total_char_len;
    }

    best: Abbreviation_Result;
    best.success = false;

    while lo <= hi {
        mid := (lo + hi) / 2;
        attempt := find_unique_assignment(string_list, mid);
        if attempt.success {
            if best.success  array_free(best.abbreviations);
            best = attempt;
            hi = mid - 1;
        } else {
            lo = mid + 1;
        }
    }

    return best;
}
