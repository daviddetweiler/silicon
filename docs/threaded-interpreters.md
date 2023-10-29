# Threaded Interpreters

These are, first and foremost, stack-based virtual machines with a very thin interpreted skin atop them. However, they
slightly generalize over a "pure" stack-based DTC sequencer by employing literals and indirect threading (to support
parameterization). The natural sequence of logical ideas that yields these (at least their inner interpreters) is:
1. Cheapest way to represent VM instructions (DTC)
2. Cheapest way to represent parameterization (literal values)
3. Cheapest way to have shared thread sections (`invoke_thread`, return stack, data areas, ITC)

Another way of looking at it is how to de-duplicate code as aggressively as possible: essentially representing any
computation as a sequence of function calls, which is the inspiration for DTC. Then the need for cheap parameter-passing
naturally brings in the idea of the data stack and in-thread literals, and the idea of having a threaded subroutine
brings in step 3.

What is a program if not a sequence of instructions? We want to abstract just one layer up from assembly language, so
each one of our "instructions" may execute any number of machine-language instructions. Given some list of instructions,
we wish to execute their code in sequence. So let's make each "instruction" a pointer to its machine code. To make it
run, we need some kind of "inner interpreter." So we keep track of the instruction pointer, and each cycle, we fetch
from the instruction pointer, advance it, then jump to the code. Each code fragment then just jumps back to the inner
interpreter to continue. But, since it's so small to begin with, we could just inline this "next" function after each
code fragment.

A single data stack is the most obvious way to pass information between instructions, and the most obvious way to
provide constant arguments to them is to provide them inline in the thread. So we get literals, branches, jumps, etc.
Now, we would like to have subroutines. This requires a way to keep a stack of return addresses to jump back to, and it
is much more convenient if it is a separate stack. So we come up with `call`/`return`, with `call` taking an immediate
pointer to a thread, pushing the return address, and `return` restoring it. But this is wasteful: there will be many
instances of the same `call`-address pair, which should functionally behave as a single instruction. The solution here
is to add a level of indirection. Each "instruction" is now a pointer to a variable-length structure that starts with a
code pointer (so `next` needs be adjusted). `next` is modified to maintain `wp`, a register indicating the start of the
current such structure being executed. Through `wp`, the code can access its stored arguments in the rest of the data
structure. Now, since we can have variable-length payloads, we can inline the stored thread, replacing the pointer.
