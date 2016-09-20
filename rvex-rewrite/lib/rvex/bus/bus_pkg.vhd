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

--=============================================================================
-- This package contains definitions to do with the bus system used within the
-- rvex system.
-------------------------------------------------------------------------------
package bus_pkg is
--=============================================================================

  -----------------------------------------------------------------------------
  -- Bus timing (standard format)
  -----------------------------------------------------------------------------
  -- The diagram below shows the timing for the bus. The signal drawn for
  -- request specifies the timing for address, readEnable, writeEnable,
  -- writeMask, writeData and flags; result represents readData and fault. The
  -- result is valid when ack is high, which is the first cycle after the
  -- request is given where busy is low. The bus request signals must remain
  -- valid while busy is high.
  --
  --         |___     ___     ___     ___     ___     ___     ___     ___     |
  --     clk |   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/|
  --         |                                                                |
  -- request |nop====><valid1================><valid2><valid3><nop============|
  --         |                                                                |
  --  result |--------------------------------<valid1><valid2><valid3>--------|
  --         |                 _______________                                |
  --    busy |________________/               \_______________________________|
  --         |                                 _______________________        |
  --     ack |________________________________/                       \_______|
  --         |                                                                |
  --
  -- The clock and potential enable signal for the bus are not enclosed in the
  -- bus signal records and should be routed elsewhere.
  --
  -----------------------------------------------------------------------------
  -- Bus signal types and methods (standard format)
  -----------------------------------------------------------------------------
  -- Bus request flags.
  type bus_flags_type is record
    
    -- Burst flags. When burstEnable is high, the bus is expected to make
    -- several word requests without delaying which map to a contiguous region
    -- of memory which does not cross a 1kB boundary. burstStart must be
    -- asserted during the first transfer of the burst.
    burstEnable                 : std_logic;
    burstStart                  : std_logic;
    
    -- Lock flag for bus arbitration. While the master which has access over
    -- the bus asserts this signal, arbiters may not grant access to another
    -- master.
    lock                        : std_logic;
    
  end record;
  
  -- Default values for the bus flags.
  constant BUS_FLAGS_DEFAULT    : bus_flags_type := (
    burstEnable                 => '0',
    burstStart                  => '0',
    lock                        => '0'
  );
  
  -- Bus signals running from master to slave.
  type bus_mst2slv_type is record
    
    -- Address. Used for both read and write accesses. The 2 LSB are ignored.
    address                     : rvex_address_type;
    
    -- Read enable flag. When high, the slave is requested to return the word
    -- at the location specified by address. May not be high when writeEnable
    -- is high.
    readEnable                  : std_logic;
    
    -- Write enable flag. When high, the slave is requested to store the data
    -- specified by writeData and writeMask at the location specified by
    -- address. May not be high when readEnable is high.
    writeEnable                 : std_logic;
    
    -- Bytemask for writes. Each bit corresponds to a byte within writeData;
    -- when a bit is low, the associated byte should not be written. Ignored
    -- for reads.
    writeMask                   : rvex_mask_type;
    
    -- Data for writes. Ignored for reads.
    writeData                   : rvex_data_type;
    
    -- Flags for the command.
    flags                       : bus_flags_type;
    
  end record;
  
  -- Bus signals running from slave to master.
  type bus_slv2mst_type is record
    
    -- Read data result for a read request, or fault code when fault is high.
    readData                    : rvex_data_type;
    
    -- Fault flag. This is valid in the same cycle as readData. When low,
    -- readData contains the data as requested, or is undefined when no data
    -- was requested. When high, readData specifies a fault code. The fault
    -- code encoding depends on the bus.
    fault                       : std_logic;
    
    -- Busy flag. While high, the bus is busy servicing the request.
    busy                        : std_logic;
    
    -- Busy flag. When high, the request has been serviced and readData and
    -- fault are valid.
    ack                         : std_logic;
    
  end record;
  
  -- Array types for the busses above.
  type bus_mst2slv_array is array (natural range <>) of bus_mst2slv_type;
  type bus_slv2mst_array is array (natural range <>) of bus_slv2mst_type;
  
  -- This function generates or modifies bus flags. Always use this function
  -- instead of assigning the bus flags directly to make code forward
  -- compatible with additions to the bus flags.
  function bus_flags_gen(
    base                        : bus_flags_type := BUS_FLAGS_DEFAULT;
    burstEnable                 : std_logic := '-';
    burstStart                  : std_logic := '-';
    lock                        : std_logic := '-'
  ) return bus_flags_type;
  
  -- Idle state for the bus signals from master to slave.
  constant BUS_MST2SLV_IDLE     : bus_mst2slv_type := (
    address     => (others => '0'),
    readEnable  => '0',
    writeEnable => '0',
    writeMask   => (others => '0'),
    writeData   => (others => '0'),
    flags       => BUS_FLAGS_DEFAULT
  );
  
  -- Idle state for the bus signals from master to slave.
  constant BUS_SLV2MST_IDLE     : bus_slv2mst_type := (
    readData    => (others => '0'),
    fault       => '0',
    busy        => '0',
    ack         => '0'
  );
  
  -- Forces the bus request to no-operation when gate is low.
  function bus_gate(
    b     : bus_mst2slv_type;
    g     : boolean
  ) return bus_mst2slv_type;
  function bus_gate(
    b     : bus_mst2slv_type;
    g     : std_logic
  ) return bus_mst2slv_type;
  
  -- Returns high when the specified bus is requesting something or low when
  -- it is idle. This just or's readEnable and writeEnable.
  function bus_requesting(
    b     : bus_mst2slv_type
  ) return std_logic;
  
  -- Returns true when the specified bus is reading from the specified address,
  -- respecting don't cares.
  function bus_reading(
    b     : bus_mst2slv_type;
    a     : rvex_address_type
  ) return boolean;
  
  -- Returns true when the specified bus is writing to the specified byte
  -- address, respecting don't cares.
  function bus_writing(
    b     : bus_mst2slv_type;
    a     : rvex_address_type
  ) return boolean;
  
