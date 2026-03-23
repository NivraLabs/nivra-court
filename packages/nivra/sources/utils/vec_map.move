// © 2026 Nivra Labs Ltd.

module nivra::vec_map;

// === Imports ===
use sui::vec_map::{Self, VecMap};

// === Public Functions ===
public macro fun do<$K, $V: copy>(
    $v: &VecMap<$K, $V>,
    $f: |&$K, $V| -> (),
) {
    let mut i = 0;

    while(i < vec_map::length($v)) {
        let (k, v) = vec_map::get_entry_by_idx($v, i);

        $f(k, *v);

        i = i + 1;
    };
}

public macro fun unique_values<$K, $V: copy>(
    $v: &VecMap<$K, $V>,
): vector<$V> {
    let mut unique_values: vector<$V> = vector[];
    let mut i = 0;

    while(i < vec_map::length($v)) {
        let (_, val) = vec_map::get_entry_by_idx($v, i);

        if (!unique_values.contains(val)) {
            unique_values.push_back(*val);
        };

        i = i + 1;
    };

    unique_values
}

public macro fun count_unique_values<$K, $V: copy>(
    $v: &VecMap<$K, $V>,
): u64 {
    let mut unique_values: vector<$V> = vector[];
    let mut i = 0;

    while(i < vec_map::length($v)) {
        let (_, val) = vec_map::get_entry_by_idx($v, i);

        if (!unique_values.contains(val)) {
            unique_values.push_back(*val);
        };

        i = i + 1;
    };

    unique_values.length()
}

public macro fun eq<$K, $V>(
    $v: &VecMap<$K, $V>,
    $t: &VecMap<$K, $V>,
): bool {
    if (vec_map::length($v) != vec_map::length($t)) {
        return false
    };

    let mut i = 0;

    while(i < vec_map::length($v)) {
        let (v_key, v_val) = vec_map::get_entry_by_idx($v, i);
        let (t_key, t_val) = vec_map::get_entry_by_idx($t, i);

        if (*v_key != *t_key || *v_val != *t_val) {
            return false
        };

        i = i + 1;
    };

    true
}

/// WARNING: Existance of a matching option is assumed!
public macro fun most_significant_option_idx<$K, $V>(
    $v: &VecMap<$K, $V>,
    $t: $V,
): u64 {
    let mut i = 0;

    while(i < vec_map::length($v) - 1) {
        let (_, v) = vec_map::get_entry_by_idx($v, i);

        if (v == $t) {
            return i
        };

        i = i + 1;
    };

    return i
}