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
-- This entity contains the control logic which decodes configuration requests
-- into the signals which the various interconnect blocks and the
-- reconfiguration controller use.
-------------------------------------------------------------------------------
entity core_cfgCtrl_decode is
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
    -- Configuration request input and handshaking signals
    ---------------------------------------------------------------------------
    -- This signal describes the to-be-decoded configuration. The signal uses
    -- the encoding defined in core_ctrlRegs_pkg.vhd and is valid when the
    -- start signal is high.
    newConfiguration_in         : in  rvex_data_type;
    
    -- Start signal. Restarts the decoding state machine when high.
    start                       : in  std_logic;
    
    -- Busy signal. High while the configuration is being decoded.
    busy                        : out std_logic;
    
    -- Error signal. This goes high in the last busy cycle when the new
    -- configuration was determined to be invalid.
    error                       : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Decoded configuration control signals
    ---------------------------------------------------------------------------
    -- Returns the configuration as it was when start was high.
    newConfiguration_out        : out rvex_data_type;
    
    -- Enable (run) signal for each context.
    contextEnable               : out std_logic_vector(2**CFG.numContextsLog2-1 downto 0);
    
    -- Context to last pipelane group mapping. When there are less than 8
    -- groups, the MSBs in here will always be zero. This value may be
    -- undefined for contexts where run is low.
    lastPipelaneGroupForContext : out rvex_3bit_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- log2 of the number of groups per context for each context, used to
    -- determine PC increment value. This value may be undefined for contexts
    -- where run is low.
    numPipelaneGroupsLog2ForContext: out rvex_2bit_array(2**CFG.numContextsLog2-1 downto 0);
    
    -- Diagonal block matrix of n*n size, where n is the number of pipelane
    -- groups. C_n,m is high when pipelane group n and m are coupled/share a
    -- context, or low when they don't.
    coupleMatrix                : out std_logic_vector(4**CFG.numLaneGroupsLog2-1 downto 0)
    
  );
end core_cfgCtrl_decode;

--=============================================================================
architecture Behavioral of core_cfgCtrl_decode is
--=============================================================================
  
  -- New configuration register, stored when start is high.
  signal newConfiguration_r     : rvex_data_type;
  
  -- Group ID type. The group ID is set to either the context associated with
  -- a pipelane group or, if the pipelane group is disabled, the pipelane group
  -- index, with bit 3 also set. This is used internally when figuring out
  -- which pipelane groups work together, such that disabled pipelane groups
  -- are never incorrectly detected to work together with other pipelane
  -- groups. The size of a group ID is fixed to 4 bits, which is enough for the
  -- greatest supported number of pipelane groups and contexts (both 8).
  constant GROUP_ID_SIZE : natural := 4;
  subtype groupID_type is std_logic_vector(GROUP_ID_SIZE-1 downto 0);
  type groupID_array is array (natural range <>) of groupID_type;
  
  -- Group IDs for each pipelane group.
  signal groupIDs               : groupID_array(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Index of the pipelane group currently being evaluated. This is essentially
  -- the finite state machine state variable.
  signal currentPipelaneGroup_r : std_logic_vector(CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Next pipelane group for which to evaluate grouping.
  signal nextPipelaneGroup      : std_logic_vector(CFG.numLaneGroupsLog2-1 downto 0);
  
  -- Group ID for the current pipelane group.
  signal currentGroupID         : groupID_type;
  
  -- Group ID match signals between the current group ID and the group IDs of
  -- all the pipelane groups.
  signal groupIDMatch           : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
  
  -- log2 of the number of pipelanes sharing the current group ID.
  signal numPipelaneGroupsLog2  : std_logic_vector(1 downto 0);
  
  -- Goes high the cycle after start is high, and then stays high until
  -- decoding completes or an error occurs.
  signal busy_r                 : std_logic;
  
  -- Goes high then the decode logic detects a misalligned or discontinuous
  -- group of pipelanes sharing a group ID/context.
  signal error_s                : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Theory of operation
  -----------------------------------------------------------------------------
  -- To avoid generating all the logic needed to determine all the decoded
  -- signals combinatorially, this unit contains a state machine to do it in
  -- multiple cycles. In each cycle, a group of pipelanes associated with a
  -- single context is evaluated. This is done by looping over the pipelane
  -- groups. The context selected for the current pipelane group (which is
  -- available directly from the configuration vector) is then evaluated.
  -- Among other things, the number of pipelanes sharing the context is
  -- determined (this is needed for the branch unit) and this is used to skip
  -- looping over the pipelanes which share the same context.
  --
  -- As an example, consider a design with 4 pipelane groups, which is
  -- reconfigured to use the following pipelane group to context mapping:
  --
  --   group 0 -> context 1
  --   group 1 -> context 2
  --   group 2 -> context 3
  --   group 3 -> context 3
  --
  -- Looping over the pipelanes is done in descending order, so group 3 would
  -- be evaluated first, which means that context(group 3) = context 3 would
  -- be evaluated first. Since there are two pipelane groups sharing context 3,
  -- the next decoding iteration would evaluate group 3 - 2 = group 1, with
  -- context(group 1) = context 2, etc.
  --
  -- The context to pipelane mappings are initialized with the control signals
  -- indicating that each context has zero pipelanes paired with it (i.e.,
  -- each context starts out as disabled). When a pipelane is evaluated, the
  -- context to pipelane mappings for the context associated with that pipelane
  -- are updated.
  --
  -- When a disabled pipelane group is evaluated, no operation is performed on
  -- the context to pipelane mappings, and the next decoding cycle will
  -- evaluate the next pipelane group. Internally this is handled by
  -- associating disabled pipelanes with a non-existing context, indexed by
  -- the pipelane group index, allowing all the decoding logic to work
  -- correctly without needing extra control logic.
  
  -----------------------------------------------------------------------------
  -- Instantiate registers
  -----------------------------------------------------------------------------
  process (clk) is
    variable contextID : natural;
    constant LAST_PIPELANE_GROUP : std_logic_vector(CFG.numLaneGroupsLog2-1 downto 0) := (others => '1');
  begin
    if rising_edge(clk) then
      if reset = '1' then
        
        -- Load the configuration output for having context 0 run on all
        -- pipelanes.
        newConfiguration_r <= (others => '0');
        contextEnable <= (others => '0');
        contextEnable(0) <= '1';
        lastPipelaneGroupForContext <= (others =>
          uint2vect(2**CFG.numLaneGroupsLog2-1, 3));
        numPipelaneGroupsLog2ForContext <= (others =>
          uint2vect(CFG.numLaneGroupsLog2, 2));
        coupleMatrix <= (others => '1');
        
        -- Start idle.
        busy_r <= '0';
        currentPipelaneGroup_r <= (others => '0');
        
      elsif clkEn = '1' then
        
        if start = '1' then
          
          -- Store the new configuration for processing.
          newConfiguration_r <= newConfiguration_in;
          
          -- Reset everything when we're starting to decode.
          contextEnable <= (others => '0');
          lastPipelaneGroupForContext <= (others =>
            uint2vect(2**CFG.numLaneGroupsLog2-1, 3));
          numPipelaneGroupsLog2ForContext <= (others =>
            uint2vect(CFG.numLaneGroupsLog2, 2));
          coupleMatrix <= (others => '0');
          
          -- Start decoding.
          busy_r <= '1';
          currentPipelaneGroup_r <= (others => '1');
          
        elsif error_s = '1' then
          
          -- An error occured, stop decoding.
          busy_r <= '0';
          currentPipelaneGroup_r <= (others => '0');
          
        elsif busy_r = '1' then
          
          -- Update registers when we're busy. We always have something to
          -- update in the couple matrix, we only need to update context
          -- related registers when the current group ID maps to a context.
          if currentGroupID(GROUP_ID_SIZE-1) = '0' then
            contextID := vect2uint(currentGroupID(CFG.numContextsLog2-1 downto 0));
            
            -- Enable the context specified by the current group index.
            contextEnable(contextID) <= '1';
            
            -- Update the context control registers for the current group ID.
            lastPipelaneGroupForContext(contextID)(CFG.numLaneGroupsLog2-1 downto 0)
              <= currentPipelaneGroup_r;
            lastPipelaneGroupForContext(contextID)(2 downto CFG.numLaneGroupsLog2)
              <= (others => '0');
            numPipelaneGroupsLog2ForContext(contextID) <= numPipelaneGroupsLog2;
            
          end if;
          
          -- Update the coupled vector.
          for i in 0 to 2**CFG.numLaneGroupsLog2-1 loop
            if groupIDMatch(i) = '1' then
              coupleMatrix(
                i*2**CFG.numLaneGroupsLog2 + 2**CFG.numLaneGroupsLog2-1
                downto i*2**CFG.numLaneGroupsLog2) <= groupIDMatch;
            end if;
          end loop;
          
          -- Update the state. If the next group coming out of the subtractor
          -- is the highest indexed group again, we've finished decoding and
          -- can clear the busy flag.
          currentPipelaneGroup_r <= nextPipelaneGroup;
          if nextPipelaneGroup = LAST_PIPELANE_GROUP then
            busy_r <= '0';
          end if;
          
        end if;
        
      end if;
    end if;
  end process;
  
  -- Forward the new configuration and busy registers and error signal. Note
  -- the and gate in the error signal, ensuring that the error signal is only
  -- a one-cycle pulse.
  newConfiguration_out <= newConfiguration_r;
  error <= error_s and busy_r;
  busy <= busy_r;
  
  -----------------------------------------------------------------------------
  -- Determine next state
  -----------------------------------------------------------------------------
  next_state_gen: process (currentPipelaneGroup_r, numPipelaneGroupsLog2) is
    variable decCount: integer range 0 to 15;
  begin
    
    -- We start with the highest indexed pipelane group, so we need to count
    -- down. When a group of pipelanes has been detected, we don't need to look
    -- at the pipelanes in that group again, so we can skip over the entire
    -- group. Fortunately, groups are always aligned and (the log2 of) the size
    -- is computed already. So we can just decrement the pipelane group index
    -- by that number.
    case numPipelaneGroupsLog2 is
      when "00"   => decCount := 1;
      when "01"   => decCount := 2;
      when "10"   => decCount := 4;
      when others => decCount := 8;
    end case;
    
    -- Infer the subtractor.
    nextPipelaneGroup <=
      std_logic_vector(vect2unsigned(currentPipelaneGroup_r) - decCount);
    
  end process;
  
  -----------------------------------------------------------------------------
  -- Group ID selection and matching
  -----------------------------------------------------------------------------
  -- Generate the group IDs.
  group_id_gen: process (newConfiguration_r) is
  begin
    for i in 0 to 2**CFG.numLaneGroupsLog2-1 loop
      if newConfiguration_r(4*i+3) = '1' then
        
        -- Lane disabled, set group ID to pipelane group index, with bit 3 set.
        groupIDs(i) <= "1" & uint2vect(i, GROUP_ID_SIZE-1);
         
      else
        
        -- Lane enabled, set groupID to context.
        groupIDs(i)(GROUP_ID_SIZE-1 downto CFG.numContextsLog2) <= (others => '0');
        groupIDs(i)(CFG.numContextsLog2-1 downto 0) <=
          newConfiguration_r(4*i+CFG.numContextsLog2-1 downto 4*i);
        
      end if;
      
    end loop;
  end process;
  
  -- Generate the mux which selects the current group ID.
  currentGroupID <= groupIDs(vect2uint(currentPipelaneGroup_r));
  
  -- Generate the match units.
  match_gen: process (groupIDs, currentGroupID) is
  begin
    for i in 0 to 2**CFG.numLaneGroupsLog2-1 loop
      if groupIDs(i) = currentGroupID then
        groupIDMatch(i) <= '1';
      else
        groupIDMatch(i) <= '0';
      end if;
    end loop;
  end process;
  
  -----------------------------------------------------------------------------
  -- Lanes per context and alignment detection
  -----------------------------------------------------------------------------
  -- Detect the number of lanes used for the currently selected context, and
  -- whether the lane selection range is properly aligned and continuous.
  process (groupIDMatch) is
    
    -- Among other things, this will instantiate a binary tree network. The
    -- edges between the nodes in the tree contain the following signals.
    type edge_type is record
      
      -- High when any pipelane in this group is associated with the current
      -- group ID.
      anyMatch    : std_logic;
      
      -- High when all pipelanes in this group is associated with the current
      -- group ID.
      allMatch    : std_logic;
      
      -- High when a configuration error is detected.
      error       : std_logic;
      
    end record;
    
    -- Array type for the edges in the binary tree.
    type edge_array is array (natural range <>) of edge_type;
    
    -- Array of edges in the binary tree. We will be re-using this variable
    -- for the interconnect between every two levels in the binary tree to
    -- keep the indexes comprehensible; the synthesizer should be able to
    -- properly unroll the loop and figure out how to convert to single
    -- assignment.
    variable edges              : edge_array(0 to 2**CFG.numLaneGroupsLog2-1);
    
    -- Temporary copies of the edge input signals for a node.
    variable in1, in2           : edge_type;
    
    -- This variable will keep track of whether there are any full groups
    -- left after this level in the tree. Then, a priority decoder can be
    -- used on this signal for every level to determine the logarithm of the
    -- number of lane groups selected.
    variable anyFullGroup: std_logic;
    
  begin
    
    -- Connect the first level of the tree.
    for i in 0 to 2**CFG.numLaneGroupsLog2-1 loop
      edges(i).anyMatch := groupIDMatch(i);
      edges(i).allMatch := groupIDMatch(i);
      edges(i).error    := '0';
    end loop;
    
    -- Set the log2 of the number of pipelane groups sharing this context to
    -- 0 as a default to not infer a latch when none of the pipelane groups
    -- use this context. That should never happen, but the synthesizer might
    -- very well not know that.
    numPipelaneGroupsLog2 <= (others => '0');
    
    -- Describe the binary tree.
    for lvl in 0 to CFG.numLaneGroupsLog2-1 loop
      
      -- Initialize anyFullGroup to low so we can generate an n-input or gate.
      anyFullGroup := '0';
      
      -- Loop over all the nodes in this binary tree level.
      for i in 0 to 2**((CFG.numLaneGroupsLog2-1)-lvl)-1 loop
        
        -- Make copies of the input nodes, so we can write to the output for
        -- the next layer without overriding the input.
        in1 := edges(i*2);
        in2 := edges(i*2 + 1);
        
        -- Merge the anySelected and allSelected signals trivially.
        edges(i).anyMatch :=
          in1.anyMatch or in2.anyMatch;
        
        edges(i).allMatch :=
          in1.allMatch and in2.allMatch;
        
        -- The error signal should be asserted when a non-empty, non-full group
        -- is being merged with a non-empty group.
        edges(i).error :=
          in1.error or in2.error or (
            ((in1.anyMatch and not in1.allMatch) and in2.anyMatch) or
            ((in2.anyMatch and not in2.allMatch) and in1.anyMatch)
          );
        
        -- Pull anyFullGroup up when this group is full.
        anyFullGroup := anyFullGroup or edges(i).allMatch;
        
      end loop;
      
      -- Instantiate the priority encoder for anyFullGroup, in conjunction with
      -- the default value for size set just before the lvl loop.
      if anyFullGroup = '1' then
        numPipelaneGroupsLog2 <= uint2vect(lvl + 1, 2);
      end if;
      
    end loop;
    
    -- Drive the error output signal.
    error_s <= edges(0).error;
    
  end process;

end Behavioral;

