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
use rvex.bus_addrConv_pkg.all;
use rvex.core_pkg.all;
use rvex.cache_pkg.all;

--=============================================================================
-- This package contains type definitions and constants relevant both in the
-- standalone system internally and for anything which wants to instantiate
-- the standalone system.
-------------------------------------------------------------------------------
package rvsys_standalone_pkg is
--=============================================================================
  
  -- rvex core configuration record.
  type rvex_sa_generic_config_type is record
    
    -- Configuration for the rvex core.
    core                        : rvex_generic_config_type;
    
    -- This parameter drastically affects what the bus system looks like. Refer
    -- to the diagrams in rvsys_standalone.vhd for the full documentation. In
    -- short, when the cache is enabled, all bus accesses from the cache are
    -- routed through the lowest indexed data memory bus. The instruction
    -- memory is disabled and i.e., imemDepthLog2B and debugBusMap_imem are
    -- ignored. When the cache is disabled, cache_cfg and cache_bypass are
    -- ignored.
    cache_enable                : boolean;
    
    -- Cache configuration, if enabled by cache_enable.
    cache_config                : cache_generic_config_type;
    
    -- Address range for which the cache is bypassed for data accesses
    -- (peripheral space).
    cache_bypassRange           : addrRange_type;
    
    -- Whether to inject latency cycles in a cached system. When enabled, the
    -- memory access latency is runtime configurable from 2 to 255 cycles. When
    -- disabled, there is no additional latency.
    inject_latency              : boolean;
    
    -- Depth of the instruction memory, represented as log2(number_of_bytes).
    imemDepthLog2B              : natural;
    
    -- Depth of the instruction memory, represented as log2(number_of_bytes).
    dmemDepthLog2B              : natural;
    
    -- Depth of the trace buffer, represented as log2(number_of_bytes).
    traceDepthLog2B             : natural;
    
    -- The following entries define the memory map as seen by the debug bus.
    debugBusMap_imem            : addrRangeAndMapping_type;
    debugBusMap_dmem            : addrRangeAndMapping_type;
    debugBusMap_rvex            : addrRangeAndMapping_type;
    debugBusMap_trace           : addrRangeAndMapping_type;
    
    -- Specifies whether the debug bus memory map is mutually exclusive. When
    -- set to false, bus commands can be routed to for instance both the data
    -- memory and instruction memory at once.
    debugBusMap_mutex           : boolean;
    
    -- The following entries define the memory map as seen by the rvex.
    rvexDataMap_dmem            : addrRangeAndMapping_type;
    rvexDataMap_bus             : addrRangeAndMapping_type;
    
  end record;
  
  -- Default rvex core configuration.
  constant RVEX_SA_DEFAULT_CONFIG  : rvex_sa_generic_config_type := (
    core                        => RVEX_DEFAULT_CONFIG,
    cache_enable                => false,
    cache_config                => CACHE_DEFAULT_CONFIG,
    cache_bypassRange           => addrRange(match => "1-------------------------------"),
    inject_latency              => true,
    imemDepthLog2B              => 16,
    dmemDepthLog2B              => 16,
    traceDepthLog2B             => 13,
    debugBusMap_imem            => addrRangeAndMap(match => "00-1----------------------------"),
    debugBusMap_dmem            => addrRangeAndMap(match => "001-----------------------------"),
    debugBusMap_rvex            => addrRangeAndMap(match => "1111----------------------------"),
    debugBusMap_trace           => addrRangeAndMap(match => "1110----------------------------"),
    debugBusMap_mutex           => false,
    rvexDataMap_dmem            => addrRangeAndMap(match => "0-------------------------------"),
    rvexDataMap_bus             => addrRangeAndMap(match => "1-------------------------------")
  );
  
  constant ADDR_RANGE_UNDEF     : addrRange_type := addrRange(match => "UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU");
  constant ADDR_MAPPING_UNDEF   : addrRangeAndMapping_type := addrRangeAndMap(match => "UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU");
  
  -- Generates a configuration for the standalone system. None of the
  -- parameters are required; just use named associations to set the parameters
  -- you want to affect, the rest of the parameters will take their value from
  -- base, which is itself set to the default configuration if not specified.
  -- To set boolean values, use 1 for true and 0 for false (-1 is used to
  -- detect when a parameter is not specified). By using this method to
  -- generate configurations, code instantiating the standalone system will be
  -- forward compatible when new configuration options are added.
  function rvex_sa_cfg(
    base                        : rvex_sa_generic_config_type := RVEX_SA_DEFAULT_CONFIG;
    core                        : rvex_generic_config_type := RVEX_DEFAULT_CONFIG;
    core_valid                  : boolean := false;
    cache_enable                : integer := -1;
    cache_config                : cache_generic_config_type := CACHE_DEFAULT_CONFIG;
    cache_config_valid          : boolean := false;
    cache_bypassRange           : addrRange_type := ADDR_RANGE_UNDEF;
    inject_latency              : integer := -1;
    imemDepthLog2B              : integer := -1;
    dmemDepthLog2B              : integer := -1;
    traceDepthLog2B             : integer := -1;
    debugBusMap_imem            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_dmem            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_rvex            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_trace           : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_mutex           : integer := -1;
    rvexDataMap_dmem            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    rvexDataMap_bus             : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF
  ) return rvex_sa_generic_config_type;
  
