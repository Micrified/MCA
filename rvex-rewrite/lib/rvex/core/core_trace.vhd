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

--=============================================================================
-- This entity contains the optional trace control unit. This unit will
-- compress trace information selected in the context control registers into a
-- bytestream and will ensure that the core is stalled while the trace data is
-- being outputted.
-------------------------------------------------------------------------------
entity core_trace is
--=============================================================================
  generic (
    
    -- Configuration.
    CFG                         : rvex_generic_config_type := rvex_cfg
    
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
    
    -- Combined stall input.
    stallIn                     : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Stall output. When high, the entire core should stall.
    stallOut                    : out std_logic;
    
    -----------------------------------------------------------------------------
    -- Decoded configuration signals
    -----------------------------------------------------------------------------
    -- Current encoded configuration word.
    cfg2any_configWord          : in  rvex_data_type;
    
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
    -- context, or low when they don't.
    cfg2any_coupled             : in  std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies the context associated with the indexed pipelane group.
    cfg2any_context             : in  rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies whether the indexed pipeline group is active.
    cfg2any_active              : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Trace control
    ---------------------------------------------------------------------------
    -- Whether tracing should be enabled or not for each context. Active high.
    cxreg2trace_enable          : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Whether trap information should be traced. Active high.
    cxreg2trace_trapEn          : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Whether memory operations should be traced. Active high.
    cxreg2trace_memEn           : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Whether register writes should be traced. Active high.
    cxreg2trace_regEn           : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Whether cache performance information should be traced. Active high.
    cxreg2trace_cacheEn         : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Whether instructions (the raw syllables) should be traced. Active high.
    cxreg2trace_instrEn         : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Trace raw data input
    ---------------------------------------------------------------------------
    -- Inputs from the pipelanes.
    pl2trace_data               : in  pl2trace_data_array(2**CFG.numLanesLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Trace output
    ---------------------------------------------------------------------------
    -- When high, data is valid and should be registered.
    trace2trsink_push           : out std_logic;
    
    -- Trace data signal. Valid when push is high.
    trace2trsink_data           : out rvex_byte_type;
    
    -- When high, this is the last byte of this trace packet. This has the same
    -- timing as the data signal. FIXME: this signal doesn't work correctly
    -- right now; if things are being traced for the last pipelane the last
    -- byte pushed will not have this signal asserted.
    trace2trsink_end            : out std_logic;
    
    -- When high while push is high, the trace unit is stalled. While stalled,
    -- push will stay high and data and end will remain stable.
    trsink2trace_busy           : in  std_logic
    
  );
end core_trace;

--=============================================================================
architecture Behavioral of core_trace is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Trace packet data format
  -----------------------------------------------------------------------------
  -- The mess below specifies the organization of a trace packet. Each constant
  -- represents a byte; the condition and contents of the byte are specified
  -- below each. The bytes are transmitted in order, but a byte is only
  -- transmitted when its conditions are met. This is done to compress the data
  -- stream as much as possible.
  --
  -- The only byte which is always sent is the FLAGS byte. A packet with FLAGS
  -- set to zero (which will only be one byte long) should be interpreted as
  -- a cycle end marker. However, a sequence of multiple null packets has no
  -- other meaning than a single null packet, allowing packets to be
  -- zero-padded when necessary for, for instance, alignment reasons.
  --
  -- Note that a trace data stream generated by a newer version which has
  -- additional fields will NOT be readable by older versions of interpreting
  -- systems. In addition, if the contents of existing fields are changed, it
  -- won't be forward-compatible either. This is deemed an acceptable side 
  -- effect of compressing the trace data stream as much as possible.
  --
  -- *** Header ***
  -- 
  constant I_FLAGS              : natural := 0;
  -- Always.
  --  - Bit 7: PC field valid
  --  - Bit 6: Memory operation fields valid
  --  - Bit 5: Register write fields valid
  --  - Bit 4..1: Lane index
  --  - Bit 0: EXFLAGS valid
  --
  -- *** PC update fields ***
  -- 
  constant I_PC0                : natural := I_FLAGS + 1;
  -- Only if FLAGS(7) = 1.
  --  - Bit 7..2: PC(7..2)
  --  - Bit 1..0: update mode; 0=only PC0, 1=PC0..1, 2=PC0..3 (normal), 3=PC0..3 (branch)
  --
  constant I_PC1                : natural := I_PC0 + 1;
  -- Only if FLAGS(7) = 1 and PC0(1..0) >= 1.
  constant I_PC2                : natural := I_PC1 + 1;
  constant I_PC3                : natural := I_PC2 + 1;
  -- Only if FLAGS(7) = 1 and PC0(1..0) >= 2.
  --  - Bit 7..0: PC
  --
  -- *** Memory operation fields ***
  --
  constant I_MEMFLAGS           : natural := I_PC3 + 1;
  -- Only if FLAGS(6) = 1.
  --  - Bit 3..0: write mask + validity
  -- 
  constant I_MEMADDR0           : natural := I_MEMFLAGS + 1;
  constant I_MEMADDR1           : natural := I_MEMADDR0 + 1;
  constant I_MEMADDR2           : natural := I_MEMADDR1 + 1;
  constant I_MEMADDR3           : natural := I_MEMADDR2 + 1;
  -- Only if FLAGS(6) = 1.
  --  - Bit 7..0: memory address
  --
  constant I_MEMDATA0           : natural := I_MEMADDR3 + 1;
  -- Only if FLAGS(6) = 1 and MEMFLAGS(0) = 0.
  constant I_MEMDATA1           : natural := I_MEMDATA0 + 1;
  -- Only if FLAGS(6) = 1 and MEMFLAGS(1) = 0.
  constant I_MEMDATA2           : natural := I_MEMDATA1 + 1;
  -- Only if FLAGS(6) = 1 and MEMFLAGS(2) = 0.
  constant I_MEMDATA3           : natural := I_MEMDATA2 + 1;
  -- Only if FLAGS(6) = 1 and MEMFLAGS(3) = 0.
  --  - Bit 7..0: memory data
  --
  -- *** Register write fields ***
  --
  constant I_REGWFLAGS          : natural := I_MEMDATA3 + 1;
  -- Only if FLAGS(5) = 1.
  --  - Bit 7: branch register written
  --  - Bit 6: link register written
  --  - Bit 5..0: register index or 0 if no GP register written
  -- 
  constant I_REGWDATA0          : natural := I_REGWFLAGS + 1;
  constant I_REGWDATA1          : natural := I_REGWDATA0 + 1;
  constant I_REGWDATA2          : natural := I_REGWDATA1 + 1;
  constant I_REGWDATA3          : natural := I_REGWDATA2 + 1;
  -- Only if FLAGS(5) = 1 and (REGWFLAGS(6) = 1 or REGWFLAGS(5..0) != 0).
  --  - Bit 7..0: gpreg/link data
  --
  constant I_REGWBRMASK         : natural := I_REGWDATA3 + 1;
  -- Only if FLAGS(5) = 1 and REGWFLAGS(7) = 1.
  --  - Bit 7..0: 1 if indexed branch register is written, 0 if not
  --
  constant I_REGWBRDATA         : natural := I_REGWBRMASK + 1;
  -- Only if FLAGS(5) = 1 and REGWFLAGS(7) = 1.
  --  - Bit 7..0: new value for the indexed branch register
  --
  -- *** Extended fields ***
  --
  constant I_EXFLAGS            : natural := I_REGWBRDATA + 1;
  -- Only if FLAGS(0) = 1.
  --  - Bit 7: trap fields valid
  --  - Bit 6: reconfiguration fields valid
  --  - Bit 5: cache information field valid
  --  - Bit 4: instruction field valid
  --  - Bit 3..1: reserved for new fields, should be 0
  --  - Bit 0: reserved for EXFLAGS2
  --
  -- *** Trap fields ***
  --
  constant I_TC                 : natural := I_EXFLAGS + 1;
  -- Only if FLAGS(0) = 1 and EXFLAGS(7) = 1.
  --  - Bit 7..0: trap cause
  --
  constant I_TP0                : natural := I_TC + 1;
  constant I_TP1                : natural := I_TP0 + 1;
  constant I_TP2                : natural := I_TP1 + 1;
  constant I_TP3                : natural := I_TP2 + 1;
  -- Only if FLAGS(0) = 1 and EXFLAGS(7) = 1.
  --  - Bit 7..0: trap point
  --
  constant I_TA0                : natural := I_TP3 + 1;
  constant I_TA1                : natural := I_TA0 + 1;
  constant I_TA2                : natural := I_TA1 + 1;
  constant I_TA3                : natural := I_TA2 + 1;
  -- Only if FLAGS(0) = 1 and EXFLAGS(7) = 1.
  --  - Bit 7..0: trap argument
  --
  -- *** Reconfiguration fields ***
  --
  constant I_CFG                : natural := I_TA3 + 1;
  -- Only if FLAGS(0) = 1 and EXFLAGS(6) = 1. 
  --  - Bit 2..0: context associated with the associated lane group.
  --  - Bit 3: run flag (0 if running, 1 if halted).
  --
  -- *** Cache information fields ***
  --
  constant I_CACHEINFO          : natural := I_CFG + 1;
  -- Only if FLAGS(0) = 1 and EXFLAGS(5) = 1.
  --  - Bit 7: 1 if an instruction fetch was performed in the cache block
  --      associated with this lane, 0 if not.
  --  - Bit 6: 1 if the instruction fetch resulted in a miss.
  --  - Bit 5..4: data memory access type serviced by the cache block
  --      associated with this lane:
  --        00 - no access performed.
  --        01 - read access.
  --        10 - write access, full cache line.
  --        11 - write access, partial cache line.
  --  - Bit 3: 1 if the data memory access bypassed the cache, 0 otherwise.
  --  - Bit 2: 1 if the data memory access involved a memory location which was
  --      not in the cache, 0 otherwise.
  --  - Bit 1: 1 if the write buffer associated with this lane was full
  --      (which would have caused an additional cycle count penalty), 0
  --      otherwise.
  --  - Bit 0: reserved. If 1, additional fields which have not yet been
  --      defined are to be expected.
  --
  -- *** Instruction field ***
  --
  constant I_INSTR0             : natural := I_CACHEINFO + 1;
  constant I_INSTR1             : natural := I_INSTR0 + 1;
  constant I_INSTR2             : natural := I_INSTR1 + 1;
  constant I_INSTR3             : natural := I_INSTR2 + 1;
  -- Only if FLAGS(0) = 1 and EXFLAGS(4) = 1.
  --  - Bit 7..0: instruction which was executed.
  --
  -- *** (end) ***
  
  -- Total number of bytes in a completely filled packet.
  constant PACKET_SIZE          : natural := I_INSTR3 + 1;
  
  -- Packet type declarations.
  subtype packet_type is rvex_byte_array(0 to PACKET_SIZE-1);
  type packet_array is array (natural range <>) of packet_type;
  
  -----------------------------------------------------------------------------
  -- Signal declarations
  -----------------------------------------------------------------------------
  -- Packet buffers for each pipelane.
  signal packetBuffers          : packet_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- Pending signals for each packet buffer.
  signal packetPending          : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
  
  -- High when any of the pending signals are high.
  signal anyPacketPending       : std_logic;
  
  -- When high, the packetPending flags will be cleared.
  signal dismissPackets         : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Generate packets from the incoming data (i.e. compress the incoming data)
  -- and instantiate buffers for the packets
  -----------------------------------------------------------------------------
  packet_buffer_block: block is
    
    -- PC as currently reported and its validity. Used to determine how much of
    -- the PC needs to be updated.
    signal currentPC            : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
    signal currentPC_valid      : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
    
    -- Runtime configuration word as currently reported.
    signal currentConfig        : rvex_4bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Trace configuration type.
    type traceConfig_type is record
      
      -- Whether tracing should be enabled.
      enable                    : std_logic;
      
      -- Whether trap information should be traced.
      trapEn                    : std_logic;
      
      -- Whether memory operations should be traced.
      memEn                     : std_logic;
      
      -- Whether register operations should be traced.
      regEn                     : std_logic;
      
      -- Whether the cache performance flags should be traced.
      cacheEn                   : std_logic;
      
      -- Whether the fetched instruction should be traced.
      instrEn                   : std_logic;
      
    end record;
    type traceConfig_array is array (natural range <>) of traceConfig_type;
    
    -- Trace configuration for each pipelane group.
    signal traceConfig          : traceConfig_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Whether the trace unit should be enabled at all.
    signal traceEnable          : std_logic;
    
  begin
    
    -- Decode trace configuration.
    trace_config_decode: process (
      cfg2any_context, cfg2any_active, cxreg2trace_enable, cxreg2trace_trapEn,
      cxreg2trace_memEn, cxreg2trace_regEn, cxreg2trace_cacheEn,
      cxreg2trace_instrEn
    ) is
      variable ctxt             : natural range 0 to 7;
    begin
      
      -- Mux between contexts for each lane group to get the configuration per
      -- lane group.
      for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        ctxt := vect2uint(cfg2any_context(laneGroup));
        traceConfig(laneGroup).enable <= cxreg2trace_enable(ctxt)
                                     and cfg2any_active(laneGroup);
        traceConfig(laneGroup).trapEn <= cxreg2trace_trapEn(ctxt);
        traceConfig(laneGroup).memEn  <= cxreg2trace_memEn(ctxt);
        traceConfig(laneGroup).regEn  <= cxreg2trace_regEn(ctxt);
        traceConfig(laneGroup).cacheEn<= cxreg2trace_cacheEn(ctxt);
        traceConfig(laneGroup).instrEn<= cxreg2trace_instrEn(ctxt);
      end loop;
      
      -- traceEnable should be high when any of the bits in cxreg2trace_enable
      -- is high.
      traceEnable <= '0';
      for c in 0 to 2**CFG.numContextsLog2-1 loop
        if cxreg2trace_enable(c) = '1' then
          traceEnable <= '1';
        end if;
      end loop;
      
    end process;
    
    -- Instantiate the packet buffer.
    packet_buffer_reg: process (clk) is
      
      -- Field validity flags for the trace packet for each lane.
      variable traceMem         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      variable traceReg         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      variable traceTrap        : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      variable traceCfg         : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      variable traceCache       : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      variable traceInstr       : std_logic_vector(2**CFG.numLanesLog2-1 downto 0);
      
      -- Whether there is any nonempty trace packet within the coupled lane
      -- group, excluding PC information. This is used to determine whether PC
      -- information should be logged regardless of branch(ing) state.
      variable traceAnyInGroup  : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
      
      -- Whether any lane within the coupled lane groups committed an
      -- instruction.
      variable anyValid         : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
      
      -- PC information from the previously computed lane (i.e. the next lane).
      variable p_prev           : rvex_byte_array(0 to I_PC3);
      
      -- Scratch variables/temporaries.
      variable n                : rvex_4bit_type;
      variable d                : pl2trace_data_type;
      variable p                : packet_type;
      variable c                : traceConfig_type;
      
    begin
      if rising_edge(clk) then
        if reset = '1' then
          
          -- Only reset the pending and valid flags to save a bit of area.
          packetPending <= (others => '0');
          currentPC <= (others => (others => '0'));
          currentPC_valid <= (others => '0');
          currentConfig <= (others => (others => '0'));
          
        elsif clkEn = '1' then
          
          -- If we're done transmitting the pending packets, clear the pending
          -- flags.
          if dismissPackets = '1' then
            packetPending <= (others => '0');
          end if;
          
          -- Determine whether there's memory, register or trap information to
          -- trace.
          traceMem := (others => '0');
          traceReg := (others => '0');
          traceTrap := (others => '0');
          traceCache := (others => '0');
          traceInstr := (others => '0');
          for lane in 0 to 2**CFG.numLanesLog2-1 loop
            c := traceConfig(lane2group(lane, CFG));
            d := pl2trace_data(lane);
            
            -- Determine whether we need to trace memory in this lane.
            traceMem(lane)  := c.enable
                           and c.memEn
                           and d.valid
                           and d.mem_enable;
            
            -- Determine whether we need to trace register operations in this
            -- lane.
            traceReg(lane)  := c.enable
                           and c.regEn
                           and d.valid 
                           and (d.reg_gpEnable
                            or d.reg_linkEnable
                            or d.reg_brEnable(0)
                            or d.reg_brEnable(1)
                            or d.reg_brEnable(2)
                            or d.reg_brEnable(3)
                            or d.reg_brEnable(4)
                            or d.reg_brEnable(5)
                            or d.reg_brEnable(6)
                            or d.reg_brEnable(7));
            
            -- Determine whether we need to trace traps in this lane.
            traceTrap(lane) := c.enable
                           and c.trapEn
                           and d.valid
                           and d.trap_enable;
            
            -- Determine whether we need to trace cache information in this
            -- lane.
            if lane2indexInGroup(lane, CFG) = 0 then
              traceCache(lane) := c.enable
                              and c.cacheEn
                              and (
                                d.cache_status.instr_access
                                or d.cache_status.data_accessType(1)
                                or d.cache_status.data_accessType(0)
                              );
            end if;
                            
            -- Determine whether we need to trace the syllable fetched in this
            -- lane.
            traceInstr(lane) := c.enable
                            and c.instrEn
                            and d.instr_enable;
            
          end loop;
          
          -- Determine whether there's reconfiguration data to trace.
          traceCfg := (others => '0');
          for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
            n := cfg2any_configWord(laneGroup*4+3 downto laneGroup*4);
            if traceEnable = '1' then
              if n /= currentConfig(laneGroup) then
                traceCfg(group2lastLane(laneGroup, CFG)) := '1';
                if stallIn(laneGroup) = '0' then
                  currentConfig(laneGroup) <= n;
                end if;
              end if;
            else
              if stallIn(laneGroup) = '0' then
                currentConfig(laneGroup) <= (others => '0');
              end if;
            end if;
          end loop;
          
          -- Determine traceAnyInGroup and anyValid, which are needed to
          -- determine whether we should trace the PC (we want to always trace
          -- the PC when anything else is traced).
          traceAnyInGroup := (others => '0');
          anyValid := (others => '0');
          for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
            for lane in 0 to 2**CFG.numLanesLog2-1 loop
              if cfg2any_coupled(lane2group(lane, CFG)*2**CFG.numLaneGroupsLog2 + laneGroup) = '1' then
                
                traceAnyInGroup(laneGroup)
                  := traceAnyInGroup(laneGroup)
                  or traceMem(lane)
                  or traceReg(lane)
                  or traceTrap(lane)
                  or traceCfg(lane)
                  or traceCache(lane)
                  or traceInstr(lane);
                
                anyValid(laneGroup)
                  := anyValid(laneGroup)
                  or pl2trace_data(lane).valid;
                
              end if;
            end loop;
          end loop;
          
          -- Update the packet buffer contents if stall is low.
          p_prev := (others => X"00");
          for lane in 2**CFG.numLanesLog2-1 downto 0 loop
            
            -- Initialize the packet we're going to construct with the reset
            -- state and load the trace configuration and incoming data for
            -- this lane into c and d for shorthand notation.
            p := (others => X"00");
            c := traceConfig(lane2group(lane, CFG));
            d := pl2trace_data(lane);
            
            ------------------
            -- Trace the PC --
            ------------------
            
            -- If this lane has an active branch unit, determine whether its
            -- state is worth tracing. If it does not, copy the state from
            -- the coupled lane which does.
            if d.pc_enable = '1' then
              
              -- Determine whether we need to trace the PC.
              p(I_FLAGS)(7) := anyValid(lane2group(lane, CFG)) and c.enable and (
                
                -- Always need to trace if we're branching or have branched.
                d.pc_isBranch or d.pc_isBranching
                
                -- Always trace PC when something else is being traced.
                or traceAnyInGroup(lane2group(lane, CFG))
                
              );
              
              -- Determine the PC update mode.
              if d.pc_isBranch = '1' then
                p(I_PC0)(1 downto 0) := "11";
              elsif currentPC_valid(lane) = '0' then
                p(I_PC0)(1 downto 0) := "10";
              elsif currentPC(lane)(31 downto 16) /= d.pc_PC(31 downto 16) then
                p(I_PC0)(1 downto 0) := "10";
              elsif currentPC(lane)(15 downto 8) /= d.pc_PC(15 downto 8) then
                p(I_PC0)(1 downto 0) := "01";
              else
                p(I_PC0)(1 downto 0) := "00";
              end if;
              
              -- Write the new PC to the packet.
              p(I_PC0)(7 downto 2) := d.pc_PC(7  downto  2);
              p(I_PC1)(7 downto 0) := d.pc_PC(15 downto  8);
              p(I_PC2)(7 downto 0) := d.pc_PC(23 downto 16);
              p(I_PC3)(7 downto 0) := d.pc_PC(31 downto 24);
              
              -- Update the currentPC register.
              if stallIn(lane2group(lane, CFG)) = '0' then
                if p(I_FLAGS)(7) = '1' then
                  currentPC(lane)(1 downto 0) <= "00";
                  currentPC(lane)(31 downto 2) <= d.pc_PC(31 downto 2);
                  currentPC_valid(lane) <= '1';
                end if;
              end if;
              
              -- Store the PC trace information for the next loop iteration;
              -- the PC information will not necessarily be traced as being
              -- part of the lane with the branch unit. Instead, it is
              -- associated with the lane which has the stop bit set, so the
              -- trace data interpreter implicitely knows how large the bundle
              -- was.
              p_prev := p(0 to I_PC3);
              
            else
              
              -- Take the PC information from the active branch unit lane.
              p(0 to I_PC3) := p_prev;
              
            end if;
            
            -- Disable PC tracing in this lane if this lane does not have a
            -- stop bit.
            if d.stop = '0' then
              p(I_FLAGS)(7) := '0';
            end if;
            
            -----------------------------
            -- Trace memory operations --
            -----------------------------
            
            -- Set the field valid flag.
            p(I_FLAGS)(6) := traceMem(lane);
            
            -- Write the write mask into the packet.
            p(I_MEMFLAGS)(3 downto 0) := d.mem_writeMask;
            
            -- Write the address to the packet.
            p(I_MEMADDR0)(7 downto 0) := d.mem_address(7  downto  0);
            p(I_MEMADDR1)(7 downto 0) := d.mem_address(15 downto  8);
            p(I_MEMADDR2)(7 downto 0) := d.mem_address(23 downto 16);
            p(I_MEMADDR3)(7 downto 0) := d.mem_address(31 downto 24);
            
            -- Write the data to the packet.
            p(I_MEMDATA0)(7 downto 0) := d.mem_writeData(7  downto  0);
            p(I_MEMDATA1)(7 downto 0) := d.mem_writeData(15 downto  8);
            p(I_MEMDATA2)(7 downto 0) := d.mem_writeData(23 downto 16);
            p(I_MEMDATA3)(7 downto 0) := d.mem_writeData(31 downto 24);
            
            -------------------------------
            -- Trace register operations --
            -------------------------------
            
            -- Set the field valid flag.
            p(I_FLAGS)(5) := traceReg(lane);
            
            -- Determine the register update flags.
            if d.reg_brEnable /= X"00" then
              p(I_REGWFLAGS)(7) := '1';
            else
              p(I_REGWFLAGS)(7) := '0';
            end if;
            p(I_REGWFLAGS)(6) := d.reg_linkEnable;
            if d.reg_gpEnable = '1' then
              p(I_REGWFLAGS)(5 downto 0) := d.reg_gpAddress;
            else
              p(I_REGWFLAGS)(5 downto 0) := (others => '0');
            end if;
            
            -- Write the written integer to the packet.
            p(I_REGWDATA0)(7 downto 0) := d.reg_intData(7  downto  0);
            p(I_REGWDATA1)(7 downto 0) := d.reg_intData(15 downto  8);
            p(I_REGWDATA2)(7 downto 0) := d.reg_intData(23 downto 16);
            p(I_REGWDATA3)(7 downto 0) := d.reg_intData(31 downto 24);
            
            -- Write branch register update information to the packet.
            p(I_REGWBRMASK)(7 downto 0) := d.reg_brEnable;
            p(I_REGWBRDATA)(7 downto 0) := d.reg_brData;
            
            -----------------
            -- Trace traps --
            -----------------
            
            -- Set the field valid flag.
            p(I_EXFLAGS)(7) := traceTrap(lane);
            
            -- Write the trap cause to the packet.
            p(I_TC)(7 downto 0) := d.trap_cause;
            
            -- Write the trap point to the packet.
            p(I_TP0)(7 downto 0) := d.trap_point(7  downto  0);
            p(I_TP1)(7 downto 0) := d.trap_point(15 downto  8);
            p(I_TP2)(7 downto 0) := d.trap_point(23 downto 16);
            p(I_TP3)(7 downto 0) := d.trap_point(31 downto 24);
            
            -- Write the trap argument to the packet.
            p(I_TA0)(7 downto 0) := d.trap_arg(7  downto  0);
            p(I_TA1)(7 downto 0) := d.trap_arg(15 downto  8);
            p(I_TA2)(7 downto 0) := d.trap_arg(23 downto 16);
            p(I_TA3)(7 downto 0) := d.trap_arg(31 downto 24);
            
            ---------------------------
            -- Trace reconfiguration --
            ---------------------------
            
            -- Set the field valid flag.
            p(I_EXFLAGS)(6) := traceCfg(lane);
            
            -- Write the configuration into the packet.
            p(I_CFG)(7 downto 4) := (others => '0');
            p(I_CFG)(3 downto 0) := cfg2any_configWord(
              lane2group(lane, CFG)*4+3 downto lane2group(lane, CFG)*4
            );
            
            -----------------------------------
            -- Trace cache performance flags --
            -----------------------------------
            
            -- Only trace reconfiguration in the first lane of a group.
            if lane2indexInGroup(lane, CFG) = 0 then
              
              -- Set the field valid flag.
              p(I_EXFLAGS)(5) := traceCache(lane);
              
              -- Write the cache performance flags to the packet.
              p(I_CACHEINFO)(7) := d.cache_status.instr_access;
              p(I_CACHEINFO)(6) := d.cache_status.instr_miss;
              p(I_CACHEINFO)(5) := d.cache_status.data_accessType(1);
              p(I_CACHEINFO)(4) := d.cache_status.data_accessType(0);
              p(I_CACHEINFO)(3) := d.cache_status.data_bypass;
              p(I_CACHEINFO)(2) := d.cache_status.data_miss;
              p(I_CACHEINFO)(1) := d.cache_status.data_writePending;
              
            end if;
            
            -----------------------------
            -- Trace instruction fetch --
            -----------------------------
            
            -- Set the field valid flag.
            p(I_EXFLAGS)(4) := traceInstr(lane);
            
            -- Write the cache performance flags to the packet.
            p(I_INSTR0)(7 downto 0) := d.instr_syllable(7  downto  0);
            p(I_INSTR1)(7 downto 0) := d.instr_syllable(15 downto  8);
            p(I_INSTR2)(7 downto 0) := d.instr_syllable(23 downto 16);
            p(I_INSTR3)(7 downto 0) := d.instr_syllable(31 downto 24);
            
            -----------------------------------
            -- Update packet buffer register --
            -----------------------------------
            
            -- Enable the valid flag for EXFLAGS in FLAGS if EXFLAGS is
            -- nonzero.
            if p(I_EXFLAGS) /= X"00" then
              p(I_FLAGS)(0) := '1';
            end if;
            
            -- Set the pending flag if any of the valid flags in FLAGS are
            -- nonzero and buffer the constructed packet.
            if stallIn(lane2group(lane, CFG)) = '0' then
              if p(I_FLAGS) /= X"00" then
                packetPending(lane) <= '1';
              end if;
              packetBuffers(lane) <= p;
            end if;
            
          end loop;
        end if;
        
        -- Override all the above for the lane index in FLAGS, which is obviously
        -- always the same for each buffer.
        for lane in 0 to 2**CFG.numLanesLog2-1 loop
          packetBuffers(lane)(I_FLAGS)(4 downto 1) <= uint2vect(lane, 4);
        end loop;
        
      end if;
    end process;
    
    -- Generate the anyPacketPending signal.
    any_pending_proc: process (packetPending) is
    begin
      anyPacketPending <= '0';
      for lane in 0 to 2**CFG.numLanesLog2-1 loop
        if packetPending(lane) = '1' then
          anyPacketPending <= '1';
        end if;
      end loop;
    end process;
    
    -- Stall when packets are pending transmission.
    stallOut <= anyPacketPending;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Instantiate packet serializer state machine
  -----------------------------------------------------------------------------
  serializer_block: block is
    
    -- The lane index for which we are currently transmitting a trace packet.
    signal currentLane          : natural range 0 to 2**CFG.numLanesLog2-1;
    
    -- The current byte within the packet.
    signal currentByte          : natural range 0 to PACKET_SIZE-1;
    
    -- Packet buffer and pending flag as selected by currentLane.
    signal currentPacket        : packet_type;
    signal currentByteVal       : rvex_byte_type;
    signal currentPending       : std_logic;
    
  begin
    
    -- Generate the packet buffer and pending muxes.
    currentPacket <= packetBuffers(currentLane);
    currentByteVal <= currentPacket(currentByte);
    currentPending <= packetPending(currentLane);
    
    -- Instantiate the finite state machine for conversion from packet buffer
    -- to bytestream.
    serializer_fsm: process (clk) is
      
      -- Pushes the current byte to the output stream.
      procedure push(
        nextByte                : natural range 0 to PACKET_SIZE-1 := 0;
        incLane                 : boolean := false;
        last                    : boolean := false;
        pushNull                : boolean := false
      ) is
      begin
        if trsink2trace_busy = '0' then
          if incLane then
            if currentLane < 2**CFG.numLanesLog2-1 then
              currentLane <= currentLane + 1;
            else
              currentLane <= 0;
              dismissPackets <= '1';
            end if;
          end if;
          currentByte         <= nextByte;
          trace2trsink_push   <= '1';
          if pushNull then
            trace2trsink_data <= (others => '0');
          else
            trace2trsink_data <= currentByteVal;
          end if;
          if last then
            trace2trsink_end  <= '1';
          else
            trace2trsink_end  <= '0';
          end if;
        end if;
      end procedure;
      
      -- Skips the current byte.
      procedure skip(
        nextByte                : natural range 0 to PACKET_SIZE-1 := 0;
        incLane                 : boolean := false
      ) is
      begin
        if incLane then
          if currentLane < 2**CFG.numLanesLog2-1 then
            currentLane <= currentLane + 1;
          else
            currentLane <= 0;
            dismissPackets <= '1';
          end if;
        end if;
        currentByte           <= nextByte;
        if trsink2trace_busy = '0' then
          trace2trsink_push   <= '0';
        end if;
      end procedure;
      
    begin
      if rising_edge(clk) then
        if reset = '1' then
          
          -- Reset state.
          currentLane       <= 0;
          currentByte       <= 0;
          
          -- Reset output registers.
          dismissPackets    <= '0';
          trace2trsink_push <= '0';
          trace2trsink_data <= (others => '0');
          trace2trsink_end  <= '0';
          
        elsif clkEn = '1' then
          
          -- Don't dismiss the packet buffer by default.
          dismissPackets <= '0';
          
          -- Push all bytes of all packets in order by default.
          if currentByte < PACKET_SIZE-1 then
            push(nextByte => currentByte + 1);
          else
            push(incLane => true);
          end if;
          
          -- Handle exceptions to the above rule.
          case currentByte is
            
            when I_FLAGS =>
              
              if currentLane = 0 and (anyPacketPending = '0' or dismissPackets = '1') then
                
                -- If we're in lane 0 and there are no packets pending, we need
                -- to wait for more trace data.
                skip;
                
              elsif currentPending = '0' then
                
                -- If this lane does not have a packet pending, go to the next.
                -- If this is the last lane, push a null packet in this case to
                -- indicate the end of the cycle.
                if currentLane = 2**CFG.numLanesLog2-1 then
                  push(incLane => true, last => true, pushNull => true);
                else
                  skip(incLane => true);
                end if;
                
              end if;
              
            when I_PC0 =>
              
              if currentPacket(I_FLAGS)(7) = '0' then
                
                -- The PC does not need to be traced, skip to the memory.
                skip(nextByte => I_MEMFLAGS);
                
              elsif currentPacket(I_PC0)(1 downto 0) = "00" then
                
                -- Only this byte needs to be traced.
                push(nextByte => I_MEMFLAGS);
                
              end if;
              
            when I_PC1 =>
              
              if currentPacket(I_PC0)(1) = '0' then
                
                -- Only this byte needs to be traced.
                push(nextByte => I_MEMFLAGS);
                
              end if;
              
            when I_MEMFLAGS =>
              
              if currentPacket(I_FLAGS)(6) = '0' then
                
                -- The memory does not need to be traced, skip to the
                -- registers.
                skip(nextByte => I_REGWFLAGS);
                
              end if;
              
            -- Skip memory write data bytes when the associated write mask bits
            -- are low.
            when I_MEMDATA0 =>
              if currentPacket(I_MEMFLAGS)(0) = '0' then
                skip(nextByte => currentByte + 1);
              end if;
              
            when I_MEMDATA1 =>
              if currentPacket(I_MEMFLAGS)(1) = '0' then
                skip(nextByte => currentByte + 1);
              end if;
              
            when I_MEMDATA2 =>
              if currentPacket(I_MEMFLAGS)(2) = '0' then
                skip(nextByte => currentByte + 1);
              end if;
              
            when I_MEMDATA3 =>
              if currentPacket(I_MEMFLAGS)(3) = '0' then
                skip(nextByte => currentByte + 1);
              end if;
              
            when I_REGWFLAGS =>
              
              if currentPacket(I_FLAGS)(5) = '0' then
                
                -- No register information needs to be traced, skip to the
                -- EXFLAGS byte.
                skip(nextByte => I_EXFLAGS);
                
              end if;
              
            when I_REGWDATA0 =>
              
              if currentPacket(I_REGWFLAGS)(6 downto 0) = "0000000" then
                
                -- No integer data has been written, skip to branch data.
                skip(nextByte => I_REGWBRMASK);
                
              end if;
              
            when I_REGWBRMASK =>
              
              if currentPacket(I_REGWFLAGS)(7) = '0' then
                
                -- No branch registers have been written, skip to EXFLAGS.
                skip(nextByte => I_EXFLAGS);
                
              end if;
              
            when I_EXFLAGS =>
              
              if currentPacket(I_FLAGS)(0) = '0' then
                
                -- No extended fields have to be traced, continue to next lane.
                skip(incLane => true);
                
              end if;
              
            when I_TC =>
              
              if currentPacket(I_EXFLAGS)(7) = '0' then
                
                -- Trap information does not need to be traced. Skip to
                -- reconfiguration data.
                skip(nextByte => I_CFG);
                
              end if;
              
            when I_CFG =>
              
              if currentPacket(I_EXFLAGS)(6) = '0' then
                
                -- Reconfiguration data does not need to be traced. Skip to
                -- cache performance data.
                skip(nextByte => I_CACHEINFO);
                
              end if;
              
            when I_CACHEINFO =>
              
              if currentPacket(I_EXFLAGS)(5) = '0' then
                
                -- Cache performance data does not need to be traced. Skip to
                -- syllable.
                skip(nextByte => I_INSTR0);
                
              end if;
              
            when I_INSTR0 =>
              
              if currentPacket(I_EXFLAGS)(4) = '0' then
                
                -- Syllable does not need to be traced, continue to the next
                -- lane.
                skip(incLane => true);
                
              end if;
              
            when others =>
              null;
              
          end case;
          
        end if;
      end if;
    end process;
    
  end block;
  
end Behavioral;

