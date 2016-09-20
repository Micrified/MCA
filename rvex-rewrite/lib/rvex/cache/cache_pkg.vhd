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

--=============================================================================
-- This package contains type definitions and constants for the rvex cache.
-------------------------------------------------------------------------------
package cache_pkg is
--=============================================================================
  
  -- Cache configuration record.
  type cache_generic_config_type is record
    
    -- log2 of the number of cache lines in the instruction cache. An
    -- instruction cache line has the size of a full rvex instruction, so
    -- that's the number of lanes in the core times 32 bits.
    instrCacheLinesLog2         : natural;
    
    -- log2 of the number of cache lines in the data cache. A data cache line
    -- is fixed to 32 bits.
    dataCacheLinesLog2          : natural;
    
  end record;
  
  -- Default cache configuration.
  constant CACHE_DEFAULT_CONFIG  : cache_generic_config_type := (
    instrCacheLinesLog2         => 6,
    dataCacheLinesLog2          => 6
  );
  
  -- Generates a configuration for the rvex cache. None of the parameters are
  -- required; just use named associations to set the parameters you want to
  -- affect, the rest of the parameters will take their value from base, which
  -- is itself set to the default configuration if not specified. By using this
  -- method to generate configurations, code instantiating the rvex cache will
  -- be forward compatible when new configuration options are added.
  function cache_cfg(
    base                        : cache_generic_config_type := CACHE_DEFAULT_CONFIG;
    instrCacheLinesLog2         : integer := -1;
    dataCacheLinesLog2          : integer := -1
  ) return cache_generic_config_type;
  
  -- Returns the log2 of the number of bytes needed to represent the
  -- instruction for a single lane group.
  function laneGroupInstrSizeBLog2(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the instruction cache line width.
  function icacheLineWidth(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the LSB of the line offset within the instruction cache for a
  -- given address.
  function icacheOffsetLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the number of bits used to represent the line offset within the
  -- instruction cache for a given address.
  function icacheOffsetSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the LSB of the instruction cache tag for a given address.
  function icacheTagLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns number of bits used to represent the instruction cache tag.
  function icacheTagSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the LSB of the line offset within the data cache for a given
  -- address.
  function dcacheOffsetLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the number of bits used to represent the line offset within the
  -- data cache for a given address.
  function dcacheOffsetSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns the LSB of the data cache tag for a given address.
  function dcacheTagLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Returns number of bits used to represent the data cache tag.
  function dcacheTagSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural;
  
  -- Data cache block status record for performance counters/tracing.
  type dcache_status_type is record
    
    -- Type of data memory access:
    --   00 - No access.
    --   01 - Read access.
    --   10 - Write access, complete cache line.
    --   11 - Write access, only part of a cache line (update first).
    accessType                  : std_logic_vector(1 downto 0);
    
    -- Whether the memory access bypassed the cache.
    bypass                      : std_logic;
    
    -- Whether the requested memory address was initially in the cache.
    miss                        : std_logic;
    
    -- This is set when the write buffer was filled when the request was made.
    -- If the request would result in some kind of bus access, this means an
    -- extra penalty would be paid.
    writePending                : std_logic;
    
  end record;
  type dcache_status_array is array (natural range <>) of dcache_status_type;
  
end cache_pkg;

package body cache_pkg is

  -- Generates a configuration for the cache.
  function cache_cfg(
    base                        : cache_generic_config_type := CACHE_DEFAULT_CONFIG;
    instrCacheLinesLog2         : integer := -1;
    dataCacheLinesLog2          : integer := -1
  ) return cache_generic_config_type is
    variable cfg  : cache_generic_config_type;
  begin
    cfg := base;
    if instrCacheLinesLog2  >= 0 then cfg.instrCacheLinesLog2 := instrCacheLinesLog2; end if;
    if dataCacheLinesLog2   >= 0 then cfg.dataCacheLinesLog2  := dataCacheLinesLog2;  end if;
    return cfg;
  end cache_cfg;
  
  -- Returns the log2 of the number of bytes needed to represent the
  -- instruction for a single lane group.
  function laneGroupInstrSizeBLog2(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return RCFG.numLanesLog2 - RCFG.numLaneGroupsLog2 + 2;
  end laneGroupInstrSizeBLog2;
  
  -- Returns the instruction cache line width.
  function icacheLineWidth(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return rvex_syllable_type'length * 2**RCFG.numLanesLog2;
  end icacheLineWidth;
  
  -- Returns the LSB of the line offset within the instruction cache for a
  -- given address.
  function icacheOffsetLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return RCFG.numLanesLog2 + 2;
  end icacheOffsetLSB;
  
  -- Returns the number of bits used to represent the line offset within the
  -- instruction cache for a given address.
  function icacheOffsetSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return CCFG.instrCacheLinesLog2;
  end icacheOffsetSize;
  
  -- Returns the LSB of the instruction cache tag for a given address.
  function icacheTagLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return icacheOffsetLSB(RCFG, CCFG) + icacheOffsetSize(RCFG, CCFG);
  end icacheTagLSB;
  
  -- Returns number of bits used to represent the instruction cache tag.
  function icacheTagSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return rvex_address_type'length - icacheTagLSB(RCFG, CCFG);
  end icacheTagSize;
  
  -- Returns the LSB of the line offset within the data cache for a given
  -- address.
  function dcacheOffsetLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return 2;
  end dcacheOffsetLSB;
  
  -- Returns the number of bits used to represent the line offset within the
  -- data cache for a given address.
  function dcacheOffsetSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return CCFG.dataCacheLinesLog2;
  end dcacheOffsetSize;
  
  -- Returns the LSB of the data cache tag for a given address.
  function dcacheTagLSB(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return dcacheOffsetLSB(RCFG, CCFG) + dcacheOffsetSize(RCFG, CCFG);
  end dcacheTagLSB;
  
  -- Returns number of bits used to represent the data cache tag.
  function dcacheTagSize(
    RCFG                        : rvex_generic_config_type;
    CCFG                        : cache_generic_config_type
  ) return natural is
  begin
    return rvex_address_type'length - dcacheTagLSB(RCFG, CCFG);
  end dcacheTagSize;
  
end cache_pkg;
