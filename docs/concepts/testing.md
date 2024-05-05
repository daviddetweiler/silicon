# Unit testing in `silicon`

The recent discovery of a new bug in block comments specific to the file input subsystem has made it clear to me that
`silicon` is sufficiently complex as to require proper unit testing to assure correctness. The problem is that in order
to achieve maximum coverage, the "kernel" test suite must essentially be integrated into the kernel itself. An excess of
caution leads me to believe that the test suite must use its own independent fork of whatever code it depends on, which
leads to questions about exactly how to build a test suite that can test everything from extremely low-level core
routines to larger concerns, such as verifying the behavior of the bootstrap decompressor. In the latter case I see no
way to test it that doesn't involve somehow wrapping the decompressor as threaded code and having file load/unload
capbilities in the test harness.

On the other hand, external testing harnesses have the gross disadvantage of requiring build system assistance.

An idea: port the decompressor to threaded code and build a threaded-code testing harness, while shunting off the more
dubious steps (like file loads) into the unit tests themselves. Though that might require a _highly_ invasive set of
changes to `silicon`. It also means having to put threaded code in the bootstrapping stub and greatly increasing its
size, which I don't like... The only way to directly test the bootstrapping stub is to have the test harness do a
context switch, since it uses _all_ the CPU registers. Not to mention the difficulty in actually providing the stub to a
unit test, considering the build system magic that goes into inserting it in the first place. Perhaps possible for a
second-gen metacompiled version, but as it stands, testing that stub cannot be done without support from `nasm` or the
makefile. I see a clear way forward for unit-testing all the kernel routines (namely writing a threaded test harness and
guarding it and the unit tests behind an ifdef that switches the entry point as well), but that stub will be a problem.

The environment to be replicated for the kernel routines is easy: it's just the threading engine plus some setup steps
expected by the routine, which can be integrated in the unit tests. But the threading engine itself, if it were worth
testing, and the bootstrap stub itself, are essentially raw assembly code with free reign of the processor, and the
former expects to be the very first code executed in the process. It has to somehow be repackaged in a way that makes it
possible to run tests on it, which is really, really hard considering that it yields control to the decompressed blob
pretty much unconditionally. Not to mention, how do we support the ability to specify what blob it should be packaged
with in a unit test?

There is also the problem of unit-testing the interpreter; I see no way to accomplish this without an external test
harness, since the terminal subsystem itself is under scrutiny here and feeding it a mocked string is simply out of the
question.
