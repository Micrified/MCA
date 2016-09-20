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

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.core_pkg.all;
use rvex.core_intIface_pkg.all;
use rvex.core_pipeline_pkg.all;
use rvex.core_trap_pkg.all;

--=============================================================================
-- This block interfaces between the pipelanes (the branch units in particular)
-- and the context-specific registers other than the general purpose register
-- file.
-------------------------------------------------------------------------------
entity core_contextPipelaneIFace is
--=============================================================================
  generic (
    
    -- Configuration.
    CFG                         : rvex_generic_config_type
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Active high global clock enable input.
    clkEn                       : in  std_logic;
    
    -- Active high stall input for each pipelane group.
    stall                       : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -----------------------------------------------------------------------------
    -- Decoded configuration signals
    -----------------------------------------------------------------------------
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
    -- context, or low when they don't.
    cfg2any_coupled             : in  std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- log2 of the number of coupled pipelane groups for each pipelane group.
    cfg2any_numGroupsLog2       : in  rvex_2bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies the context associated with the indexed pipelane group.
    cfg2any_context             : in  rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies whether the indexed pipeline group is active.
    cfg2any_active              : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Last pipelane group associated with each context.
    cfg2any_lastGroupForCtxt    : in  rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- The lane index within the coupled groups for each lane.
    cfg2any_laneIndex           : in  rvex_4bit_array(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface: configuration and run control
    ---------------------------------------------------------------------------
    -- Indicates whether the pipelane is ready for reconfiguration. This is
    -- essentially an active low idle output.
    pl2cxplif_blockReconfig     : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- External interrupt request signal, active high. This is already masked
    -- by the interrupt enable bit in the control register.
    cxplif2pl_irq               : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- External interrupt identification. Guaranteed to be loaded in the trap
    -- argument register in the same clkEn'd cycle where irqAck is high.
    cxplif2br_irqID             : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- External interrupt acknowledge signal, active high. and'ed with the
    -- stall input, so it goes high for exactly one clkEn'abled cycle.
    br2cxplif_irqAck            : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Active high run signal. This is the combined run signal from the
    -- external run input and the BRK flag in the debug control register.
    cxplif2br_run               : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Active high idle output.
    pl2cxplif_idle              : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface: next operation routing
    ---------------------------------------------------------------------------
    -- The PC for the current instruction, as chosen by the active branch unit
    -- within the group. The PC is distributed by the context-pipelane
    -- interface block so all coupled pipelanes have it.
    br2cxplif_PC                : in  rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    cxplif2pl_PC                : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- The PC which needs to be fetched next. This is PC rounded up to the next
    -- address which is aligned to the current issue width during normal
    -- operation or rounded down when branch is high. They are needed by the
    -- instruction buffer.
    br2cxplif_fetchPC           : in  rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    br2cxplif_branch            : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Whether an instruction fetch is being initiated or not.
    br2cxplif_limmValid         : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    cxplif2pl_limmValid         : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Whether the next instruction is valid and should be committed or not.
    br2cxplif_valid             : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    cxplif2pl_valid             : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Whether breakpoints are valid in the next instruction or not. This is
    -- low when returning from a debug interrupt.
    br2cxplif_brkValid          : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    cxplif2pl_brkValid          : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Whether or not pipeline stages S_IF+1 to S_BR-1 should be invalidated
    -- due to a branch or the core stopping.
    br2cxplif_invalUntilBR      : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    cxplif2pl_invalUntilBR      : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface: instruction memory command routing
    ---------------------------------------------------------------------------
    -- Active high fetch enable signal from each branch unit.
    br2cxplif_imemFetch         : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Active high cancel signal for the previous fetch. This is a hint to the
    -- memory/cache that, if it would need to stall the core to fetch the
    -- previously requested opcode, it can stop the fetch and allow the core to
    -- continue.
    br2cxplif_imemCancel        : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface: branch/link registers
    ---------------------------------------------------------------------------
    -- These signals are array'd outside this entity and contain pipeline
    -- configuration dependent data types, so they need to be put in records.
    -- The signals are documented in core_intIface_pkg.vhd, where the types are
    -- defined.
    
    -- Branch/link register read port.
    cxplif2pl_brLinkReadPort    : out cxreg2pl_readPort_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Branch/link register write port.
    pl2cxplif_brLinkWritePort   : in  pl2cxreg_writePort_array(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface: special registers
    ---------------------------------------------------------------------------
    -- The current value of the context PC register and associated override
    -- flag. When the override flag is set, the branch unit should behave as if
    -- there was a branch to the value in contextPC. This happens when the
    -- debug bus writes to the PC register.
    cxplif2br_contextPC         : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    cxplif2br_overridePC        : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Current trap handler. When the application has marked that it is not
    -- currently capable of accepting a trap, this is set to the panic handler
    -- register instead.
    cxplif2pl_trapHandler       : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Trap information for the trap currently handled by the branch unit, if
    -- any. We can commit this in the branch stage already, because it is
    -- guaranteed that there is no instruction valid in S_MEM while a trap is
    -- entered.
    br2cxplif_trapInfo          : in  trap_info_array(2**CFG.numLanesLog2-1 downto 0);
    br2cxplif_trapPoint         : in  rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Debug trap information for externally handled breakpoints. When the
    -- enable bit in the trap information record is high, the BRK bit should
    -- be set to halt the core and the trap information should be stored for
    -- the external debugger.
    br2cxplif_exDbgTrapInfo     : in  trap_info_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Stop signal, goes high when the branch unit is executing a stop
    -- instruction. When high, the done bit is set and the BRK bit is set to
    -- halt the core.
    br2cxplif_stop              : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Trap handler return address. This is just connected to the current value
    -- of the trap point register.
    cxplif2br_trapReturn        : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Commands the register logic to reset the trap cause to 0 and restore
    -- the control registers which were saved upon trap entry.
    pl2cxplif_rfi               : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Whether debug traps are to be handled normally or by halting execution
    -- for debugging through the external bebug bus.
    cxplif2br_extDebug          : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Set when the current value of the trap cause register maps to a debug
    -- trap.
    cxplif2br_handlingDebugTrap : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Current value of the debug trap enable bit in the control register.
    cxplif2pl_debugTrapEnable   : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Current breakpoint information.
    cxplif2brku_breakpoints     : out cxreg2pl_breakpoint_info_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Soft context switch trap request signals to the pipelanes.
    cxplif2pl_softCtxtSwitch    : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Current value of the stepping flag in the debug control register. When
    -- high, a step trap must be triggered if there is no other trap and
    -- breakpoints are enabled.
    cxplif2brku_stepping        : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface: performance counter status signals
    ---------------------------------------------------------------------------
    -- Syllable committed flag for each lane, used for the performance
    -- counters.
    pl2cxplif2_sylCommit        : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- NOP flag for each lane with the same timing as sylCommit, used for the
    -- performance counters.
    pl2cxplif2_sylNop           : in  std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Run control interface
    ---------------------------------------------------------------------------
    -- External interrupt request signal, active high. This is already masked
    -- by the interrupt enable bit in the control register.
    rctrl2cxplif_irq            : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- External interrupt identification. Guaranteed to be loaded in the trap
    -- argument register in the same clkEn'd cycle where irqAck is high.
    rctrl2cxplif_irqID          : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- External interrupt acknowledge signal, active high. and'ed with the
    -- stall input, so it goes high for exactly one clkEn'abled cycle.
    cxplif2rctrl_irqAck         : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high run signal. This is the combined run signal from the
    -- external run input and the BRK flag in the debug control register.
    rctrl2cxplif_run            : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high idle output.
    cxplif2rctrl_idle           : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Instruction memory interface
    ---------------------------------------------------------------------------
    -- Potentially misaligned PC addresses for each group, to be accounted for
    -- by the instruction buffer.
    cxplif2ibuf_PCs             : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Properly aligned addresses for each group which need to be fetched. This
    -- is the value of PCs rounded down when branch is high or rounded up when
    -- branch is low.
    cxplif2ibuf_fetchPCs        : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Whether the current fetch is nonconsequitive w.r.t. the previous fetch.
    cxplif2ibuf_branch          : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high fetch enable signal for each group.
    cxplif2ibuf_fetch           : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high cancel signal for the previous fetch. This is a hint to the
    -- memory/cache that, if it would need to stall the core to fetch the
    -- previously requested opcode, it can stop the fetch and allow the core to
    -- continue.
    cxplif2ibuf_cancel          : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Configuration control interface
    ---------------------------------------------------------------------------
    -- The active bits are tied to the run bits in the current configuration;
    -- a context should not be modified and kept in a halted state when active
    -- is low.
    cfg2cxplif_active           : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Reconfiguration request signal. These bits will be pulled high when the
    -- reconfiguration controller wants to reconfigure contexts while the
    -- relevant blockReconfig signals are high. A context should halt when
    -- this is high.
    cfg2cxplif_requestReconfig  : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high reconfiguration block bit. When high, reconfiguration is
    -- not permitted for the indexed context. This is essentially an active low
    -- idle flag.
    cxplif2cfg_blockReconfig    : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Context register interface: misc.
    ---------------------------------------------------------------------------
    -- When high, the context registers must maintain their current value.
    cxplif2cxreg_stall          : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Idle flag, as reported to the external run control interface. Used for
    -- the performance counters.
    cxplif2cxreg_idle           : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Syllable committed flag for each lane, used for the performance
    -- counters.
    cxplif2cxreg_sylCommit      : out rvex_sylStatus_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- NOP flag for each lane with the same timing as sylCommit, used for the
    -- performance counters.
    cxplif2cxreg_sylNop         : out rvex_sylStatus_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- Stop flag. When high, the BRK and done flags in the debug control
    -- register should be set.
    cxplif2cxreg_stop           : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Context register interface: branch/link registers
    ---------------------------------------------------------------------------
    -- Branch register interface (without forwarding) for each context.
    cxplif2cxreg_brWriteData    : out rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_brWriteEnable  : out rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_brReadData     : in  rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- Link register interface (without forwarding) for each context.
    cxplif2cxreg_linkWriteData  : out rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_linkWriteEnable: out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_linkReadData   : in  rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Context register interface: program counter
    ---------------------------------------------------------------------------
    -- Next value for the PC register. This is written when stall is low and
    -- overridePC is not asserted.
    cxplif2cxreg_nextPC         : out rvex_address_array(2**CFG.numContextsLog2-1 downto 0);

    -- Current value of the PC register.
    cxreg2cxplif_currentPC      : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);

    -- The overridePC flag is set when the debug bus writes to the context
    -- registers or when the context or processor is reset. This is reset when
    -- overridePC_ack is asserted while stall is low. It indicates to the
    -- branch unit that it should inject a branch to the current PC register
    -- regardless of the current instruction or state.
    cxreg2cxplif_overridePC     : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_overridePC_ack : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    ---------------------------------------------------------------------------
    -- Context register interface: trap handling
    ---------------------------------------------------------------------------
    -- Current trap handler. When the application has marked that it is not
    -- currently capable of accepting a trap, this is set to the panic handler
    -- register instead.
    cxreg2cxplif_trapHandler    : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);

    -- Regular trap information. When the trap in trapInfo is active, the trap
    -- information should be stored in the trap cause/arg registers. In
    -- addition, the register hardware should save the current value of the
    -- control register and should clear the ready-for-trap and interrupt-
    -- enable bits, as well as the debug-trap-enable bit if the trap cause maps
    -- to a debug trap.
    cxplif2cxreg_trapInfo       : out trap_info_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_trapPoint      : out rvex_address_array(2**CFG.numContextsLog2-1 downto 0);

    -- Connected to the current value of the trap point register. Used by the
    -- branch unit as the return address for the RFI instruction.
    cxreg2cxplif_trapReturn     : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);

    -- RFI flag. When high, the saved control register value should be restored
    -- and the trap cause field should be set to 0.
    cxplif2cxreg_rfi            : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Set when the current value of the trap cause register maps to a debug
    -- trap. This is used by the branch unit to disable breakpoints for the
    -- first instruction executed after the debug trap returns.
    cxreg2cxplif_handlingDebugTrap:in std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Current value of the interrupt-enable flag in the control register.
    cxreg2cxplif_interruptEnable: in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Current value of the debug-trap-enable flag in the control register.
    cxreg2cxplif_debugTrapEnable: in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Current hardware breakpoint configuration.
    cxreg2cxplif_breakpoints    : in  cxreg2pl_breakpoint_info_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- Soft context switch trap request signals from the control registers.
    cxreg2cxplif_softCtxtSwitch : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    ---------------------------------------------------------------------------
    -- Context register interface: external debug control signals
    ---------------------------------------------------------------------------
    -- Whether debug traps are to be handled normally or by halting execution
    -- for debugging through the external bebug bus.
    cxreg2cxplif_extDebug       : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- External debug trap information. When the trap in exDbgTrapInfo is
    -- active, the trap cause should be stored in the debug control register
    -- and the BRK flag in the debug control register should be set.
    cxplif2cxreg_exDbgTrapInfo  : out trap_info_array(2**CFG.numContextsLog2-1 downto 0);

    -- BRK flag from the debug control register. When high, the core should
    -- be halted.
    cxreg2cxplif_brk            : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Stepping mode flag from the debug control register. When high,
    -- executing any instruction which has the brkValid flag set should cause
    -- a step trap.
    cxreg2cxplif_stepping       : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);

    -- Resuming flag. This is set when the BRK flag is cleared by the debug
    -- bus. It is cleared when the resumed bit is high while stall is low.
    -- While high, issued instructions should have the brkValid flag cleared,
    -- so breakpoints and step traps are ignored.
    cxreg2cxplif_resuming       : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_resuming_ack   : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0)
    
  );
