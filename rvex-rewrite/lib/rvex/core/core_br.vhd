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
use rvex.core_opcode_pkg.all;
use rvex.core_opcodeBranch_pkg.all;

-- pragma translate_off
use rvex.simUtils_pkg.all;
-- pragma translate_on

--=============================================================================
-- This entity contains the optional branch unit for a pipelane.
-------------------------------------------------------------------------------
entity core_br is
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
    
    -- Active high stall input for the pipeline.
    stall                       : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- VHDL simulation debug information
    ---------------------------------------------------------------------------
    -- pragma translate_off
    br2pl_sim                   : out rvex_string_builder_array(S_IF to S_IF);
    br2pl_simActive             : out std_logic_vector(S_IF to S_IF);
    -- pragma translate_on
    
    ---------------------------------------------------------------------------
    -- Configuration inputs
    ---------------------------------------------------------------------------
    -- Number of coupled lane groups.
    cfg2br_numGroupsLog2        : in  rvex_2bit_type;
    
    ---------------------------------------------------------------------------
    -- Next operation outputs
    ---------------------------------------------------------------------------
    -- The PC for the instruction in S_IF (i.e. the next PC).
    br2cxplif_PC                : out rvex_address_array(S_IF to S_IF);
    
    -- The PC which needs to be fetched next. This is PC rounded up to the next
    -- address which is aligned to the current issue width during normal
    -- operation or rounded down when branch is high. They are needed by the
    -- instruction buffer.
    br2cxplif_fetchPC           : out rvex_address_array(S_IF to S_IF);
    br2cxplif_branch            : out std_logic_vector(S_IF to S_IF);
    
    -- Whether an instruction fetch is being initiated or not.
    br2cxplif_imemFetch         : out std_logic_vector(S_IF to S_IF);
    br2cxplif_limmValid         : out std_logic_vector(S_IF to S_IF);
    
    -- Whether the next instruction is valid and should be committed or not.
    br2cxplif_valid             : out std_logic_vector(S_IF to S_IF);
    
    -- Whether breakpoints are valid in the next instruction or not. This is
    -- low when returning from a debug interrupt.
    br2cxplif_brkValid          : out std_logic_vector(S_IF to S_IF);
    
    -- Whether or not pipeline stages S_IF+1 to S_BR-1 should be invalidated
    -- due to a branch or the core stopping.
    br2cxplif_imemCancel        : out std_logic_vector(S_IF+L_IF to S_IF+L_IF);
    br2cxplif_invalUntilBR      : out std_logic_vector(S_BR to S_BR);
    
    ---------------------------------------------------------------------------
    -- Run control signals
    ---------------------------------------------------------------------------
    -- External interrupt identification. Guaranteed to be loaded in the trap
    -- argument register in the same clkEn'd cycle where irqAck is high.
    cxplif2br_irqID             : in  rvex_address_array(S_BR to S_BR);
    
    -- External interrupt acknowledge signal, active high. and'ed with the
    -- stall input, so it goes high for exactly one clkEn'abled cycle.
    br2cxplif_irqAck            : out std_logic_vector(S_BR to S_BR);
    
    -- Active high run signal. This is the combined run signal from the
    -- external run input and the BRK flag in the debug control register.
    cxplif2br_run               : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Branch control signals from and to pipelane
    ---------------------------------------------------------------------------
    -- Opcode for the branch unit.
    pl2br_opcode                : in  rvex_opcode_array(S_BR to S_BR);
    
    -- Stop bit of the syllable corrosponding to opcode.
    pl2br_stopBit               : in  std_logic_vector(S_BR to S_BR);
    
    -- Whether the opcode is valid.
    pl2br_valid                 : in  std_logic_vector(S_BR to S_BR);
    
    -- PC+1 input for normal program flow.
    pl2br_PC_plusSbit_IFP1      : in  rvex_address_array(S_IF+1 to S_IF+1);
    
    -- PC+1 input from branch stage for STOP instruction, which should stop
    -- execution and set the resumption PC to the instruction following the
    -- stop.
    pl2br_PC_plusSbit_BR        : in  rvex_address_array(S_BR to S_BR);
    
    -- Next fetch address for normal program flow.
    pl2br_PC_plusSbitFetch      : in  rvex_address_array(S_IF+1 to S_IF+1);
    
    -- Link register branch target for RETURN, ICALL and IGOTO.
    pl2br_brTgtLink             : in  rvex_address_array(S_BR to S_BR);
    
    -- PC-relative branch target for other branch instructions.
    pl2br_brTgtRel              : in  rvex_address_array(S_BR to S_BR);
    
    -- Branch operand for conditional branches.
    pl2br_opBr                  : in  std_logic_vector(S_BR to S_BR);
    
    -- Whether a trap is pending in the pipeline somewhere.
    pl2br_trapPending           : in  std_logic_vector(S_BR to S_BR);
    
    -- Trap which should be handled by this instruction, if any, along with
    -- the trap point, and the address of the handler as it was while the
    -- instruction with the trap was being executed.
    pl2br_trapToHandleInfo      : in  trap_info_array(S_BR to S_BR);
    pl2br_trapToHandlePoint     : in  rvex_address_array(S_BR to S_BR);
    pl2br_trapToHandleHandler   : in  rvex_address_array(S_BR to S_BR);
    
    -- Commands the register logic to reset the trap cause to 0 and restore
    -- the control registers which were saved upon trap entry. This is sent to
    -- the pipelane first to delay it until S_MEM to keep the RFI command for
    -- the control registers synchronized with most other register accesses.
    br2pl_rfi                   : out std_logic_vector(S_BR to S_BR);
    
    -- High when the PC is a branch target (or anything other than PC+1).
    br2pl_isBranch              : out std_logic_vector(S_IF to S_IF);
    br2pl_isBranching           : out std_logic_vector(S_BR to S_BR);
    
    -- Trap output for unaligned branches.
    br2pl_trap                  : out trap_info_array(S_BR to S_BR);
    
    ---------------------------------------------------------------------------
    -- Branch control signals from and to context registers
    ---------------------------------------------------------------------------
    -- The current value of the context PC register and associated override
    -- flag. When the override flag is set, the branch unit should behave as if
    -- there was a branch to the value in contextPC. This happens when the
    -- debug bus writes to the PC register. overridePC will remain asserted
    -- until after the next cycle where br2cxplif_valid is asserted.
    cxplif2br_contextPC         : in  rvex_address_array(S_IF+1 to S_IF+1);
    cxplif2br_overridePC        : in  std_logic_vector(S_IF+1 to S_IF+1);
    
    -- Trap information for the trap currently handled by the branch unit, if
    -- any. We can commit this in the branch stage already, because it is
    -- guaranteed that there is no instruction valid in S_MEM while a trap is
    -- entered.
    br2cxplif_trapInfo          : out trap_info_array(S_BR to S_BR);
    br2cxplif_trapPoint         : out rvex_address_array(S_BR to S_BR);
    
    -- Debug trap information for externally handled breakpoints. When the
    -- enable bit in the trap information record is high, the BRK bit should
    -- be set to halt the core and the trap information should be stored for
    -- the external debugger.
    br2cxplif_exDbgTrapInfo     : out trap_info_array(S_BR to S_BR);
    
    -- Stop signal, goes high when the branch unit is executing a stop
    -- instruction. When high, the done bit is set and the BRK bit is set to
    -- halt the core.
    br2cxplif_stop              : out std_logic_vector(S_BR to S_BR);
    
    -- Trap handler return address. This is just connected to the current value
    -- of the trap point register.
    cxplif2br_trapReturn        : in  rvex_address_array(S_BR to S_BR);
    
    -- Set when the current value of the trap cause register maps to a debug
    -- trap.
    cxplif2br_handlingDebugTrap : in  std_logic_vector(S_BR to S_BR);
    
    -- Whether debug traps are to be handled normally or by halting execution
    -- for debugging through the external bebug bus.
    cxplif2br_extDebug          : in  std_logic_vector(S_BR to S_BR);
    
    ---------------------------------------------------------------------------
    -- Trace output signals
    ---------------------------------------------------------------------------
    -- Trap information for the trace unit (this first passes through the
    -- pipelane to sync up with all the other signals).
    br2pl_traceTrapInfo         : out trap_info_array(S_IF to S_IF);
    br2pl_traceTrapPoint        : out rvex_address_array(S_IF to S_IF)
    
  );
