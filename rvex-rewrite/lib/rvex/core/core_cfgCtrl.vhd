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
-- This entity contains the control logic which arbitrates between
-- reconfiguration requests and controls committing the new configuration in
-- such a way that the core does not end up in an undefined state.
-------------------------------------------------------------------------------
entity core_cfgCtrl is
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
    
    ---------------------------------------------------------------------------
    -- Configuration request inputs
    ---------------------------------------------------------------------------
    -- Each nibble in the data word corresponds to a pipelane group, of which
    -- bit 3 specifies whether the pipelane group should be disabled (high) or
    -- enabled (low) and, if low, bit 2..0 specify the context it should run
    -- on. Bits which are not supported by the core (as specified in the CFG
    -- generic) should be written zero or the request will be ignored (as
    -- specified by the error flag in the global control register file).
    --
    -- The enable signal is active high. When multiple requests are made at
    -- once, the bus first take priority, after which the core contexts in
    -- increasing order.
    cxreg2cfg_requestData       : in  rvex_data_array(2**CFG.numContextsLog2-1 downto 0);
    cxreg2cfg_requestEnable     : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    gbreg2cfg_requestData       : in  rvex_data_type;
    gbreg2cfg_requestEnable     : in  std_logic;
    
    -- cxreg2cfg_wakeupEnable is high when the wakeup system is active, and
    -- rctrl2cfg_irq_ct0 is high when it should activate.
    -- cxreg2cfg_wakeupConfig represents the wakeup configuration word, using
    -- the same encoding as the words above. When the wakeup system activates,
    -- cxreg2cfg_wakeupAck will be high for one cycle. This should disable the
    -- wakeup system.
    cxreg2cfg_wakeupConfig      : in  rvex_data_type;
    cxreg2cfg_wakeupEnable      : in  std_logic;
    cfg2cxreg_wakeupAck         : out std_logic;
    rctrl2cfg_irq_ct0           : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Configuration status outputs
    ---------------------------------------------------------------------------
    -- Configuration busy signal. When set, new configuration requests are not
    -- accepted.
    cfg2gbreg_busy              : out std_logic;
    
    -- Configuration error signal. This is set when the last configuration
    -- request was erroneous.
    cfg2gbreg_error             : out std_logic;
    
    -- When reconfiguration is requested, this field is set to the index of
    -- the context which requested the configuration, or all ones if the source
    -- was the debug bus.
    cfg2gbreg_requesterID       : out std_logic_vector(3 downto 0);
    
    ---------------------------------------------------------------------------
    -- Branch unit interface (through context-pipelane interface)
    ---------------------------------------------------------------------------
    -- The active bits are tied to the run bits in the current configuration;
    -- a context should not be modified and kept in a halted state when active
    -- is low.
    cfg2cxplif_active           : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Reconfiguration request signal. These bits will be pulled high when the
    -- reconfiguration controller wants to reconfigure contexts while the
    -- relevant blockReconfig signals are high. A context should halt when
    -- this is high.
    cfg2cxplif_requestReconfig  : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Active high reconfiguration block input from the branch units. When this
    -- is low, associated contexts may not be reconfigured.
    cxplif2cfg_blockReconfig    : in  std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Memory interface
    ---------------------------------------------------------------------------
    -- Active high reconfiguration block input from the instruction and data
    -- memories. When this is low, associated lanes may not be reconfigured.
    mem2cfg_blockReconfig       : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Configuration control signals
    ---------------------------------------------------------------------------
    -- Current configuration, using the same encoding as the request data.
    cfg2any_configWord          : out rvex_data_type;
    
    -- None of the following signals hold more information than the configWord
    -- output; instead they are different representations of the configuration
    -- for different blocks. Predetermining these control signals instead of
    -- doing it in the pipeline essentially every cycle saves a lot of time in
    -- the interconnect networks at the cost of a few extra registers.
    
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_i,j is high when pipelane groups i and j are coupled/share a
    -- context, or low when they don't.
    cfg2any_coupled             : out std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Decouple vector. This is just another way to look at the coupled matrix.
    -- The vector is assigned such that dec_i = not C_i,i+1. The MSB in the
    -- vector is always high. This representation is useful because the bits
    -- can also be regarded as master/slave bits: when the decouple bit for
    -- a group is high, it is a master, otherwise it is a slave. Slaves answer
    -- to the next higher indexed master group.
    cfg2any_decouple            : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- log2 of the number of coupled pipelane groups for each pipelane group.
    cfg2any_numGroupsLog2       : out rvex_2bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies the context associated with the indexed pipelane group.
    cfg2any_context             : out rvex_3bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Specifies whether the indexed pipeline group is active.
    cfg2any_active              : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Last pipelane group associated with each context.
    cfg2any_lastGroupForCtxt    : out rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- The lane index within the coupled groups for each lane.
    cfg2any_laneIndex           : out rvex_4bit_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- The amount which the branch unit residing in the indexed lane should
    -- add to the current PC to get PC_plusOne, should it be the active branch
    -- unit.
    cfg2any_pcAddVal            : out rvex_address_array(2**CFG.numLanesLog2-1 downto 0)
    
  );
