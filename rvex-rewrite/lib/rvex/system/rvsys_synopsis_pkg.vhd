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
use rvex.rvsys_standalone_pkg.all;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.bus_addrConv_pkg.all;
use rvex.core_pkg.all;
use rvex.cache_pkg.all;

--=============================================================================
-- This package contains the definition of the configuration for the synopsis
-- platform.
-------------------------------------------------------------------------------
package rvsys_synopsis_pkg is
--=============================================================================
  
  -- Minimal rvex core configuration.
  constant RVEX_CORE_CONFIG  : rvex_generic_config_type := (
    numLanesLog2                => 3,
    numLaneGroupsLog2           => 2,
    numContextsLog2             => 2,
    genBundleSizeLog2           => 3,
    bundleAlignLog2             => 1,
    multiplierLanes             => 2#11111111#,
    memLaneRevIndex             => 1,
    numBreakpoints              => 4,
    forwarding                  => true,
    limmhFromNeighbor           => true,
    limmhFromPreviousPair       => false,
    reg63isLink                 => false,
    cregStartAddress            => X"FFFFFC00",
    resetVectors                => (others => (others => '0')),
    unifiedStall                => false,
    gpRegImpl                   => RVEX_GPREG_IMPL_SIMPLE,
    traceEnable                 => false,
    perfCountSize               => 4,
    cachePerfCountEnable        => false
  );
  constant RVEX_SYNOPSYS_CONFIG  : rvex_sa_generic_config_type := (
    core                        => RVEX_CORE_CONFIG,
    cache_enable                => false,
    cache_config                => CACHE_DEFAULT_CONFIG,
    cache_bypassRange           => addrRange(match => "1-------------------------------"),
    imemDepthLog2B              => 8,
    dmemDepthLog2B              => 8,
    traceDepthLog2B             => 13,
    debugBusMap_imem            => addrRangeAndMap(match => "00-1----------------------------"),
    debugBusMap_dmem            => addrRangeAndMap(match => "001-----------------------------"),
    debugBusMap_rvex            => addrRangeAndMap(match => "1111----------------------------"),
    debugBusMap_trace           => addrRangeAndMap(match => "1110----------------------------"),
    debugBusMap_mutex           => false,
    rvexDataMap_dmem            => addrRangeAndMap(match => "0-------------------------------"),
    rvexDataMap_bus             => addrRangeAndMap(match => "1-------------------------------")
  );
  constant rvex_synopsis_cfg : rvex_sa_generic_config_type :=
    RVEX_SYNOPSYS_CONFIG;

end rvsys_synopsis_pkg;

--=============================================================================
package body rvsys_synopsis_pkg is
--=============================================================================

end rvsys_synopsis_pkg;
