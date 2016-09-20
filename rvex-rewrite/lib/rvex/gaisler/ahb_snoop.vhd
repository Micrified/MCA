-- r-VEX processor
-- Copyright (C) 2008-2015 by TU Delft.
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

-- Copyright (C) 2008-2015 by TU Delft.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.bus_pkg.all;

library grlib;
use grlib.amba.all;
use grlib.devices.all;
use grlib.stdlib.all;
use grlib.dma2ahb_package.all;

--=============================================================================
-- AHB bus snooping interface for the rvex cache.
-------------------------------------------------------------------------------
entity ahb_snoop is
--=============================================================================
  generic (
    
    -- AHB master index belonging to cache block 0. The remaining cache blocks
    -- are assumed to have contiguous indices. This is used to generate the
    -- invalSource signal.
    FIRST_MASTER                : integer := 0;
    
    -- Number of cache blocks.
    NUM_CACHE_BLOCKS            : natural := 1
    
  );
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- AHB interface
    ---------------------------------------------------------------------------
    -- AHB slave input signal routed to all slaves.
    ahbsi                       : in  ahb_slv_in_type;
      
    ---------------------------------------------------------------------------
    -- Cache interface
    ---------------------------------------------------------------------------
    -- Bus address which is to be invalidated when invalEnable is high.
    invalAddr                   : out rvex_address_type;
    
    -- If one of the data cache blocks is causing the invalidation due to a
    -- write, the signal in this vector indexed by that data cache block will
    -- be high.
    invalSource                 : out std_logic_vector(NUM_CACHE_BLOCKS-1 downto 0);
    
    -- Active high enable signal for line invalidation.
    invalEnable                 : out std_logic
    
  );
end ahb_snoop;

--=============================================================================
architecture Behavioral of ahb_snoop is
--=============================================================================
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Drive the invalAddr signal.
  invalAddr <= ahbsi.haddr(31 downto 2) & "00";
  
  -- Decode the hmaster signal and drive the invalSource signal.
  hmaster_decode_proc: process (ahbsi.hmaster) is
  begin
    invalSource <= (others => '0');
    for i in 0 to NUM_CACHE_BLOCKS - 1 loop
      if vect2uint(ahbsi.hmaster) = FIRST_MASTER + i then
        invalSource(i) <= '1';
      end if;
    end loop;
  end process;
  
  -- Decode the AHB bus state and drive the invalEnable signal.
  invalEnable <=
    ahbsi.hready and ahbsi.hwrite
    when (ahbsi.htrans = HTRANS_NONSEQ or ahbsi.htrans = HTRANS_SEQ)
    else '0';
  
end Behavioral;

