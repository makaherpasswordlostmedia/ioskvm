@ iOS/armv7 stub for the C interpreter build (counterpart of AsmStubs_mips.s):
@ the C loop only needs the 'end_of_the_world' marker symbol. Mach-O prefixes C symbols with '_',
@ so both spellings are provided.
.text
.align 2
.globl end_of_the_world
.globl _end_of_the_world
end_of_the_world:
_end_of_the_world:
