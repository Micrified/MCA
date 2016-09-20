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
-- This entity contains the general purpose register file and associated
-- forwarding logic.
-------------------------------------------------------------------------------
entity core_instructionBuffer is
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
    
    -- Active high stall signal for each lane group.
    stall                       : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -----------------------------------------------------------------------------
    -- Decoded configuration signals
    -----------------------------------------------------------------------------
    -- log2 of the number of coupled pipelane groups for each pipelane group.
    cfg2any_numGroupsLog2       : in  rvex_2bit_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Instruction memory interface
    ---------------------------------------------------------------------------
    -- Fetch addresses from each pipelane group.
    ibuf2imem_PCs               : out rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Active high instruction fetch enable signal. When a bit in this vector
    -- is high, stall is low and the bit in mem_decouple is high, the
    -- instruction memory must fetch the instruction pointed to by the
    -- associated vector in PCs.
    ibuf2imem_fetch             : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Combinatorial cancel signal, valid one cycle after PCs and fetch,
    -- regardless of memory stalls. This will go high when a branch is detected
    -- by the next pipeline stage and the previously requested instruction is
    -- not going to be executed. In this case, the instruction memory may
    -- choose not to complete the request if that is faster somehow (a cache 
    -- may choose to cancel line validation if a miss occured to allow the core
    -- to continue earlier). Note that this signal can be safely ignored for
    -- proper operation, it's just a hint which may be used to speed things up.
    ibuf2imem_cancel            : out std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Fetched instruction.
    imem2ibuf_instr             : in  rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Exception input from the instruction memory. When active, instr is
    -- assumed to be invalid and the specified trap is thrown.
    imem2ibuf_exception         : in  trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    ---------------------------------------------------------------------------
    -- Pipelane interface
    ---------------------------------------------------------------------------
    -- Potentially misaligned PC addresses for each group, to be accounted for
    -- by the instruction buffer.
    cxplif2ibuf_PCs             : in  rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Properly aligned addresses for each group which need to be fetched. This
    -- is the value of PCs rounded down when branch is high or rounded up when
    -- branch is low.
    cxplif2ibuf_fetchPCs        : in  rvex_address_array(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Whether the current fetch is nonconsequitive w.r.t. the previous fetch.
    cxplif2ibuf_branch          : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Fetch enable signal from the pipelane groups.
    cxplif2ibuf_fetch           : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Cancel signal from the pipelane groups. This is intended to go high
    -- combinatorially when the previously requested instruction is not going
    -- to be used, for instance due to a branch. This is a bit broken though,
    -- because a memory operation affecting the branch signal which is used
    -- to determine whether to branch may not be valid immediately, and may
    -- thus cancel a fetch even if the branch is not going to be taken after
    -- all. Thus, we're ignoring this and outputting '0' for ibuf2imem_cancel
    -- until further notice.
    cxplif2ibuf_cancel          : in  std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
    -- Fetched instruction.
    ibuf2pl_instr               : out rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
    
    -- Exception output. When active, instr is invalid and a trap should be
    -- issued.
    ibuf2pl_exception           : out trap_info_array(2**CFG.numLaneGroupsLog2-1 downto 0)
    
  );
end core_instructionBuffer;

