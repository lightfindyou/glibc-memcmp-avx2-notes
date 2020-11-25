# glibc-memcmp-avx2-notes
A simple note for reading glibc memcmp asm code

A new version of memcmp which add a fourth parameter to return the first memory addr that diff.
Put two file in same dir, compile with command *gcc -ggdb -o memcmpGlibcASM memcmpGlibcASM.c memcmp-avx2-addr.S* , run with *./memcmpGlibcASM*