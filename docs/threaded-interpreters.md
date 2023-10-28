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