--=============================================================================
architecture Behavioral of core_instructionBuffer is
--=============================================================================
  
  -- Instruction buffer register.
  signal instrBuf               : rvex_syllable_array(2**CFG.numLanesLog2-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Ensure that L_IF (the instruction fetch latency as seen by the pipelanes)
  -- is set to 1; the actual memory latency (L_IF_MEM) is hidden from the
  -- pipelanes here.
  assert L_IF = 1
    report "L_IF must be set to 1 in core_pipeline_pkg.vhd when the "
         & "instruction buffer is used."
    severity failure;
  
  assert L_IF_MEM = 1
    report "L_IF_MEM must be set to 1 because apparently different values "
         & "were never actually implemented."
    severity failure;
  
  -- Forward the signals which we don't have to do anything with.
  ibuf2imem_PCs     <= cxplif2ibuf_fetchPCs;
  ibuf2imem_fetch   <= cxplif2ibuf_fetch;
  ibuf2imem_cancel  <= cxplif2ibuf_cancel;
  ibuf2pl_exception <= imem2ibuf_exception;
  
  -----------------------------------------------------------------------------
  -- Instruction buffer register
  -----------------------------------------------------------------------------
  -- The instruction buffer register holds the previously fetched instruction.
  -- Storing this previous fetch result only has to work correctly in normal
  -- operation without branches or cycles without a fetch, because the branch
  -- unit will ensure that instructions fetched where these requirements are
  -- not met and the buffer is actually used (it's not for aligned accesses,
  -- even if a branch is involved) are properly invalidated. Because of these
  -- assumptions, we can detect when the fetch address changes (and thus need
  -- to assert the register write enable) by just looking at the LSB of the
  -- aligned fetch address. This will toggle for every new access, because it
  -- always has one added to it.
  ibuf_block: block is
    
    -- Relevant bits from the PC, used to determine when to load the registers.
    signal PC_LSB               : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    signal PC_LSB_r             : std_logic_vector(2**CFG.numLaneGroupsLog2-1 downto 0);
    
  begin
    
    -- Determine which PC bit to use to detect when to load the registers. This
    -- depends on the configuration.
    instr_buf_ctrl_proc: process (cxplif2ibuf_fetchPCs, cfg2any_numGroupsLog2) is
    begin
      for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
        PC_LSB(laneGroup) <= cxplif2ibuf_fetchPCs(laneGroup)(
          SYLLABLE_SIZE_LOG2B + CFG.numLanesLog2 - CFG.numLaneGroupsLog2
          + vect2uint(cfg2any_numGroupsLog2(laneGroup))
        );
      end loop;
    end process;
    
    -- Instantiate the registers.
    instr_buf_proc: process (clk) is
      variable laneGroup: natural;
    begin
      if rising_edge(clk) then
        if clkEn = '1' then
          for laneGroup in 0 to 2**CFG.numLaneGroupsLog2-1 loop
            if stall(laneGroup) = '0' then
              PC_LSB_r(laneGroup) <= PC_LSB(laneGroup);
              if PC_LSB_r(laneGroup) /= PC_LSB(laneGroup) then
                for lane in group2firstLane(laneGroup, CFG) to group2lastLane(laneGroup, CFG) loop
                  instrBuf(lane) <= imem2ibuf_instr(lane);
                end loop;
              end if;
            end if;
          end loop;
        end if;
        
        -- Not having a reset here might make the register a bit smaller. We'll
        -- want to ensure that its value is never used after a reset before the
        -- register is loaded however. So in simulation, reset it with undefined.
        -- pragma translate_off
        if reset = '1' then
          instrBuf <= (others => (others => RVEX_UNDEF));
          PC_LSB_r <= (others => '0');
        end if;
        -- pragma translate_on
        
      end if;
    end process;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Instruction mux
  -----------------------------------------------------------------------------
  -- The instruction mux behaves somewhat like a shifter. As an example, for
  -- the finest granularity in 8-way mode, the mux options look like this:
  --
  -- mux    | 001     010     011     100     101     110     111     000
  -- -------+----------------------------------------------------------------
  -- Lane 0 | buf(1)  buf(2)  buf(3)  buf(4)  buf(5)  buf(6)  buf(7)  mem(0)
  -- Lane 1 | buf(2)  buf(3)  buf(4)  buf(5)  buf(6)  buf(7)  mem(0)  mem(1)
  -- Lane 2 | buf(3)  buf(4)  buf(5)  buf(6)  buf(7)  mem(0)  mem(1)  mem(2)
  -- Lane 3 | buf(4)  buf(5)  buf(6)  buf(7)  mem(0)  mem(1)  mem(2)  mem(3)
  -- Lane 4 | buf(5)  buf(6)  buf(7)  mem(0)  mem(1)  mem(2)  mem(3)  mem(4)
  -- Lane 5 | buf(6)  buf(7)  mem(0)  mem(1)  mem(2)  mem(3)  mem(4)  mem(5)
  -- Lane 6 | buf(7)  mem(0)  mem(1)  mem(2)  mem(3)  mem(4)  mem(5)  mem(6)
  -- Lane 7 | mem(0)  mem(1)  mem(2)  mem(3)  mem(4)  mem(5)  mem(6)  mem(7)
  --
  -- Note that 000 is drawn in the last column instead of the first, because
  -- it represents 1000 in terms of shift amount.
  --
  -- When lane groups are decoupled, we still only need those options. However,
  -- decoding becomes a little tricky. For example, in 2x4 way, the following
  -- options are needed.
  --
  -- mux    | 000     001     010     011     100     101     110     111
  -- -------+----------------------------------------------------------------
  -- Lane 0 | mem(0)  buf(1)  buf(2)  buf(3)
  -- Lane 1 | mem(1)  buf(2)  buf(3)                                  mem(0)
  -- Lane 2 | mem(2)  buf(3)                                  mem(0)  mem(1)
  -- Lane 3 | mem(3)                                  mem(0)  mem(1)  mem(2)
  -- Lane 4 | mem(4)  buf(5)  buf(6)  buf(7)
  -- Lane 5 | mem(5)  buf(6)  buf(7)                                  mem(4)
  -- Lane 6 | mem(6)  buf(7)                                  mem(4)  mem(5)
  -- Lane 7 | mem(7)                                  mem(4)  mem(5)  mem(6)
  --
  -- The LSBs are still dependent on the PC just like in 8-way mode, but the
  -- MSBs cannot just be tied to zero or something else convenient. They are
  -- magic, to get the above diagram. In stead of trying to explain this
  -- constructively (which I can't because I was just applying trial and error)
  -- observe that a useful pattern emerges when comparing with the one's
  -- complement of the relevant PC bits.
  --
  -- mux    | 000     001     010     011     100     101     110     111
  -- -------+----------------------------------------------------------------
  -- Lane 0 | ~PC=11  ~PC=10  ~PC=01  ~PC=00
  -- Lane 1 | ~PC=11  ~PC=10  ~PC=01                                  ~PC=00
  -- Lane 2 | ~PC=11  ~PC=10                                  ~PC=01  ~PC=00
  -- Lane 3 | ~PC=11                                  ~PC=10  ~PC=01  ~PC=00
  -- Lane 4 | ~PC=11  ~PC=10  ~PC=01  ~PC=00
  -- Lane 5 | ~PC=11  ~PC=10  ~PC=01                                  ~PC=00
  -- Lane 6 | ~PC=11  ~PC=10                                  ~PC=01  ~PC=00
  -- Lane 7 | ~PC=11                                  ~PC=10  ~PC=01  ~PC=00
  -- 
  -- As we can see, the MSB of the mux signal can be tied to ~PC < lane index.
  -- 
  -- It's also worth noting that, while this is difficult to describe
  -- algorithmically, it easily fits in a single LUT for each bit. In the most
  -- fine-grained version 5:1 LUTs suffice (2 bits for cfg2any_numGroupsLog2
  -- and the 3 relevant PC bits). To make sure that the synthesis tools
  -- recognize this, we just model it as a ROM.
  mux_block: block is
    
    -- Size if the instruction mux.
    constant MUX_SIZE_LOG2      : natural := CFG.numLanesLog2 - CFG.bundleAlignLog2;
    
    -- Mux selection signal type.
    subtype mux_type is std_logic_vector(MUX_SIZE_LOG2-1 downto 0);
    type mux_array is array (natural range <>) of mux_type;
    
    -- Mux selection control signal for each lane.
    signal mux                  : mux_array(2**CFG.numLanesLog2-1 downto 0);
    
  begin
    
    -- Instantiate the control logic for the mux. Because the muxing is done
    -- one cycle after the PCs are valid (because the fetch takes one cycle)
    -- we need a cycle delay in the mux signal. We can do this by just making
    -- this process sequential.
    instr_mux_ctrl_proc: process (clk) is
      
      -- Lookup table type.
      subtype lookupTable_type is mux_array(0 to 2**(MUX_SIZE_LOG2+2)-1);
      type lookupTable_array is array (natural range <>) of lookupTable_type;
      subtype lookupTables_type is lookupTable_array(0 to 2**CFG.numLanesLog2-1);
      
      -- Generates the values for the lookup tables. The configuration
      -- (cfg2any_numGroupsLog2) makes up the two MSBs of the index; the rest
      -- is assumed to be the PC bits.
      function constructTables return lookupTables_type is
        variable ret            : lookupTables_type;
        variable addr           : natural;
        variable i              : integer;
      begin
        for lane in 0 to 2**CFG.numLanesLog2-1 loop
          for numGroupsLog2 in 0 to 3 loop
            i := numGroupsLog2
               + (CFG.numLanesLog2 - CFG.numLaneGroupsLog2)
               - CFG.bundleAlignLog2;
            if i < 0 then
              i := 0;
            elsif i >= MUX_SIZE_LOG2 then
              i := MUX_SIZE_LOG2;
            end if;
            for PC in 0 to 2**MUX_SIZE_LOG2-1 loop
              addr := numGroupsLog2*2**MUX_SIZE_LOG2 + PC;
              ret(lane)(addr) := uint2vect(PC, MUX_SIZE_LOG2);
              if (((2**MUX_SIZE_LOG2-1) - PC) mod 2**i) < ((lane / 2**CFG.bundleAlignLog2) mod 2**i) then
                ret(lane)(addr)(MUX_SIZE_LOG2-1 downto i) := (others => '1');
              else
                ret(lane)(addr)(MUX_SIZE_LOG2-1 downto i) := (others => '0');
              end if;
            end loop;
          end loop;
        end loop;
        return ret;
      end constructTables;
      
      -- Lookup table constant.
      constant lookupTable      : lookupTables_type := constructTables;
      
      -- Lookup table address.
      variable addr             : std_logic_vector(MUX_SIZE_LOG2+1 downto 0);
      
    begin
      if rising_edge(clk) then
        if clkEn = '1' then
          for lane in 0 to 2**CFG.numLanesLog2-1 loop
            if stall(lane2group(lane, CFG)) = '0' then
              
              -- Load the relevant part of the PC.
              addr(MUX_SIZE_LOG2-1 downto 0) := cxplif2ibuf_PCs(lane2group(lane, CFG))(
                CFG.numLanesLog2 + SYLLABLE_SIZE_LOG2B - 1 downto
                CFG.bundleAlignLog2 + SYLLABLE_SIZE_LOG2B
              );
              
              -- Load the configuration.
              addr(MUX_SIZE_LOG2+1 downto MUX_SIZE_LOG2)
                := cfg2any_numGroupsLog2(lane2group(lane, CFG));
              
              -- Perform the table lookup.
              mux(lane) <= lookupTable(lane)(vect2uint(addr));
              
            end if;
          end loop;
        end if;
      end if;
    end process;
    
    -- Instantiate the actual mux.
    instr_mux_proc: process (mux, instrBuf, imem2ibuf_instr) is
      variable index  : unsigned(CFG.numLanesLog2 downto 0);
    begin
      for lane in 0 to 2**CFG.numLanesLog2-1 loop
        
        -- Determine the index from the lane index and mux signal.
        index(CFG.numLanesLog2-1 downto CFG.bundleAlignLog2)
          := unsigned(mux(lane));
        index(CFG.bundleAlignLog2-1 downto 0)
          := (others => '0');
        if unsigned(mux(lane)) = 0 then
          index(CFG.numLanesLog2) := '1';
        else
          index(CFG.numLanesLog2) := '0';
        end if;
        index := index + to_unsigned(lane, CFG.numLanesLog2+1);
        
        -- Perform the muxing.
        if index(CFG.numLanesLog2) = '1' then
          ibuf2pl_instr(lane) <= imem2ibuf_instr(
            to_integer(index(CFG.numLanesLog2-1 downto 0))
          );
        else
          ibuf2pl_instr(lane) <= instrBuf(
            to_integer(index(CFG.numLanesLog2-1 downto 0))
          );
        end if;
        
      end loop;
    end process;
    
  end block;
  
end Behavioral;

