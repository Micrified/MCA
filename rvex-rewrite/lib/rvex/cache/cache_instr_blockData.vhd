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
use rvex.core_pkg.all;
use rvex.cache_pkg.all;

--=============================================================================
-- This entity infers the block RAMs which store the cache lines for an
-- instruction cache block.
-------------------------------------------------------------------------------
entity cache_instr_blockData is
--=============================================================================
  generic (
    
    -- Core configuration. Must be equal to the configuration presented to the
    -- rvex core connected to the cache.
    RCFG                        : rvex_generic_config_type := rvex_cfg;
    
    -- Cache configuration.
    CCFG                        : cache_generic_config_type := cache_cfg
    
  );
  port (
    
    -- Clock input.
    clk                       : in  std_logic;
    
    -- Active high enable input.
    enable                    : in  std_logic;
    
    -- CPU address input.
    cpuAddr                   : in  rvex_address_type;
    
    -- Read data output.
    readData                  : out std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
    
    -- Active high write enable input.
    writeEnable               : in  std_logic;
    
    -- Write data input.
    writeData                 : in  std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0)
    
  );
end cache_instr_blockData;

--=============================================================================
architecture Behavioral of cache_instr_blockData is
--=============================================================================
  
  -- Declare XST RAM extraction hints.
  attribute ram_extract       : string;
  attribute ram_style         : string;
  
  -- Cache data memory.
  type ram_data_type
    is array(0 to 2**CCFG.instrCacheLinesLog2-1)
    of std_logic_vector(icacheLineWidth(RCFG, CCFG)-1 downto 0);
  signal ram_data             : ram_data_type := (others => (others => 'X'));
  
  -- Hints for XST to implement the data memory in block RAMs.
  attribute ram_extract of ram_data : signal is "yes";
  attribute ram_style   of ram_data : signal is "block";
  
  -- CPU address/PC signals.
  signal cpuOffset            : std_logic_vector(icacheOffsetSize(RCFG, CCFG)-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Extract the offset from the CPU address.
  cpuOffset <= cpuAddr(
    icacheOffsetLSB(RCFG, CCFG) + icacheOffsetSize(RCFG, CCFG) - 1
    downto icacheOffsetLSB(RCFG, CCFG)
  );
  
  -- Instantiate the data memory.
  ram_data_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if enable = '1' then
        if writeEnable = '1' then
          ram_data(to_integer(unsigned(cpuOffset))) <= writeData;
          readData <= writeData;
        else
          readData <= ram_data(to_integer(unsigned(cpuOffset)));
        end if;
      end if;
    end if;
  end process;
  
end Behavioral;