end core_br;

--=============================================================================
architecture Behavioral of core_br is
--=============================================================================
  
  -- Decoded opcode signals.
  signal ctrl                   : branchCtrlSignals_array(S_BR to S_BR);
  
  -- Combined run flag. run_r is delayes by one cycle so the first instruction
  -- after a halt can be detected.
  signal run, run_r             : std_logic_vector(S_BR to S_BR);
  
  -- Stop flags. When stop or stop_r are active, instruction fetching should be
  -- disabled, and if stop_r is active, a stop trap should be generated.
  signal stop, stop_r           : std_logic_vector(S_BR to S_BR);
  
  -- RFI flush control signals. The first of these is generated in the branch
  -- determination process. It is set only if the change in CCR due to the SCCR
  -- restore affects instruction fetches, in which case fetching should be
  -- disabled until CCR is updated (this happens in S_MEM). Fetching is
  -- disabled when rfiFlush(S_BR..S_MEM) is nonzero. The branch determination
  -- logic will continue to force the next PC to the trap point when
  -- rfiFlush(S_BR+1..S_MEM+1) is nonzero.
  signal rfiFlush               : std_logic_vector(S_BR to S_MEM+1);
  signal rfiFlush_r             : std_logic_vector(S_BR+1 to S_MEM+1);
  
  -- Breakpoint enable signal for the next instruction. Goes low for the first
  -- valid instruction after leaving a debug trap.
  signal brkptEnable            : std_logic_vector(S_IF to S_IF);
  
  -- Breakpoint enable set and reset signals.
  signal brkptEnableSet         : std_logic_vector(S_IF to S_IF);
  signal brkptEnableClear       : std_logic_vector(S_BR to S_BR);
  
  -- Next PC source type and signal.
  subtype nextPCsrc_type is std_logic_vector(2 downto 0);
  constant NEXT_PC_NORMAL       : nextPCsrc_type := "000"; -- Normal flow: PC(IF+1)+1
  constant NEXT_PC_CURRENT      : nextPCsrc_type := "001"; -- Current PC (halt): contextPC
  constant NEXT_PC_TRAP_POINT   : nextPCsrc_type := "010"; -- Incoming trap point
  constant NEXT_PC_TRAP_HANDLER : nextPCsrc_type := "011"; -- Trap handler
  constant NEXT_PC_TRAP_RETURN  : nextPCsrc_type := "100"; -- Trap return address (trap point register)
  constant NEXT_PC_BR_RELATIVE  : nextPCsrc_type := "101"; -- PC+1+offset
  constant NEXT_PC_BR_LINK      : nextPCsrc_type := "110"; -- Link register
  type nextPCsrc_array is array (natural range <>) of nextPCsrc_type;
  signal nextPCsrc              : nextPCsrc_array(S_BR to S_BR);
  
  -- Branch signal. This is high whenever the next PC source is something other
  -- than the "expected" normal PC+1 case.
  signal branching              : std_logic_vector(S_BR to S_BR);
  
  -- Branch signal for the instruction fetch stage. This is high in both fetch
  -- cycles after a branch if a double fetch was required due to misalignment.
  signal branch                 : std_logic_vector(S_IF to S_IF);
  
  -- This is an output of the next PC decoding logic. When high, the next PC
  -- should NOT be post-decremented by 1 in the case that a necessary LIMMH
  -- operation might be present in the previous pair. This is the case when the
  -- core should be halted, to prevent the context PC register from
  -- decrementing.
  signal noLimmPrefetch         : std_logic_vector(S_BR to S_BR);
  
  -- Computed PC for IF stage.
  signal nextPC                 : rvex_address_array(S_IF to S_IF);
  
  -- PC which needs to be fetched next. Not necessarily aligned, but the
  -- misaligned bits are ignored in the instruction buffer.
  signal fetchPC                : rvex_address_array(S_IF to S_IF);
  
  -- This is pulled high when the next requested instruction cannot be fetched
  -- in a single cycle. This happens when a branch occurs to a misaligned
  -- address for as far as the memory system is concerned. When high, the
  -- associated instruction should be invalidated.
  signal doubleFetch            : std_logic_vector(S_IF to S_IF);
  
  -- This goes high when the next PC is not aligned to the syllable size for a
  -- single group.
  signal nextPCMisaligned       : std_logic_vector(S_IF to S_IF);
  
  -- Branch reason, for simulation.
  -- pragma translate_off
  signal simReason              : rvex_string_builder_type;
  -- pragma translate_on
  
  -- Action taken, for simulation.
  -- pragma translate_off
  signal simAction              : rvex_string_builder_type;
  -- pragma translate_on
  
  -- Trap information for the trace unit.
  signal traceTrapInfo          : trap_info_array(S_IF to S_IF);
  signal traceTrapPoint         : rvex_address_array(S_IF to S_IF);

