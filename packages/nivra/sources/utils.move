// © 2026 Nivra Labs Ltd.

module nivra::utils;

use sui::linked_table::{Self, LinkedTable};

public macro fun do_ref<$K, $V>(
    $v: &LinkedTable<$K, $V>,
    $f: |$K, &$V| -> ()
) {
    let mut i = linked_table::front($v);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = linked_table::borrow($v, k);

        $f(k,v);

        i = linked_table::next($v, k);
    };
}

public macro fun do<$K, $V>(
    $v: &mut LinkedTable<$K, $V>,
    $f: |$K, &mut $V| -> ()
) {
    let mut i = linked_table::front($v);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = linked_table::borrow_mut($v, k);

        $f(k,v);

        i = linked_table::next($v, k);
    };
}

public fun bytes_lt(a: &vector<u8>, b: &vector<u8>): bool {
    let min = if (a.length() < b.length()) { a.length() } else { b.length() };
    let mut i = 0;

    while (i < min) {
        if (a[i] < b[i]) {
            return true
        };
        if (a[i] > b[i]) {
            return false
        };
        i = i + 1;
    };

    a.length() < b.length()
}