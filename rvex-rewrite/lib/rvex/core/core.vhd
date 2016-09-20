-- r-VEX processor
-- Copyright (C) 2008-2016 by TU Delft.
-- All Rights Reserved.

-- THIS IS A LEGAL DOCUMENT, BY USING r-VEX,
-- YOU ARE AGREEING TO THESE TERMS AND CONDITIONS.

-- No portion of this work may be used by any commercial entity, or for any
-- commercial purpose, without the prior, written permission of TU Delft.
-- Nonprofit and noncommercial use is permitted as described below.

-- 1. r-VEX is provided AS IS, with no warranty of any kind, express
-- or implied. The user of the code accepts full responsibility for the
-- application of the code and the use of any results.

-- 2. Nonprofit and noncommercial use is encouraged. r-VEX may be
-- downloaded, compiled, synthesized, copied, and modified solely for nonprofit,
-- educational, noncommercial research, and noncommercial scholarship
-- purposes provided that this notice in its entirety accompanies all copies.
-- Copies of the modified software can be delivered to persons who use it
-- solely for nonprofit, educational, noncommercial research, and
-- noncommercial scholarship purposes provided that this notice in its
-- entirety accompanies all copies.

-- 3. ALL COMMERCIAL USE, AND ALL USE BY FOR PROFIT ENTITIES, IS EXPRESSLY
-- PROHIBITED WITHOUT A LICENSE FROM TU Delft (J.S.S.M.Wong@tudelft.nl).

-- 4. No nonprofit user may place any restrictions on the use of this software,
-- including as modified by the user, by any other authorized user.

-- 5. Noncommercial and nonprofit users may distribute copies of r-VEX
-- in compiled or binary form as set forth in Section 2, provided that
-- either: (A) it is accompanied by the corresponding machine-readable source
-- code, or (B) it is accompanied by a written offer, with no time limit, to
-- give anyone a machine-readable copy of the corresponding source code in
-- return for reimbursement of the cost of distribution. This written offer
-- must permit verbatim duplication by anyone, or (C) it is distributed by
-- someone who received only the executable form, and is accompanied by a
-- copy of the written offer of source code.

-- 6. r-VEX was developed by Stephan Wong, Thijs van As, Fakhar Anjam,
-- Roel Seedorf, Anthony Brandon, Jeroen van Straten. r-VEX is currently
-- maintained by TU Delft (J.S.S.M.Wong@tudelft.nl).

-- Copyright (C) 2008-2016 by TU Delft.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- pragma translate_off
use IEEE.std_logic_textio.all;
-- pragma translate_on

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.core_pkg.all;
use rvex.core_intIface_pkg.all;
use rvex.core_trap_pkg.all;
use rvex.core_pipeline_pkg.all;
use rvex.core_ctrlRegs_pkg.all;
--use rvex.cache_pkg.all;

-- pragma translate_off
use rvex.simUtils_pkg.all;
use std.textio.all;
-- pragma translate_on


-------------------------------------------------------------------------------
-- Processor overview and naming conventions
-------------------------------------------------------------------------------
-- The figure below shows how the rvex core is organized. The abbreviations
-- used are keyed below.
-- 
-- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
--
--          .--------------------------------------------------------.
--          | rv  .----------------------------------------.         |
--          |     | pls (pipelanes)                        |         |
--          |     |  .==================================.  | .-----. |
--          |     |  | pl (pipelane)                    |  | |gpreg| |
--          |     |  |  - . .---.  - - .  - - .  - - .  |  | |.===.| |
--          |     |  | |br  |alu| |mulu  |memu  |brku   |<-+>||fwd|| |
--          |     |  |  - ' '---'  - - '  - - '  - - '  |  | |'==='| |
--          |     |  '=================================='  | '-----' |
--          |     |    ^     |   ^      ^      ^      ^    |    ^    |
--          |     |    v     |   |      |      |      |    |    |    |
--          |     | .------. |   v      v      v      v    |    |    |
--          |     | |cxplif| | .====. .----. .----. .----. |    |    |
-- rctrl <--+-----+>|.===. | | |dmsw| |sbit| |trap| |limm| |    |    |
--          |     | ||fwd| | | '====' '----' '----' '----' |    |    |
--          |     | |'===' | |  ^  ^                       |    |    |
--          |     | '------' |  |  '-----------------------+----+----+--> dmem
--          |     |   ^  ^   |  |                          |    |    |
--          |     '---+--+---+--+--------------------------'    |    |
--          | .----.  |  |   |  |                               |    |
--  imem <--+>|ibuf|<-'  |   |  '-.  .--------------------------'    |
--          | '----'     v   |    v  v                               |
-- rctrl    |       .=====.  |   .----.      .-----.      .-----.    |
-- reset <--+------>|cxreg|<-+-->|creg|<---->|gbreg|<---->|     |<---+--> mem
-- and done |       '====='  |   '----'      '-----'      | cfg |    |
--          |        |   |   |      ^           ^   ...<--|     |    |
--          |        |   '---+------+-----------+-------->|     |    |
--          |        v       |      |           |         '-----'    |--> sim
--          |        - - -   |      |           |                    |
--          |       |trace|<-'      |           |                    |
--          |        - - -          |           |                    |
--          |          |            |           |                    |
--          '----------+------------+-----------+--------------------'
--                     |            |           |
--                     v            v           |
--                   trsink        dbg    imem affinity
--
-- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
--
-- The abbreviations for the blocks used in the diagram are the following.
-- 
--  - rv     = RVex processor             @ core.vhd
--  - pls    = PipeLaneS                  @ core_pipelanes.vhd
--  - pl     = PipeLane                   @ core_pipelane.vhd
--  - br     = BRanch unit                @ core_branch.vhd
--  - alu    = Arith. Logic Unit          @ core_alu.vhd
--  - memu   = MEMory Unit                @ core_memu.vhd
--  - mulu   = MULtiply Unit              @ core_mulu.vhd
--  - brku   = BReaKpoint Unit            @ core_breakpoint.vhd
--  - gpreg  = General Purpose REGisters  @ core_gpRegs.vhd
--  - fwd    = ForWarDing logic           @ core_forward.vhd
--  - cxplif = ConteXt-PipeLane InterFace @ core_contextPipelaneIFace.vhd
--  - dmsw   = Data Memory SWitch         @ core_dmemSwitch.vhd
--  - sbit   = Stop BIT related routing   @ core_stopBitRouting.vhd
--  - trap   = TRAP routing               @ core_trapRouting.vhd
--  - limm   = Long IMMediate routing     @ core_limmRouting.vhd
--  - ibuf   = Instruction BUFfer         @ core_instructionBuffer.vhd
--  - cxreg  = ConteXt REGister logic     @ core_contextRegLogic.vhd
--  - creg   = Control REGisters          @ core_ctrlRegs.vhd
--  - gbreg  = GloBal REGister logic      @ core_globalRegLogic.vhd
--  - cfg    = ConFiGuration control      @ core_cfgCtrl.vhd
--  - trace  = TRACE unit                 @ core_trace.vhd
--  - mem    = interface common to instruction and data MEMory/cache
--  - imem   = Instruction MEMory/cache
--  - dmem   = Data MEMory/cache
--  - dbg    = DeBuG bus interface
--  - rctrl  = Run ConTRoL
--  - sim    = vhdl SIMulation only
--  - trsink = TRace data SINK
--
-- The pipelane (pl), ALU and multiplier blocks are instantiated for each
-- pipelane (although the multiplier can be disabled for selected pipelanes
-- through design-time configuration). The memory unit (memu), breakpoint
-- unit (brku), branch unit (br) and data memory switch blocks are
-- instantiated for each pipelane *group*. The context register logic (cxreg)
-- block is instantiated for each context. Blocks which are instantiated
-- multiple times are shown with double (=====) lines in the block diagram,
-- blocks which are instantiated optionally are shown with dashed ( - - )
-- lines.
--
-- Some blocks have subblocks which are not shown in this block diagram.
-- The entity names and filenames for these blocks are of the form
-- core_<block>_<subblock>.vhd. In general, _ is used as a hierarchy
-- separator in the code, whereas camelCase is used to indicate word
-- boundaries.
--
-- Most signal names have the form <source>2<dest>_<name>, where source and
-- dest are the block abbreviations of the source and destination blocks
-- respectively. In addition, "any" is used as destination for the
-- configuration control signals shared between a large number of blocks, as
-- indicated by the ellipsis in the block diagram.
--
-- Pipeline related signals are array-indexed by their pipeline stage index
-- using increasing ranges wherever possible. Also, in the pipelines
-- themselves, every state signal which passes through a pipeline register is
-- generally duplicated for every pipeline stage. This simplifies the
-- pipeline register code, makes things more readable, and makes debugging
-- the core in VHDL simulation much simpler. A downside is that it is not
-- trivial to see just how many registers are actually used. Also, it is of
-- vital importance for the area usage of the processor that the synthesizer
-- properly culls unused registers.
--
-----------------------------------------------------------------------------
-- VHDL packages
-----------------------------------------------------------------------------
-- The following VHDL packages are used within the processor. Only core_pkg
-- and the generic common_pkg is necessary to instantiate the core.
--
--  - core_pkg
--      -> Contains data types used in the toplevel interface description of
--         the rvex processor and the component specification for the
--         toplevel block.
--
--  - core_intIface_pkg
--      -> Contains data types and constants used throughout the core, in
--         addition to those in core_pkg.
--
--  - core_pipeline_pkg
--      -> Contains constants which specify what should happen in which
--         pipeline stage. In theory, it should be possible to change this
--         without modifying code to change timing characteristics, but not
--         everything is tested and it's relatively easy to break things
--         here.
--
--  - core_opcode_pkg, core_opcodeAlu_pkg, core_opcodeMultiplier_pkg,
--    core_opcodeDatapath_pkg, core_opcodeBranch_pkg, core_opcodeMemory_pkg
--      -> Contains a constant table of all decoding signals based on the
--         opcode field of a syllable, as well as disassembly information for
--         simulation. In theory, there should be no other mappings from
--         opcode to functionality elsewhere in the code. Control signals for
--         the various functional units are specified in core_opcode_pkg as
--         constants, which are defined in the core_opcode*_pkg packages, in
--         order to keep the line count sane.
--
--  - core_trap_pkg
--      -> Similar to core_opcode_pkg, this packages contains a decoding
--         table for trap causes.
--
--  - core_ctrlRegs_pkg
--      -> Contains constants defining the control register map at the word
--         level and some types and records used in the core.
--
--  - core_asDisas_pkg
--      -> Contains simulation-only assembly and pretty-printing related
--         methods.