end core_cfgCtrl;

--=============================================================================
architecture Behavioral of core_cfgCtrl is
--=============================================================================
  
  -- Bitmask for the configuration control bits which are actually in use. Bits
  -- in this mask which are zero are considered to be reserved and must be set
  -- to zero in a request for it to be considered valid.
  function determineConfigMask return rvex_data_type is
    variable bits : rvex_data_type;
  begin
    bits := (others => '0');
    for i in 2**CFG.numLaneGroupsLog2-1 downto 0 loop
      
      -- Run bit.
      bits(i*4+3) := '1';
      
      -- Context selection bit.
      bits(i*4+CFG.numContextsLog2-1 downto 0) := (others => '1');
      
    end loop;
    return bits;
  end function;
  constant CONFIGURATION_MASK   : rvex_data_type := determineConfigMask;
  
  -- This is high when the wakeup system is requesting a reconfiguration.
  signal wakeupActive           : std_logic;
  
  -- This is high when any of the requestEnable inputs are high and busy_r is
  -- low.
  signal reconfigRequest        : std_logic;
  
  -- This is high when reconfigRequest is high, but the requested configuration
  -- has ones written in reserved positions.
  signal reconfigRequestError   : std_logic;
  
  -- This is high when reconfigRequest is high, reconfigRequestError is low and
  -- the new configuration actually differs from the old one.
  signal reconfigRequestOK      : std_logic;
  
  -- When reconfiguration is requested, this field is set to the index of
  -- the context which requested the configuration, or all ones if the source
  -- was the debug bus. requesterID is combinatorial based on the requestEnable
  -- signals, requesterID_r is registered when reconfigRequest is high.
  signal requesterID            : std_logic_vector(3 downto 0);
  signal requesterID_r          : std_logic_vector(3 downto 0);
  
  -- New configuration register. This is combinatorially set to the currently
  -- requested configuration indexed by requesterID.
  signal newConfiguration       : rvex_data_type;
  
  -- Internal busy register. This is synchronously set when reconfigRequest is
  -- high, and reset when commit goes high or an error occurs.
  signal busy_r                 : std_logic;
  
  -- Internal error register. This is synchronously reset when reconfigRequest
  -- is high, and set when the request or decoder logic detects an error in the
  -- new configuration vector.
  signal error_r                : std_logic;
  
  -- Decoder busy and error flags.
  signal decoderBusy            : std_logic;
  signal decoderError           : std_logic;
  
  -- Flag for each context which is set when its new configuration differs from
  -- the current one ans is cleared when it doesn't. Contexts for which this
  -- bit is cleared do not need to be stopped to commit the new configuration.
  signal contextsToUpdate       : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  
  -- Block reconfiguration registers.
  signal blockReconfig_ctxt     : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal blockReconfig_mem      : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  signal blockReconfig_decode   : std_logic;
  
  -- Commit signal. When high, the new configuration will be committed to the
  -- current configuration registers and busy will be cleared.
  signal commit                 : std_logic;
  
  -- New configuration registers from the decoder unit.
  signal newConfiguration_r     : rvex_data_type;
  signal newContextEnable_r     : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal newLastPipelaneGroupForContext_r : rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
  signal newNumPipelaneGroupsLog2ForContext_r : rvex_2bit_array(2**CFG.numContextsLog2-1 downto 0);
  signal newCoupleMatrix_r      : std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
  signal newLaneIndex_r         : rvex_4bit_array(2**CFG.numLanesLog2-1 downto 0);
  signal newPcAddVal_r          : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  
  -- Current configuration registers.
  signal curConfiguration_r     : rvex_data_type;
  signal curContextEnable_r     : std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
  signal curLastPipelaneGroupForContext_r : rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
  signal curNumPipelaneGroupsLog2ForContext_r : rvex_2bit_array(2**CFG.numContextsLog2-1 downto 0);
  signal curCoupleMatrix_r      : std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0);
  signal curLaneIndex_r         : rvex_4bit_array(2**CFG.numLanesLog2-1 downto 0);
  signal curPcAddVal_r          : rvex_address_array(2**CFG.numLanesLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Handle the wakeup system
  -----------------------------------------------------------------------------
  wakeup_condition: process (
    busy_r, cxreg2cfg_wakeupEnable, rctrl2cfg_irq_ct0, curConfiguration_r
  ) is
    variable active : std_logic;          
  begin
    
    -- Activate when the system is enabled, there's an interrupt pending on
    -- context 0 and we're not already reconfiguring.
    active := cxreg2cfg_wakeupEnable and rctrl2cfg_irq_ct0 and not busy_r;
    
    -- Don't activate when context 0 is already running. This ensures that the
    -- wakeup system can never disable itself while context 0 may still be
    -- preparing to go to sleep.
    for i in 2**CFG.numLaneGroupsLog2-1 downto 0 loop
      if curConfiguration_r(i*4+3 downto i*4) = "0000" then
        active := '0';
      end if;
    end loop;
    
    -- Forward the signal.
    wakeupActive <= active;
    cfg2cxreg_wakeupAck <= active;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Priority encoding among reconfiguration request inputs
  -----------------------------------------------------------------------------
  -- Generate the reconfigRequest signal. This is just a big or gate across the
  -- request enable signals.
  reconfig_request_gen: process (
    busy_r, cxreg2cfg_requestEnable, gbreg2cfg_requestEnable, wakeupActive
  ) is
  begin
    if busy_r = '0' then
      reconfigRequest <= gbreg2cfg_requestEnable or wakeupActive;
      for i in 2**CFG.numContextsLog2-1 downto 0 loop
        if cxreg2cfg_requestEnable(i) = '1' then
          reconfigRequest <= '1';
        end if;
      end loop;
    else
      reconfigRequest <= '0';
    end if;
  end process;
  
  -- Generate the reconfigRequestError signal.
  reconfigRequestError <= '0' when
    vect2unsigned(newConfiguration and not CONFIGURATION_MASK) = 0
    else reconfigRequest;
  
  -- Generate the reconfigRequestOK signal.
  reconfigRequestOK <= '0' when
    (newConfiguration and CONFIGURATION_MASK) = (curConfiguration_r and CONFIGURATION_MASK)
    else (reconfigRequest and not reconfigRequestError);
  
  -- Generate the priority encoder for the incoming requests.
  request_priority_encoder: process (
    cxreg2cfg_requestEnable, gbreg2cfg_requestEnable, wakeupActive
  ) is
  begin
    
    -- Use the bus ID as default value (lowest priority).
    requesterID <= "1111";
    
    -- Priority encode between the request signals from the contexts, giving
    -- the highest priority to the lowest indexed context.
    if gbreg2cfg_requestEnable = '0' then
      for i in 2**CFG.numContextsLog2-1 downto 0 loop
        if cxreg2cfg_requestEnable(i) = '1' then
          requesterID <= uint2vect(i, 4);
        end if;
      end loop;
    end if;
    
    -- If the wakeup system is active, select its ID (highest priority). This
    -- MUST be the highest priority, because the wakeup system is not capable
    -- of retrying in case it loses arbitration.
    if wakeupActive = '1' then
      requesterID <= "1000";
    end if;
    
  end process;
  
  -- Mux between the requested configuration vectors based on the priority
  -- encoder output.
  request_mux: process (
    requesterID, cxreg2cfg_requestData, gbreg2cfg_requestData,
    cxreg2cfg_wakeupConfig
  ) is
    variable sel : integer range 0 to 15;
  begin
    
    -- Convert the mux selection signal to something we can work with.
    sel := vect2uint(requesterID);
    
    -- Select the right data signal.
    if sel < 2**CFG.numContextsLog2 then
      newConfiguration <= cxreg2cfg_requestData(sel); -- From a context.
    elsif sel < 12 then
      newConfiguration <= cxreg2cfg_wakeupConfig; -- From the wakeup system.
    else
      newConfiguration <= gbreg2cfg_requestData; -- From the debug bus.
    end if;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Instantiate reconfiguration status registers
  -----------------------------------------------------------------------------
  -- Generate the busy, error and requesterID registers.
  status_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        busy_r <= '0';
        error_r <= '0';
        requesterID_r <= (others => '1');
      elsif clkEn = '1' then
        
        -- Set the requester ID whenever a request occurs.
        if reconfigRequest = '1' then
          requesterID_r <= requesterID;
        end if;
        
        -- Set the busy flag, clear the error flag and store the requested
        -- configuration when a reconfiguration is requested and initial
        -- checks are positive.
        if reconfigRequestOK = '1' then
          busy_r <= '1';
          error_r <= '0';
        end if;
        
        -- Set the error flag when a reconfiguration is requested and initial
        -- checks are negative or when there is a decode error.
        if (reconfigRequestError = '1') or (decoderError = '1') then
          busy_r <= '0';
          error_r <= '1';
        end if;
        
        -- Clear the busy and error flags when commit goes high.
        if commit = '1' then
          busy_r <= '0';
          error_r <= '0';
        end if;
        
      end if;
    end if;
  end process;
  
  -- Forward the internal registers to the status registers.
  cfg2gbreg_busy <= busy_r;
  cfg2gbreg_error <= error_r;
  cfg2gbreg_requesterID <= requesterID_r;
  
  -----------------------------------------------------------------------------
  -- Instantiate the decoder
  -----------------------------------------------------------------------------
  decoder: entity rvex.core_cfgCtrl_decode
    generic map (
      CFG                       => CFG
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => clkEn,
      
      -- Configuration request input and handshaking signals.
      newConfiguration_in       => newConfiguration,
      start                     => reconfigRequestOK,
      busy                      => decoderBusy,
      error                     => decoderError,
      
      -- Decoded configuration control signals.
      newConfiguration_out      => newConfiguration_r,
      contextEnable             => newContextEnable_r,
      lastPipelaneGroupForContext => newLastPipelaneGroupForContext_r,
      numPipelaneGroupsLog2ForContext => newNumPipelaneGroupsLog2ForContext_r,
      coupleMatrix              => newCoupleMatrix_r
      
    );
  
  -- Determine newLaneIndex_r and newPcAddVal_r. We can trivially determine
  -- newPcAddVal_r-1 from the couple matrix, because that's essentially just
  -- the lane index with some alignment based on CFG. Only the (small) +1 adder
  -- here is significant.
  pc_add_val_decoder: process (
    newCoupleMatrix_r, newConfiguration_r, newNumPipelaneGroupsLog2ForContext_r
  ) is
    
    -- Log2 of the size in bytes of an instruction for a lane group.
    constant GRP_SIZE_LOG2B : natural
      := CFG.numLanesLog2 - CFG.numLaneGroupsLog2 + SYLLABLE_SIZE_LOG2B;
    
    -- Number of groups working together for the current group.
    variable numGroupsLog2  : natural;
    
    -- Number of LSBs of the PC which should always be zero (i.e. PC
    -- alignment).
    variable align          : natural;
    
    -- Computed value to add minus one.
    variable addValMinusOne : unsigned(31 downto 0);
    
    -- Lane group currently being evaluated.
    variable laneGroup      : natural;
    
    -- Secondary lane group.
    variable prevLaneGroup  : integer;
    
  begin
    
    for lane in 0 to 2**CFG.numLanesLog2-1 loop
      laneGroup := lane2group(lane, CFG);
      
      -- Determine the value to add to the PC minus one if all lanes were to
      -- be coupled and there are no alignment constraints. Note that this is
      -- simply the lane index, so that's all we need to compute.
      addValMinusOne := to_unsigned(lane * 2**SYLLABLE_SIZE_LOG2B, 32);
      
      -- Handle runtime configuration. We can do this by just clearing bits
      -- when lanes are not coupled by noticing the following addValMinusOne
      -- values for a 4-lane core which can be configured as a 2x2 lane core:
      -- 
      -- Lane | 1x4  | 2x2
      -- -----+------+------
      --   0  | 0b00 | 0b00
      --   1  | 0b01 | 0b01
      --   2  | 0b10 | 0b00
      --   3  | 0b11 | 0b01
      --
      -- The MSB for lanes 2 and 3 in 2x2 mode are simply cleared when lane 0
      -- and 2 and lane 1 and 3 respectively are not coupled. This can be
      -- trivially generalized for any CFG.
      --
      for i in 0 to CFG.numLaneGroupsLog2-1 loop
        prevLaneGroup := laneGroup - 2**i;
        if prevLaneGroup >= 0 then
          if newCoupleMatrix_r(laneGroup + prevLaneGroup*2**CFG.numLaneGroupsLog2) = '0' then
            addValMinusOne(GRP_SIZE_LOG2B + i) := '0';
          end if;
        end if;
      end loop;
      
      -- Extract the lane index to get newLaneIndex_r.
      newLaneIndex_r(lane) <= std_logic_vector(addValMinusOne(
        SYLLABLE_SIZE_LOG2B + 3 downto SYLLABLE_SIZE_LOG2B
      ));
      
      -- Determine how the PC addition value should be aligned.
      numGroupsLog2 := vect2uint(newNumPipelaneGroupsLog2ForContext_r(
        vect2uint(newConfiguration_r(laneGroup*4+CFG.numLaneGroupsLog2-1 downto laneGroup*4))
      ));
      
      align := min_nat(
        (CFG.numLanesLog2 - CFG.numLaneGroupsLog2) + numGroupsLog2,
        CFG.bundleAlignLog2
      ) + SYLLABLE_SIZE_LOG2B;
      
      -- Enforce alignment.
      for i in 0 to 2**CFG.numLanesLog2-1 loop
        if i < align then
          addValMinusOne(i) := '0';
        end if;
      end loop;
      
      -- Perform the +1 addition to get newPcAddVal_r.
      newPcAddVal_r(lane) <= std_logic_vector(
        addValMinusOne + to_unsigned(2**align, 32)
      );
      
    end loop;
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Generate reconfiguration control logic
  -----------------------------------------------------------------------------
  -- Generate the contextsToUpdate signal by comparing the new and current
  -- configuration for each context.
  gen_contextsToUpdate: process (
    newContextEnable_r, curContextEnable_r,
    newLastPipelaneGroupForContext_r, curLastPipelaneGroupForContext_r,
    newNumPipelaneGroupsLog2ForContext_r, curNumPipelaneGroupsLog2ForContext_r
  ) is
  begin
    for i in 2**CFG.numContextsLog2-1 downto 0 loop
      contextsToUpdate(i) <= '0';
      if newContextEnable_r(i) = '1' or curContextEnable_r(i) = '1' then
        if newContextEnable_r(i) /= curContextEnable_r(i) then
          contextsToUpdate(i) <= '1';
        end if;
        if newLastPipelaneGroupForContext_r(i) /= curLastPipelaneGroupForContext_r(i) then
          contextsToUpdate(i) <= '1';
        end if;
        if newNumPipelaneGroupsLog2ForContext_r(i) /= curNumPipelaneGroupsLog2ForContext_r(i) then
          contextsToUpdate(i) <= '1';
        end if;
      end if;
    end loop;
  end process;
  
  -- Generate the active bits for each context.
  cfg2cxplif_active <= curContextEnable_r;
  
  -- Generate the requestReconfig bits for each context.
  gen_request_reconfig_bits: process (
    contextsToUpdate, decoderBusy, busy_r
  ) is
  begin
    for i in 2**CFG.numContextsLog2-1 downto 0 loop
      
      -- We should start disabling the run bit for the contexts which need to
      -- be updated when the decoder is done, so when decoderBusy goes low but
      -- busy_r is still high.
      cfg2cxplif_requestReconfig(i)
        <= contextsToUpdate(i) and busy_r and not decoderBusy;
      
    end loop;
  end process;
  
  -- Place registers in the blockReconfig signal paths. This delays
  -- reconfiguration by one cycle, but removes the decoding logic from the
  -- paths driving the blockReconfig signals.
  block_reconf_regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        blockReconfig_ctxt    <= (others => '0');
        blockReconfig_mem     <= (others => '0');
        blockReconfig_decode  <= '1';
      elsif clkEn = '1' then
        blockReconfig_ctxt    <= cxplif2cfg_blockReconfig;
        blockReconfig_mem     <= mem2cfg_blockReconfig;
        blockReconfig_decode  <= decoderBusy;
      end if;
    end if;
  end process;
  
  -- Generate the commit signal. We commit when the decoder is done but busy_r
  -- is still high, while all the contexts with their contextsToUpdate bit set
  -- are idle.
  gen_commit: process (
    contextsToUpdate, decoderBusy, busy_r, blockReconfig_ctxt, 
    curContextEnable_r, curLastPipelaneGroupForContext_r, blockReconfig_mem,
    blockReconfig_decode
  ) is
    variable laneGroup : natural;
  begin
    
    -- Set default to 0.
    commit <= '0';
    
    if busy_r = '1' and decoderBusy = '0' then
      
      -- Commit unless we find anything which is blocking reconfiguration.
      commit <= '1';
      
      -- Do not reconfigure the first cycle where we're halting the relevant
      -- pipelanes, because at this time the blockReconfig signals are not yet
      -- guaranteed to stay low if they are low now due to the register in the
      -- path.
      if blockReconfig_decode = '1' then
        commit <= '0';
      end if;
      
      -- Block reconfiguration if the 
      for i in 2**CFG.numContextsLog2-1 downto 0 loop
        if contextsToUpdate(i) = '1' then
          if blockReconfig_ctxt(i) = '1' then
            commit <= '0';
          end if;
          if curContextEnable_r(i) = '1' then
            laneGroup := vect2uint(
              curLastPipelaneGroupForContext_r(i)(CFG.numContextsLog2-1 downto 0)
            );
            if blockReconfig_mem(laneGroup) = '1' then
              commit <= '0';
            end if;
          end if;
        end if;
      end loop;
      
    end if;
  end process;
  
  -- Generate the current configuration registers.
  cur_config_regs: process (clk) is
    variable addValMinusOne : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      if reset = '1' then
        
        -- Reset configuration is all pipelane groups connected to context 0.
        curConfiguration_r <= (others => '0');
        curContextEnable_r <= (others => '0');
        curContextEnable_r(0) <= '1';
        curLastPipelaneGroupForContext_r <= (others =>
          uint2vect(2**CFG.numLaneGroupsLog2-1, 3));
        curNumPipelaneGroupsLog2ForContext_r <= (others =>
          uint2vect(CFG.numLaneGroupsLog2, 2));
        curCoupleMatrix_r <= (others => '1');
        
        for lane in 0 to 2**CFG.numLanesLog2-1 loop
          
          -- Determine the default lane indices.
          curLaneIndex_r(lane) <= uint2vect(lane, 4);
          
          -- Determine the default PC add values.
          addValMinusOne := to_unsigned(lane * 2**SYLLABLE_SIZE_LOG2B, 32);
          addValMinusOne(cfg2pcAlignLog2(CFG)-1 downto 0) := (others => '0');
          curPcAddVal_r(lane) <= std_logic_vector(
            addValMinusOne + to_unsigned(2**cfg2pcAlignLog2(CFG), 32)
          );
          
        end loop;
        
      elsif clkEn = '1' and commit = '1' then
        
        -- Commit the new configuration.
        curConfiguration_r <= newConfiguration_r;
        curContextEnable_r <= newContextEnable_r;
        curLastPipelaneGroupForContext_r <= newLastPipelaneGroupForContext_r;
        curNumPipelaneGroupsLog2ForContext_r <= newNumPipelaneGroupsLog2ForContext_r;
        curCoupleMatrix_r <= newCoupleMatrix_r;
        curLaneIndex_r <= newLaneIndex_r;
        curPcAddVal_r <= newPcAddVal_r;
        
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Forward current configuration
  -----------------------------------------------------------------------------
  -- Forward the trivial signals.
  cfg2any_configWord <= curConfiguration_r;
  cfg2any_lastGroupForCtxt <= curLastPipelaneGroupForContext_r;
  cfg2any_coupled <= curCoupleMatrix_r;
  cfg2any_laneIndex <= curLaneIndex_r;
  cfg2any_pcAddVal <= curPcAddVal_r;
  
  -- Construct the vector containing the number of groups working together for
  -- each lane group and extract the contexts from the configuration vector.
  num_groups_per_lane_gen: process (curConfiguration_r, curNumPipelaneGroupsLog2ForContext_r) is
    variable contextBits  : rvex_3bit_type;
    variable activeBit    : std_logic;
    variable context      : natural;
  begin
    for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
      contextBits := curConfiguration_r(laneGroup*4+2 downto laneGroup*4);
      activeBit := not curConfiguration_r(laneGroup*4+3);
      cfg2any_context(laneGroup) <= contextBits;
      cfg2any_active(laneGroup) <= activeBit;
      context := vect2uint(contextBits(CFG.numContextsLog2-1 downto 0));
      cfg2any_numGroupsLog2(laneGroup) <= curNumPipelaneGroupsLog2ForContext_r(context);
    end loop;
  end process;
  
  -- Construct the decoupled vector for the cache and similar interconnect
  -- structures.
  decouple_gen: process (curCoupleMatrix_r) is
    constant LANES_PER_GROUP : natural := 2**(CFG.numLanesLog2-CFG.numLaneGroupsLog2);
  begin
    for i in 0 to 2**CFG.numLaneGroupsLog2-2 loop
      cfg2any_decouple(i) <= not curCoupleMatrix_r(i*2**CFG.numLaneGroupsLog2 + i+1);
    end loop;
    cfg2any_decouple(2**CFG.numLaneGroupsLog2-1) <= '1';
  end process;
  
end Behavioral;

