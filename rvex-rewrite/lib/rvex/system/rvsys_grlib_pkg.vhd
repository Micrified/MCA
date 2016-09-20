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
use rvex.cache_pkg.all;
use rvex.core_pkg.all;

--=============================================================================
-- This package contains grlib specific data types used within the rvex-grlib
-- interface.
-------------------------------------------------------------------------------
package rvsys_grlib_pkg is
--=============================================================================
  
  -- rvex core configuration record.
  type rvex_grlib_generic_config_type is record
    
    -- Configuration for the rvex core.
    core                        : rvex_generic_config_type;
    
    -- Configuration for cache.
    cache                       : cache_generic_config_type;
    
  end record;
  
  type rvex_grlib_generic_config_array is array (natural range <>) of rvex_grlib_generic_config_type;
  
  -- Default rvex core configuration.
  constant RVEX_GRLIB_DEFAULT_CONFIG : rvex_grlib_generic_config_type := (
    core                        => RVEX_DEFAULT_CONFIG,
    cache                       => CACHE_DEFAULT_CONFIG
  );
  
  -- Generates a configuration for the grlib system. None of the parameters are
  -- required; just use named associations to set the parameters you want to
  -- affect, the rest of the parameters will take their value from base, which
  -- is itself set to the default configuration if not specified. To configure
  -- the core or cache, you also need to set core_valid/cache_valid to true, to
  -- allow the mathod to detect that you specified them. To set boolean values,
  -- use 1 for true and 0 for false (-1 is used to detect when a parameter is
  -- not specified). By using this method to generate configurations, code
  -- instantiating the grlib system will be forward compatible when new
  -- configuration options are added.
  function rvex_grlib_cfg(
    base                        : rvex_grlib_generic_config_type := RVEX_GRLIB_DEFAULT_CONFIG;
    core                        : rvex_generic_config_type := RVEX_DEFAULT_CONFIG;
    core_valid                  : boolean := false;
    cache                       : cache_generic_config_type := CACHE_DEFAULT_CONFIG;
    cache_valid                 : boolean := false
  ) return rvex_grlib_generic_config_type;

  -- Calulates the total number of lane groups in a GRLIB system based on the
  -- provided configuration.
  function rvex_grlib_num_lane_groups(
    config : rvex_grlib_generic_config_array
  ) return integer;
    
  -- Calulates the total number of contexts in a GRLIB system based on the
  -- provided configuration.
  function rvex_grlib_num_contexts(
    config : rvex_grlib_generic_config_array
  ) return integer;
    
end rvsys_grlib_pkg;

--=============================================================================
package body rvsys_grlib_pkg is
--=============================================================================

  -- Generates a configuration for the rvex core.
  function rvex_grlib_cfg(
    base                        : rvex_grlib_generic_config_type := RVEX_GRLIB_DEFAULT_CONFIG;
    core                        : rvex_generic_config_type := RVEX_DEFAULT_CONFIG;
    core_valid                  : boolean := false;
    cache                       : cache_generic_config_type := CACHE_DEFAULT_CONFIG;
    cache_valid                 : boolean := false
  ) return rvex_grlib_generic_config_type is
    variable cfg  : rvex_grlib_generic_config_type;
  begin
    cfg := base;
    if core_valid   then cfg.core   := core;  end if;
    if cache_valid  then cfg.cache  := cache; end if;
    return cfg;
  end rvex_grlib_cfg;

  -- Calulates the total number of lange groups in a GRLIB system based on the
  -- provided configuration.
  function rvex_grlib_num_lane_groups(
    config : rvex_grlib_generic_config_array
  ) return integer is
    variable count : integer := 0;
  begin
      for index in config'low to config'high loop
          count := count + 2**config(index).core.numLaneGroupsLog2;
      end loop;
      return count;
  end rvex_grlib_num_lane_groups;
  
  -- Calulates the total number of contexts in a GRLIB system based on the
  -- provided configuration.
  function rvex_grlib_num_contexts(
    config : rvex_grlib_generic_config_array
  ) return integer is
    variable count : integer := 0;
  begin
      for index in config'low to config'high loop
          count := count + 2**config(index).core.numContextsLog2;
      end loop;
      return count;
  end rvex_grlib_num_contexts;
  
end rvsys_grlib_pkg;
