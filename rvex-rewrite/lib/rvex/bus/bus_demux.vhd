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
use IEEE.math_real.all;

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.simutils_pkg.all;
use rvex.bus_pkg.all;
use rvex.bus_addrConv_pkg.all;

--=============================================================================
-- Splits the bus coming from a master up into a number of slave busses, which
-- are selected based upon the address. It allows the slave addresses to be
-- transformed according to a mapping as specified in bus_addrConv_pkg.
-------------------------------------------------------------------------------
entity bus_demux is
--=============================================================================
  generic (
    
    -- Defines the ranges and address mappings for each slave, and
    -- implcicitely, the number of slaves.
    ADDRESS_MAP                 : addrRangeAndMapping_array;
    
    -- When the master attempts to access undefined memory, the following 
    -- fault code is returned.
    OOR_FAULT_CODE              : rvex_data_type := (others => '1');
    
    -- When true, only one slave bus is active at the same time. If multiple
    -- slave address ranges match the requested address, the highest indexed
    -- matching slave is used. When this is set to false, extra logic is
    -- instantiated to ensure that all matching slaves get the command, and
    -- that the bus result is properly merged.
    MUTUALLY_EXCLUSIVE          : boolean := true
    
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
    -- Busses
    ---------------------------------------------------------------------------
    -- Incoming bus from the master.
    mst2demux                   : in  bus_mst2slv_type;
    demux2mst                   : out bus_slv2mst_type;
    
    -- Outgoing busses to the slaves.
    demux2slv                   : out bus_mst2slv_array(ADDRESS_MAP'range);
    slv2demux                   : in  bus_slv2mst_array(ADDRESS_MAP'range)
    
  );
end bus_demux;

--=============================================================================
architecture Behavioral of bus_demux is
--=============================================================================
  
  -- Number of slave busses.
  constant NUM_SLAVES           : natural := ADDRESS_MAP'length;
  
  -- log2 of the number of slave busses + 1; defines the width of the select
  -- signal for the (de)muxes. The extra option is needed for when an
  -- out-of-range address is requested.
  constant SEL_LOG2             : natural := integer(ceil(log2(real(NUM_SLAVES + 1))));
  
begin
  
  --===========================================================================
  -- Architecture for when only one slave is active at a time
  --===========================================================================
  mutually_exclusive_gen: if MUTUALLY_EXCLUSIVE generate
    
    -- Index of the selected bus, valid while the bus request is valid.
    signal selectRequest          : std_logic_vector(SEL_LOG2-1 downto 0);
    
    -- Index of the selected bus, valid after the bus request (so while the
    -- slave is busy and while the result is valid).
    signal selectResult           : std_logic_vector(SEL_LOG2-1 downto 0);
    
    -- Local signal for the muxed busy flag, as returned to the master.
    signal busy                   : std_logic;
    
  begin
  
    ---------------------------------------------------------------------------
    -- Determine which slave should be accessed
    ---------------------------------------------------------------------------
    select_request_proc: process (mst2demux) is
    begin
      
      -- Choose out-of-range by default so we generate a fault when the code
      -- below does not find a slave which the request belongs to, unless the
      -- master is not requesting anything, in which case we should not
      -- generate a fault.
      if bus_requesting(mst2demux) = '1' then
        selectRequest <= uint2vect(NUM_SLAVES, SEL_LOG2);
      else
        selectRequest <= uint2vect(0, SEL_LOG2);
      end if;
      
      -- Check if the address is in any of the ranges of the slaves; if so,
      -- select that slave bus instead.
      for i in 0 to NUM_SLAVES-1 loop
        if isAddrInRange(
          mst2demux.address,
          ADDRESS_MAP(ADDRESS_MAP'low + i).addrRange
        ) then
          selectRequest <= uint2vect(i, SEL_LOG2);
        end if;
      end loop;
      
    end process;
    
    -- Delay the selectRequest signal to align it with the result.
    select_result_proc: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          selectResult <= (others => '0');
        elsif busy = '0' and clkEn = '1' then
          selectResult <= selectRequest;
        end if;
      end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Perform command demuxing
    ---------------------------------------------------------------------------
    command_demux_proc: process (mst2demux, selectRequest) is
      variable req  : bus_mst2slv_type;
    begin
      for i in 0 to NUM_SLAVES-1 loop
        
        -- Copy the master bus request while gating the enable signals to
        -- prevent unaddressed slaves from executing a command.
        req := bus_gate(mst2demux, vect2uint(selectRequest) = i);
        
        -- Transform the slave address.
        req.address := applyAddrMap(
          mst2demux.address,
          ADDRESS_MAP(i + ADDRESS_MAP'low).addrMapping
        );
        
        -- Drive the output signal.
        demux2slv(i + demux2slv'low) <= req;
        
      end loop;
    end process;
    
    ---------------------------------------------------------------------------
    -- Perform result muxing
    ---------------------------------------------------------------------------
    result_mux_proc: process (slv2demux, selectResult) is
      variable muxed  : bus_slv2mst_type;
    begin
      
      if vect2uint(selectResult) < NUM_SLAVES then
        
        -- Select the result data from the selected slave bus.
        muxed := slv2demux(vect2uint(selectResult) + slv2demux'low);
        
      else
        
        -- Raise the bus fault specified for out-of-range accesses.
        muxed           := BUS_SLV2MST_IDLE;
        muxed.readData  := OOR_FAULT_CODE;
        muxed.fault     := '1';
        muxed.busy      := '0';
        muxed.ack       := '1';
        
      end if;
      
      -- Drive output signals.
      demux2mst <= muxed;
      busy <= muxed.busy;
      
    end process;
    
  end generate;
  
  --===========================================================================
  -- Architecture for when multiple slaves may be active at a time.
  --===========================================================================
  not_mutually_exclusive_gen: if not MUTUALLY_EXCLUSIVE generate
    
    -- Index of the selected bus, valid while the bus request is valid.
    signal selectRequest          : std_logic_vector(NUM_SLAVES-1 downto 0);
    
    -- Index of the selected bus, valid after the bus request (so while the
    -- slave is busy and while the result is valid).
    signal selectResult           : std_logic_vector(NUM_SLAVES-1 downto 0);
    
    -- Mux signal for the readData and fault signals.
    signal resultMux              : std_logic_vector(SEL_LOG2-1 downto 0);
    
    -- This signal is asserted when the master was requesting something in the
    -- previous cycle.
    signal requesting_r           : std_logic;
    
    -- This signal is set when any of the addressed slave busses are busy.
    signal busy                   : std_logic;
    
  begin
  
    ---------------------------------------------------------------------------
    -- Determine which slave should be accessed
    ---------------------------------------------------------------------------
    select_request_proc: process (mst2demux) is
    begin
      
      -- For each slave, check if the address is in the specified range, and if
      -- so, select that slave.
      for i in 0 to NUM_SLAVES-1 loop
        if isAddrInRange(
          mst2demux.address,
          ADDRESS_MAP(ADDRESS_MAP'low + i).addrRange
        ) then
          selectRequest(i) <= '1';
        else
          selectRequest(i) <= '0';
        end if;
      end loop;
      
    end process;
    
    -- Delay the selectRequest signal to align it with the result.
    select_result_proc: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          selectResult <= (others => '0');
          requesting_r <= '0';
        elsif busy = '0' and clkEn = '1' then
          selectResult <= selectRequest;
          requesting_r <= bus_requesting(mst2demux);
        end if;
      end if;
    end process;
    
    ---------------------------------------------------------------------------
    -- Perform command demuxing
    ---------------------------------------------------------------------------
    command_demux_proc: process (mst2demux, selectRequest) is
      variable req  : bus_mst2slv_type;
    begin
      for i in 0 to NUM_SLAVES-1 loop
        
        -- Copy the master bus request while gating the enable signals to
        -- prevent unaddressed slaves from executing a command.
        req := bus_gate(mst2demux, selectRequest(i));
        
        -- Transform the slave address.
        req.address := applyAddrMap(
          mst2demux.address,
          ADDRESS_MAP(i + ADDRESS_MAP'low).addrMapping
        );
        
        -- Drive the output signal.
        demux2slv(i + demux2slv'low) <= req;
        
      end loop;
    end process;
    
    ---------------------------------------------------------------------------
    -- Generate busy signal
    ---------------------------------------------------------------------------
    -- The busy signal is high when any of the selected slaves are busy.
    busy_proc: process (slv2demux, selectResult) is
    begin
      busy <= '0';
      for slv in 0 to NUM_SLAVES-1 loop
        if selectResult(slv) = '1' and slv2demux(slv).busy = '1' then
          busy <= '1';
        end if;
      end loop;
    end process;
    
    ---------------------------------------------------------------------------
    -- Perform result muxing
    ---------------------------------------------------------------------------
    -- Generate the mux select signal. This must be set to one of the addressed
    -- slaves which has ack set.
    result_sel_proc: process (slv2demux, selectResult) is
    begin
      if vect2unsigned(selectResult) = 0 then
        
        -- None of the slaves is addressed; select fault output.
        resultMux <= uint2vect(NUM_SLAVES, SEL_LOG2);
        
      else
        
        -- Select any slave as default value; this is don't care.
        resultMux <= uint2vect(0, SEL_LOG2);
        
      end if;
      
      -- If any of the selected slaves are acknowledging the command, select
      -- that slave.
      for slv in 0 to NUM_SLAVES-1 loop
        if selectResult(slv) = '1' and slv2demux(slv).ack = '1' then
          resultMux <= uint2vect(slv, SEL_LOG2);
        end if;
      end loop;
      
    end process;
    
    -- Instantiate the mux.
    result_mux_proc: process (slv2demux, resultMux, busy, requesting_r) is
      variable muxed  : bus_slv2mst_type;
    begin
      
      if vect2uint(resultMux) < NUM_SLAVES then
        
        -- Select the result data from the selected slave bus.
        muxed := slv2demux(vect2uint(resultMux) + slv2demux'low);
        
        -- When any of the slaves are busy, we need to set the handshaking
        -- signal state to busy.
        muxed.busy := busy;
        muxed.ack  := muxed.ack and not busy;
        
      else
        
        -- Raise the bus fault specified for out-of-range accesses.
        muxed           := BUS_SLV2MST_IDLE;
        muxed.readData  := OOR_FAULT_CODE;
        muxed.fault     := '1';
        muxed.busy      := '0';
        muxed.ack       := requesting_r;
        
      end if;
      
      -- Drive output signals.
      demux2mst <= muxed;
      
    end process;
    
  end generate;
  
end Behavioral;

