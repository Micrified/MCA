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
use rvex.bus_pkg.all;

--=============================================================================
-- This package contains types and methods to do with address ranges and
-- address conversions/mappings.
-------------------------------------------------------------------------------
package bus_addrConv_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Address ranges
  -----------------------------------------------------------------------------
  -- Specifies a range of addresses. An address is considered in range when it
  -- lies between low and high (both inclusive) when masked by mask AND
  -- std_match(address, match) return true.
  type addrRange_type is record
    low       : rvex_address_type;
    high      : rvex_address_type;
    mask      : rvex_address_type;
    match     : rvex_address_type;
  end record;
  
  -- Array of address ranges.
  type addrRange_array is array (natural range <>) of addrRange_type;
  
  -- Generates an address range. By default, it matches every address.
  function addrRange(
    low       : rvex_address_type := (others => '0');
    high      : rvex_address_type := (others => '1');
    mask      : rvex_address_type := (others => '1');
    match     : rvex_address_type := (others => '-')
  ) return addrRange_type;
  
  -- Returns true when the given address lies within the specified range, or
  -- false otherwise.
  function isAddrInRange(
    addr      : rvex_address_type;
    addrRange : addrRange_type
  ) return boolean;
  
  -----------------------------------------------------------------------------
  -- Address mappings
  -----------------------------------------------------------------------------
  -- An address mapping transforms one address into another. The mappings
  -- specified here support moving address bits around and overriding address
  -- bits to 0 or 1. They can be constructed using combinations or mapRange and
  -- mapConstant. For example,
  --
  --   mapConstant(X"00001") & mapRange(11, 2) & mapConstant(2, '0')
  --
  -- will generate a mapping which uses bit 11..2 from the original address but
  -- overrides the rest of it with 0x00001000.
  
  -- Address mapping type. An integer in this array specifies what to use for
  -- the address bit at the indexed position. When the integer lies within 0 to
  -- 31, the specified bit is used from the original address. When it is -1,
  -- the bit is forced to '0'; when it is -2, the bit is forced to '1'.
  type bitMapping_array is array (natural range <>) of integer;
  
  -- Constrained array type for the above, having a mapping for each bit in a
  -- 32 bit address.
  subtype addrMapping_type is bitMapping_array(rvex_address_type'range);
  
  -- Array of address mappings.
  type addrMapping_array is array (natural range <>) of addrMapping_type;
  
  -- Maps a range from the original address.
  function mapRange(
    high      : natural;
    low       : natural
  ) return bitMapping_array;
  
  -- Maps a constant vector.
  function mapConstant(
    vect      : std_logic_vector
  ) return bitMapping_array;
  
  -- Maps a constant vector by replicating the specified value count times.
  function mapConstant(
    count     : natural;
    value     : std_logic
  ) return bitMapping_array;
  
  -- Applies an address map to an address.
  function applyAddrMap(
    addr      : rvex_address_type;
    addrMap   : addrMapping_type
  ) return rvex_address_type;
  
  -- Applies an address map to the address in a bus request.
  function applyAddrMap(
    addr      : bus_mst2slv_type;
    addrMap   : addrMapping_type
  ) return bus_mst2slv_type;
  
  -----------------------------------------------------------------------------
  -- Address range + mapping type
  -----------------------------------------------------------------------------
  -- The bus demuxing entity supports a range and an address mapping for each
  -- slave bus. Because it's nice to specify the range and mapping for a single
  -- slave next to each other as opposed to specifying all ranges and then
  -- specifying all mappings, we define a record which contains both of them.
  type addrRangeAndMapping_type is record
    addrRange   : addrRange_type;
    addrMapping : addrMapping_type;
  end record;
  
  -- Array type for the above.
  type addrRangeAndMapping_array is array (natural range <>) of addrRangeAndMapping_type;
  
  -- Generates an address range and mapping. By default, it matches every
  -- address and does not change the address.
  function addrRangeAndMap(
    low       : rvex_address_type := (others => '0');
    high      : rvex_address_type := (others => '1');
    mask      : rvex_address_type := (others => '1');
    match     : rvex_address_type := (others => '-');
    mapping   : addrMapping_type := mapRange(31, 0)
  ) return addrRangeAndMapping_type;
  
end bus_addrConv_pkg;

--=============================================================================
package body bus_addrConv_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Address ranges
  -----------------------------------------------------------------------------
  -- Generates an address range. By default, it matches every address.
  function addrRange(
    low       : rvex_address_type := (others => '0');
    high      : rvex_address_type := (others => '1');
    mask      : rvex_address_type := (others => '1');
    match     : rvex_address_type := (others => '-')
  ) return addrRange_type is
  begin
    return (
      low   => low,
      high  => high,
      mask  => mask,
      match => match
    );
  end addrRange;
  
  -- Returns true when the given address lies within the specified range, or
  -- false otherwise.
  function isAddrInRange(
    addr      : rvex_address_type;
    addrRange : addrRange_type
  ) return boolean is
  begin
    return (vect2unsigned(addr and addrRange.mask) >= vect2unsigned(addrRange.low))
       and (vect2unsigned(addr and addrRange.mask) <= vect2unsigned(addrRange.high))
       and std_match(addr, addrRange.match);
  end isAddrInRange;
  
  -----------------------------------------------------------------------------
  -- Address mappings
  -----------------------------------------------------------------------------
  -- Maps a range from the original address.
  function mapRange(
    high      : natural;
    low       : natural
  ) return bitMapping_array is
    variable res : bitMapping_array(high-low downto 0);
  begin
    for i in res'range loop
      res(i) := i + low;
    end loop;
    return res;
  end mapRange;
  
  -- Maps a constant vector.
  function mapConstant(
    vect      : std_logic_vector
  ) return bitMapping_array is
    variable res : bitMapping_array(vect'length-1 downto 0);
  begin
    for i in res'range loop
      if vect(i + vect'low) = '1' then
        res(i) := -2; -- Code for '1'.
      else
        res(i) := -1; -- Code for '0'.
      end if;
    end loop;
    return res;
  end mapConstant;
  
  -- Maps a constant vector by replicating the specified value count times.
  function mapConstant(
    count     : natural;
    value     : std_logic
  ) return bitMapping_array is
    variable res : bitMapping_array(count-1 downto 0);
  begin
    if value = '1' then
      res := (others => -2); -- Code for '1'.
    else
      res := (others => -1); -- Code for '0'.
    end if;
    return res;
  end mapConstant;
  
  -- Applies an address map to an address.
  function applyAddrMap(
    addr      : rvex_address_type;
    addrMap   : addrMapping_type
  ) return rvex_address_type is
    variable res : rvex_address_type;
  begin
    for i in res'range loop
      if addrMap(i) = -2 then -- Code for '1'.
        res(i) := '1';
      elsif addrMap(i) = -1 then -- Code for '0'.
        res(i) := '0';
      else
        res(i) := addr(addrMap(i));
      end if;
    end loop;
    return res;
  end applyAddrMap;
  
  -- Applies an address map to the address in a bus request.
  function applyAddrMap(
    addr      : bus_mst2slv_type;
    addrMap   : addrMapping_type
  ) return bus_mst2slv_type is
    variable b  : bus_mst2slv_type;
  begin
    b := addr;
    b.address := applyAddrMap(b.address, addrMap);
    return b;
  end applyAddrMap;
  
  -----------------------------------------------------------------------------
  -- Address range + mapping type
  -----------------------------------------------------------------------------
  -- Generates an address range and mapping. By default, it matches every
  -- address and does not change the address.
  function addrRangeAndMap(
    low       : rvex_address_type := (others => '0');
    high      : rvex_address_type := (others => '1');
    mask      : rvex_address_type := (others => '1');
    match     : rvex_address_type := (others => '-');
    mapping   : addrMapping_type := mapRange(31, 0)
  ) return addrRangeAndMapping_type is
    variable retval   : addrRangeAndMapping_type;
  begin
    retval.addrRange := (
      low   => low,
      high  => high,
      mask  => mask,
      match => match
    );
    retval.addrMapping := mapping;
    return retval;
  end addrRangeAndMap;
  
end bus_addrConv_pkg;