--=============================================================================
-- This is the toplevel entity for the rvex core.
-------------------------------------------------------------------------------
entity core is
--=============================================================================
  generic (
    
    -- Configuration.
    CFG                         : rvex_generic_config_type := rvex_cfg;
    
    -- This is used as the core index register in the global control registers.
    CORE_ID                     : natural := 0;
    
    -- Does the same thing as CORE_ID above (or well, they're added to each
    -- other so both are supported). Exists for compatibility only; new designs
    -- should use CORE_ID as it adheres to the naming conventions.
    CoreID                      : natural := 0;
    
    -- Platform version tag. This is put in the global control registers.
    PLATFORM_TAG                : std_logic_vector(55 downto 0) := (others => '0');
    
    -- Register consistency check output filename.
    RCC_RECORD                  : string := "";
    
    -- Register consistency check input filename.
    RCC_CHECK                   : string := "";
    
    -- Context to use for the consistency check.
    RCC_CTXT                    : natural := 0
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- This signal is asserted high when the debug bus writes a one to the
    -- reset flag in the control registers. In this case, reset is already
    -- asserted internally, so this signal may be ignored. For more complex
    -- systems, the signal may be used to reset support systems as well.
    resetOut                    : out std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Active high global clock enable input.
    clkEn                       : in  std_logic := '1';
    
    ---------------------------------------------------------------------------
    -- VHDL simulation debug information
    ---------------------------------------------------------------------------
    -- pragma translate_off
    
    -- Describes the current state of the processor, aligned with the last
    -- pipeline stage. Only generated when GEN_VHDL_SIM_INFO in
    -- rvex_intIface_pkg is true. You don't need to connect anything to this
    -- (and with such a complicated config-dependent array size you don't want
    -- to either); just leave it open but add it to the simulation trace if
    -- you want to see what the processor is doing.
    rv2sim                      : out rvex_string_array(1 to 2*2**CFG.numLanesLog2+2**CFG.numLaneGroupsLog2+2**CFG.numContextsLog2);
    
    -- pragma translate_on
    
    ---------------------------------------------------------------------------
    -- Run control interface
    ---------------------------------------------------------------------------
    -- External interrupt request signal, active high.
    rctrl2rv_irq                : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0) := (others => '0');
    
    -- External interrupt identification. Guaranteed to be loaded in the trap
    -- argument register in the same clkEn'd cycle where irqAck is high.
    rctrl2rv_irqID              : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0) := (others => (others => '0'));
    
    -- External interrupt acknowledge signal, active high. Goes high for one
    -- clkEn'abled cycle.
    rv2rctrl_irqAck             : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high run signal. When released, the context will stop running as
    -- soon as possible.
    rctrl2rv_run                : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0) := (others => '1');
    
    -- Active high idle output. This is asserted when the core is no longer
    -- doing anything.
    rv2rctrl_idle               : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high break output. This is asserted when the core is waiting for
    -- an externally handled breakpoint, or the B flag in DCR is otherwise set.
    rv2rctrl_break              : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high trace stall output. This can be used to stall other cores
    -- and timers simultaneously in order to be able to trace more accurately.
    rv2rctrl_traceStall         : out std_logic;
    
    -- Trace stall input. This just stalls all lane groups when asserted.
    rctrl2rv_traceStall         : in  std_logic := '0';
    
    -- Active high context reset input. When high, the context control
    -- registers (including PC, done and break flag) will be reset.
    rctrl2rv_reset              : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0) := (others => '0');
    
    -- Reset vector. When the context or the entire core is reset, the PC
    -- register will be set to this value.
    rctrl2rv_resetVect          : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0) := CFG.resetVectors(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high done output. This is asserted when the context encounters
    -- a stop syllable. Processing a stop signal also sets the BRK control
    -- register, which stops the core. This bit can be reset by issuing a core
    -- reset or by means of the debug interface.
    rv2rctrl_done               : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Common memory interface
    ---------------------------------------------------------------------------
    -- Decouple vector to the instruction and data memory/caches. This vector
    -- works as follows. Each pipelane group has a bit in the vector. When this
    -- bit is low, the pipelane group is a slave to the first higher-indexed
    -- group which has a high decouple bit. In such a case, the following
    -- interfacing rules apply:
    --  - All groups will issue instruction memory read commands regardless of
    --    decouple state. However, coupled groups will always make aligned
    --    accesses. In other words, you could for example only use the PC from
    --    the lowest indexed pipelane group just make wider memory accesses to
    --    deliver all the syllables.
    --  - The memories must provide equal stall and blockReconfig signals to
    --    coupled pipelane groups or behavior will be undefined.
    --  - The memories must provide equal stall signals to coupled pipelane
    --    groups or behavior will be undefined.
    -- The rvex core will follow the following rules:
    --  - Pipelane groups working together are properly aligned (see also the
    --    config control signal documentation) and the highest indexed debouple
    --    bit is always high. For example, for an rvex with 8 lanes and 4
    --    pipelane groups, the only decouple outputs generated under normal
    --    conditions are "1111", "1110", "1011", "1010" and "1000".
    --  - The decouple outputs will not split or merge two groups when either
    --    group is asserting the blockReconfig signal.
    rv2mem_decouple             : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high reconfiguration block input from the instruction and data
    -- memories. When this is low, associated lanes may not be reconfigured.
    -- The processor assumes that this signal will go low eventually when no
    -- fetch/read/write requests are made by associated lanes.
    mem2rv_blockReconfig        : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    
    -- Stall inputs from the instruction and data memories. When a bit in this
    -- vector is high, the associated pipelane group will stall. Equal stall
    -- signals must be provided to coupled pipelane groups (see also the
    -- mem_decouple signal documentation).
    mem2rv_stallIn              : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    
    -- Stall outputs to the instruction and data memories. When a bit in this
    -- vector is high, the associated pipelane group will not register data
    -- from the memories on the next rising clock edge, and the memories should
    -- ignore any commands given. The stall output is guaranteed to be high if
    -- the stall input is high, but the rvex may pull the stall output high for
    -- reasons other than memory stalls as well.
    rv2mem_stallOut             : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Cache performance information signals. Optional. Refer to core_pkg.vhd
    -- for more information about this signal (look for rvex_cacheStatus_type).
    mem2rv_cacheStatus          : in  rvex_cacheStatus_array(2**CFG.numLaneGroupsLog2-1 downto 0) := (others => RVEX_CACHE_STATUS_IDLE);
    
    ---------------------------------------------------------------------------
    -- Instruction memory interface
    ---------------------------------------------------------------------------
    -- Program counters from each pipelane group.
    rv2imem_PCs                 : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high instruction fetch enable signal. When a bit in this vector
    -- is high, the bit in mem_stallOut is low and the bit in mem_decouple is
    -- high, the instruction memory must fetch the instruction pointed to by
    -- the associated vector in imem_pcs.
    rv2imem_fetch               : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Combinatorial cancel signal, valid one cycle after rv2imem_PCs and
    -- rv2imem_fetch, regardless of memory stalls. This will go high when a
    -- branch is detected by the next pipeline stage and the previously
    -- requested instruction is not going to be executed. In this case, the
    -- instruction memory may choose not to complete the request if that is
    -- faster somehow (a cache may choose to cancel line validation if a miss
    -- occured to allow the core to continue earlier). Note that this signal
    -- can be safely ignored for proper operation, it's just a hint which may
    -- be used to speed things up.
    rv2imem_cancel              : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- (L_IF_MEM clock cycles delay with clkEn high and stallOut low; L_IF_MEM
    -- is set in core_pipeline_pkg.vhd)
    
    -- Fetched instruction, from instruction memory to the rvex.
    imem2rv_instr               : in  rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Cache block affinity data from cache. This should be set to cache block
    -- index which serviced the request. This is just a hint for the processor
    -- (when a core splits, the affinity values are used to determine which
    -- lane the context which was running should be run on for maximum cache
    -- locality).
    imem2rv_affinity            : in  std_logic_vector(2**CFG.numLaneGroupsLog2*CFG.numLaneGroupsLog2-1 downto 0) := (others => '1');
    
    -- Active high fault signals from the instruction memory. When high,
    -- imem2rv_instr is assumed to be invalid and an exception will be thrown.
    imem2rv_busFault            : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    
    ---------------------------------------------------------------------------
    -- Data memory interface
    ---------------------------------------------------------------------------
    -- Data memory addresses from each pipelane group. Note that a section
    -- of the address space 1kiB in size must be mapped to the core control
    -- registers, making that section of the data memory inaccessible.
    -- The start address of this section is configurable with CFG.
    rv2dmem_addr                : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high read enable from each pipelane group. When a bit in this
    -- vector is high, the bit in mem_stallOut is low and the bit in
    -- mem_decouple is high, the data memory must fetch the data at the address
    -- specified by the associated vector in dmem_addr.
    rv2dmem_readEnable          : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Write data from the rvex to the data memory.
    rv2dmem_writeData           : out rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Write byte mask from the rvex to the data memory, active high.
    rv2dmem_writeMask           : out rvex_mask_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active write enable from each pipelane group. When a bit in this
    -- vector is high, the bit in mem_stallOut is low and the bit in
    -- mem_decouple is high, the data memory must write the data in
    -- dmem_writeData to the address specified by dmem_addr, respecting the
    -- byte mask specified by dmem_writeMask.
    rv2dmem_writeEnable         : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- (L_MEM clock cycles delay with clkEn high and stallOut low; L_MEM is set
    -- in core_pipeline_pkg.vhd)
    
    -- Data output from data memory to rvex.
    dmem2rv_readData            : in  rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high fault signals from the data memory. When high,
    -- dmem2rv_readData is assumed to be invalid and an exception will be
    -- thrown.
    dmem2rv_ifaceFault          : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    dmem2rv_busFault            : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0) := (others => '0');
    
    ---------------------------------------------------------------------------
    -- Control/debug bus interface
    ---------------------------------------------------------------------------
    -- The control/debug bus interface may be used to access the core control
    -- registers for debugging. All cores are forcibly stalled when a read or
    -- write is requested here, such that addressing logic may be reused. More
    -- information about the memory map is available in core_ctrlRegs_pkg.vhd.
    
    -- Address for the request. Only the 13 LSB are currently used in the
    -- largest configuration.
    dbg2rv_addr                 : in  rvex_address_type := (others => '0');
    
    -- Active high read enable signal.
    dbg2rv_readEnable           : in  std_logic := '0';
    
    -- Active high write enable signal.
    dbg2rv_writeEnable          : in  std_logic := '0';
    
    -- Active high byte write mask signal.
    dbg2rv_writeMask            : in  rvex_mask_type := (others => '1');
    
    -- Write data.
    dbg2rv_writeData            : in  rvex_data_type := (others => '0');
    
    -- (one clock cycle delay with clkEn high)
    
    -- Read data.
    rv2dbg_readData             : out rvex_data_type;
    
    ---------------------------------------------------------------------------
    -- Trace interface
    ---------------------------------------------------------------------------
    -- These signals connect to the optional trace unit. When the trace unit is
    -- disabled in CFG, these signals are unused.
    
    -- When high, data is valid and should be registered in the next clkEn'd
    -- cycle.
    rv2trsink_push              : out std_logic;
    
    -- Trace data signal. Valid when push is high.
    rv2trsink_data              : out rvex_byte_type;
    
    -- When high, this is the last byte of this trace packet. This has the same
    -- timing as the data signal.
    rv2trsink_end               : out std_logic;
    
    -- When high while push is high, the trace unit is stalled. While stalled,
    -- push will stay high and data and end will remain stable.
    trsink2rv_busy              : in  std_logic := '0'
    
  );
