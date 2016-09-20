library IEEE;
use IEEE.std_logic_1164.all;

-- [x] Make the pretty-print procedure for trap information to finish
--     pretty-printed simulation output.
-- [x] Make bus logic stuff for control registers.
-- [x] Make package with procedures which allow procedural
--     generation/configuration of the control registers, so cxreg and gbreg
--     don't become one big mess.
-- [x] Figure out the register map again, with all changes that I've implicitly
--     made embedded in it.
-- [x] Code cxreg and gbreg, (hopefully) in such a way that the code is neatly
--     formatted enough to double as a register map table.
-- [x] Port general purpose register file from current rvex design to the code
--     style of the new design and add the debug bus interface and forwarding
--     to it.
-- [x] Make a testbench for the processor which accepts a bunch of test cases
--     with assembly input and a set of expected memory accesses. (mostly done)
-- [x] Make a lot of those test cases.
-- [x] Debug core.
-- [x] Make synthesizable standalone core design to synthesize and test on the
--     ML605.
-- [x] Debug standalone on ML605.
-- (standalone core should be functional at this point) [it is, mostly]
-- [x] Make reconfCache generic-configurable.
-- [x] Add the necessary extra status outputs to reconfCache.
-- [x] Fix the incorrect flushing behavior for bypass writes while you're at
--     it.
-- [ ] Make cached core design.
-- [ ] Make a synthesizable testbench thing to test the core + cache without
--     needing to deal with grlib first.
-- [ ] Debug cache(d core) on ML605.
-- [ ] Connect cached core design to grlib.
-- [ ] Debug grlib'd core on ML605.
-- (full core should be functional at this point)
-- [ ] Optimize timing performance if necessary/possible.
-- [ ] Add performance counters, at least to the point where it supports the
--     same stuff as the old core.
-- [ ] Add ll/sc instructions.
-- [ ] Make basic PDF with documentation.
-- [ ] Wrap everything up in a box nicely.

entity todo is
end todo;

architecture Behavioral of todo is
begin
end Behavioral;