end bus_pkg;

--=============================================================================
package body bus_pkg is
--=============================================================================
  
  -- This function generates or modifies bus flags.
  function bus_flags_gen(
    base                        : bus_flags_type := BUS_FLAGS_DEFAULT;
    burstEnable                 : std_logic := '-';
    burstStart                  : std_logic := '-';
    lock                        : std_logic := '-'
  ) return bus_flags_type is
    variable f  : bus_flags_type;
  begin
    f := base;
    f.burstEnable := overrideStdLogic(f.burstEnable, burstEnable);
    f.burstStart := overrideStdLogic(f.burstStart, burstStart);
    f.lock := overrideStdLogic(f.lock, lock);
    return f;
  end bus_flags_gen;
  
  -- Forces the bus request to no-operation when gate is low.
  function bus_gate(
    b     : bus_mst2slv_type;
    g     : boolean
  ) return bus_mst2slv_type is
  begin
    if g then
      return b;
    else
      return bus_gate(b, '0');
    end if;
  end bus_gate;
  function bus_gate(
    b     : bus_mst2slv_type;
    g     : std_logic
  ) return bus_mst2slv_type is
    variable result : bus_mst2slv_type;
  begin
    result := b;
    result.readEnable := b.readEnable and g;
    result.writeEnable := b.writeEnable and g;
    return result;
  end bus_gate;
  
  -- Returns high when the specified bus is requesting something or low when
  -- it is idle. This just or's readEnable and writeEnable.
  function bus_requesting(
    b     : bus_mst2slv_type
  ) return std_logic is
  begin
    return b.readEnable or b.writeEnable;
  end bus_requesting;
  
  -- Returns true when the specified bus is reading from the specified address,
  -- respecting don't cares.
  function bus_reading(
    b     : bus_mst2slv_type;
    a     : rvex_address_type
  ) return boolean is
  begin
    return b.readEnable = '1'
       and std_match(b.address(31 downto 2), a(31 downto 2));
  end bus_reading;
  
  -- Returns true when the specified bus is writing to the specified byte
  -- address, respecting don't cares.
  function bus_writing(
    b     : bus_mst2slv_type;
    a     : rvex_address_type
  ) return boolean is
  begin
    return b.writeEnable = '1'
       and std_match(b.address(31 downto 2), a(31 downto 2))
       and b.writeMask(vect2uint(a(1 downto 0))) = '1';
  end bus_writing;
  
end bus_pkg;
