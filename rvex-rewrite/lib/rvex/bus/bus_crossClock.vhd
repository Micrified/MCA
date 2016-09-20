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
use rvex.bus_pkg.all;

--=============================================================================
-- Clock-domain crossing for the rvex bus.
-------------------------------------------------------------------------------
entity bus_crossClock is
--=============================================================================
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high asynchronous reset input for the synchronization logic. This
    -- must be released a couple cycles before the master starts sending
    -- requests, or it can be left disconnected.
    reset                       : in  std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- Master bus
    ---------------------------------------------------------------------------
    -- Clock input, registers are rising edge triggered.
    mst_clk                     : in  std_logic;
    
    -- Active high global clock enable input.
    mst_clkEn                   : in  std_logic := '1';
    
    -- Bus signals.
    mst2crclk                   : in  bus_mst2slv_type;
    crclk2mst                   : out bus_slv2mst_type;
    
    ---------------------------------------------------------------------------
    -- Slave bus
    ---------------------------------------------------------------------------
    -- Clock input, registers are rising edge triggered.
    slv_clk                     : in  std_logic;
    
    -- Active high global clock enable input.
    slv_clkEn                   : in  std_logic := '1';
    
    -- Bus signals.
    crclk2slv                   : out bus_mst2slv_type;
    slv2crclk                   : in  bus_slv2mst_type
        
  );
end bus_crossClock;

--=============================================================================
architecture Behavioral of bus_crossClock is
--=============================================================================
  
  -- Master to slave control and data signals. req_reg is clocked by mst_clk,
  -- req_sync is clocked by slv_clk.
  signal req_reg, req_sync      : bus_mst2slv_type;
  
  -- Slave to master reply. res_reg is clocked by slv_clk, res_sync is clocked
  -- by mst_clk.
  signal res_reg, res_sync      : bus_slv2mst_type;
  
  -- In-control and release-control signals from the synchronization state
  -- machine.
  signal mst_inControl          : std_logic;
  signal slv_inControl          : std_logic;
  signal mst_release            : std_logic;
  signal slv_release            : std_logic;
  
  -- Busy flag register for the master.
  signal mst_busy               : std_logic;
  
begin
  
  -----------------------------------------------------------------------------
  -- Master clock domain
  -----------------------------------------------------------------------------
  -- Release control in the first cycle of a request.
  mst_release <= bus_requesting(mst2crclk) and not mst_busy;
  
  -- Generate the busy register.
  mst_ctrl_regs: process (reset, mst_clk) is
  begin
    if reset = '1' then
      mst_busy <= '0';
    elsif rising_edge(mst_clk) then
      if mst_clkEn = '1' then
        if mst_release = '1' then
          mst_busy <= '1';
        elsif mst_inControl = '1' then
          mst_busy <= '0';
        end if;
      end if;
    end if;
  end process;
  
  -- Generate the bus result signal.
  mst_bus_res_proc: process (mst_busy, req_reg, res_sync) is
  begin
    crclk2mst <= res_sync;
    crclk2mst.busy <= mst_busy;
    crclk2mst.ack <= bus_requesting(req_reg) and not mst_busy;
  end process;
  
  -----------------------------------------------------------------------------
  -- Synchronization
  -----------------------------------------------------------------------------
  -- Control signal synchronization.
  ctrl_sync: entity rvex.utils_sync
    port map (
      reset                     => reset,
      a_clk                     => mst_clk,
      a_clkEn                   => mst_clkEn,
      a_inControl               => mst_inControl,
      a_release                 => mst_release,
      b_clk                     => slv_clk,
      b_clkEn                   => slv_clkEn,
      b_inControl               => slv_inControl,
      b_release                 => slv_release
    );
  
  -- Data signal synchronization, master clock domain.
  mst_sync_proc: process (reset, mst_clk) is
  begin
    if reset = '1' then
      req_reg  <= BUS_MST2SLV_IDLE;
      res_sync <= BUS_SLV2MST_IDLE;
    elsif rising_edge(mst_clk) then
      if mst_clkEn = '1' then
        req_reg  <= mst2crclk;
        res_sync <= res_reg;
      end if;
    end if;
  end process;
  
  -- Data signal synchronization, slave clock domain.
  slv_sync_proc: process (reset, slv_clk) is
  begin
    if reset = '1' then
      req_sync <= BUS_MST2SLV_IDLE;
      res_reg  <= BUS_SLV2MST_IDLE;
    elsif rising_edge(slv_clk) then
      if slv_clkEn = '1' then
        req_sync <= req_reg;
        if slv2crclk.ack = '1' then
          res_reg  <= slv2crclk;
        end if;
      end if;
    end if;
  end process;
  
  -----------------------------------------------------------------------------
  -- Slave clock domain
  -----------------------------------------------------------------------------
  -- Forward the bus request if it is valid and ack is low.
  crclk2slv <= bus_gate(req_sync, slv_inControl and not slv2crclk.ack);
  
  -- Release control when the slave acknowledges the request.
  slv_release <= slv2crclk.ack;
  
end Behavioral;

