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
-- This entity infers the block RAMs which store the cache tags for a data
-- cache block and checks whether the tag matches the incoming address.
-------------------------------------------------------------------------------
entity cache_data_blockTag is
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
    
    -- Active high enable input for CPU signals.
    enableCPU                   : in  std_logic;
    
    -- Active high enable input for bus signals.
    enableBus                   : in  std_logic;
    
    -- CPU address input.
    cpuAddr                     : in  rvex_address_type;
    
    -- Hit output for the CPU, delayed by one cycle with enable high due to
    -- the memory.
    cpuHit                      : out std_logic;
    
    -- Write enable signal to write the CPU tag to the memory.
    writeCpuTag                 : in  std_logic;
    
    -- Invalidate address input.
    invalAddr                   : in  rvex_address_type;
    
    -- Hit output for the invalidation logic, delayed by one cycle with
    -- enable high due to the memory.
    invalHit                    : out std_logic
    
  );
end cache_data_blockTag;

--=============================================================================
architecture Behavioral of cache_data_blockTag is
--=============================================================================
  
  -- Declare XST RAM extraction hints.
  attribute ram_extract         : string;
  attribute ram_style           : string;
  
  -- Load shorthand notations for the address vector metrics.
  constant OFFSET_LSB           : natural := dcacheOffsetLSB(RCFG, CCFG);
  constant OFFSET_SIZE          : natural := dcacheOffsetSize(RCFG, CCFG);
  constant TAG_LSB              : natural := dcacheTagLSB(RCFG, CCFG);
  constant TAG_SIZE             : natural := dcacheTagSize(RCFG, CCFG);
  
  -- Cache tag memory.
  type ram_tag_type
    is array(0 to 2**CCFG.dataCacheLinesLog2-1)
    of std_logic_vector(TAG_SIZE-1 downto 0);
  signal ram_tag                : ram_tag_type := (others => (others => 'X'));
  
  -- Hints for XST to implement the tag memory in block RAMs.
  attribute ram_extract of ram_tag  : signal is "yes";
  attribute ram_style   of ram_tag  : signal is "block";
  
  -- CPU address/PC signals.
  signal cpuOffset              : std_logic_vector(OFFSET_SIZE-1 downto 0);
  signal cpuTag                 : std_logic_vector(TAG_SIZE-1 downto 0);
  signal cpuTag_r               : std_logic_vector(TAG_SIZE-1 downto 0);
  signal cpuTag_mem             : std_logic_vector(TAG_SIZE-1 downto 0);
  
  -- Invalidate address/PC signals.
  signal invalOffset            : std_logic_vector(OFFSET_SIZE-1 downto 0);
  signal invalTag               : std_logic_vector(TAG_SIZE-1 downto 0);
  signal invalTag_r             : std_logic_vector(TAG_SIZE-1 downto 0);
  signal invalTag_mem           : std_logic_vector(TAG_SIZE-1 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Extract the offsets and tags from the CPU and invalidate addresses.
  cpuOffset   <= cpuAddr  (OFFSET_LSB + OFFSET_SIZE-1 downto OFFSET_LSB);
  cpuTag      <= cpuAddr  (TAG_LSB    + TAG_SIZE-1    downto TAG_LSB);
  invalOffset <= invalAddr(OFFSET_LSB + OFFSET_SIZE-1 downto OFFSET_LSB);
  invalTag    <= invalAddr(TAG_LSB    + TAG_SIZE-1    downto TAG_LSB);
  
  -- Register the CPU and invalidate tags for the tag comparator, to account
  -- for the delay in memory access.
  tag_registers: process (clk) is
  begin
    if rising_edge(clk) then
      if enableCPU = '1' then
        cpuTag_r <= cpuTag;
      end if;
      if enableBus = '1' then
        invalTag_r <= invalTag;
      end if;
    end if;
  end process;
  
  -- Instantiate the tag memory.
  ram_tag_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if enableCPU = '1' then
        if writeCpuTag = '1' then
          ram_tag(to_integer(unsigned(cpuOffset))) <= cpuTag_r;
          cpuTag_mem <= cpuTag_r;
        else
          cpuTag_mem <= ram_tag(to_integer(unsigned(cpuOffset)));
        end if;
      end if;
      if enableBus = '1' then
        invalTag_mem <= ram_tag(to_integer(unsigned(invalOffset)));
      end if;
    end if;
  end process;
  
  -- Determine the hit outputs.
  cpuHit <= '1' when cpuTag_mem = cpuTag_r else '0';
  invalHit <= '1' when invalTag_mem = invalTag_r else '0';
  
end Behavioral;

