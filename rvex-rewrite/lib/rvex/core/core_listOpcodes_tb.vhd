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

library std;
use std.textio.all;

library rvex;
use rvex.utils_pkg.all;
use rvex.simUtils_pkg.all;
use rvex.simUtils_scanner_pkg.all;
use rvex.core_intIface_pkg.all;
use rvex.core_opcode_pkg.all;

--=============================================================================
-- This "testbench" simply dumps a list of all the implemented and free opcodes
-- to the simulation output.
-------------------------------------------------------------------------------
entity core_listOpcodes_tb is
end core_listOpcodes_tb;
-------------------------------------------------------------------------------
architecture Behavioral of core_listOpcodes_tb is
begin
--=============================================================================
  
  list_opcodes: process is
    procedure dump(s: string) is
      variable ln : std.textio.line;
    begin
      ln := new string(1 to s'length);
      ln.all := s;
      writeline(std.textio.output, ln);
      if ln /= null then
        deallocate(ln);
      end if;
      
      -- If writing to stdout does not work, you can also use reports:
      --report s severity note;
    end procedure;
    
    variable pos        : positive;
    variable token      : line;
    variable unusedCnt  : natural;
  begin
    unusedCnt := 0;
    for opcode in opcodeTable_type'range loop
      
      -- Dump opcode using register for op2.
      if OPCODE_TABLE(opcode).valid(0) = '1' then
        pos := 1;
        scanToken(OPCODE_TABLE(opcode).syntax_reg, pos, token);
        if token = null then
          dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(0) = ?");
        else
          dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(0) = " & token.all);
        end if;
        unusedCnt := 0;
      elsif OPCODE_TABLE(opcode).valid(1) = '1' then
        dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(0) = <invalid>");
      end if;
      
      -- Dump opcode using immediate for op2.
      if OPCODE_TABLE(opcode).valid(1) = '1' then
        pos := 1;
        scanToken(OPCODE_TABLE(opcode).syntax_imm, pos, token);
        if token = null then
          dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(1) = ?");
        else
          dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(1) = " & token.all);
        end if;
        unusedCnt := 0;
      elsif OPCODE_TABLE(opcode).valid(0) = '1' then
        dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(1) = <invalid>");
      end if;
      
      -- Handle pretty-printing unused opcode ranges.
      if OPCODE_TABLE(opcode).valid = "00" then
        if unusedCnt = 0 then
          dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(-) = <free>");
        end if;
        unusedCnt := unusedCnt + 1;
        if (opcode = opcodeTable_type'high) or (OPCODE_TABLE(opcode + 1).valid /= "00") then
          if unusedCnt > 2 then
            dump("...");
          end if;
          if unusedCnt > 1 then
            dump(rvs_bin(uint2vect(opcode, rvex_opcode_type'length)) & "(-) = <free>");
          end if;
          unusedCnt := 0;
        end if;
      end if;
    end loop;
    
    report "Done" severity failure;
    wait;
  end process;
  
end Behavioral;

