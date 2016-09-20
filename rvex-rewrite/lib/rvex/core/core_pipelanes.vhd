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

-- pragma translate_off
use rvex.simUtils_pkg.all;
-- pragma translate_on

--=============================================================================
-- This entity contains all pipeline logic for the entire processor. Everything
-- but the register files and configuration control logic is instantiated in
-- here.
-------------------------------------------------------------------------------
entity core_pipelanes is
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
    
    ---------------------------------------------------------------------------
    -- VHDL simulation debug information
    ---------------------------------------------------------------------------
    -- pragma translate_off
    
    -- String with commit information, exact PC, disassembly and trap info for
    -- the last instruction in the pipeline.
    pl2sim_instr                : out rvex_string_builder_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- String with register write and data memory access information for the
    -- last instruction in the pipeline.
    pl2sim_op                   : out rvex_string_builder_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- String with branch information for the last instruction, if the branch
    -- unit is active.
    br2sim                      : out rvex_string_builder_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- High when the indexed branch unit is the active branch unit.
    br2sim_active               : out std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- pragma translate_on
    
    -----------------------------------------------------------------------------
    -- Decoded configuration signals
    -----------------------------------------------------------------------------
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
    -- context, or low when they don't.
    cfg2any_coupled             : in  std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Decouple vector. This is just another way to look at the coupled matrix.
    -- The vector is assigned such that dec_i = not C_i,i+1. The MSB in the
    -- vector is always high. This representation is useful because the bits
    -- can also be regarded as master/slave bits: when the decouple bit for
    -- a group is high, it is a master, otherwise it is a slave. Slaves answer
    -- to the next higher indexed master group.
    cfg2any_decouple            : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
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
    
    -- The amount which the branch unit residing in the indexed lane should
    -- add to the current PC to get PC_plusOne, should it be the active branch
    -- unit.
    cfg2any_pcAddVal            : in  rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Configuration and run control
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
    
    -- Instruction bundle(s) from the instruction memory.
    ibuf2pl_instr               : in  rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Exception input from instruction memory.
    ibuf2pl_exception           : in  trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Data memory interface
    ---------------------------------------------------------------------------
    -- Data memory address, shared between read and write command.
    dmsw2dmem_addr              : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Data memory write command.
    dmsw2dmem_writeData         : out rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    dmsw2dmem_writeMask         : out rvex_mask_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    dmsw2dmem_writeEnable       : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Data memory read command and result.
    dmsw2dmem_readEnable        : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    dmem2dmsw_readData          : in  rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Exception input from data memory.
    dmem2dmsw_exception         : in  trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Common memory interface
    ---------------------------------------------------------------------------
    -- Cache performance information from the cache. The instruction cache
    -- related signals are part of the S_IF+L_IF stage, the data cache related
    -- signals are part of the S_MEM+L_MEM stage.
    mem2pl_cacheStatus          : in  rvex_cacheStatus_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Control register interface
    ---------------------------------------------------------------------------
    -- Control register address, shared between read and write command.
    dmsw2creg_addr              : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Control register write command.
    dmsw2creg_writeData         : out rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    dmsw2creg_writeMask         : out rvex_mask_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    dmsw2creg_writeEnable       : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Control register read command and result.
    dmsw2creg_readEnable        : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    creg2dmsw_readData          : in  rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Register file interface
    ---------------------------------------------------------------------------
    -- The general purpose register file signals are documented in
    -- core_intIface_pkg.vhd, where the types are defined.
    
    -- General purpose register file read ports.
    pl2gpreg_readPorts          : out pl2gpreg_readPort_array(2*2**CFG.numLanesLog2-1 downto 0);
    gpreg2pl_readPorts          : in  gpreg2pl_readPort_array(2*2**CFG.numLanesLog2-1 downto 0);
    
    -- General purpose register file write ports.
    pl2gpreg_writePorts         : out pl2gpreg_writePort_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Branch register interface (without forwarding) for each context.
    cxplif2cxreg_brWriteData    : out rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_brWriteEnable  : out rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_brReadData     : in  rvex_brRegData_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- Link register interface (without forwarding) for each context.
    cxplif2cxreg_linkWriteData  : out rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_linkWriteEnable: out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_linkReadData   : in  rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Special context register interface
    ---------------------------------------------------------------------------
    -- Refer to the documentation in the entity of rvex_contextPipelaneIFace or
    -- rvex_contextRegLogic for information about the signals.
    cxplif2cxreg_stall          : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_idle           : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_sylCommit      : out rvex_sylStatus_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_sylNop         : out rvex_sylStatus_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_stop           : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_nextPC         : out rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_currentPC      : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_overridePC     : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_overridePC_ack : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_trapHandler    : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_trapInfo       : out trap_info_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_trapPoint      : out rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_trapReturn     : in  rvex_address_array(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_rfi            : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_handlingDebugTrap:in std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_interruptEnable: in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_debugTrapEnable: in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_breakpoints    : in  cxreg2pl_breakpoint_info_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_softCtxtSwitch : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_extDebug       : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_exDbgTrapInfo  : out trap_info_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_brk            : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_stepping       : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cxplif_resuming       : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    cxplif2cxreg_resuming_ack   : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Raw trace data
    ---------------------------------------------------------------------------
    -- Trace data from pipelane to trace control unit.
    pl2trace_data               : out pl2trace_data_array(2**CFG.numLanesLog2-1 downto 0)
    
  );
