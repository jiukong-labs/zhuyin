#!/usr/bin/env python3
"""Compare complete dictionary content across SQLite file-format versions.

Usage: python3 scripts/check-dictionary-reproduction.py pinned.sqlite3 rebuilt.sqlite3
"""

import sys
import pathlib
import sqlite3

pinned = pathlib.Path(sys.argv[1]).resolve()
rebuilt = pathlib.Path(sys.argv[2]).resolve()
with sqlite3.connect(pinned.as_uri() + "?mode=ro", uri=True) as expected, \
     sqlite3.connect(rebuilt.resolve().as_uri() + "?mode=ro", uri=True) as actual:
    for connection in (expected, actual):
        assert connection.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
    for pragma in ("user_version", "application_id"):
        assert expected.execute("PRAGMA " + pragma).fetchall() == actual.execute("PRAGMA " + pragma).fetchall(), pragma
    schema_query = "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"
    assert expected.execute(schema_query).fetchall() == actual.execute(schema_query).fetchall(), "Dictionary schema differs"
    tables = expected.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").fetchall()
    for (table,) in tables:
        quoted = '"' + table.replace('"', '""') + '"'
        columns = expected.execute("PRAGMA table_info(" + quoted + ")").fetchall()
        order = ", ".join(str(index + 1) for index in range(len(columns)))
        query = "SELECT * FROM " + quoted + " ORDER BY " + order
        assert expected.execute(query).fetchall() == actual.execute(query).fetchall(), "Dictionary table differs: " + table
    print("All dictionary schemas, metadata, and rows reproduced exactly.")
    if pinned.read_bytes() != rebuilt.read_bytes():
        print("SQLite file bytes differ across toolchains; logical content is identical.")