end core_contextPipelaneIFace;

--=============================================================================
architecture Behavioral of core_contextPipelaneIFace is
--=============================================================================
  --
  -- The architecture consists of 4 distinguishable blocks.
  --
  -- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  --
  --                                cfg2any_ctxtEnable,
  --                             cfg2any_lastGroupForCtxt
  --                                         |
  --                       Per          Per  |   Per
  --                       lane        group v context
  --                      ,-^-.        ,-^-. _  ,-^-.
  --              -  - --.     .------.     |g\      .-- -  -
  --                     |---->| Arb. |--o->|2 |---->|
  --                     |     '------'  |  |c/      |
  --                     |               |           | Contexts and
  --               Lanes |     .------.  |*_arb      | external run
  --                     |     |      |<-'    _      | control
  --                     |<----|Broad.|      /c|     |
  --                     |     |      |<----| 2|<----|
  --              -  - --'     '------'*_mux \g|     '-- -  -
  --                                          ^
  --                                          |
  --                                   cfg2any_context
  --
  -- . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  --
  -- Arb.   = Arbitrator. Merges the signals from coupled lanes together.
  -- Broad. = Broadcasting block. Broadcasts the signals from the contexts and
  --          some merged signals from the pipelanes to all coupled pipelanes.
  -- g2c    = Pipelane group to context mux. Selects the signals from the
  --          highest indexed group associated with a context, or if the
  --          context is disabled, it selects a NOP signal.
  -- c2g    = Context to pipelane group mux. Muxes between the contexts for
  --          each pipelane group.
  --
  -- The *_arb named signals route from the arbitrator to the group-to-context
  -- mux and the broadcast block. The *_mux named signals route from the
  -- context-to-group mux to the broadcast block.
  --
  -- Not depicted is the interconnect from the *_arb signals to the instruction
  -- memory. Also not depicted is the forwarding logic for the branch and link
  -- registers, which is instantiated per pipelane group.
  --
  -----------------------------------------------------------------------------
  -- Arbitrator outputs
  -----------------------------------------------------------------------------
  -- Names match the inputs from the pipelanes in the entity description. Refer
  -- to the documentation there for more information.
  signal blockReconfig_arb      : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal irqAck_arb             : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal idle_arb               : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal PC_arb                 : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal limmValid_arb          : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal valid_arb              : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal brkValid_arb           : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal invalUntilBR_arb       : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal brLinkWritePort_arb    : pl2cxreg_writePort_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal trapInfo_arb           : trap_info_array   (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal trapPoint_arb          : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal exDbgTrapInfo_arb      : trap_info_array   (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal stop_arb               : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal rfi_arb                : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Context to group mux outputs
  -----------------------------------------------------------------------------
  -- Names match the outputs to the pipelanes in the entity description. Refer
  -- to the documentation there for more information.
  signal irq_mux                : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal irqID_mux              : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal run_mux                : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal brLinkReadPort_mux     : cxreg2pl_readPort_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal brReadData_mux         : rvex_brRegData_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal linkReadData_mux       : rvex_data_array   (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal contextPC_mux          : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal overridePC_mux         : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal trapHandler_mux        : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal trapReturn_mux         : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal extDebug_mux           : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal handlingDebugTrap_mux  : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal debugTrapEnable_mux    : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal breakpoints_mux        : cxreg2pl_breakpoint_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal softCtxtSwitch_mux     : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal stepping_mux           : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  signal resuming_mux           : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -----------------------------------------------------------------------------
  -- Other signals
  -----------------------------------------------------------------------------
  -- Masked IRQ flag for each context.
  signal irq_ctxt               : std_logic_vector  (2**CFG.numContextsLog2-1 downto 0);
  
  -- Run flag for each context, taking the external run input and the BRK
  -- control bits into consideration.
  signal run_ctxt               : std_logic_vector  (2**CFG.numContextsLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Arbitrator
  -----------------------------------------------------------------------------
  arbitrator: process (
    
    -- Configuration signal.
    cfg2any_coupled, cfg2any_numGroupsLog2, cfg2any_laneIndex,
    
    -- Signals from pipelanes.
    br2cxplif_irqAck, pl2cxplif_idle, pl2cxplif_blockReconfig,
    br2cxplif_PC, br2cxplif_fetchPC, br2cxplif_branch, br2cxplif_limmValid,
    br2cxplif_valid, br2cxplif_brkValid, br2cxplif_invalUntilBR, 
    pl2cxplif_brLinkWritePort, br2cxplif_trapInfo, br2cxplif_trapPoint, 
    br2cxplif_exDbgTrapInfo, br2cxplif_stop, pl2cxplif_rfi,
    br2cxplif_imemFetch, br2cxplif_imemCancel
    
  ) is
    
    -- Variables for all the signals we need to route.
    variable blockReconfig_v    : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable irqAck_v           : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable idle_v             : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable PC_v               : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    variable fetchPC_v          : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    variable branch_v           : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable limmValid_v        : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable valid_v            : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable brkValid_v         : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable invalUntilBR_v     : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable imemFetch_v        : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable imemCancel_v       : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable brLinkWritePort_v  : pl2cxreg_writePort_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    variable trapPoint_v        : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    variable trapInfo_v         : trap_info_array   (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable exDbgTrapInfo_v    : trap_info_array   (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable stop_v             : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    variable rfi_v              : std_logic_vector  (2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Indexing/static variables.
    variable selectedLane       : natural;
    variable currentLane        : natural;
    variable groupA             : natural;
    variable groupB             : natural;
    variable index              : natural;
    variable coupled            : std_logic;
    variable pcIndex            : std_logic_vector(3 downto 0);
    
    -- Bitwise or operator for a branch register data array, so we can keep the
    -- code below sane.
    function "or" (
      l: rvex_brRegData_array;
      r: rvex_brRegData_array
    ) return rvex_brRegData_array is
      variable retval: rvex_brRegData_array(l'range);
    begin
      for i in l'range loop
        retval(i) := l(i) or r(i);
      end loop;
      return retval;
    end "or";
    
  begin
    
    -- Perform static arbitration for all signals except for the branch write
    -- port and the idle signal: only the signals from the lanes with a branch
    -- unit are valid for these.
    for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
      
      -- Figure out which branch unit to use.
      selectedLane := group2lastLane(laneGroup, CFG);
      
      -- Select the incoming values from the branch units for signals which are
      -- only valid for those lanes.
      irqAck_v(laneGroup)           := br2cxplif_irqAck(selectedLane);
      PC_v(laneGroup)               := br2cxplif_PC(selectedLane);
      fetchPC_v(laneGroup)          := br2cxplif_fetchPC(selectedLane);
      branch_v(laneGroup)           := br2cxplif_branch(selectedLane);
      limmValid_v(laneGroup)        := br2cxplif_limmValid(selectedLane);
      valid_v(laneGroup)            := br2cxplif_valid(selectedLane);
      brkValid_v(laneGroup)         := br2cxplif_brkValid(selectedLane);
      invalUntilBR_v(laneGroup)     := br2cxplif_invalUntilBR(selectedLane);
      imemFetch_v(laneGroup)        := br2cxplif_imemFetch(selectedLane);
      imemCancel_v(laneGroup)       := br2cxplif_imemCancel(selectedLane);
      trapInfo_v(laneGroup)         := br2cxplif_trapInfo(selectedLane);
      trapPoint_v(laneGroup)        := br2cxplif_trapPoint(selectedLane);
      exDbgTrapInfo_v(laneGroup)    := br2cxplif_exDbgTrapInfo(selectedLane);
      stop_v(laneGroup)             := br2cxplif_stop(selectedLane);
      
      -- Override the fetchPC bits which we don't need to zero.
      fetchPC_v(laneGroup)(
        (CFG.numLanesLog2 - CFG.numLaneGroupsLog2)
        + SYLLABLE_SIZE_LOG2B - 1
        downto 0
      ) := (others => '0');
      
      -- Load default values into rfi_v, blockReconfig_v, idle_v and
      -- brLinkWritePort_v.
      rfi_v(laneGroup)              := '0';
      blockReconfig_v(laneGroup)    := '0';
      idle_v(laneGroup)             := '1';
      brLinkWritePort_v(laneGroup)  := (
        brData                      => (others => (others => '0')),
        linkData                    => (others => (others => '0')),
        brWriteEnable               => (others => (others => '0')),
        linkWriteEnable             => (others => '0'),
        brForwardEnable             => (others => (others => '0')),
        linkForwardEnable           => (others => '0')
      );
      
      -- Generate merging logic for the idle signal, blockReconfig signal and
      -- the branch/link register write port. The value written to the link
      -- register is priority encoded (giving precedence to higher indexed
      -- lanes. The branch register value - written is wired-or in case of
      -- write conflicts, because that's cheaper and maybe even useful in some
      -- cases.
      for groupIndex in 0 to 2**(CFG.numLanesLog2 - CFG.numLaneGroupsLog2)-1 loop
        currentLane := group2firstLane(laneGroup, CFG) + groupIndex;
        
        -- RFI signal is wired-or.
        rfi_v(laneGroup)
          := rfi_v(laneGroup)
          or pl2cxplif_rfi(currentLane);
        
        -- BlockReconfig signal is wired-or.
        blockReconfig_v(laneGroup)
          := blockReconfig_v(laneGroup)
          or pl2cxplif_blockReconfig(currentLane);
        
        -- Idle signal is wired-and.
        idle_v(laneGroup)
          := idle_v(laneGroup)
          and pl2cxplif_idle(currentLane);
        
        -- Write/forward enable signals are wired-or.
        brLinkWritePort_v(laneGroup).brWriteEnable
          := brLinkWritePort_v(laneGroup).brWriteEnable
          or pl2cxplif_brLinkWritePort(currentLane).brWriteEnable;
        
        brLinkWritePort_v(laneGroup).linkWriteEnable
          := brLinkWritePort_v(laneGroup).linkWriteEnable
          or pl2cxplif_brLinkWritePort(currentLane).linkWriteEnable;
        
        brLinkWritePort_v(laneGroup).brForwardEnable
          := brLinkWritePort_v(laneGroup).brForwardEnable
          or pl2cxplif_brLinkWritePort(currentLane).brForwardEnable;
        
        brLinkWritePort_v(laneGroup).linkForwardEnable
          := brLinkWritePort_v(laneGroup).linkForwardEnable
          or pl2cxplif_brLinkWritePort(currentLane).linkForwardEnable;
        
        -- Branch register write data is also wired-or. Make sure we mask by
        -- the forward enable signals first though; sometimes the write values
        -- are nonzero while the registers are not being written.
        for stage in S_FIRST to S_SWB loop
          brLinkWritePort_v(laneGroup).brData(stage)
            := brLinkWritePort_v(laneGroup).brData(stage)
            or (
              pl2cxplif_brLinkWritePort(currentLane).brData(stage)
              and pl2cxplif_brLinkWritePort(currentLane).brForwardEnable(stage)
            );
        end loop;
        
      end loop;
      
      -- Handle link register write arbitration for each forwarded pipeline
      -- stage.
      for stage in S_FIRST to S_SWB loop
        selectedLane := group2firstLane(laneGroup, CFG);
        for groupIndex in 0 to 2**(CFG.numLanesLog2 - CFG.numLaneGroupsLog2)-1 loop
          currentLane := group2firstLane(laneGroup, CFG) + groupIndex;
          if pl2cxplif_brLinkWritePort(currentLane).linkForwardEnable(stage) = '1' then
            selectedLane := currentLane;
          end if;
        end loop;
        
        -- Mux between the incoming data signal based on the priority encoder
        -- output.
        brLinkWritePort_v(laneGroup).linkData(stage)
          := pl2cxplif_brLinkWritePort(selectedLane).linkData(stage);
        
      end loop;
      
    end loop;
    
    -- Use a binary tree to merge the signals coming from the lane groups
    -- together based on the current configuration. Refer to the documentation
    -- for binTreeIndices in utils_pkg.vhd for more information on what- this
    -- tree looks like.
    for level in 0 to CFG.numLaneGroupsLog2-1 loop
      for blockIndex in 0 to (2**CFG.numLaneGroupsLog2)/2-1 loop
        binTreeIndices(level, blockIndex, groupA, groupB);
        
        -- Merge the signals from the two groups together when the groups are
        -- coupled.
        if cfg2any_coupled(groupA + groupB * 2**CFG.numLaneGroupsLog2) = '1' then
          
          -- Copy the signals coming from the branch units in the higher
          -- indexed lane group to the lower indexed lane group.
          irqAck_v(groupA)       := irqAck_v(groupB);
          PC_v(groupA)           := PC_v(groupB);
          fetchPC_v(groupA)      := fetchPC_v(groupB);
          branch_v(groupA)       := branch_v(groupB);
          limmValid_v(groupA)    := limmValid_v(groupB);
          valid_v(groupA)        := valid_v(groupB);
          brkValid_v(groupA)     := brkValid_v(groupB);
          invalUntilBR_v(groupA) := invalUntilBR_v(groupB);
          imemFetch_v(groupA)    := imemFetch_v(groupB);
          imemCancel_v(groupA)   := imemCancel_v(groupB);
          trapInfo_v(groupA)     := trapInfo_v(groupB);
          trapPoint_v(groupA)    := trapPoint_v(groupB);
          exDbgTrapInfo_v(groupA):= exDbgTrapInfo_v(groupB);
          stop_v(groupA)         := stop_v(groupB);
          rfi_v(groupA)          := rfi_v(groupB);
          
          -- Override the fetchPC bits for this level appropriately.
          index := level + (CFG.numLanesLog2 - CFG.numLaneGroupsLog2) + SYLLABLE_SIZE_LOG2B;
          fetchPC_v(groupA)(index) := '0';
          fetchPC_v(groupB)(index) := '1';
          
          -- Handle wired-and/or signals.
          rfi_v(groupA)
            := rfi_v(groupA)
            or rfi_v(groupB);
          rfi_v(groupB)
            := rfi_v(groupA);
            
          blockReconfig_v(groupA)
            := blockReconfig_v(groupA)
            or blockReconfig_v(groupB);
          blockReconfig_v(groupB)
            := blockReconfig_v(groupA);
          
          idle_v(groupA)
            := idle_v(groupA)
           and idle_v(groupB);
          idle_v(groupB)
            := idle_v(groupA);
          
          brLinkWritePort_v(groupA).brWriteEnable
            := brLinkWritePort_v(groupA).brWriteEnable
            or brLinkWritePort_v(groupB).brWriteEnable;
          brLinkWritePort_v(groupB).brWriteEnable
            := brLinkWritePort_v(groupA).brWriteEnable;
          
          brLinkWritePort_v(groupA).linkWriteEnable
            := brLinkWritePort_v(groupA).linkWriteEnable
            or brLinkWritePort_v(groupB).linkWriteEnable;
          brLinkWritePort_v(groupB).linkWriteEnable
            := brLinkWritePort_v(groupA).linkWriteEnable;
          
          brLinkWritePort_v(groupA).brForwardEnable
            := brLinkWritePort_v(groupA).brForwardEnable
            or brLinkWritePort_v(groupB).brForwardEnable;
          brLinkWritePort_v(groupB).brForwardEnable
            := brLinkWritePort_v(groupA).brForwardEnable;
          
          brLinkWritePort_v(groupA).brData
            := brLinkWritePort_v(groupA).brData
            or brLinkWritePort_v(groupB).brData;
          brLinkWritePort_v(groupB).brData
            := brLinkWritePort_v(groupA).brData;
          
          -- Handle link register write/forward data.
          for stage in S_FIRST to S_SWB loop
            if brLinkWritePort_v(groupB).linkForwardEnable(stage) = '1' then
              brLinkWritePort_v(groupA).linkData(stage)
                := brLinkWritePort_v(groupB).linkData(stage);
            else
              brLinkWritePort_v(groupB).linkData(stage)
                := brLinkWritePort_v(groupA).linkData(stage);
            end if;
          end loop;
          
          brLinkWritePort_v(groupA).linkForwardEnable
            := brLinkWritePort_v(groupA).linkForwardEnable
            or brLinkWritePort_v(groupB).linkForwardEnable;
          brLinkWritePort_v(groupB).linkForwardEnable
            := brLinkWritePort_v(groupA).linkForwardEnable;
          
        end if;
        
      end loop;
    end loop;
    
    -- Invalidate lane groups which would be executing syllables coming before
    -- the PC. This can happen when the PC is misaligned (with respect to
    -- CFG.bundleAlignLog2) after returning from a trap, which can happen when
    -- a trap occurs somewhere in the middle of an instruction in a mode with
    -- a small issue width, and the configuration changes while the trap
    -- handler is executed.
    if CFG.numLaneGroupsLog2 > 0 then
      for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        
        -- Determine the lane index part of the PC.
        for i in 0 to 3 loop
          pcIndex(i) := PC_v(laneGroup)(SYLLABLE_SIZE_LOG2B + i);
          if i >= CFG.bundleAlignLog2 then
            pcIndex(i) := '0';
          end if;
          if i >= (CFG.numLanesLog2-CFG.numLaneGroupsLog2) + vect2uint(cfg2any_numGroupsLog2(laneGroup)) then
            pcIndex(i) := '0';
          end if;
        end loop;
        
        if vect2uint(cfg2any_laneIndex(group2firstLane(laneGroup, CFG)))
         < vect2uint(pcIndex)
        then
          valid_v(laneGroup) := '0';
        end if;
      end loop;
    end if;
    
    -- Drive *_arb output signals.
    blockReconfig_arb     <= blockReconfig_v;
    irqAck_arb            <= irqAck_v;
    idle_arb              <= idle_v;
    PC_arb                <= PC_v;
    limmValid_arb         <= limmValid_v;
    valid_arb             <= valid_v;
    brkValid_arb          <= brkValid_v;
    invalUntilBR_arb      <= invalUntilBR_v;
    brLinkWritePort_arb   <= brLinkWritePort_v;
    trapInfo_arb          <= trapInfo_v;
    trapPoint_arb         <= trapPoint_v;
    exDbgTrapInfo_arb     <= exDbgTrapInfo_v;
    stop_arb              <= stop_v;
    rfi_arb               <= rfi_v;
    
    -- Drive instruction memory output signals.
    cxplif2ibuf_PCs       <= PC_v;
    cxplif2ibuf_fetchPCs  <= fetchPC_v;
    cxplif2ibuf_branch    <= branch_v;
    cxplif2ibuf_fetch     <= imemFetch_v;
    cxplif2ibuf_cancel    <= imemCancel_v;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Broadcasting block
  -----------------------------------------------------------------------------
  broadcasting: for lane in 0 to 2**CFG.numLanesLog2-1 generate
    
    -- Pipelane group for the current lane.
    constant laneGroup  : natural := lane2group(lane, CFG);
    
    -- Index of the current lane within the group.
    constant laneIndex  : natural := lane2indexInGroup(lane, CFG);
    
    -- Number of LSBs in the lane PC which are fixed per lane due to alignment
    -- requirements.
    constant fixedPCBits: natural
      := (CFG.numLanesLog2 - CFG.numLaneGroupsLog2)
       + SYLLABLE_SIZE_LOG2B;
    
  begin
    
    -- Broadcast all the normal signals.
    cxplif2pl_irq(lane)               <= irq_mux(laneGroup);
    cxplif2br_irqID(lane)             <= irqID_mux(laneGroup);
    cxplif2br_run(lane)               <= run_mux(laneGroup);
    cxplif2pl_PC(lane)                <= PC_arb(laneGroup);
    cxplif2pl_limmValid(lane)         <= limmValid_arb(laneGroup);
    cxplif2pl_valid(lane)             <= valid_arb(laneGroup);
    cxplif2pl_brkValid(lane)          <= brkValid_arb(laneGroup)  -- Executing first instr. after debug trap.
                                 and not resuming_mux(laneGroup); -- Executing first instr. after BRK flag cleared.
    cxplif2pl_invalUntilBR(lane)      <= invalUntilBR_arb(laneGroup);
    cxplif2pl_brLinkReadPort(lane)    <= brLinkReadPort_mux(laneGroup);
    cxplif2br_contextPC(lane)         <= contextPC_mux(laneGroup);
    cxplif2br_overridePC(lane)        <= overridePC_mux(laneGroup);
    cxplif2pl_trapHandler(lane)       <= trapHandler_mux(laneGroup);
    cxplif2br_trapReturn(lane)        <= trapReturn_mux(laneGroup);
    cxplif2br_extDebug(lane)          <= extDebug_mux(laneGroup);
    cxplif2br_handlingDebugTrap(lane) <= handlingDebugTrap_mux(laneGroup);
    cxplif2pl_debugTrapEnable(lane)   <= debugTrapEnable_mux(laneGroup)
                                      or extDebug_mux(laneGroup); -- Always enable debug traps in external debug mode.
    cxplif2brku_breakpoints(lane)     <= breakpoints_mux(laneGroup);
    cxplif2pl_softCtxtSwitch(lane)    <= softCtxtSwitch_mux(laneGroup)
                                      when laneIndex = 0 else '0'; -- Only need this in one pipelane per group.
    cxplif2brku_stepping(lane)        <= stepping_mux(laneGroup);
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Group to context muxing and logic
  -----------------------------------------------------------------------------
  group2context: for ctxt in 0 to 2**CFG.numContextsLog2-1 generate
    signal laneGroup: natural;
  begin
    
    -- Determine the group to use for this context.
    laneGroup <= vect2uint(cfg2any_lastGroupForCtxt(ctxt));
    
    -- Generate all the muxes.
    cxplif2cfg_blockReconfig(ctxt)      <= blockReconfig_arb(laneGroup) and cfg2cxplif_active(ctxt);
    cxplif2rctrl_irqAck(ctxt)           <= irqAck_arb(laneGroup) and cfg2cxplif_active(ctxt);
    cxplif2rctrl_idle(ctxt)             <= idle_arb(laneGroup) or not cfg2cxplif_active(ctxt);
    cxplif2cxreg_stall(ctxt)            <= stall(laneGroup) or not cfg2cxplif_active(ctxt);
    cxplif2cxreg_idle(ctxt)             <= idle_arb(laneGroup) or not cfg2cxplif_active(ctxt);
    cxplif2cxreg_stop(ctxt)             <= stop_arb(laneGroup);
    cxplif2cxreg_brWriteData(ctxt)      <= brLinkWritePort_arb(laneGroup).brData(S_SWB);
    cxplif2cxreg_brWriteEnable(ctxt)    <= brLinkWritePort_arb(laneGroup).brWriteEnable(S_SWB);
    cxplif2cxreg_linkWriteData(ctxt)    <= brLinkWritePort_arb(laneGroup).linkData(S_SWB);
    cxplif2cxreg_linkWriteEnable(ctxt)  <= brLinkWritePort_arb(laneGroup).linkWriteEnable(S_SWB);
    cxplif2cxreg_nextPC(ctxt)           <= PC_arb(laneGroup);
    cxplif2cxreg_overridePC_ack(ctxt)   <= valid_arb(laneGroup);
    cxplif2cxreg_trapInfo(ctxt)         <= trapInfo_arb(laneGroup);
    cxplif2cxreg_trapPoint(ctxt)        <= trapPoint_arb(laneGroup);
    cxplif2cxreg_rfi(ctxt)              <= rfi_arb(laneGroup);
    cxplif2cxreg_exDbgTrapInfo(ctxt)    <= exDbgTrapInfo_arb(laneGroup);
    cxplif2cxreg_resuming_ack(ctxt)     <= valid_arb(laneGroup);
    
    -- While we're at it, combine the external run control and control register
    -- data where necessary for each context.
    irq_ctxt(ctxt) <= rctrl2cxplif_irq(ctxt)
                  and cxreg2cxplif_interruptEnable(ctxt);
    run_ctxt(ctxt) <= rctrl2cxplif_run(ctxt)
                  and cfg2cxplif_active(ctxt)
                  and (not cfg2cxplif_requestReconfig(ctxt))
                  and (not cxreg2cxplif_brk(ctxt));
    
    -- Mask the lane performance counter status signals for each context.
    group2context_perf_count_status: process (
      cfg2any_context, pl2cxplif2_sylCommit, pl2cxplif2_sylNop
    ) is
    begin
      cxplif2cxreg_sylCommit(ctxt)      <= (others => '0');
      cxplif2cxreg_sylNop(ctxt)         <= (others => '0');
      for lane in 0 to 2**CFG.numLanesLog2-1 loop
        if vect2uint(cfg2any_context(lane2group(lane, CFG))) = ctxt then
          cxplif2cxreg_sylCommit(ctxt)(lane)  <= pl2cxplif2_sylCommit(lane);
          cxplif2cxreg_sylNop(ctxt)(lane)     <= pl2cxplif2_sylNop(lane);
        end if;
      end loop;
    end process;
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Context to group muxing and logic
  -----------------------------------------------------------------------------
  context2group: for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 generate
    signal ctxt   : natural;
    signal active : std_logic;
  begin
    
    -- Determine the context to use for this group.
    ctxt <= vect2uint(cfg2any_context(laneGroup));
    
    -- Determine whether this group is enabled at all.
    active <= cfg2any_active(laneGroup);
    
    -- Generate all the muxes.
    irq_mux(laneGroup)                <= irq_ctxt(ctxt)                       when active = '1' else '0';
    irqID_mux(laneGroup)              <= rctrl2cxplif_irqID(ctxt);
    run_mux(laneGroup)                <= run_ctxt(ctxt)                       when active = '1' else '0';
    brReadData_mux(laneGroup)         <= cxreg2cxplif_brReadData(ctxt);
    linkReadData_mux(laneGroup)       <= cxreg2cxplif_linkReadData(ctxt);
    contextPC_mux(laneGroup)          <= cxreg2cxplif_currentPC(ctxt);
    overridePC_mux(laneGroup)         <= cxreg2cxplif_overridePC(ctxt)        when active = '1' else '0';
    trapHandler_mux(laneGroup)        <= cxreg2cxplif_trapHandler(ctxt);
    trapReturn_mux(laneGroup)         <= cxreg2cxplif_trapReturn(ctxt);
    extDebug_mux(laneGroup)           <= cxreg2cxplif_extDebug(ctxt)          when active = '1' else '0';
    handlingDebugTrap_mux(laneGroup)  <= cxreg2cxplif_handlingDebugTrap(ctxt) when active = '1' else '0';
    debugTrapEnable_mux(laneGroup)    <= cxreg2cxplif_debugTrapEnable(ctxt)   when active = '1' else '0';
    breakpoints_mux(laneGroup)        <= cxreg2cxplif_breakpoints(ctxt);
    softCtxtSwitch_mux(laneGroup)     <= cxreg2cxplif_softCtxtSwitch(ctxt)    when active = '1' else '0';
    stepping_mux(laneGroup)           <= cxreg2cxplif_stepping(ctxt)          when active = '1' else '0';
    resuming_mux(laneGroup)           <= cxreg2cxplif_resuming(ctxt)          when active = '1' else '0';
    
  end generate;
  
  -----------------------------------------------------------------------------
  -- Branch register forwarding logic
  -----------------------------------------------------------------------------
  branch_fwd_gen_group: for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 generate
    br_fwd_gen_stage: for stage in S_SRD to S_SFW generate
      constant stagesToForward    : natural := S_SWB-stage;
    begin
      br_fwd_gen_reg: for b in 0 to 7 generate
        signal writeDatas         : std_logic_vector(stagesToForward-1 downto 0);
        signal writeEnables       : std_logic_vector(stagesToForward-1 downto 0);
      begin
        br_fwd_gen_stageIndices: for index in 0 to stagesToForward-1 generate
          writeDatas(index)   <= brLinkWritePort_arb(laneGroup).brData(stage + index + 1)(b);
          writeEnables(index) <= brLinkWritePort_arb(laneGroup).brForwardEnable(stage + index + 1)(b);
        end generate;
        
        br_fwd: entity rvex.core_forward
          generic map (
            ENABLE_FORWARDING     => CFG.forwarding,
            DATA_WIDTH            => 1,
            ADDRESS_WIDTH         => 0,
            NUM_LANES             => 1,
            NUM_STAGES_TO_FORWARD => stagesToForward
          )
          port map (
            
            -- Register read connections.
            readAddress           => (others => '0'),
            readDataIn(0)         => brReadData_mux(laneGroup)(b),
            readDataOut(0)        => brLinkReadPort_mux(laneGroup).brData(stage)(b),
            readDataForwarded     => open,
            
            -- Queued write signals.
            writeAddresses        => (others => '0'),
            writeDatas            => writeDatas,
            writeEnables          => writeEnables,
            coupled               => "1"
            
          );
      
      end generate;
    end generate;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Link register forwarding logic
  -----------------------------------------------------------------------------
  link_fwd_gen_group: for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 generate
    link_fwd_gen_stage: for stage in S_SRD to S_SFW generate
      constant stagesToForward    : natural := S_SWB-stage;
      signal writeDatas           : std_logic_vector(32*stagesToForward-1 downto 0);
      signal writeEnables         : std_logic_vector(stagesToForward-1 downto 0);
    begin
      link_fwd_gen_stageIndices: for index in 0 to stagesToForward-1 generate
        writeDatas(32*index+31 downto 32*index) <= brLinkWritePort_arb(laneGroup).linkData(stage + index + 1);
        writeEnables(index) <= brLinkWritePort_arb(laneGroup).linkForwardEnable(stage + index + 1);
      end generate;
      
      link_fwd: entity rvex.core_forward
        generic map (
          ENABLE_FORWARDING       => CFG.forwarding,
          DATA_WIDTH              => 32,
          ADDRESS_WIDTH           => 0,
          NUM_LANES               => 1,
          NUM_STAGES_TO_FORWARD   => stagesToForward
        )
        port map (
          
          -- Register read connections.
          readAddress             => (others => '0'),
          readDataIn              => linkReadData_mux(laneGroup),
          readDataOut             => brLinkReadPort_mux(laneGroup).linkData(stage),
          readDataForwarded       => open,
          
          -- Queued write signals.
          writeAddresses          => (others => '0'),
          writeDatas              => writeDatas,
          writeEnables            => writeEnables,
          coupled                 => "1"
          
        );
    end generate;
  end generate;
  
end Behavioral;