end core_pipelanes;

--=============================================================================
architecture Behavioral of core_pipelanes is
--=============================================================================
  
  -- Context to pipelane interface <-> pipelane interconnect signals.
  signal pl2cxplif_blockReconfig    : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_irq              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_irqID            : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_irqAck           : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_run              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2cxplif_idle             : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_PC               : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_PC               : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_fetchPC          : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_branch           : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_limmValid        : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_limmValid        : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_valid            : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_valid            : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_brkValid         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_brkValid         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_invalUntilBR     : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_invalUntilBR     : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_imemFetch        : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_imemCancel       : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_brLinkReadPort   : cxreg2pl_readPort_array(2**CFG.numLanesLog2-1 downto 0);
  signal pl2cxplif_brLinkWritePort  : pl2cxreg_writePort_array(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_contextPC        : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_overridePC       : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_trapHandler      : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_trapInfo         : trap_info_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_trapPoint        : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_exDbgTrapInfo    : trap_info_array(2**CFG.numLanesLog2-1 downto 0);
  signal br2cxplif_stop             : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_trapReturn       : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal pl2cxplif_rfi              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_extDebug         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2br_handlingDebugTrap: std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_debugTrapEnable  : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2brku_breakpoints    : cxreg2pl_breakpoint_info_array(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2pl_softCtxtSwitch   : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal cxplif2brku_stepping       : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2cxplif2_sylCommit       : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2cxplif2_sylNop          : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  
  -- Data memory switch <-> pipelane interconnect signals.
  signal memu2dmsw_addr             : rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal memu2dmsw_writeData        : rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal memu2dmsw_writeMask        : rvex_mask_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal memu2dmsw_writeEnable      : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal memu2dmsw_readEnable       : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmsw2memu_readData         : rvex_data_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal dmsw2pl_exception          : trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Stop bit/branch operation routing <-> pipelane interconnect signals.
  signal pl2sbit_stop               : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2sbit_valid              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2sbit_syllable           : rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
  signal pl2sbit_PC_ind             : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal pl2sbit_PC_fetchInd        : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal sbit2pl_stop               : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal sbit2pl_invalidate         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal sbit2pl_valid              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal sbit2pl_syllable           : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal sbit2pl_PC_ind             : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  signal sbit2pl_PC_fetchInd        : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- Long immediate routing <-> pipelane interconnect signals.
  signal pl2limm_valid              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2limm_enable             : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2limm_target             : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal pl2limm_data               : rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
  signal limm2pl_enable             : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal limm2pl_data               : rvex_limmh_array(2**CFG.numLanesLog2-1 downto 0);
  signal limm2pl_error              : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  
  -- Trap routing <-> pipelane interconnect signals.
  signal pl2trap_trap               : trap_info_stages_array(2**CFG.numLanesLog2-1 downto 0);
  signal trap2pl_trapToHandle       : trap_info_array(2**CFG.numLanesLog2-1 downto 0);
  signal trap2pl_trapPending        : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  signal trap2pl_disable            : std_logic_stages_array(2**CFG.numLanesLog2-1 downto 0);
  signal trap2pl_flush              : std_logic_stages_array(2**CFG.numLanesLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Check configuration
  -----------------------------------------------------------------------------
  assert CFG.numLaneGroupsLog2 <= CFG.numLanesLog2
    report "Cannot have more lane groups than there are lanes."
    severity failure;
  
  assert CFG.genBundleSizeLog2 >= (CFG.numLanesLog2 - CFG.numLaneGroupsLog2)
    report "Cannot support generic binary bundle size smaller than the "
         & "number of lanes in a group."
    severity failure;
  
  assert CFG.memLaneRevIndex < 2**(CFG.numLanesLog2 - CFG.numLaneGroupsLog2)
    report "Memory lane index out of group range."
    severity failure;
  
  -----------------------------------------------------------------------------
  -- Instantiate the pipelanes
  -----------------------------------------------------------------------------
  pl_gen: for lane in 2**CFG.numLanesLog2-1 downto 0 generate
    
    -- Lane group which lane belongs to.
    constant laneGroup: natural := lane2group(lane, CFG);
    
    -- Lane index within the group for lane.
    constant laneIndex: natural := lane2indexInGroup(lane, CFG);
    
    -- Lane index counting down from the last lane in the group, such that 0 is
    -- the last lane in the group, 1 is the second to last lane, etc.
    constant laneIndexRev: natural := lane2indexInGroupRev(lane, CFG);
    
    -- Whether lane should have a multiplier.
    constant mul: boolean := testBit(CFG.multiplierLanes, lane);
    
    -- Whether lane should have a memory unit.
    constant mem: boolean := laneIndexRev = CFG.memLaneRevIndex;
    
    -- Whether lane should have a breakpoint unit. We instantiate a breakpoint
    -- unit for each lane which has a memory unit, which is the minimum needed
    -- to support data memory breakpoints for each runtime configuration.
    constant brk: boolean := mem;
    
    -- The last lane in each lane group needs a branch unit.
    constant br: boolean := laneIndexRev = 0;
      
    -- The lane before each possible bundle border needs to support stop bits.
    -- In addition, the last lane in every group needs this is well when
    -- finer-grained configurations are used.
    constant stop: boolean := br or ((lane+1) mod 2**CFG.bundleAlignLog2) = 0;
    
  begin
    
    pl_inst: entity rvex.core_pipelane
      generic map (
        
        -- Global configuration.
        CFG                               => CFG,
        
        -- Lane configuration.
        LANE_INDEX                        => lane,
        HAS_MUL                           => mul,
        HAS_MEM                           => mem,
        HAS_BRK                           => brk,
        HAS_BR                            => br,
        HAS_STOP                          => stop
        
      )
      port map (
        
        -- System control.
        reset                             => reset,
        clk                               => clk,
        clkEn                             => clkEn,
        stall                             => stall(laneGroup),
        
        -- VHDL simulation debug information.
        -- pragma translate_off
        pl2sim_instr                      => pl2sim_instr(lane),
        pl2sim_op                         => pl2sim_op(lane),
        br2sim                            => br2sim(lane),
        br2sim_active                     => br2sim_active(lane),
        -- pragma translate_on
        
        -- Configuration and run control.
        cfg2pl_decouple                   => cfg2any_decouple(laneGroup),
        cfg2pl_numGroupsLog2              => cfg2any_numGroupsLog2(laneGroup),
        cfg2pl_laneIndex                  => cfg2any_laneIndex(lane),
        cfg2pl_pcAddVal                   => cfg2any_pcAddVal(lane),
        pl2cxplif_blockReconfig           => pl2cxplif_blockReconfig(lane),
        cxplif2pl_irq(S_MEM)              => cxplif2pl_irq(lane),
        cxplif2br_irqID(S_BR)             => cxplif2br_irqID(lane),
        br2cxplif_irqAck(S_BR)            => br2cxplif_irqAck(lane),
        cxplif2br_run                     => cxplif2br_run(lane),
        pl2cxplif_idle                    => pl2cxplif_idle(lane),
        
        -- Next operation routing interface.
        br2cxplif_PC(S_IF)                => br2cxplif_PC(lane),
        cxplif2pl_PC(S_IF)                => cxplif2pl_PC(lane),
        br2cxplif_fetchPC(S_IF)           => br2cxplif_fetchPC(lane),
        br2cxplif_branch(S_IF)            => br2cxplif_branch(lane),
        br2cxplif_limmValid(S_IF)         => br2cxplif_limmValid(lane),
        cxplif2pl_limmValid(S_IF)         => cxplif2pl_limmValid(lane),
        br2cxplif_valid(S_IF)             => br2cxplif_valid(lane),
        cxplif2pl_valid(S_IF)             => cxplif2pl_valid(lane),
        br2cxplif_brkValid(S_IF)          => br2cxplif_brkValid(lane),
        cxplif2pl_brkValid(S_IF)          => cxplif2pl_brkValid(lane),
        br2cxplif_invalUntilBR(S_BR)      => br2cxplif_invalUntilBR(lane),
        cxplif2pl_invalUntilBR(S_BR)      => cxplif2pl_invalUntilBR(lane),
        
        -- Instruction memory interface.
        br2cxplif_imemFetch(S_IF)         => br2cxplif_imemFetch(lane),
        br2cxplif_imemCancel(S_IF+L_IF)   => br2cxplif_imemCancel(lane),
        ibuf2pl_syllable(S_IF+L_IF)       => ibuf2pl_instr(lane),
        ibuf2pl_exception(S_IF+L_IF)      => ibuf2pl_exception(laneGroup),
        
        -- Data memory interface.
        memu2dmsw_addr(S_MEM)             => memu2dmsw_addr(laneGroup),
        memu2dmsw_writeData(S_MEM)        => memu2dmsw_writeData(laneGroup),
        memu2dmsw_writeMask(S_MEM)        => memu2dmsw_writeMask(laneGroup),
        memu2dmsw_writeEnable(S_MEM)      => memu2dmsw_writeEnable(laneGroup),
        memu2dmsw_readEnable(S_MEM)       => memu2dmsw_readEnable(laneGroup),
        dmsw2memu_readData(S_MEM+L_MEM)   => dmsw2memu_readData(laneGroup),
        dmsw2pl_exception(S_MEM+L_MEM)    => dmsw2pl_exception(laneGroup),
        
        -- Common memory interface.
        mem2pl_cacheStatus                => mem2pl_cacheStatus(laneGroup),
        
        -- Register file interface.
        pl2gpreg_readPortA                => pl2gpreg_readPorts(lane*2+0),
        gpreg2pl_readPortA                => gpreg2pl_readPorts(lane*2+0),
        pl2gpreg_readPortB                => pl2gpreg_readPorts(lane*2+1),
        gpreg2pl_readPortB                => gpreg2pl_readPorts(lane*2+1),
        pl2gpreg_writePort                => pl2gpreg_writePorts(lane),
        cxplif2pl_brLinkReadPort          => cxplif2pl_brLinkReadPort(lane),
        pl2cxplif_brLinkWritePort         => pl2cxplif_brLinkWritePort(lane),
        
        -- Special register interface.
        cxplif2br_contextPC(S_IF+1)       => cxplif2br_contextPC(lane),
        cxplif2br_overridePC(S_IF+1)      => cxplif2br_overridePC(lane),
        cxplif2pl_trapHandler(S_MEM)      => cxplif2pl_trapHandler(lane),
        br2cxplif_trapInfo(S_BR)          => br2cxplif_trapInfo(lane),
        br2cxplif_trapPoint(S_BR)         => br2cxplif_trapPoint(lane),
        br2cxplif_exDbgTrapInfo(S_BR)     => br2cxplif_exDbgTrapInfo(lane),
        br2cxplif_stop(S_BR)              => br2cxplif_stop(lane),
        cxplif2br_trapReturn(S_BR)        => cxplif2br_trapReturn(lane),
        pl2cxplif_rfi(S_MEM)              => pl2cxplif_rfi(lane),
        cxplif2br_extDebug(S_BR)          => cxplif2br_extDebug(lane),
        cxplif2br_handlingDebugTrap(S_BR) => cxplif2br_handlingDebugTrap(lane),
        cxplif2pl_debugTrapEnable(S_MEM)  => cxplif2pl_debugTrapEnable(lane),
        cxplif2brku_breakpoints(S_BRK)    => cxplif2brku_breakpoints(lane),
        cxplif2pl_softCtxtSwitch(S_MEM)   => cxplif2pl_softCtxtSwitch(lane),
        cxplif2brku_stepping(S_BRK)       => cxplif2brku_stepping(lane),
        
        -- Performance counter status signals.
        pl2cxplif2_sylCommit(S_LAST)      => pl2cxplif2_sylCommit(lane),
        pl2cxplif2_sylNop(S_LAST)         => pl2cxplif2_sylNop(lane),
      
        -- Stop bit/PC+1 routing interface
        pl2sbit_stop(S_STOP)              => pl2sbit_stop(lane),
        pl2sbit_valid(S_STOP)             => pl2sbit_valid(lane),
        pl2sbit_syllable(S_STOP)          => pl2sbit_syllable(lane),
        pl2sbit_PC_ind(S_STOP)            => pl2sbit_PC_ind(lane),
        pl2sbit_PC_fetchInd(S_STOP)       => pl2sbit_PC_fetchInd(lane),
        sbit2pl_stop(S_STOP)              => sbit2pl_stop(lane),
        sbit2pl_invalidate(S_STOP)        => sbit2pl_invalidate(lane),
        sbit2pl_valid(S_STOP)             => sbit2pl_valid(lane),
        sbit2pl_syllable(S_STOP)          => sbit2pl_syllable(lane),
        sbit2pl_PC_ind(S_STOP)            => sbit2pl_PC_ind(lane),
        sbit2pl_PC_fetchInd(S_STOP)       => sbit2pl_PC_fetchInd(lane),
        
        -- Long immediate routing interface.
        pl2limm_valid(S_LIMM)             => pl2limm_valid(lane),
        pl2limm_enable(S_LIMM)            => pl2limm_enable(lane),
        pl2limm_target(S_LIMM)            => pl2limm_target(lane),
        pl2limm_data(S_LIMM)              => pl2limm_data(lane),
        limm2pl_enable(S_LIMM)            => limm2pl_enable(lane),
        limm2pl_data(S_LIMM)              => limm2pl_data(lane),
        limm2pl_error(S_LIMM)             => limm2pl_error(lane),
        
        -- Trap routing interface.
        pl2trap_trap                      => pl2trap_trap(lane),
        trap2pl_trapToHandle(S_TRAP)      => trap2pl_trapToHandle(lane),
        trap2pl_trapPending(S_TRAP)       => trap2pl_trapPending(lane),
        trap2pl_disable                   => trap2pl_disable(lane),
        trap2pl_flush                     => trap2pl_flush(lane),
        
        -- Trace unit interface.
        pl2trace_data                     => pl2trace_data(lane)
        
      );
    
  end generate; -- for each lane
  
  -----------------------------------------------------------------------------
  -- Instantiate context to pipelane interface
  -----------------------------------------------------------------------------
  cxplif_inst: entity rvex.core_contextPipelaneIFace
    generic map (
      CFG                               => CFG
    )
    port map (
      
      -- System control.
      reset                             => reset,
      clk                               => clk,
      clkEn                             => clkEn,
      stall                             => stall,
      
      -- Decoded configuration signals.
      cfg2any_coupled                   => cfg2any_coupled,
      cfg2any_numGroupsLog2             => cfg2any_numGroupsLog2,
      cfg2any_context                   => cfg2any_context,
      cfg2any_active                    => cfg2any_active,
      cfg2any_lastGroupForCtxt          => cfg2any_lastGroupForCtxt,
      cfg2any_laneIndex                 => cfg2any_laneIndex,
      
      -- Pipelane interface: configuration and run control.
      pl2cxplif_blockReconfig           => pl2cxplif_blockReconfig,
      cxplif2pl_irq                     => cxplif2pl_irq,
      cxplif2br_irqID                   => cxplif2br_irqID,
      br2cxplif_irqAck                  => br2cxplif_irqAck,
      cxplif2br_run                     => cxplif2br_run,
      pl2cxplif_idle                    => pl2cxplif_idle,
      
      -- Pipelane interface: next operation routing.
      br2cxplif_PC                      => br2cxplif_PC,
      cxplif2pl_PC                      => cxplif2pl_PC,
      br2cxplif_fetchPC                 => br2cxplif_fetchPC,
      br2cxplif_branch                  => br2cxplif_branch,
      br2cxplif_limmValid               => br2cxplif_limmValid,
      cxplif2pl_limmValid               => cxplif2pl_limmValid,
      br2cxplif_valid                   => br2cxplif_valid,
      cxplif2pl_valid                   => cxplif2pl_valid,
      br2cxplif_brkValid                => br2cxplif_brkValid,
      cxplif2pl_brkValid                => cxplif2pl_brkValid,
      br2cxplif_invalUntilBR            => br2cxplif_invalUntilBR,
      cxplif2pl_invalUntilBR            => cxplif2pl_invalUntilBR,
      
      -- Pipelane interface: instruction memory command routing.
      br2cxplif_imemFetch               => br2cxplif_imemFetch,
      br2cxplif_imemCancel              => br2cxplif_imemCancel,
      
      -- Pipelane interface: branch/link registers.
      cxplif2pl_brLinkReadPort          => cxplif2pl_brLinkReadPort,
      pl2cxplif_brLinkWritePort         => pl2cxplif_brLinkWritePort,
      
      -- Pipelane interface: special registers.
      cxplif2br_contextPC               => cxplif2br_contextPC,
      cxplif2br_overridePC              => cxplif2br_overridePC,
      cxplif2pl_trapHandler             => cxplif2pl_trapHandler,
      br2cxplif_trapInfo                => br2cxplif_trapInfo,
      br2cxplif_trapPoint               => br2cxplif_trapPoint,
      br2cxplif_exDbgTrapInfo           => br2cxplif_exDbgTrapInfo,
      br2cxplif_stop                    => br2cxplif_stop,
      cxplif2br_trapReturn              => cxplif2br_trapReturn,
      pl2cxplif_rfi                     => pl2cxplif_rfi,
      cxplif2br_extDebug                => cxplif2br_extDebug,
      cxplif2br_handlingDebugTrap       => cxplif2br_handlingDebugTrap,
      cxplif2pl_debugTrapEnable         => cxplif2pl_debugTrapEnable,
      cxplif2brku_breakpoints           => cxplif2brku_breakpoints,
      cxplif2pl_softCtxtSwitch          => cxplif2pl_softCtxtSwitch,
      cxplif2brku_stepping              => cxplif2brku_stepping,
      
      -- Pipelane interface: performance counter status signals.
      pl2cxplif2_sylCommit              => pl2cxplif2_sylCommit,
      pl2cxplif2_sylNop                 => pl2cxplif2_sylNop,
      
      -- Run control interface.
      rctrl2cxplif_irq                  => rctrl2cxplif_irq,
      rctrl2cxplif_irqID                => rctrl2cxplif_irqID,
      cxplif2rctrl_irqAck               => cxplif2rctrl_irqAck,
      rctrl2cxplif_run                  => rctrl2cxplif_run,
      cxplif2rctrl_idle                 => cxplif2rctrl_idle,
      
      -- Instruction memory interface.
      cxplif2ibuf_PCs                   => cxplif2ibuf_PCs,
      cxplif2ibuf_fetchPCs              => cxplif2ibuf_fetchPCs,
      cxplif2ibuf_branch                => cxplif2ibuf_branch,
      cxplif2ibuf_fetch                 => cxplif2ibuf_fetch,
      cxplif2ibuf_cancel                => cxplif2ibuf_cancel,
      
      -- Configuration control interface.
      cfg2cxplif_active                 => cfg2cxplif_active,
      cfg2cxplif_requestReconfig        => cfg2cxplif_requestReconfig,
      cxplif2cfg_blockReconfig          => cxplif2cfg_blockReconfig,
      
      -- Context register interface: misc.
      cxplif2cxreg_stall                => cxplif2cxreg_stall,
      cxplif2cxreg_idle                 => cxplif2cxreg_idle,
      cxplif2cxreg_sylCommit            => cxplif2cxreg_sylCommit,
      cxplif2cxreg_sylNop               => cxplif2cxreg_sylNop,
      cxplif2cxreg_stop                 => cxplif2cxreg_stop,
      
      -- Context register interface: branch/link registers.
      cxplif2cxreg_brWriteData          => cxplif2cxreg_brWriteData,
      cxplif2cxreg_brWriteEnable        => cxplif2cxreg_brWriteEnable,
      cxreg2cxplif_brReadData           => cxreg2cxplif_brReadData,
      cxplif2cxreg_linkWriteData        => cxplif2cxreg_linkWriteData,
      cxplif2cxreg_linkWriteEnable      => cxplif2cxreg_linkWriteEnable,
      cxreg2cxplif_linkReadData         => cxreg2cxplif_linkReadData,
      
      -- Context register interface: program counter.
      cxplif2cxreg_nextPC               => cxplif2cxreg_nextPC,
      cxreg2cxplif_currentPC            => cxreg2cxplif_currentPC,
      cxreg2cxplif_overridePC           => cxreg2cxplif_overridePC,
      cxplif2cxreg_overridePC_ack       => cxplif2cxreg_overridePC_ack,

      -- Context register interface: trap handling.
      cxreg2cxplif_trapHandler          => cxreg2cxplif_trapHandler,
      cxplif2cxreg_trapInfo             => cxplif2cxreg_trapInfo,
      cxplif2cxreg_trapPoint            => cxplif2cxreg_trapPoint,
      cxreg2cxplif_trapReturn           => cxreg2cxplif_trapReturn,
      cxplif2cxreg_rfi                  => cxplif2cxreg_rfi,
      cxreg2cxplif_handlingDebugTrap    => cxreg2cxplif_handlingDebugTrap,
      cxreg2cxplif_interruptEnable      => cxreg2cxplif_interruptEnable,
      cxreg2cxplif_debugTrapEnable      => cxreg2cxplif_debugTrapEnable,
      cxreg2cxplif_breakpoints          => cxreg2cxplif_breakpoints,
      cxreg2cxplif_softCtxtSwitch       => cxreg2cxplif_softCtxtSwitch,

      -- Context register interface: external debug control signals.
      cxreg2cxplif_extDebug             => cxreg2cxplif_extDebug,
      cxplif2cxreg_exDbgTrapInfo        => cxplif2cxreg_exDbgTrapInfo,
      cxreg2cxplif_brk                  => cxreg2cxplif_brk,
      cxreg2cxplif_stepping             => cxreg2cxplif_stepping,
      cxreg2cxplif_resuming             => cxreg2cxplif_resuming,
      cxplif2cxreg_resuming_ack         => cxplif2cxreg_resuming_ack
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate data memory/control register switches
  -----------------------------------------------------------------------------
  dmsw_gen: for laneGroup in 2**CFG.numLaneGroupsLog2-1 downto 0 generate
    
    dmsw_inst: entity rvex.core_dmemSwitch
      generic map (
        CFG                             => CFG
      )
      port map (
        
        -- System control.
        reset                           => reset,
        clk                             => clk,
        clkEn                           => clkEn,
        stall                           => stall(laneGroup),
        
        -- Pipelane interface.
        memu2dmsw_addr(S_MEM)           => memu2dmsw_addr(laneGroup),
        memu2dmsw_writeData(S_MEM)      => memu2dmsw_writeData(laneGroup),
        memu2dmsw_writeMask(S_MEM)      => memu2dmsw_writeMask(laneGroup),
        memu2dmsw_writeEnable(S_MEM)    => memu2dmsw_writeEnable(laneGroup),
        memu2dmsw_readEnable(S_MEM)     => memu2dmsw_readEnable(laneGroup),
        dmsw2memu_readData(S_MEM+L_MEM) => dmsw2memu_readData(laneGroup),
        dmsw2pl_exception(S_MEM+L_MEM)  => dmsw2pl_exception(laneGroup),
        
        -- Data memory interface.
        dmsw2dmem_addr(S_MEM)           => dmsw2dmem_addr(laneGroup),
        dmsw2dmem_writeData(S_MEM)      => dmsw2dmem_writeData(laneGroup),
        dmsw2dmem_writeMask(S_MEM)      => dmsw2dmem_writeMask(laneGroup),
        dmsw2dmem_writeEnable(S_MEM)    => dmsw2dmem_writeEnable(laneGroup),
        dmsw2dmem_readEnable(S_MEM)     => dmsw2dmem_readEnable(laneGroup),
        dmem2dmsw_readData(S_MEM+L_MEM) => dmem2dmsw_readData(laneGroup),
        dmem2dmsw_exception(S_MEM+L_MEM)=> dmem2dmsw_exception(laneGroup),
        
        -- Control register interface
        dmsw2creg_addr(S_MEM)           => dmsw2creg_addr(laneGroup),
        dmsw2creg_writeData(S_MEM)      => dmsw2creg_writeData(laneGroup),
        dmsw2creg_writeMask(S_MEM)      => dmsw2creg_writeMask(laneGroup),
        dmsw2creg_writeEnable(S_MEM)    => dmsw2creg_writeEnable(laneGroup),
        dmsw2creg_readEnable(S_MEM)     => dmsw2creg_readEnable(laneGroup),
        creg2dmsw_readData(S_MEM+1)     => creg2dmsw_readData(laneGroup)
        
      );
    
  end generate; -- for each lane group
  
  -----------------------------------------------------------------------------
  -- Instantiate stop bit and branch operation routing
  -----------------------------------------------------------------------------
  sbit_inst: entity rvex.core_stopBitRouting
    generic map (
      CFG                       => CFG
    )
    port map (
      
      -- Decoded configuration signals.
      cfg2any_coupled           => cfg2any_coupled,
      
      -- Pipelane interface.
      pl2sbit_stop              => pl2sbit_stop,
      pl2sbit_valid             => pl2sbit_valid,
      pl2sbit_syllable          => pl2sbit_syllable,
      pl2sbit_PC_ind            => pl2sbit_PC_ind,
      pl2sbit_PC_fetchInd       => pl2sbit_PC_fetchInd,
      sbit2pl_stop              => sbit2pl_stop,
      sbit2pl_invalidate        => sbit2pl_invalidate,
      sbit2pl_valid             => sbit2pl_valid,
      sbit2pl_syllable          => sbit2pl_syllable,
      sbit2pl_PC_ind            => sbit2pl_PC_ind,
      sbit2pl_PC_fetchInd       => sbit2pl_PC_fetchInd
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate LIMM routing network
  -----------------------------------------------------------------------------
  limm_inst: entity rvex.core_limmRouting
    generic map (
      CFG                       => CFG
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      stall                     => stall,
      
      -- Decoded configuration signals.
      cfg2any_coupled           => cfg2any_coupled,
      
      -- Pipelane interface.
      pl2limm_valid             => pl2limm_valid,
      pl2limm_enable            => pl2limm_enable,
      pl2limm_target            => pl2limm_target,
      pl2limm_data              => pl2limm_data,
      limm2pl_enable            => limm2pl_enable,
      limm2pl_data              => limm2pl_data,
      limm2pl_error             => limm2pl_error
      
    );
  
  -----------------------------------------------------------------------------
  -- Instantiate trap routing network
  -----------------------------------------------------------------------------
  trap_routing: if CFG.traps > 0 generate
    trap_inst: entity rvex.core_trapRouting
      generic map (
        CFG                       => CFG
      )
      port map (
        
        -- Decoded configuration signals.
        cfg2any_coupled           => cfg2any_coupled,
        
        -- Pipelane interface.
        pl2trap_trap              => pl2trap_trap,
        trap2pl_trapToHandle      => trap2pl_trapToHandle,
        trap2pl_trapPending       => trap2pl_trapPending,
        trap2pl_disable           => trap2pl_disable,
        trap2pl_flush             => trap2pl_flush
        
      );
  end generate;
  
  -- We don't need the trap routing entity when traps are disabled.
  no_trap_routing: if CFG.traps = 0 generate
    trap2pl_trapToHandle <= (others => TRAP_INFO_NONE);
    trap2pl_trapPending  <= (others => '0');
    trap2pl_disable      <= (others => (others => '0'));
    trap2pl_flush        <= (others => (others => '0'));
  end generate;
  
end Behavioral;
