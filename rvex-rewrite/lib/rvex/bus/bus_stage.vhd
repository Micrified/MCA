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

--=============================================================================
-- Adds registers between the master and slave busses. Each access will be two
-- cycles slower, but there are no combinatorial paths between the two busses,
-- so this can be used to break a critical path.
--
-- Timing diagram for clarity:
--          |__    __    __    __    __    __    __    __    __    __    |
--      clk |  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/|
--          |                                                            |
--  req_mst |nop==><val1============><val2==================><nop========|
--          |                                                            |
--  res_mst |------------------------<val1>------------------<val2>------|
--          |             ___________       _________________            |
-- busy_mst |____________/           \_____/                 \___________|
--          |                         _____                   _____      |
--  ack_mst |________________________/     \_________________/     \_____|
--          |                                                            |
--  req_slv |nop========><val1><nop=======><val2======><nop==============|
--          |                                                            |
--  res_slv |------------------<val1>------------------<val2>------------|
--          |                                     _____                  |
-- busy_slv |____________________________________/     \_________________|
--          |                   _____                   _____            |
--  ack_slv |__________________/     \_________________/     \___________|
--          |                                                            |
-------------------------------------------------------------------------------
entity bus_stage is
--=============================================================================
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
    mst2stage                   : in  bus_mst2slv_type;
    stage2mst                   : out bus_slv2mst_type;
    
    -- Outgoing bus to the slave.
    stage2slv                   : out bus_mst2slv_type;
    slv2stage                   : in  bus_slv2mst_type
    
  );
end bus_stage;

--=============================================================================
architecture Behavioral of bus_stage is
--=============================================================================
  
  -- Registered input signals.
  signal mst2stage_r            : bus_mst2slv_type;
  signal slv2stage_r            : bus_slv2mst_type;
  
begin
  
  -- Register all input signals to break all combinatorial paths.
  regs: process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        mst2stage_r <= BUS_MST2SLV_IDLE;
        slv2stage_r <= BUS_SLV2MST_IDLE;
      elsif clkEn = '1' then
        mst2stage_r <= mst2stage;
        slv2stage_r <= slv2stage;
      end if;
    end if;
  end process;
  
  -- Combinatorial logic stuff.
  comb: process (mst2stage_r, slv2stage_r, slv2stage.ack) is
    variable stage2slv_v: bus_mst2slv_type;
    variable stage2mst_v: bus_slv2mst_type;
  begin
    
    -- The request line needs to be nopped out when either bus is acknowledging
    -- the request. Otherwise it can just be the delayed signal from the
    -- master.
    stage2slv_v := bus_gate(mst2stage_r, not (slv2stage_r.ack or slv2stage.ack));
    
    -- The result line is mostly just delayed by one cycle. Only the busy
    -- signal needs to be changed. This can just be derived from the ack signal
    -- and the request.
    stage2mst_v := slv2stage_r;
    stage2mst_v.busy := bus_requesting(mst2stage_r) and not slv2stage_r.ack;
    
    stage2slv <= stage2slv_v;
    stage2mst <= stage2mst_v;
    
  end process;
  
end Behavioral;

