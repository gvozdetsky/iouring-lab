#!/usr/bin/env python3
"""Wire the io_uring contest group and runtimetest check into youki (idempotent)."""
import pathlib, sys

root = pathlib.Path.home() / "iouring-lab/youki"

def edit(rel, old, new):
    p = root / rel
    text = p.read_text()
    if new in text:
        print(f"{rel}: already done")
        return
    if text.count(old) != 1:
        sys.exit(f"{rel}: anchor found {text.count(old)} times")
    p.write_text(text.replace(old, new))
    print(f"{rel}: edited")

edit("Cargo.toml", 'flate2 = "1.1"\n', 'flate2 = "1.1"\nio-uring = "0.7"\n')
edit("tests/contest/runtimetest/Cargo.toml", "caps = { workspace = true }\n",
     "caps = { workspace = true }\nio-uring = { workspace = true }\n")
edit("tests/contest/runtimetest/src/main.rs", "mod tests;\n", "mod io_uring;\nmod tests;\n")
edit("tests/contest/runtimetest/src/main.rs",
     '        "tmpcopyup" => tests::validate_tmpcopyup(&spec),\n',
     '        "tmpcopyup" => tests::validate_tmpcopyup(&spec),\n'
     '        "io_uring" => io_uring::validate_io_uring(),\n')
edit("tests/contest/contest/src/tests/mod.rs", "pub mod io_priority;\n",
     "pub mod io_priority;\npub mod io_uring;\n")
edit("tests/contest/contest/src/main.rs",
     "use crate::tests::io_priority::get_io_priority_test;\n",
     "use crate::tests::io_priority::get_io_priority_test;\n"
     "use crate::tests::io_uring::get_io_uring_tests;\n")
edit("tests/contest/contest/src/main.rs",
     "    let io_priority_test = get_io_priority_test();\n",
     "    let io_priority_test = get_io_priority_test();\n"
     "    let io_uring = get_io_uring_tests();\n")
edit("tests/contest/contest/src/main.rs",
     "    tm.add_test_group(Box::new(io_priority_test));\n",
     "    tm.add_test_group(Box::new(io_priority_test));\n"
     "    tm.add_test_group(Box::new(io_uring));\n")