--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Some things in here will not work properly if S_BR equals 2. They're
  -- marked with FIXMEs.
  assert S_BR > 2
    report "S_BR has to be 3 or more or the branch unit might misbehave, " &
           "depending on the rest of the system."
    severity failure;
  
  -----------------------------------------------------------------------------
  -- Generate internal control signals
  -----------------------------------------------------------------------------
  -- Decode the opcode.
  ctrl(S_BR) <= OPCODE_TABLE(vect2uint(pl2br_opcode(S_BR))).branchCtrl;
  
  -- Load the incoming run signal into a local signal for convenience.
  run(S_BR) <= cxplif2br_run;
  
  -- Generate the registers used to delay run and stop with.
  run_stop_reg_gen: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        run_r(S_BR) <= '0';
        stop_r(S_BR) <= '0';
      elsif clkEn = '1' and stall = '0' then
        run_r(S_BR) <= run(S_BR);
        stop_r(S_BR) <= stop(S_BR);
      end if;
    end if;
  end process;
  
  -- Generate the breakpoint enable set/reset register. This is used to disable
  -- breakpoints in the first instruction processed after a debug trap.
  brk_enable_gen: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        brkptEnable(S_IF) <= '1';
      elsif clkEn = '1' and stall = '0' then
        if brkptEnableClear(S_BR) = '1' then
          brkptEnable(S_IF) <= '0';
        elsif brkptEnableSet(S_IF) = '1' then
          brkptEnable(S_IF) <= '1';
        end if;
      end if;
    end if;
  end process;
  
  -- Generate the RFI flush stage registers.
  rfi_flush_reg_gen: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rfiFlush_r <= (others => '0');
      elsif clkEn = '1' and stall = '0' then
        rfiFlush_r(S_BR+1 to S_MEM+1) <= rfiFlush(S_BR to S_MEM);
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Determine next PC source and control signal states
  -----------------------------------------------------------------------------
  det_branch: process (
    stall, ctrl, run, run_r, stop_r, cxplif2br_irqID, rfiFlush_r,
    pl2br_valid, pl2br_opBr,
    pl2br_trapPending, cxplif2br_overridePC,
    pl2br_trapToHandleInfo, pl2br_trapToHandlePoint,
    cxplif2br_extDebug, cxplif2br_handlingDebugTrap
  ) is
    variable rfiFlushInProgress : std_logic;
  begin
    
    -- Set trap information defaults.
    br2cxplif_trapInfo(S_BR)      <= pl2br_trapToHandleInfo(S_BR);
    traceTrapInfo(S_IF)           <= pl2br_trapToHandleInfo(S_BR);
    br2cxplif_trapPoint(S_BR)     <= pl2br_trapToHandlePoint(S_BR);
    traceTrapPoint(S_IF)          <= pl2br_trapToHandlePoint(S_BR);
    br2cxplif_exDbgTrapInfo(S_BR) <= pl2br_trapToHandleInfo(S_BR);
    
    -- Don't try to fetch the previous instruction first by default.
    noLimmPrefetch(S_BR) <= '1';
    
    -- Set special instruction flags low by default.
    br2pl_rfi(S_BR) <= '0';
    rfiFlush(S_BR) <= '0';
    rfiFlush(S_BR+1 to S_MEM+1) <= rfiFlush_r(S_BR+1 to S_MEM+1);
    br2cxplif_stop(S_BR) <= '0';
    stop(S_BR) <= '0';
    
    -- Don't clear the breakpoint enable register by default.
    brkptEnableClear(S_BR) <= '0';
    
    -- Do not acknowledge interrupts by default.
    br2cxplif_irqAck(S_BR) <= '0';
    
    -- Determine whether we're currently handling an RFI flush.
    rfiFlushInProgress := '0';
    for stage in S_BR+1 to S_MEM+1 loop
      rfiFlushInProgress := rfiFlushInProgress or rfiFlush_r(stage);
    end loop;
    
    -- Determine what to do next.
    if rfiFlushInProgress = '1' then -- FIXME: this will not work properly if S_BR = 2!
      
      -- Set the next PC to the trap return address.
      nextPCsrc(S_BR) <= NEXT_PC_TRAP_RETURN;
      
      -- Fetch the previous instruction first if it's possible that there's
      -- relevant LIMMH instructions there.
      noLimmPrefetch(S_BR) <= '0';
      
      -- pragma translate_off
      if rfiFlush_r(S_MEM+1) = '1' then
        simReason <= to_rvs("RFI return");
      else
        simReason <= to_rvs("RFI flush");
      end if;
      -- pragma translate_on
      
    elsif cxplif2br_overridePC(S_IF+1) = '1' then
      
      -- Branch to the address in the context PC register when requested.
      nextPCsrc(S_BR) <= NEXT_PC_CURRENT;
      
      -- Fetch the previous instruction first if it's possible that there's
      -- relevant LIMMH instructions there.
      noLimmPrefetch(S_BR) <= '0';
      
      -- pragma translate_off
      simReason <= to_rvs("resuming");
      -- pragma translate_on
      
    elsif pl2br_trapToHandleInfo(S_BR).active = '1' then
      
      -- Handle traps.
      if (run(S_BR) = '0') and (rvex_isStopTrap(pl2br_trapToHandleInfo(S_BR)) = '0') then
        
        -- The core is halting. Instead of trying to handle the trap now, we
        -- delay this until the core resumes again, by simply resetting the PC
        -- to the instruction which caused the trap. We cannot do this for stop
        -- traps though, as the trap point is set to the instruction AFTER the
        -- stop instruction.
        nextPCsrc(S_BR) <= NEXT_PC_TRAP_POINT;
        br2cxplif_trapInfo(S_BR).active <= '0';
        traceTrapInfo(S_IF).active <= '0';
        br2cxplif_exDbgTrapInfo(S_BR).active <= '0';
        
        -- pragma translate_off
        simReason <= to_rvs("halting, deferring trap");
        -- pragma translate_on
        
      elsif (rvex_isDebugTrap(pl2br_trapToHandleInfo(S_BR)) = '1' and cxplif2br_extDebug(S_BR) = '1')
         or (rvex_isStopTrap(pl2br_trapToHandleInfo(S_BR)) = '1')
      then
        
        -- This is a debug trap and external debugging is turned on, or this is
        -- a stop trap (issued one cycle after a stop instruction). Disable
        -- regular trapping behavior; instead, halt the core (this happens
        -- automatically based on the exDbgTrapInfo.active signal or by means
        -- of the stop output signal) and set the resumption address/PC to the
        -- trap point.
        nextPCsrc(S_BR) <= NEXT_PC_TRAP_POINT;
        br2cxplif_trapInfo(S_BR).active <= '0';
        traceTrapInfo(S_IF).active <= '0';
        
        if rvex_isStopTrap(pl2br_trapToHandleInfo(S_BR)) = '1' then
          
          -- Assert the stop control signal, which sets the brk and done flags.
          br2cxplif_stop(S_BR) <= '1';
          
          -- pragma translate_off
          simReason <= to_rvs("stop trap");
          -- pragma translate_on
          
        else
          
          -- pragma translate_off
          simReason <= to_rvs("ext. debug trap");
          -- pragma translate_on
          
        end if;
        
      else
        
        -- This is a normal trap, or a debug trap with external debugging
        -- turned off. Hardware control register saving is handled
        -- automatically by the context register logic based on the
        -- trapInfo.active signal, so all we need to do is branch to the trap
        -- handler.
        nextPCsrc(S_BR) <= NEXT_PC_TRAP_HANDLER;
        br2cxplif_exDbgTrapInfo(S_BR).active <= '0';
        
        -- Fetch the previous instruction first if it's possible that there's
        -- relevant LIMMH instructions there.
        noLimmPrefetch(S_BR) <= '0';
        
        -- Handle interrupt handshaking and override the trap argument with the
        -- current interrupt ID.
        if rvex_isInterruptTrap(pl2br_trapToHandleInfo(S_BR)) = '1' then
          br2cxplif_trapInfo(S_BR).arg <= cxplif2br_irqID(S_BR);
          traceTrapInfo(S_IF).arg <= cxplif2br_irqID(S_BR);
          br2cxplif_irqAck(S_BR) <= not stall;
        end if;
        
        -- pragma translate_off
        simReason <= to_rvs("trap");
        -- pragma translate_on
        
      end if;
      
    elsif ctrl(S_BR).RFI = '1' and pl2br_valid(S_BR) = '1' then
      
      -- RFI instruction. Jump to the trap return address (stored in the trap
      -- point context control register) and set the RFI flag high for the
      -- control register restore logic, committed in S_MEM.
      nextPCsrc(S_BR) <= NEXT_PC_TRAP_RETURN;
      br2pl_rfi(S_BR) <= '1';
      
      -- Fetch the previous instruction first if it's possible that there's
      -- relevant LIMMH instructions there.
      noLimmPrefetch(S_BR) <= '0';
      
      -- If we were are returning from a debug trap, disable breakpoints for
      -- the next cycle.
      brkptEnableClear(S_BR) <= cxplif2br_handlingDebugTrap(S_BR);
      
      -- pragma translate_off
      simReason <= to_rvs("RFI instr.");
      -- pragma translate_on
      
      -- Determine if we need to flush due to the SCCR->CCR transfer casuing
      -- changes in fetch behavior. This doesn't occur yet, but it will when
      -- the MMU is added.
      if false then
        
        -- We need to flush.
        rfiFlush(S_BR) <= '1';
        
      end if;
      
    elsif ctrl(S_BR).stop = '1' and pl2br_valid(S_BR) = '1' then
      
      -- Stop instruction. We want to generate a stop trap with the trap point
      -- set to PC+1; easiest way to do that is to just proceed to the next
      -- instruction and cause a trap there. So, we select the regular PC+1 mux
      -- input for the next PC, and set a stop flag. This flag will do two
      -- things: it prevents the next opcode fetch and it is delayed by one
      -- cycle to cause the trap. Note that we need to check for validity here,
      -- because otherwise we'd be committing a trap for a disabled
      -- instruction.
      nextPCsrc(S_BR) <= NEXT_PC_NORMAL;
      stop(S_BR) <= '1';
      
      -- pragma translate_off
      simReason <= to_rvs("STOP instr.");
      -- pragma translate_on
      
    elsif (
      (ctrl(S_BR).branchIfTrue  and     pl2br_opBr(S_BR)) or
      (ctrl(S_BR).branchIfFalse and not pl2br_opBr(S_BR))
    ) = '1' and pl2br_valid(S_BR) = '1' then
      
      -- Regular branch instruction. Jump to the selected branch target.
      if ctrl(S_BR).branchToLink = '1' then
        nextPCsrc(S_BR) <= NEXT_PC_BR_LINK;
        -- pragma translate_off
        simReason <= to_rvs("branch to link");
        -- pragma translate_on
      else
        nextPCsrc(S_BR) <= NEXT_PC_BR_RELATIVE;
        -- pragma translate_off
        simReason <= to_rvs("relative branch");
        -- pragma translate_on
      end if;
      
      -- Branch targets should always point to the start of an instruction if
      -- the program is sane. Therefore, we do not need to fetch the preceding
      -- instruction, even if we're not sure if the target marks the start of
      -- an instruction based on alignment alone.
      noLimmPrefetch(S_BR) <= '1';
      
    elsif run(S_BR) = '0' or pl2br_trapPending(S_BR) = '1' then
      
      -- Halt the core. We need to "branch" to the current instruction
      -- constantly while the core is halted to maintain the current value of
      -- the PC register. In the case of a pending trap, we halt only to
      -- prevent unnecessary instruction fetches while the pipeline is being
      -- flushed. Recall that trapPending only means that there is a trap
      -- somewhere in the pipeline; once it reaches the end, the trap handling
      -- system a few cases above will take priority over this case and handle
      -- the trap.
      nextPCsrc(S_BR) <= NEXT_PC_CURRENT;
      
      -- pragma translate_off
      if run(S_BR) = '0' then
        if pl2br_trapPending(S_BR) = '1' then
          simReason <= to_rvs("halting, trap pending");
        else
          simReason <= to_rvs("halting");
        end if;
      else
        simReason <= to_rvs("trap pending");
      end if;
      -- pragma translate_on
      
    elsif run_r(S_BR) = '0' then
      
      -- Because of priority stuff, run(S_BR) has to be '1', so this marks a
      -- restart. To do so, we need to actively jump to the context PC register
      -- instead of normal program flow, in order to start at that address and
      -- not PC register + 1.
      nextPCsrc(S_BR) <= NEXT_PC_CURRENT;
      
      -- Fetch the previous instruction first if it's possible that there's
      -- relevant LIMMH instructions there.
      noLimmPrefetch(S_BR) <= '0';
      
      -- pragma translate_off
      simReason <= to_rvs("resuming");
      -- pragma translate_on
      
    else
      
      -- Normal operation; don't branch.
      nextPCsrc(S_BR) <= NEXT_PC_NORMAL;
      
      -- pragma translate_off
      simReason <= to_rvs("running");
      -- pragma translate_on
    end if;
    
    -- pragma translate_off
    if stop_r(S_BR) = '1' then
      simReason <= to_rvs("causing stop trap");
    end if;
    -- pragma translate_on
    
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Instantiate mux for the next PC
  -----------------------------------------------------------------------------
  next_pc_mux: process (
    pl2br_PC_plusSbit_BR, pl2br_brTgtLink, pl2br_brTgtRel,
    cxplif2br_trapReturn, pl2br_trapToHandlePoint, pl2br_trapToHandleHandler,
    cxplif2br_contextPC, pl2br_PC_plusSbit_IFP1, nextPCsrc
  ) is
  begin
    case nextPCsrc(S_BR) is
      when NEXT_PC_CURRENT      => nextPC(S_IF) <= cxplif2br_contextPC(S_IF+1);
      when NEXT_PC_TRAP_POINT   => nextPC(S_IF) <= pl2br_trapToHandlePoint(S_BR);
      when NEXT_PC_TRAP_HANDLER => nextPC(S_IF) <= pl2br_trapToHandleHandler(S_BR);
      when NEXT_PC_TRAP_RETURN  => nextPC(S_IF) <= cxplif2br_trapReturn(S_BR);
      when NEXT_PC_BR_RELATIVE  => nextPC(S_IF) <= pl2br_brTgtRel(S_BR);
      when NEXT_PC_BR_LINK      => nextPC(S_IF) <= pl2br_brTgtLink(S_BR);
      when others               => nextPC(S_IF) <= pl2br_PC_plusSbit_IFP1(S_IF+1);
    end case;
  end process;
  
  -- Determine whether we're branching or not.
  branching(S_BR) <= '1' when nextPCsrc(S_BR) /= NEXT_PC_NORMAL else '0';
  
  -- Determine the PC which is to be fetched. If we're branching, this should
  -- be the next PC, rounded down, in order to get the first part of the
  -- instruction or, if the PC happens to be aligned, the whole instruction.
  -- The rounding part is ommitted because the LSBs are ignored by the
  -- instruction buffer anyway. In any other case, we need PC+1 rounded
  -- upwards to the next alignment point. This program counter is not as easily
  -- generated because rounding up can generate a carry, so the value is
  -- computed in parallel to the normal program counter in the pipeline.
  fetch_pc_mux: process (
    branching, nextPC, pl2br_PC_plusSbitFetch
  ) is
  begin
    if branching(S_BR) = '1' then
      fetchPC(S_IF) <= nextPC(S_IF);
    else
      fetchPC(S_IF) <= pl2br_PC_plusSbitFetch(S_IF+1);
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Test next PC alignment
  -----------------------------------------------------------------------------
  -- Determine if the branch target is aligned.
  nextPCMisaligned(S_IF) <=
    '0' when vect2uint(nextPC(S_IF)(cfg2pcAlignLog2(CFG)-1 downto 0)) = 0
    else '1';
  
  -- Determine if the instruction at the requested PC can be fetched in a
  -- single cycle or if it needs two. The latter happens when the requested
  -- instruction is a branch and the branch target is not aligned to the
  -- current memory alignment.
  two_cycle_fetch_proc: process (branching, nextPC, cfg2br_numGroupsLog2) is
    
    -- log2 of the size of an instruction for a lane group.
    constant groupSizeLog2  : natural
      := (CFG.numLanesLog2 - CFG.numLaneGroupsLog2)
      + SYLLABLE_SIZE_LOG2B;
    
    variable mask           : rvex_address_type;
    variable nextPC_v       : rvex_address_type;
    
  begin
    
    -- Normally, we only need one cycle for a fetch.
    doubleFetch(S_IF) <= '0';
    
    -- Handle branches.
    if branching(S_BR) = '1' then
      
      -- Before testing alignment, align the target PC to what alignment the
      -- stop bit system can take care of. If stop bits are disabled, for
      -- example, we can't handle the misalignment here. In that case, cxplif
      -- will take care of it by disabling lanes which would end up getting
      -- instructions preceding the PC.
      mask := (others => '1');
      mask(SYLLABLE_SIZE_LOG2B + CFG.bundleAlignLog2 - 1 downto 0) := (
        others => '0'
      );
      nextPC_v := nextPC(S_IF) and mask;
      
      -- If the branch target is not even aligned to a lane group, we
      -- definitely need two cycles. Note that this can never happen when stop
      -- bits are disabled, because the alignment code above will always align
      -- nextPC_v to a lane group size or more.
      if unsigned(nextPC_v(groupSizeLog2-1 downto 0)) /= 0 then
        doubleFetch(S_IF) <= '1';
      end if;
      
      -- Handle reconfiguration.
      if (vect2uint(cfg2br_numGroupsLog2) >= 1) and (nextPC_v(groupSizeLog2) = '1') then
        doubleFetch(S_IF) <= '1';
      end if;
      if (vect2uint(cfg2br_numGroupsLog2) >= 2) and (nextPC_v(groupSizeLog2+1) = '1') then
        doubleFetch(S_IF) <= '1';
      end if;
      if (vect2uint(cfg2br_numGroupsLog2) >= 3) and (nextPC_v(groupSizeLog2+2) = '1') then
        doubleFetch(S_IF) <= '1';
      end if;
      
    end if;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Drive trap output
  -----------------------------------------------------------------------------
  trap_output: process (
    nextPCMisaligned, nextPC, stop_r, pl2br_valid
  ) is
    variable ti : trap_info_type;
  begin
    
    -- Cause misaligned branch traps.
    ti := (
      active => nextPCMisaligned(S_IF) and pl2br_valid(S_BR),
      cause  => rvex_trap(RVEX_TRAP_MISALIGNED_BRANCH),
      arg    => nextPC(S_IF)
    );
    
    -- Cause stop traps.
    ti := ti & (
      active => stop_r(S_BR),
      cause  => rvex_trap(RVEX_TRAP_STOP),
      arg    => nextPC(S_IF) -- This is don't care; use the misaligned branch
    );                       -- trap arg to save a mux.
    
    -- Drive the trap output.
    br2pl_trap(S_BR) <= ti;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Register the branching signal in case of a double fetch
  -----------------------------------------------------------------------------
  -- We want to have a branching signal within the pipelane in the first VALID
  -- fetch after a branch, which case branching on its own won't do in the case
  -- of a double fetch. That's what this register is for.
  branching_double_fetch_block: block is
    signal branching_r  : std_logic;
  begin
    branching_double_fetch_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          branching_r <= '0';
        elsif clkEn = '1' and stall = '0' then
          branching_r <= branching(S_BR) and doubleFetch(S_IF);
        end if;
      end if;
    end process;
    
    -- Determine whether the current instruction fetch is due to a branch.
    branch(S_IF) <= branching(S_BR) or branching_r;
    
  end block;
  
  
  -----------------------------------------------------------------------------
  -- Register the trap trace data in case of a double fetch
  -----------------------------------------------------------------------------
  trap_trace_double_fetch_block: block is
    signal traceTrapInfo_r    : trap_info_type;
    signal traceTrapPoint_r   : rvex_address_type;
    signal traceTrapFromReg   : std_logic;
  begin
    trap_trace_double_fetch_reg: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          traceTrapInfo_r <= TRAP_INFO_NONE;
          traceTrapPoint_r <= (others => '0');
          traceTrapFromReg <= '0';
        elsif clkEn = '1' and stall = '0' then
          traceTrapInfo_r <= traceTrapInfo(S_IF);
          traceTrapPoint_r <= traceTrapPoint(S_IF);
          traceTrapFromReg <= doubleFetch(S_IF);
        end if;
      end if;
    end process;
    
    -- Select the right trace signal.
    br2pl_traceTrapInfo(S_IF)
      <= traceTrapInfo_r
      when traceTrapFromReg = '1'
      else traceTrapInfo(S_IF);

    br2pl_traceTrapPoint(S_IF)
      <= traceTrapPoint_r
      when traceTrapFromReg = '1'
      else traceTrapPoint(S_IF);
    
  end block;
  
  
  -----------------------------------------------------------------------------
  -- Determine which operation to perform next
  -----------------------------------------------------------------------------
  -- We're making alignment assumptions in this block if limmhFromPreviousPair
  -- is enable, so fail if these assumptions are incorrect.
  assert not CFG.limmhFromPreviousPair or (CFG.bundleAlignLog2 >= CFG.numLanesLog2)
    report "Bundle alignment is set to less than the issue width (i.e. "
         & "stop bits are enabled) while limmhFromPreviousPair is also "
         & "enabled. These settings are mutually exclusive, because the "
         & "LIMMH from previous logic assumes alignment."
    severity failure;
  
  det_next_op: process (
    nextPC, fetchPC, branching, branch, doubleFetch, noLimmPrefetch,
    cfg2br_numGroupsLog2, run, run_r, pl2br_trapPending, brkptEnable,
    nextPCMisaligned, stop, stop_r, rfiFlush
  ) is
    variable nextPC_v           : rvex_address_array(S_IF to S_IF);
    variable fetchPC_v          : rvex_address_array(S_IF to S_IF);
    variable fetch              : std_logic_vector(S_IF to S_IF);
    variable fetchOnly          : std_logic_vector(S_IF to S_IF);
    variable numCoupledLanesLog2: natural;
    -- pragma translate_off
    variable simAction_v        : rvex_string_builder_type;
    -- pragma translate_on
  begin
    
    -- Load default values into the variables.
    fetchOnly(S_IF) := '0';
    nextPC_v(S_IF)  := nextPC(S_IF);
    fetchPC_v(S_IF) := fetchPC(S_IF);
    
    -- Determine log2(number of coupled lanes).
    numCoupledLanesLog2 :=
      vect2uint(cfg2br_numGroupsLog2)             -- Number of coupled groups.
      + (CFG.numLanesLog2-CFG.numLaneGroupsLog2); -- Number of lanes per group.
    
    -- Handle special cases in the limmhFromPreviousPair logic. These may occur
    -- when (for example):
    --  - Interrupt occurs halfway through a bundle when running in 4x2 mode.
    --  - Reconfigure to 2x4 mode.
    --  - RFI occurs, setting the PC back to the trap point.
    --  - If there were long immediates in the syllable pair immediately
    --    before the trap point, these will not be valid anymore when branching
    --    back like this.
    -- So, in these cases, we need to fetch the previous instruction first.
    if CFG.limmhFromPreviousPair then
      
      -- Check if we need to fetch the previous instruction first due to a
      -- misaligned RFI.
      if noLimmPrefetch(S_BR) = '0' then
      
        -- Fetch the previous instruction first if:
        --  - the next PC is aligned to the current number of lanes operating
        --    (i.e., in 4-way mode, the PC is aligned to 4 syllables), and
        --  - the next PC is NOT aligned to the generic binary bunble size.
        
        -- -- Test alignment to number of coupled lanes.
        -- if vect2uint(nextPC(S_IF)(
        --   numCoupledLanesLog2+SYLLABLE_SIZE_LOG2B-1 downto
        --   (CFG.numLanesLog2-CFG.numLaneGroupsLog2)+SYLLABLE_SIZE_LOG2B
        -- )) = 0 then
        --   
        --   -- Test misalignment to generic bundle size.
        --   if vect2uint(nextPC(S_IF)(
        --     CFG.genBundleSizeLog2+SYLLABLE_SIZE_LOG2B-1 downto
        --     (CFG.numLanesLog2-CFG.numLaneGroupsLog2)+SYLLABLE_SIZE_LOG2B
        --   )) /= 0 then
        --     
        --     fetchOnly(S_IF) := '1';
        --     
        --   end if;
        --   
        -- end if;
        
        -- This code below should do the same thing as the commented code above,
        -- except Vivado should understand it and doesn't understand the above.
        fetchOnly(S_IF) := '0';
        for i in CFG.genBundleSizeLog2+SYLLABLE_SIZE_LOG2B-1 downto
                (CFG.numLanesLog2-CFG.numLaneGroupsLog2)+SYLLABLE_SIZE_LOG2B
        loop
          if i > numCoupledLanesLog2+SYLLABLE_SIZE_LOG2B-1 then
            -- PC must not be aligned to generic bundle size.
            fetchOnly(S_IF) := fetchOnly(S_IF) or nextPC(S_IF)(i);
          else
            -- PC must be aligned to current number of lanes.
            fetchOnly(S_IF) := fetchOnly(S_IF) and not nextPC(S_IF)(i);
          end if;
        end loop;
      
      end if;
    
      -- Subtract 1 from the PC when we need to fetch the previous instruction
      -- first.
      if fetchOnly(S_IF) = '1' then
        
        -- This does not need to be a full subtractor, because we never
        -- subtract beyond addresses aligned by the generic bundle size
        -- (because there will never be relevant long immediate instructions
        -- in the previous generic binary bundle). That WOULD be the case when
        -- stop bits are used/bundle alignment is less than the bundle size,
        -- which is one of the reasons why limmhFromPreviousPair is not allowed
        -- in this case.
        nextPC_v(S_IF)(CFG.genBundleSizeLog2+SYLLABLE_SIZE_LOG2B-1 downto SYLLABLE_SIZE_LOG2B)
          := std_logic_vector(
            vect2unsigned(nextPC(S_IF)(CFG.genBundleSizeLog2+SYLLABLE_SIZE_LOG2B-1 downto SYLLABLE_SIZE_LOG2B))
            - to_unsigned(2**(numCoupledLanesLog2), CFG.genBundleSizeLog2)
          );
        
      end if;
      
      -- The PC which we're going to fetch always equals the actual PC, because
      -- we don't have fancy stop bit support.
      fetchPC_v(S_IF) := nextPC_v(S_IF);
      
    end if;
    
    -- Determine if we want to fetch the next instruction. Care should be taken
    -- to ensure that this signal will only ever go high after being low for at
    -- least a cycle when branching, otherwise the instruction buffer might not
    -- have a valid previous fetch value.
    fetch(S_IF)
      := run(S_BR)
      and (not pl2br_trapPending(S_BR))
      and (not nextPCMisaligned(S_IF))
      and (not stop(S_BR))
      and (not stop_r(S_BR));
    
    -- Disable fetching while we're waiting for CCR bits which control the fetch
    -- to be updated due to an RFI instruction.
    for stage in S_BR to S_MEM loop
      fetch(S_IF) := fetch(S_IF) and not rfiFlush(stage);
    end loop;
    
    -- Drive PC outputs.
    br2cxplif_PC(S_IF)                <= nextPC_v(S_IF);
    br2cxplif_fetchPC(S_IF)           <= fetchPC_v(S_IF);
    
    -- Drive fetch output signals.
    br2cxplif_imemFetch(S_IF)         <= fetch(S_IF);
    br2cxplif_limmValid(S_IF)         <= fetch(S_IF) and not doubleFetch(S_IF);
    
    -- Drive valid output signals.
    br2cxplif_valid(S_IF)             <= fetch(S_IF) and not (fetchOnly(S_IF) or doubleFetch(S_IF));
    brkptEnableSet(S_IF)              <= fetch(S_IF) and not (fetchOnly(S_IF) or doubleFetch(S_IF));
    
    -- Drive breakpoint enable signals.
    br2cxplif_brkValid(S_IF)          <= brkptEnable(S_IF);
    
    -- Drive cancel/invalidate signals.
    br2cxplif_imemCancel(S_IF+L_IF)   <= branching(S_BR); -- FIXME: this is not correct if S_BR = 2!
    br2cxplif_invalUntilBR(S_BR)      <= branching(S_BR);
    
    -- Drive branch signalling signal for the instruction buffer.
    br2cxplif_branch(S_IF)            <= branching(S_BR);
    
    -- Drive branch signalling signals for the pipelane.
    br2pl_isBranch(S_IF)              <= branch(S_IF);
    br2pl_isBranching(S_BR)           <= branching(S_BR);
    
    -- Generate simulation information.
    -- pragma translate_off
    if GEN_VHDL_SIM_INFO then
      rvs_clear(simAction_v);
      if fetch(S_IF) = '0' then
        rvs_append(simAction_v, "did not fetch ");
      elsif fetchOnly(S_IF) = '1' then
        rvs_append(simAction_v, "LIMMH-fetched ");
      else
        rvs_append(simAction_v, "fetched ");
      end if;
      rvs_append(simAction_v, rvs_hex(nextPC_v(S_IF)));
      rvs_append(simAction_v, "; ");
      simAction <= simAction_v;
    end if;
    -- pragma translate_on
    
  end process;
  
  -- Merge debugging information.
  -- pragma translate_off
  sim_info_gen: if GEN_VHDL_SIM_INFO generate
    br2pl_sim(S_IF) <= simAction & simReason;
    br2pl_simActive(S_IF) <= pl2br_stopBit(S_BR);
  end generate;
  -- pragma translate_on
  
end Behavioral;

