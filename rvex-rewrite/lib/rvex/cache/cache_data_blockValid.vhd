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
-- This entity infers the valid bit storage for a data cache block.
-------------------------------------------------------------------------------
entity cache_data_blockValid is
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
    clk                         : in  std_logic;
    
    -- Active high reset input.
    reset                       : in  std_logic;
    
    -- Active high enable input for the CPU domain.
    enableCPU                   : in  std_logic;
    
    -- Active high enable input for the bus domain.
    enableBus                   : in  std_logic;
    
    -- CPU address input.
    cpuAddr                     : in  rvex_address_type;
    
    -- Valid output for the CPU, delayed by one cycle to synchronize with the
    -- tag memory. Governed by enableCPU.
    cpuValid                    : out std_logic;
    
    -- Active high validate input. This synchronously sets the valid bit
    -- addressed by the CPU. Governed by enableCPU.
    validate                    : in  std_logic;
    
    -- Invalidate address input. Governed by enableBus.
    invalAddr                   : in  rvex_address_type;
    
    -- Active high invalidate input. This synchronously resets the valid bit
    -- addressed by invalAddr. Governed by enableBus.
    invalidate                  : in  std_logic;
    
    -- Active high flush input. This synchronously resets all valid bits.
    -- Governed by enableBus.
    flush                       : in  std_logic
    
  );
end cache_data_blockValid;

--=============================================================================
architecture Behavioral of cache_data_blockValid is
--=============================================================================
  
  -- Valid bit memory.
  signal ram_valid            : std_logic_vector(2**CCFG.dataCacheLinesLog2-1 downto 0);
  
  -- Load shorthand notations for the address vector metrics.
  constant OFFSET_LSB         : natural := dcacheOffsetLSB(RCFG, CCFG);
  constant OFFSET_SIZE        : natural := dcacheOffsetSize(RCFG, CCFG);
  
  -- CPU offset extracted from byte address/PC.
  signal cpuOffset            : std_logic_vector(OFFSET_SIZE-1 downto 0);
  
  -- Invalidate offset extracted from byte address.
  signal invalOffset          : std_logic_vector(OFFSET_SIZE-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Extract the offsets and tags from the CPU and invalidate addresses.
  cpuOffset   <= cpuAddr  (OFFSET_LSB+OFFSET_SIZE-1 downto OFFSET_LSB);
  invalOffset <= invalAddr(OFFSET_LSB+OFFSET_SIZE-1 downto OFFSET_LSB);
  
  -- Instantiate the valid memory. The memory is write-first, with the
  -- following order of precedence:
  --  - flush
  --  - invalidate
  --  - validate
  ram_tag_proc: process (clk) is
  begin
    if rising_edge(clk) then
      
      -- Handle master reset.
      if reset = '1' then
        ram_valid <= (others => '0');
        cpuValid <= '0';
      else
        
        -- Handle flushing.
        if flush = '1' and enableBus = '1' then
          ram_valid <= (others => '0');
        else
          
          -- Handle line validation.
          if validate = '1' and enableCPU = '1' then
            ram_valid(to_integer(unsigned(cpuOffset))) <= '1';
          end if;
          
          -- Handle line invalidation.
          if invalidate = '1' and enableBus = '1' then
            ram_valid(to_integer(unsigned(invalOffset))) <= '0';
          end if;
          
        end if;
        
        -- Handle reading and write-first synchronization.
        if enableCPU = '1' then
          
          -- Handle read while flush.
          if flush = '1' and enableBus = '1' then
            cpuValid <= '0';
          
          -- Handle read while invalidate.
          elsif invalidate = '1' and enableBus = '1' and invalOffset = cpuOffset then
            cpuValid <= '0';
            
          -- Handle read while validate.
          elsif validate = '1' and enableCPU = '1' then
            cpuValid <= '1';
          
          -- Handle normal reads.
          else
            cpuValid <= ram_valid(to_integer(unsigned(cpuOffset)));
          end if;
        end if;
      end if;
    end if;
  end process;
  
end Behavioral;