end rvsys_standalone_pkg;

--=============================================================================
package body rvsys_standalone_pkg is
--=============================================================================

  -- Generates a configuration for the standalone rvex system.
  function rvex_sa_cfg(
    base                        : rvex_sa_generic_config_type := RVEX_SA_DEFAULT_CONFIG;
    core                        : rvex_generic_config_type := RVEX_DEFAULT_CONFIG;
    core_valid                  : boolean := false;
    cache_enable                : integer := -1;
    cache_config                : cache_generic_config_type := CACHE_DEFAULT_CONFIG;
    cache_config_valid          : boolean := false;
    cache_bypassRange           : addrRange_type := ADDR_RANGE_UNDEF;
    inject_latency              : integer := -1;
    imemDepthLog2B              : integer := -1;
    dmemDepthLog2B              : integer := -1;
    traceDepthLog2B             : integer := -1;
    debugBusMap_imem            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_dmem            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_rvex            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_trace           : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    debugBusMap_mutex           : integer := -1;
    rvexDataMap_dmem            : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF;
    rvexDataMap_bus             : addrRangeAndMapping_type := ADDR_MAPPING_UNDEF
  ) return rvex_sa_generic_config_type is
    variable cfg  : rvex_sa_generic_config_type;
  begin
    cfg := base;
    if core_valid                              then cfg.core              := core;                           end if;
    if cache_enable /= -1                      then cfg.cache_enable      := boolean'val(cache_enable);      end if;
    if cache_config_valid                      then cfg.cache_config      := cache_config;                   end if;
    if cache_bypassRange /= ADDR_RANGE_UNDEF   then cfg.cache_bypassRange := cache_bypassRange;              end if;
    if inject_latency /= -1                    then cfg.inject_latency    := boolean'val(inject_latency);    end if;
    if imemDepthLog2B >= 0                     then cfg.imemDepthLog2B    := imemDepthLog2B;                 end if;
    if dmemDepthLog2B >= 0                     then cfg.dmemDepthLog2B    := dmemDepthLog2B;                 end if;
    if traceDepthLog2B >= 0                    then cfg.traceDepthLog2B   := traceDepthLog2B;                end if;
    if debugBusMap_imem  /= ADDR_MAPPING_UNDEF then cfg.debugBusMap_imem  := debugBusMap_imem;               end if;
    if debugBusMap_dmem  /= ADDR_MAPPING_UNDEF then cfg.debugBusMap_dmem  := debugBusMap_dmem;               end if;
    if debugBusMap_rvex  /= ADDR_MAPPING_UNDEF then cfg.debugBusMap_rvex  := debugBusMap_rvex;               end if;
    if debugBusMap_trace /= ADDR_MAPPING_UNDEF then cfg.debugBusMap_trace := debugBusMap_trace;              end if;
    if debugBusMap_mutex /= -1                 then cfg.debugBusMap_mutex := boolean'val(debugBusMap_mutex); end if;
    if rvexDataMap_dmem  /= ADDR_MAPPING_UNDEF then cfg.rvexDataMap_dmem  := rvexDataMap_dmem;               end if;
    if rvexDataMap_bus   /= ADDR_MAPPING_UNDEF then cfg.rvexDataMap_bus   := rvexDataMap_bus;                end if;
    return cfg;
  end rvex_sa_cfg;
    
end rvsys_standalone_pkg;
