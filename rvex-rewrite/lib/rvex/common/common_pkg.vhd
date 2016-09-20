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

--=============================================================================
-- This package contains basic data types which are used extensively throughout
-- the rvex library.
-------------------------------------------------------------------------------
package common_pkg is
--=============================================================================
  
  -- log2 of the size of a syllable in bytes.
  constant SYLLABLE_SIZE_LOG2B  : natural := 2;
  
  -- Subtypes for some common datatypes used within the core.
  subtype rvex_address_type     is std_logic_vector(31 downto  0); -- Any bus address or PC.
  subtype rvex_data_type        is std_logic_vector(31 downto  0); -- Any data word.
  subtype rvex_mask_type        is std_logic_vector( 3 downto  0); -- Byte mask for data words.
  subtype rvex_syllable_type    is std_logic_vector(31 downto  0); -- Any syllable.
  subtype rvex_byte_type        is std_logic_vector( 7 downto  0); -- Any byte.
  subtype rvex_7byte_type       is std_logic_vector(55 downto  0); -- Group of 7 bytes, used for tags and counters.
  
  -- Array types for the above subtypes.
  type rvex_address_array       is array (natural range <>) of rvex_address_type;
  type rvex_data_array          is array (natural range <>) of rvex_data_type;
  type rvex_mask_array          is array (natural range <>) of rvex_mask_type;
  type rvex_syllable_array      is array (natural range <>) of rvex_syllable_type;
  type rvex_byte_array          is array (natural range <>) of rvex_byte_type;
  type rvex_7byte_array         is array (natural range <>) of rvex_7byte_type;
  
  -- Null array constants.
  constant RVEX_DATA_ARRAY_NULL : rvex_data_array(0 to -1) := (others => (others => '0'));
  
end common_pkg;

package body common_pkg is
end common_pkg;