end core;

--=============================================================================
architecture Behavioral of core is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Configuration signals
  -----------------------------------------------------------------------------
  -- Current encoded configuration word.
  signal cfg2any_configWord           : rvex_data_type;
  
  -- Diagonal block matrix of n*n size, where n is the number of pipelane
  -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
  -- context, or low when they don't.
  signal cfg2any_coupled              : std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Decouple vector. This is just another way to look at the coupled matrix.
  -- The vector is assigned such that dec_i = not C_i,i+1. The MSB in the
  -- vector is always high. This representation is useful because the bits
  -- can also be regarded as master/slave bits: when the decouple bit for
  -- a group is high, it is a master, otherwise it is a slave. Slaves answer
  -- to the next higher indexed master group.
  signal cfg2any_decouple             : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- log2 of the number of coupled pipelane groups for each pipelane group.
  signal cfg2any_numGroupsLog2        : rvex_2bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Specifies the context associated with the indexed pipelane group.
  signal cfg2any_context              : rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Specifies whether the indexed pipeline group is active.
  signal cfg2any_active               : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Last pipelane group associated with each context.
  signal cfg2any_lastGroupForCtxt     : rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
  
  -- The lane index within the coupled groups for each lane.
  signal cfg2any_laneIndex            : rvex_4bit_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- The amount which the branch unit residing in the indexed lane should
  -- add to the current PC to get PC_plusOne, should it be the active branch
  -- unit.
  signal cfg2any_pcAddVal             : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Internal signals
  -----------------------------------------------------------------------------
  -- Reset signal from the global control registers.
  signal gbreg2rv_reset               : std_logic;
  
  -- Internal reset signal, asserted when either the external reset signal or
  -- the signal from the global control registers is asserted.
  signal reset_s                      : std_logic;
  
  -- Stall signal for each pipelane group.
  signal stall                        : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Debug bus access stall signals. For every debug bus access, the rvex core
  -- is stalled for two cycles. This is done to allow the debug bus to make use
  -- of the existing bus networks by claiming the bus from one of the
  -- pipelanes.
  signal debugBusStall                : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Trace unit stall signal. When the trace unit is busy outputting trace
  -- data, this will be high, to prevent the core from overflowing the trace
  -- unit with data.
  signal traceStall                   : std_logic;
  
  -- Extended memory exception trap information. These are decoded from the
  -- fault flags coming from the memory into a trap information record which
  -- the processor knows how to deal with.
  signal imem2ibuf_exception          : trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmem2dmsw_exception          : trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Interconnect signals
  -----------------------------------------------------------------------------
  -- For all the signals below: refer to the entity description of their source
  -- or destination block for documentation.
  
  -- Instruction buffer <-> pipelane (interface) signals.
  signal cxplif2ibuf_PCs              : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cxplif2ibuf_fetchPCs         : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cxplif2ibuf_branch           : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cxplif2ibuf_fetch            : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal cxplif2ibuf_cancel           : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal ibuf2pl_instr                : rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
  signal ibuf2pl_exception            : trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Pipelane <-> configuration control signals.
  signal cfg2cxplif_active            : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cfg2cxplif_requestReconfig   : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cfg_blockReconfig     : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  
  -- Data memory switch <-> control register signals.
  signal dmsw2creg_addr               : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmsw2creg_writeData          : rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmsw2creg_writeMask          : rvex_mask_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmsw2creg_writeEnable        : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmsw2creg_readEnable         : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal creg2dmsw_readData           : rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Pipelane <-> general purpose register file signals.
  signal pl2gpreg_readPorts           : pl2gpreg_readPort_array(2*2**CFG.numLanesLog2-1 downto 0);
  signal gpreg2pl_readPorts           : gpreg2pl_readPort_array(2*2**CFG.numLanesLog2-1 downto 0);
  signal pl2gpreg_writePorts          : pl2gpreg_writePort_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- Control registers <-> general purpose register file signals.
  signal creg2gpreg_claim             : std_logic;
  signal creg2gpreg_addr              : rvex_gpRegAddr_type;
  signal creg2gpreg_ctxt              : std_logic_vector(CFG.numContextsLog2-1 downto 0);
  signal creg2gpreg_writeEnable       : std_logic;
  signal creg2gpreg_writeData         : rvex_data_type;
  signal gpreg2creg_readData          : rvex_data_type;
  
  -- Control registers <-> global control register logic signals.
  signal creg2gbreg_dbgAddr           : rvex_address_type;
  signal creg2gbreg_dbgWriteEnable    : std_logic;
  signal creg2gbreg_dbgWriteMask      : rvex_mask_type;
  signal creg2gbreg_dbgWriteData      : rvex_data_type;
  signal creg2gbreg_dbgReadEnable     : std_logic;
  signal gbreg2creg_dbgReadData       : rvex_data_type;
  signal creg2gbreg_coreAddr          : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal creg2gbreg_coreReadEnable    : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal gbreg2creg_coreReadData      : rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Control registers <-> context control register logic signals.
  signal creg2cxreg_addr              : rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
  signal creg2cxreg_origin            : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal creg2cxreg_writeEnable       : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal creg2cxreg_writeMask         : rvex_mask_array(2**CFG.numContextsLog2-1 downto 0);
  signal creg2cxreg_writeData         : rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
  signal creg2cxreg_readEnable        : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2creg_readData          : rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
  
  -- Control register misc.
  signal imem2gbreg_affinity          : rvex_data_type;
  signal coreID_byte                  : rvex_byte_type;
  signal ctxtReset                    : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2rv_reset               : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal mem2cxreg_cacheStatus        : rvex_cacheStatus_array(2**CFG.numContextsLog2-1 downto 0);
  
  -- Context register <-> context-pipelane interface signals.
  signal cxplif2cxreg_brWriteData     : rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_brWriteEnable   : rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_brReadData      : rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_linkWriteData   : rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_linkWriteEnable : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_linkReadData    : rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_stall           : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_idle            : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_sylCommit       : rvex_sylStatus_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_sylNop          : rvex_sylStatus_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_stop            : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_nextPC          : rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_currentPC       : rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_overridePC      : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_overridePC_ack  : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_trapHandler     : rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_trapInfo        : trap_info_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_trapPoint       : rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_trapIsDebug     : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_trapReturn      : rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_rfi             : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_handlingDebugTrap:std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_interruptEnable : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_debugTrapEnable : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_softCtxtSwitch  : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_breakpoints     : cxreg2pl_breakpoint_info_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_extDebug        : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_exDbgTrapInfo   : trap_info_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_brk             : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_stepping        : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cxplif_resuming        : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxplif2cxreg_resuming_ack    : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  
  -- Context register logic <-> configuration control signals.
  signal cxreg2cfg_requestData        : rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cfg_requestEnable      : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2cfg_wakeupConfig       : rvex_data_type;
  signal cxreg2cfg_wakeupEnable       : std_logic;
  signal cfg2cxreg_wakeupAck          : std_logic;
  
  -- Global register logic <-> configuration control signals.
  signal gbreg2cfg_requestData        : rvex_data_type;
  signal gbreg2cfg_requestEnable      : std_logic;
  signal cfg2gbreg_busy               : std_logic;
  signal cfg2gbreg_error              : std_logic;
  signal cfg2gbreg_requesterID        : std_logic_vector(3 downto 0);
  
  -- Pipelane <-> trace control unit signals.
  signal pl2trace_data                : pl2trace_data_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- Context register logic <-> trace control unit signals.
  signal cxreg2trace_enable           : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2trace_trapEn           : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2trace_memEn            : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2trace_regEn            : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2trace_cacheEn          : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal cxreg2trace_instrEn          : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Simulation-only signals
  -----------------------------------------------------------------------------
  -- pragma translate_off
  signal pl2sim_instr                 : rvex_string_builder_array(2**CFG.numLanesLog2-1 downto 0);
  signal pl2sim_op                    : rvex_string_builder_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2sim                       : rvex_string_builder_array(2**CFG.numLanesLog2-1 downto 0);
  -- pragma translate_on
    
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Generate reset and stalling logic
  -----------------------------------------------------------------------------
  -- Combine the reset signals.
  reset_s <= reset or gbreg2rv_reset;
  
  -- Forward the reset output signal.
  resetOut <= gbreg2rv_reset;
  
  -- Generate the stall signals.
  stall_gen: process (mem2rv_stallIn, debugBusStall, traceStall) is
    variable s : std_logic;
  begin
    if CFG.unifiedStall then
      s := traceStall or rctrl2rv_traceStall;
      for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        s := s or mem2rv_stallIn(laneGroup) or debugBusStall(laneGroup);
      end loop;
      stall <= (others => s);
    else
      for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        stall(laneGroup) <= mem2rv_stallIn(laneGroup)
                         or debugBusStall(laneGroup)
                         or traceStall
                         or rctrl2rv_traceStall;
      end loop;
    end if;
  end process;
  
  -- Forward the internal stall signal to the memory.
  rv2mem_stallOut <= stall;
  
  -- Forward the trace stall signal to the run control system.
  rv2rctrl_traceStall <= traceStall;
  
  -----------------------------------------------------------------------------
  -- Decode memory faults
  -----------------------------------------------------------------------------
  -- Drive the trap information vectors to the pipelanes based on the fault
  -- flags from the memories.
  mem_trap_info_gen: for laneGroup in 2**CFG.numLaneGroupsLog2-1 downto 0 generate
    
    -- There is only one instruction memory fault.
    imem2ibuf_exception(laneGroup) <= (
      active => imem2rv_busFault(laneGroup),
      cause  => rvex_trap(RVEX_TRAP_FETCH_FAULT),
      arg    => (others => '0')
    );
    
    -- There is only one data memory fault. Note that the arg parameter will be
    -- overwritten by the address which was being accessed in the pipelane.
    dmem2dmsw_exception(laneGroup) <= (
      active => dmem2rv_ifaceFault(laneGroup) or dmem2rv_busFault(laneGroup),
      cause  => rvex_trap(RVEX_TRAP_DMEM_FAULT),
      arg    => (others => '0')
    );
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Instantiate the pipelanes
  -----------------------------------------------------------------------------
  pls_inst: entity rvex.core_pipelanes
    generic map (
      CFG                           => CFG
    )
    port map (
      
      -- System control.
      reset                         => reset_s,
      clk                           => clk,
      clkEn                         => clkEn,
      stall                         => stall,
      
      -- VHDL simulation debug information.
      -- pragma translate_off
      pl2sim_instr                  => pl2sim_instr,
      pl2sim_op                     => pl2sim_op,
      br2sim                        => br2sim,
      -- pragma translate_on
      
      -- Decoded configuration signals.
      cfg2any_coupled               => cfg2any_coupled,
      cfg2any_decouple              => cfg2any_decouple,
      cfg2any_numGroupsLog2         => cfg2any_numGroupsLog2,
      cfg2any_context               => cfg2any_context,
      cfg2any_active                => cfg2any_active,
      cfg2any_lastGroupForCtxt      => cfg2any_lastGroupForCtxt,
      cfg2any_laneIndex             => cfg2any_laneIndex,
      cfg2any_pcAddVal              => cfg2any_pcAddVal,
      
      -- Configuration signals.
      cfg2cxplif_active             => cfg2cxplif_active,
      cfg2cxplif_requestReconfig    => cfg2cxplif_requestReconfig,
      cxplif2cfg_blockReconfig      => cxplif2cfg_blockReconfig,
      
      -- External run control signals.
      rctrl2cxplif_irq              => rctrl2rv_irq,
      rctrl2cxplif_irqID            => rctrl2rv_irqID,
      cxplif2rctrl_irqAck           => rv2rctrl_irqAck,
      rctrl2cxplif_run              => rctrl2rv_run,
      cxplif2rctrl_idle             => rv2rctrl_idle,
      
      -- Instruction memory interface.
      cxplif2ibuf_PCs               => cxplif2ibuf_PCs,
      cxplif2ibuf_fetchPCs          => cxplif2ibuf_fetchPCs,
      cxplif2ibuf_branch            => cxplif2ibuf_branch,
      cxplif2ibuf_fetch             => cxplif2ibuf_fetch,
      cxplif2ibuf_cancel            => cxplif2ibuf_cancel,
      ibuf2pl_instr                 => ibuf2pl_instr,
      ibuf2pl_exception             => ibuf2pl_exception,
      
      -- Data memory interface.
      dmsw2dmem_addr                => rv2dmem_addr,
      dmsw2dmem_writeData           => rv2dmem_writeData,
      dmsw2dmem_writeMask           => rv2dmem_writeMask,
      dmsw2dmem_writeEnable         => rv2dmem_writeEnable,
      dmsw2dmem_readEnable          => rv2dmem_readEnable,
      dmem2dmsw_readData            => dmem2rv_readData,
      dmem2dmsw_exception           => dmem2dmsw_exception,
      
      -- Control register interface.
      dmsw2creg_addr                => dmsw2creg_addr,
      dmsw2creg_writeData           => dmsw2creg_writeData,
      dmsw2creg_writeMask           => dmsw2creg_writeMask,
      dmsw2creg_writeEnable         => dmsw2creg_writeEnable,
      dmsw2creg_readEnable          => dmsw2creg_readEnable,
      creg2dmsw_readData            => creg2dmsw_readData,
      
      -- Common memory interface.
      mem2pl_cacheStatus            => mem2rv_cacheStatus,
      
      -- Register file interface.
      pl2gpreg_readPorts            => pl2gpreg_readPorts,
      gpreg2pl_readPorts            => gpreg2pl_readPorts,
      pl2gpreg_writePorts           => pl2gpreg_writePorts,
      cxplif2cxreg_brWriteData      => cxplif2cxreg_brWriteData,
      cxplif2cxreg_brWriteEnable    => cxplif2cxreg_brWriteEnable,
      cxreg2cxplif_brReadData       => cxreg2cxplif_brReadData,
      cxplif2cxreg_linkWriteData    => cxplif2cxreg_linkWriteData,
      cxplif2cxreg_linkWriteEnable  => cxplif2cxreg_linkWriteEnable,
      cxreg2cxplif_linkReadData     => cxreg2cxplif_linkReadData,
      
      -- Special context register interface.
      cxplif2cxreg_stall            => cxplif2cxreg_stall,
      cxplif2cxreg_idle             => cxplif2cxreg_idle,
      cxplif2cxreg_sylCommit        => cxplif2cxreg_sylCommit,
      cxplif2cxreg_sylNop           => cxplif2cxreg_sylNop,
      cxplif2cxreg_stop             => cxplif2cxreg_stop,
      cxplif2cxreg_nextPC           => cxplif2cxreg_nextPC,
      cxreg2cxplif_currentPC        => cxreg2cxplif_currentPC,
      cxreg2cxplif_overridePC       => cxreg2cxplif_overridePC,
      cxplif2cxreg_overridePC_ack   => cxplif2cxreg_overridePC_ack,
      cxreg2cxplif_trapHandler      => cxreg2cxplif_trapHandler,
      cxplif2cxreg_trapInfo         => cxplif2cxreg_trapInfo,
      cxplif2cxreg_trapPoint        => cxplif2cxreg_trapPoint,
      cxreg2cxplif_trapReturn       => cxreg2cxplif_trapReturn,
      cxplif2cxreg_rfi              => cxplif2cxreg_rfi,
      cxreg2cxplif_handlingDebugTrap=> cxreg2cxplif_handlingDebugTrap,
      cxreg2cxplif_interruptEnable  => cxreg2cxplif_interruptEnable,
      cxreg2cxplif_debugTrapEnable  => cxreg2cxplif_debugTrapEnable,
      cxreg2cxplif_softCtxtSwitch   => cxreg2cxplif_softCtxtSwitch,
      cxreg2cxplif_breakpoints      => cxreg2cxplif_breakpoints,
      cxreg2cxplif_extDebug         => cxreg2cxplif_extDebug,
      cxplif2cxreg_exDbgTrapInfo    => cxplif2cxreg_exDbgTrapInfo,
      cxreg2cxplif_brk              => cxreg2cxplif_brk,
      cxreg2cxplif_stepping         => cxreg2cxplif_stepping,
      cxreg2cxplif_resuming         => cxreg2cxplif_resuming,
      cxplif2cxreg_resuming_ack     => cxplif2cxreg_resuming_ack,
      
      -- Trace data.
      pl2trace_data                 => pl2trace_data
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate the general purpose register file
  -----------------------------------------------------------------------------
  gpreg_inst: entity rvex.core_gpRegs
    generic map (
      CFG                           => CFG
    )
    port map (
      
      -- System control.
      reset                         => reset_s,
      clk                           => clk,
      clkEn                         => clkEn,
      stall                         => stall,

      -- Decoded configuration signals.
      cfg2any_coupled               => cfg2any_coupled,
      cfg2any_context               => cfg2any_context,
      
      -- Read and write ports.
      pl2gpreg_readPorts            => pl2gpreg_readPorts,
      gpreg2pl_readPorts            => gpreg2pl_readPorts,
      pl2gpreg_writePorts           => pl2gpreg_writePorts,
      
      -- Debug interface.
      creg2gpreg_claim              => creg2gpreg_claim,
      creg2gpreg_addr               => creg2gpreg_addr,
      creg2gpreg_ctxt               => creg2gpreg_ctxt,
      creg2gpreg_writeEnable        => creg2gpreg_writeEnable,
      creg2gpreg_writeData          => creg2gpreg_writeData,
      gpreg2creg_readData           => gpreg2creg_readData
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate the instruction buffer
  -----------------------------------------------------------------------------
  ibuf_gen: if CFG.bundleAlignLog2 < CFG.numLanesLog2 generate
    ibuf_inst: entity rvex.core_instructionBuffer
      generic map (
        CFG                         => CFG
      )
      port map (
        
        -- System control.
        reset                       => reset,
        clk                         => clk,
        clkEn                       => clkEn,
        stall                       => stall,
        
        -- Decoded configuration signals.
        cfg2any_numGroupsLog2       => cfg2any_numGroupsLog2,
        
        -- Instruction memory interface.
        ibuf2imem_PCs               => rv2imem_PCs,
        ibuf2imem_fetch             => rv2imem_fetch,
        ibuf2imem_cancel            => rv2imem_cancel,
        imem2ibuf_instr             => imem2rv_instr,
        imem2ibuf_exception         => imem2ibuf_exception,
        
        -- Pipelane interface.
        cxplif2ibuf_PCs             => cxplif2ibuf_PCs,
        cxplif2ibuf_fetchPCs        => cxplif2ibuf_fetchPCs,
        cxplif2ibuf_branch          => cxplif2ibuf_branch,
        cxplif2ibuf_fetch           => cxplif2ibuf_fetch,
        cxplif2ibuf_cancel          => cxplif2ibuf_cancel,
        ibuf2pl_instr               => ibuf2pl_instr,
        ibuf2pl_exception           => ibuf2pl_exception
        
      );
  end generate;
  
  -- Connect the ibuf signals directly to the memory if we don't need an
  -- instruction buffer.
  no_ibuf_gen: if CFG.bundleAlignLog2 >= CFG.numLanesLog2 generate
    rv2imem_PCs       <= cxplif2ibuf_fetchPCs;
    rv2imem_fetch     <= cxplif2ibuf_fetch;
    rv2imem_cancel    <= cxplif2ibuf_cancel;
    ibuf2pl_instr     <= imem2rv_instr;
    ibuf2pl_exception <= imem2ibuf_exception;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Instantiate the control registers
  -----------------------------------------------------------------------------
  creg_inst: entity rvex.core_ctrlRegs
    generic map (
      CFG                           => CFG
    )
    port map (
      
      -- System control.
      reset                         => reset_s,
      clk                           => clk,
      clkEn                         => clkEn,
      stallIn                       => stall,
      stallOut                      => debugBusStall,
      
      -- Decoded configuration signals.
      cfg2any_context               => cfg2any_context,
      
      -- Core bus interfaces.
      dmsw2creg_addr                => dmsw2creg_addr,
      dmsw2creg_writeEnable         => dmsw2creg_writeEnable,
      dmsw2creg_writeMask           => dmsw2creg_writeMask,
      dmsw2creg_writeData           => dmsw2creg_writeData,
      dmsw2creg_readEnable          => dmsw2creg_readEnable,
      creg2dmsw_readData            => creg2dmsw_readData,
      
      -- Debug bus interface.
      dbg2creg_addr                 => dbg2rv_addr,
      dbg2creg_writeEnable          => dbg2rv_writeEnable,
      dbg2creg_writeMask            => dbg2rv_writeMask,
      dbg2creg_writeData            => dbg2rv_writeData,
      dbg2creg_readEnable           => dbg2rv_readEnable,
      creg2dbg_readData             => rv2dbg_readData,
      
      -- General purpose register file interface.
      creg2gpreg_claim              => creg2gpreg_claim,
      creg2gpreg_addr               => creg2gpreg_addr,
      creg2gpreg_ctxt               => creg2gpreg_ctxt,
      creg2gpreg_writeEnable        => creg2gpreg_writeEnable,
      creg2gpreg_writeData          => creg2gpreg_writeData,
      gpreg2creg_readData           => gpreg2creg_readData,
      
      -- Debug bus <-> global control register interface.
      creg2gbreg_dbgAddr            => creg2gbreg_dbgAddr,
      creg2gbreg_dbgWriteEnable     => creg2gbreg_dbgWriteEnable,
      creg2gbreg_dbgWriteMask       => creg2gbreg_dbgWriteMask,
      creg2gbreg_dbgWriteData       => creg2gbreg_dbgWriteData,
      creg2gbreg_dbgReadEnable      => creg2gbreg_dbgReadEnable,
      gbreg2creg_dbgReadData        => gbreg2creg_dbgReadData,
      
      -- Core <-> global control register interface.
      creg2gbreg_coreAddr           => creg2gbreg_coreAddr,
      creg2gbreg_coreReadEnable     => creg2gbreg_coreReadEnable,
      gbreg2creg_coreReadData       => gbreg2creg_coreReadData,
      
      -- Core/debug bus <-> context control register interface.
      creg2cxreg_addr               => creg2cxreg_addr,
      creg2cxreg_origin             => creg2cxreg_origin,
      creg2cxreg_writeEnable        => creg2cxreg_writeEnable,
      creg2cxreg_writeMask          => creg2cxreg_writeMask,
      creg2cxreg_writeData          => creg2cxreg_writeData,
      creg2cxreg_readEnable         => creg2cxreg_readEnable,
      cxreg2creg_readData           => cxreg2creg_readData
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate the context-based control register logic
  -----------------------------------------------------------------------------
  -- Generate misc. signals.
  ctxtReset <= rctrl2rv_reset or cxreg2rv_reset;
  trap_is_dbg_gen: for ctxt in 0 to 2**CFG.numContextsLog2-1 generate
    cxplif2cxreg_trapIsDebug(ctxt) <=
      rvex_isDebugTrap(cxplif2cxreg_trapInfo(ctxt));
  end generate;
  
  -- Connect the cache status signals to cxreg if the cache performance
  -- counters are enabled.
  assert CFG.numLaneGroupsLog2 = CFG.numContextsLog2
    or not CFG.cachePerfCountEnable
    report "When the cache performance counters are enabled, the number of " &
           "lane groups must equal the number of contexts."
    severity failure;
  gen_cache_perf_count_connection: if CFG.cachePerfCountEnable generate
    mem2cxreg_cacheStatus <= mem2rv_cacheStatus;
  end generate;
  dont_gen_cache_perf_count_connection: if not CFG.cachePerfCountEnable generate
    mem2cxreg_cacheStatus <= (others => RVEX_CACHE_STATUS_IDLE);
  end generate;
  
  -- Instantiate.
  cxreg_inst: entity rvex.core_contextRegLogic
    generic map (
      CFG                           => CFG
    )
    port map (
      
      -- System control.
      reset                         => reset_s,
      ctxtReset                     => ctxtReset,
      clk                           => clk,
      clkEn                         => clkEn,
      
      -- Run control interface.
      cxreg2rv_reset                => cxreg2rv_reset,
      rctrl2cxreg_resetVect         => rctrl2rv_resetVect,
      cxreg2rctrl_done              => rv2rctrl_done,

      -- Memory interface.
      mem2cxreg_cacheStatus         => mem2cxreg_cacheStatus,
      
      -- Pipelane interface: misc.
      cxplif2cxreg_stall            => cxplif2cxreg_stall,
      cxplif2cxreg_idle             => cxplif2cxreg_idle,
      cxplif2cxreg_sylCommit        => cxplif2cxreg_sylCommit,
      cxplif2cxreg_sylNop           => cxplif2cxreg_sylNop,
      cxplif2cxreg_stop             => cxplif2cxreg_stop,

      -- Pipelane interface: branch/link registers.
      cxplif2cxreg_brWriteData      => cxplif2cxreg_brWriteData,
      cxplif2cxreg_brWriteEnable    => cxplif2cxreg_brWriteEnable,
      cxreg2cxplif_brReadData       => cxreg2cxplif_brReadData,
      cxplif2cxreg_linkWriteData    => cxplif2cxreg_linkWriteData,
      cxplif2cxreg_linkWriteEnable  => cxplif2cxreg_linkWriteEnable,
      cxreg2cxplif_linkReadData     => cxreg2cxplif_linkReadData,

      -- Pipelane interface: program counter.
      cxplif2cxreg_nextPC           => cxplif2cxreg_nextPC,
      cxreg2cxplif_currentPC        => cxreg2cxplif_currentPC,
      cxreg2cxplif_overridePC       => cxreg2cxplif_overridePC,
      cxplif2cxreg_overridePC_ack   => cxplif2cxreg_overridePC_ack,

      -- Pipelane interface: trap handling.
      cxreg2cxplif_trapHandler      => cxreg2cxplif_trapHandler,
      cxplif2cxreg_trapInfo         => cxplif2cxreg_trapInfo,
      cxplif2cxreg_trapPoint        => cxplif2cxreg_trapPoint,
      cxplif2cxreg_trapIsDebug      => cxplif2cxreg_trapIsDebug,
      cxreg2cxplif_trapReturn       => cxreg2cxplif_trapReturn,
      cxplif2cxreg_rfi              => cxplif2cxreg_rfi,
      cxreg2cxplif_handlingDebugTrap=> cxreg2cxplif_handlingDebugTrap,
      cxreg2cxplif_interruptEnable  => cxreg2cxplif_interruptEnable,
      cxreg2cxplif_debugTrapEnable  => cxreg2cxplif_debugTrapEnable,
      cxreg2cxplif_softCtxtSwitch   => cxreg2cxplif_softCtxtSwitch,

      -- Pipelane interface: external debug control signals.
      cxreg2cxplif_breakpoints      => cxreg2cxplif_breakpoints,
      cxreg2cxplif_extDebug         => cxreg2cxplif_extDebug,
      cxplif2cxreg_exDbgTrapInfo    => cxplif2cxreg_exDbgTrapInfo,
      cxreg2cxplif_brk              => cxreg2cxplif_brk,
      cxreg2cxplif_stepping         => cxreg2cxplif_stepping,
      cxreg2cxplif_resuming         => cxreg2cxplif_resuming,
      cxplif2cxreg_resuming_ack     => cxplif2cxreg_resuming_ack,

      -- Interface with configuration logic.
      cfg2cxreg_currentConfig       => cfg2any_configWord,
      cxreg2cfg_requestData         => cxreg2cfg_requestData,
      cxreg2cfg_requestEnable       => cxreg2cfg_requestEnable,
      cxreg2cfg_wakeupConfig        => cxreg2cfg_wakeupConfig,
      cxreg2cfg_wakeupEnable        => cxreg2cfg_wakeupEnable,
      cfg2cxreg_wakeupAck           => cfg2cxreg_wakeupAck,

      -- Trace control unit interface.
      cxreg2trace_enable            => cxreg2trace_enable,
      cxreg2trace_trapEn            => cxreg2trace_trapEn,
      cxreg2trace_memEn             => cxreg2trace_memEn,
      cxreg2trace_regEn             => cxreg2trace_regEn,
      cxreg2trace_cacheEn           => cxreg2trace_cacheEn,
      cxreg2trace_instrEn           => cxreg2trace_instrEn,

      -- Interface with the control registers and bus logic.
      creg2cxreg_addr               => creg2cxreg_addr,
      creg2cxreg_origin             => creg2cxreg_origin,
      creg2cxreg_writeEnable        => creg2cxreg_writeEnable,
      creg2cxreg_writeMask          => creg2cxreg_writeMask,
      creg2cxreg_writeData          => creg2cxreg_writeData,
      creg2cxreg_readEnable         => creg2cxreg_readEnable,
      cxreg2creg_readData           => cxreg2creg_readData
      
    );
  
  -- Connect the break output to the DCR.B registers.
  rv2rctrl_break <= cxreg2cxplif_brk;
  
  -----------------------------------------------------------------------------
  -- Instantiate the global (common to all contexts) control register logic
  -----------------------------------------------------------------------------
  unpack_affinity: process (imem2rv_affinity) is
    constant n: natural := CFG.numLaneGroupsLog2;
    variable aff: rvex_data_type;
  begin
    aff := (others => '0');
    for g in 0 to 2**CFG.numLaneGroupsLog2-1 loop
      aff(g*4+n-1 downto g*4) := imem2rv_affinity(g*n+n-1 downto g*n);
    end loop;
    imem2gbreg_affinity <= aff;
  end process;
  coreID_byte <= std_logic_vector(to_unsigned(CORE_ID + coreID, 8));
  
  gbreg_inst: entity rvex.core_globalRegLogic
    generic map (
      CFG                           => CFG
    )
    port map (
      
      -- System control.
      reset                         => reset_s,
      clk                           => clk,
      clkEn                         => clkEn,
      
      -- Run control.
      gbreg2rv_reset                => gbreg2rv_reset,
      
      -- Interface with configuration logic.
      gbreg2cfg_requestData         => gbreg2cfg_requestData,
      gbreg2cfg_requestEnable       => gbreg2cfg_requestEnable,
      cfg2gbreg_currentCfg          => cfg2any_configWord,
      cfg2gbreg_busy                => cfg2gbreg_busy,
      cfg2gbreg_error               => cfg2gbreg_error,
      cfg2gbreg_requesterID         => cfg2gbreg_requesterID,

      -- Interface with memory.
      imem2gbreg_affinity           => imem2gbreg_affinity,

      -- Misc.
      rv2gbreg_coreID               => coreID_byte,
      rv2gbreg_platformTag          => PLATFORM_TAG,
      
      -- Debug bus to global control register interface.
      creg2gbreg_dbgAddr            => creg2gbreg_dbgAddr,
      creg2gbreg_dbgWriteEnable     => creg2gbreg_dbgWriteEnable,
      creg2gbreg_dbgWriteMask       => creg2gbreg_dbgWriteMask,
      creg2gbreg_dbgWriteData       => creg2gbreg_dbgWriteData,
      creg2gbreg_dbgReadEnable      => creg2gbreg_dbgReadEnable,
      gbreg2creg_dbgReadData        => gbreg2creg_dbgReadData,

      -- Core to global control register interface.
      creg2gbreg_coreAddr           => creg2gbreg_coreAddr,
      creg2gbreg_coreReadEnable     => creg2gbreg_coreReadEnable,
      gbreg2creg_coreReadData       => gbreg2creg_coreReadData

    );
  
  -----------------------------------------------------------------------------
  -- Instantiate configuration logic
  -----------------------------------------------------------------------------
  cfg_inst: entity rvex.core_cfgCtrl
    generic map (
      CFG                           => CFG
    )
    port map (
      
      -- System control.
      reset                         => reset_s,
      clk                           => clk,
      clkEn                         => clkEn,
      
      -- Configuration request inputs.
      cxreg2cfg_requestData         => cxreg2cfg_requestData,
      cxreg2cfg_requestEnable       => cxreg2cfg_requestEnable,
      gbreg2cfg_requestData         => gbreg2cfg_requestData,
      gbreg2cfg_requestEnable       => gbreg2cfg_requestEnable,
      cxreg2cfg_wakeupConfig        => cxreg2cfg_wakeupConfig,
      cxreg2cfg_wakeupEnable        => cxreg2cfg_wakeupEnable,
      cfg2cxreg_wakeupAck           => cfg2cxreg_wakeupAck,
      rctrl2cfg_irq_ct0             => rctrl2rv_irq(0),
      
      -- Configuration status outputs.
      cfg2gbreg_busy                => cfg2gbreg_busy,
      cfg2gbreg_error               => cfg2gbreg_error,
      cfg2gbreg_requesterID         => cfg2gbreg_requesterID,
      
      -- Branch unit interface (through context-pipelane interface).
      cfg2cxplif_active             => cfg2cxplif_active,
      cfg2cxplif_requestReconfig    => cfg2cxplif_requestReconfig,
      cxplif2cfg_blockReconfig      => cxplif2cfg_blockReconfig,
      
      -- Memory interface.
      mem2cfg_blockReconfig         => mem2rv_blockReconfig,
      
      -- Configuration control signals.
      cfg2any_configWord            => cfg2any_configWord,
      cfg2any_coupled               => cfg2any_coupled,
      cfg2any_decouple              => cfg2any_decouple,
      cfg2any_numGroupsLog2         => cfg2any_numGroupsLog2,
      cfg2any_context               => cfg2any_context,
      cfg2any_active                => cfg2any_active,
      cfg2any_lastGroupForCtxt      => cfg2any_lastGroupForCtxt,
      cfg2any_laneIndex             => cfg2any_laneIndex,
      cfg2any_pcAddVal              => cfg2any_pcAddVal
      
    );
  
  -- Connect the external decouple signal to the decouple signal from the
  -- configuration logic.
  rv2mem_decouple <= cfg2any_decouple;
  
  -----------------------------------------------------------------------------
  -- Instantiate trace control unit
  -----------------------------------------------------------------------------
  trace_gen: if CFG.traceEnable generate
    trace_inst: entity rvex.core_trace
      generic map (
        CFG                         => CFG
      )
      port map (
        
        -- System control.
        reset                       => reset,
        clk                         => clk,
        clkEn                       => clkEn,
        stallIn                     => stall,
        stallOut                    => traceStall,
        
        -- Decoded configuration signals.
        cfg2any_configWord          => cfg2any_configWord,
        cfg2any_coupled             => cfg2any_coupled,
        cfg2any_context             => cfg2any_context,
        cfg2any_active              => cfg2any_active,
        
        -- Trace control.
        cxreg2trace_enable          => cxreg2trace_enable,
        cxreg2trace_trapEn          => cxreg2trace_trapEn,
        cxreg2trace_memEn           => cxreg2trace_memEn,
        cxreg2trace_regEn           => cxreg2trace_regEn,
        cxreg2trace_cacheEn         => cxreg2trace_cacheEn,
        cxreg2trace_instrEn         => cxreg2trace_instrEn,
        
        -- Trace raw data input.
        pl2trace_data               => pl2trace_data,
        
        -- Trace output.
        trace2trsink_push           => rv2trsink_push,
        trace2trsink_data           => rv2trsink_data,
        trace2trsink_end            => rv2trsink_end,
        trsink2trace_busy           => trsink2rv_busy
        
      );
  end generate;
  
  -- If the trace unit is disabled, connect its output signals to constant
  -- values indicating idle.
  no_trace_gen: if not CFG.traceEnable generate
    traceStall      <= '0';
    rv2trsink_push  <= '0';
    rv2trsink_data  <= (others => '0');
    rv2trsink_end   <= '0';
  end generate;
  
  -----------------------------------------------------------------------------
  -- Generate simulation information
  -----------------------------------------------------------------------------
  -- pragma translate_off
  sim_info_gen: if GEN_VHDL_SIM_INFO generate
    
    -- Generate pipeline registers for the configuration state to sync up with
    -- the simulation output.
    subtype ctxtMapping_type is rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    type ctxtMapping_array is array (natural range <>) of ctxtMapping_type;
    signal ctxt                     : ctxtMapping_array(S_FIRST+1 to S_LAST);
    signal currentCfg               : rvex_data_array(S_FIRST+1 to S_LAST);
    
  begin
    
    cfg_pipeline: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          ctxt <= (others => (others => (others => '0')));
          currentCfg <= (others => (others => '0'));
        elsif clkEn = '1' then
          
          -- Be careful to respect the stall signals.
          for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
            if stall(laneGroup) = '0' then
              
              ctxt(S_FIRST+1)(laneGroup)
                <= cfg2any_context(laneGroup);
              currentCfg(S_FIRST+1)(4*laneGroup+3 downto 4*laneGroup)
                <= cfg2any_configWord(4*laneGroup+3 downto 4*laneGroup);
              
              for s in S_FIRST+2 to S_LAST loop
                ctxt(s)(laneGroup)
                  <= ctxt(s-1)(laneGroup);
                currentCfg(s)(4*laneGroup+3 downto 4*laneGroup)
                  <= currentCfg(s-1)(4*laneGroup+3 downto 4*laneGroup);
              end loop;
              
            end if;
          end loop;
          
        end if;
      end if;
    end process;
    
    sim_info: process (
      pl2sim_instr, pl2sim_op, br2sim, currentCfg(S_LAST), ctxt(S_LAST),
      cxreg2cxplif_currentPC
    ) is
      
      -- Number of lines in the string list shown in simulation.
      constant NUM_LINES          : natural :=
        2*2**CFG.numLanesLog2+2**CFG.numLaneGroupsLog2+2**CFG.numContextsLog2;
      
      type bool_array is array(natural range <>) of boolean;
      
      variable sb                 : rvex_string_builder_type;
      variable line               : positive;
      variable curContext         : integer;
      variable prevContext        : integer;
      variable processedContexts  : bool_array(2**CFG.numContextsLog2-1 downto 0);
      variable branchUnitLane     : natural;
      
    begin
      
      -- Add information about all active lanes/contexts to the simulation.
      line := 1;
      prevContext := -1;
      processedContexts := (others => false);
      for lane in 0 to 2**CFG.numLanesLog2-1 loop
        
        -- Ignore lanes which aren't active.
        if currentCfg(S_LAST)(lane2group(lane, CFG)*4+3) = '1' then
          prevContext := -1;
          next;
        end if;
        
        -- Figure out the context running on the current lane.
        curContext := vect2uint(ctxt(S_LAST)(lane2group(lane, CFG)));
        
        -- If this lane is operating in a different context than the previous
        -- lane, inject a line of whitespace and a line with context
        -- information.
        if curContext /= prevContext then
          
          -- Inject a line of whitespace if this isn't the first line.
          if line /= 1 then
            rvs_clear(sb);
            if line <= NUM_LINES then
              rv2sim(line) <= rvs2sim(sb);
            end if;
            line := line + 1;
          end if;
          
          -- Pretty-print context information.
          rvs_clear(sb);
          rvs_append(sb, "Ctxt " & integer'image(curContext) & ": ");
          rvs_append(sb, br2sim(
            group2lastLane(
              vect2uint(cfg2any_lastGroupForCtxt(curContext)), CFG
            )
          ));
          if line <= NUM_LINES then
            rv2sim(line) <= rvs2sim(sb);
          end if;
          line := line + 1;
          
        end if;
        
        -- Print lane instruction information.
        rvs_clear(sb);
        rvs_append(sb, " '- Ln" & integer'image(lane) & ": ");
        rvs_append(sb, pl2sim_instr(lane));
        if line <= NUM_LINES then
          rv2sim(line) <= rvs2sim(sb);
        end if;
        line := line + 1;
        
        -- Print lane operation information.
        rvs_clear(sb);
        rvs_append(sb, "      '- ");
        rvs_append(sb, pl2sim_op(lane));
        if line <= NUM_LINES then
          rv2sim(line) <= rvs2sim(sb);
        end if;
        line := line + 1;
        
        -- Store the fact that information for the context belonging to this
        -- lane has been added to the simulation information.
        processedContexts(curContext) := true;
        
        -- Store the context belonging to this lane for the next loop
        -- iteration.
        prevContext := curContext;
        
      end loop;
      
      -- Inject a line of whitespace.
      if line /= 1 then
        rvs_clear(sb);
        if line <= NUM_LINES then
          rv2sim(line) <= rvs2sim(sb);
        end if;
        line := line + 1;
      end if;
      
      -- Add the current PCs for all non-active contexts to simulation.
      for ctxt in 0 to 2**CFG.numContextsLog2-1 loop
        if processedContexts(ctxt) = false then
        
          -- Pretty-print halted context information.
          rvs_clear(sb);
          rvs_append(sb, "Ctxt " & integer'image(ctxt) & ": halted at PC=");
          rvs_append(sb, rvs_hex(cxreg2cxplif_currentPC(ctxt), 8));
          if line <= NUM_LINES then
            rv2sim(line) <= rvs2sim(sb);
          end if;
          line := line + 1;
          
        end if;
      end loop;
      
      -- Finish by writing an empty string to all lines which we're not
      -- currently using.
      rvs_clear(sb);
      while line <= NUM_LINES loop
        rv2sim(line) <= rvs2sim(sb);
        line := line + 1;
      end loop;
      
    end process;
  end generate;
  -- pragma translate_on
  
  -----------------------------------------------------------------------------
  -- Register consistency check code
  -----------------------------------------------------------------------------
  -- pragma translate_off
  rcc_record_gen: if RCC_RECORD /= "" generate
    rcc_record_proc: process (clk) is
      file     f      : text open write_mode is RCC_RECORD;
      variable l      : line;
      variable lg     : natural;
      variable ena    : boolean;
      variable enas   : std_logic_vector(9 downto 0);
    begin
      if rising_edge(clk) then
        if reset = '1' then
          
          -- Rewind the file when resetting.
          file_close(f);
          file_open(f, RCC_RECORD, write_mode);
          
        elsif clkEn = '1' then
          for lane in 0 to 2**CFG.numLanesLog2-1 loop
            lg := lane2group(lane, CFG);
            
            -- Determine whether we need to record.
            ena := (stall(lg) = '0')
               and (vect2uint(cfg2any_context(lg)) = RCC_CTXT)
               and (pl2trace_data(lane).valid = '1');
            if not ena then
              next;
            end if;
            enas(0) := pl2trace_data(lane).reg_gpEnable;
            enas(1) := pl2trace_data(lane).reg_linkEnable;
            enas(9 downto 2) := pl2trace_data(lane).reg_brEnable;
            ena := false;
            for x in enas'range loop
              if enas(x) = '1' then
                ena := true;
              elsif enas(x) /= '0' then
                report "Register write enable signal is undefined. " &
                       "Reg consistency check report will be incomplete!"
                       severity error;
              end if;
            end loop;
            if ena then
              
              -- Record the data.
              write(l, pl2trace_data(lane).reg_gpEnable);
              write(l, pl2trace_data(lane).reg_gpAddress);
              write(l, pl2trace_data(lane).reg_linkEnable);
              write(l, pl2trace_data(lane).reg_intData);
              write(l, pl2trace_data(lane).reg_brEnable);
              write(l, pl2trace_data(lane).reg_brData);
              writeline(f, l);
              
            end if;
          end loop;
        end if;
      end if;
    end process;
  end generate;
  
  rcc_check_gen: if RCC_CHECK /= "" generate
    rcc_check_proc: process (clk) is
      file     f          : text open read_mode is RCC_CHECK;
      variable done       : boolean := false;
      variable good       : boolean := true;
      variable lnr        : natural := 0;
      variable l          : line;
      variable lg         : natural;
      variable ena        : boolean;
      variable enas       : std_logic_vector(9 downto 0);
      variable gpEnable   : std_logic;           -- 55
      variable gpAddress  : rvex_gpRegAddr_type; -- 54..49
      variable linkEnable : std_logic;           -- 48
      variable intData    : rvex_data_type;      -- 47..16
      variable brEnable   : rvex_brRegData_type; -- 15..8
      variable brData     : rvex_brRegData_type; -- 7..0
      
      procedure get_next is
        variable data     : std_logic_vector(55 downto 0);
      begin
        if endfile(f) then
          report "Register consistency check recording has ended."
                 severity note;
          done := true;
          return;
        end if;
        readline(f, l);
        lnr := lnr + 1;
        read(l, data, good);
        if not good then
          report "Error reading register check file " &
            RCC_CHECK & " line " & natural'image(lnr) severity error;
          return;
        end if;
        gpEnable   := data(55);
        gpAddress  := data(54 downto 49);
        linkEnable := data(48);
        intData    := data(47 downto 16);
        brEnable   := data(15 downto 8);
        brData     := data(7 downto 0);
      end get_next;
      
      procedure report_state(
        message    : string;
        gpEnable   : std_logic;
        gpAddress  : rvex_gpRegAddr_type;
        linkEnable : std_logic;
        intData    : rvex_data_type;
        brEnable   : rvex_brRegData_type;
        brData     : rvex_brRegData_type
      ) is
        variable l : line;
      begin
        write(l, message);
        if gpEnable = '1' then
          write(l, string'(" $r0.") & natural'image(vect2uint(gpAddress)) & " := 0x");
          hwrite(l, intData);
          write(l, string'(";"));
        end if;
        if linkEnable = '1' then
          write(l, string'(" $l0.0 := 0x"));
          hwrite(l, intData);
          write(l, string'(";"));
        end if;
        for x in brEnable'range loop
          if brEnable(x) = '1' then
            write(l, string'(" $l0.0 := "));
            write(l, brData(x));
            write(l, string'(";"));
          end if;
        end loop;
        report l.all severity note;
      end report_state;
      
    begin
      if good and rising_edge(clk) then
        if reset = '1' then
          
          -- Rewind the file when resetting.
          file_close(f);
          file_open(f, RCC_CHECK, read_mode);
          lnr := 0;
          done := false;
          get_next;
          
        elsif clkEn = '1' and not done then
          for lane in 0 to 2**CFG.numLanesLog2-1 loop
            lg := lane2group(lane, CFG);
            
            -- Determine whether we need to check.
            ena := (stall(lg) = '0')
               and (vect2uint(cfg2any_context(lg)) = RCC_CTXT)
               and (pl2trace_data(lane).valid = '1');
            if not ena then
              next;
            end if;
            enas(0) := pl2trace_data(lane).reg_gpEnable;
            enas(1) := pl2trace_data(lane).reg_linkEnable;
            enas(9 downto 2) := pl2trace_data(lane).reg_brEnable;
            ena := false;
            for x in enas'range loop
              if enas(x) = '1' then
                ena := true;
              elsif enas(x) /= '0' then
                report "Register write enable signal is undefined. " &
                       "Reg consistency check report will be incomplete!"
                       severity error;
              end if;
            end loop;
            if ena then
              
              -- Check the control signals.
              if gpEnable /= pl2trace_data(lane).reg_gpEnable then
                good := false;
              end if;
              if gpEnable = '1' then
                if gpAddress /= pl2trace_data(lane).reg_gpAddress then
                  good := false;
                end if;
              end if;
              if linkEnable /= pl2trace_data(lane).reg_linkEnable then
                good := false;
              end if;
              if (gpEnable or linkEnable) = '1' then
                if intData /= pl2trace_data(lane).reg_intData then
                  good := false;
                end if;
              end if;
              if brEnable /= pl2trace_data(lane).reg_brEnable then
                good := false;
              end if;
              if (brEnable and brData) /=
                  (pl2trace_data(lane).reg_brEnable and
                   pl2trace_data(lane).reg_brData) then
                good := false;
              end if;
              if not good then
                report "Register inconsistency at line " & natural'image(lnr) & "!"
                       severity error;
                report_state(
                  "The recording says:",
                  gpEnable,
                  gpAddress,
                  linkEnable,
                  intData,
                  brEnable,
                  brData
                );
                report_state(
                  "But I got:",
                  pl2trace_data(lane).reg_gpEnable,
                  pl2trace_data(lane).reg_gpAddress,
                  pl2trace_data(lane).reg_linkEnable,
                  pl2trace_data(lane).reg_intData,
                  pl2trace_data(lane).reg_brEnable,
                  pl2trace_data(lane).reg_brData
                );
              else
                get_next;
              end if;
            end if;
          end loop;
        end if;
      end if;
    end process;
  end generate;
  -- pragma translate_on
  
end Behavioral;

