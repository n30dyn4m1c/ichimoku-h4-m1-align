#!/usr/bin/env python3
"""Parse and type-check an .mq5 file with g++, against a stub of the MQL5 API.

This is NOT MetaEditor and proves nothing about how the EA trades. It catches what a C++
front end can see in MQL5 source: unbalanced braces, misspelt or undeclared names, wrong
argument counts, a value assigned to an input. It was
written for sessions that have no MetaEditor; compile in MetaEditor before running anything.

The stub (mql5_stub.h) covers the API the bottom-up stack EAs use. An "undeclared" error on a
real MQL5 function means the stub needs that function added, not that the EA is wrong.

    python3 utilities/mq5-check/mq5check.py experiments/experimental-vps-revamp-ea.mq5
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def to_cpp(src):
    # MQL5 lets a function be called above its definition, C++ does not: declare them all first.
    protos = re.findall(r"^((?:int|bool|void|double|string|datetime|long|ulong) +\w+\([^)]*\))\s*$", src, re.M)
    out = ['#include "mql5_stub.h"\n' + " ".join(p + ";" for p in protos)]
    for line in src.split("\n"):
        if re.match(r"\s*#(property|include)\b", line) or re.match(r"\s*input\s+group\b", line):
            out.append("")
            continue
        line = re.sub(r"^(\s*)input\s+", r"\1const ", line)                                   # inputs are read-only
        line = re.sub(r"^(\s*)(\w+)\s+(\w+)\[\];", r"\1DynArr<\2> \3;", line)                 # dynamic arrays
        out.append(line)
    return "\n".join(out)


def main():
    bad = 0
    for path in sys.argv[1:]:
        with tempfile.NamedTemporaryFile("w", suffix=".cpp", dir=HERE, delete=False) as f:
            f.write(to_cpp(open(path, encoding="utf-8").read()))
        r = subprocess.run(["g++", "-std=c++17", "-fsyntax-only", "-Wall", "-Wextra", "-Wno-unused-parameter",
                            "-Wno-unknown-pragmas", "-I", HERE, f.name], capture_output=True, text=True)
        os.unlink(f.name)
        msg = r.stderr.replace(f.name, path)                 # line numbers are those of the .mq5 plus one
        print(f"{path}: {'OK' if r.returncode == 0 and not msg.strip() else 'see below'}")
        if msg.strip():
            print(msg)
        bad += r.returncode != 0
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
