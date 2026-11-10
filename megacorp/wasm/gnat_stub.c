/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Robert Boettcher */

/* libgnat calls this to print an exception. The live path does not. */
void __gnat_put_exception (int file, int line, int column)
{
   (void) file;
   (void) line;
   (void) column;
}

/* Grow the wasm memory by `pages` of 64 KiB. Return the previous
   page count, which is what the runtime's allocator adds. */
unsigned int __gnat_grow (unsigned int pages)
{
   return (unsigned int) __builtin_wasm_memory_grow (0, (int) pages);
}
