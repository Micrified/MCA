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

--=============================================================================
-- This package specifies the control signal encoding for the ALU.
-------------------------------------------------------------------------------
package core_opcodeAlu_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Enumerations for muxes
  -----------------------------------------------------------------------------
  -- Operand 1 pre-add/logic operation.
  type aluOp1Mux_type is (
    
    -- Sign/zero extend operand from 32 bits (the adder is 33 bits to allow for
    -- unsigned comparisons), 16 bits or 8 bits. Whether to sign or zero extend
    -- is selected based on the unsignedOp control signal.
    EXTEND32,
    EXTEND16,
    EXTEND8,
    
    -- Same as EXTEND32, but also bitwise-complements the output.
    EXTEND32INV,
    
    -- Instead of performing sign extension, shift the operand left by a fixed
    -- number of bits.
    SHL1,
    SHL2,
    SHL3,
    SHL4
    
  );
  
  -- Operand 2 pre-add/logic operation.
  type aluOp2Mux_type is (
    
    -- Sign/zero extend operand from 32 bits (the adder is 33 bits to allow for
    -- unsigned comparisons) Whether to sign or zero extend is selected based
    -- on the unsignedOp control signal.
    EXTEND32,
    
    -- Force the operand to zero for single operand operations.
    ZERO
    
  );
  
  -- Branch register operand operation.
  type aluOpBrMux_type is (
    
    -- Let the branch register operand pass through without modification or
    -- inverted.
    PASS,
    INVERT,
    
    -- Override the branch register operand (like an immediate).
    TRUE,
    FALSE
    
  );
  
  -- ALU bitwise operation unit operation.
  type aluBitwiseOp_type is (
    
    -- The usual bitwise operations.
    BITW_AND,
    BITW_OR,
    BITW_XOR,
    
    -- Set bit operation. This sets the bit indexed by operand 2 to the branch
    -- input value. In addition, this unit will output the original bit in
    -- operand 1 indexed by operand 2.
    SET_BIT
    
  );
  
  -- Branch result selection.
  type aluBrResultMux_type is (
    
    -- Let the output from the branch operand selection mux pass through
    -- without modification. Used in particular for SLCT and SLCTF.
    PASS,
    
    -- Boolean logic operations. These are performed on the complement of the
    -- compare unit outputs. Compare unit 1 must be configured to compare
    -- operand 1 with 0.
    LOGIC_AND,
    LOGIC_NAND,
    LOGIC_OR,
    LOGIC_NOR,
    
    -- Compare operations. These are performed on the carry output of the adder
    -- and the output of compare unit 1, which should be configured to compare
    -- with operand 2.
    CMP_EQ,
    CMP_NE,
    CMP_GT,
    CMP_GE,
    CMP_LT,
    CMP_LE,
    
    -- Adder carry out for ADDCG.
    CARRY_OUT,
    
    -- Bit test flag for TBIT and TBITF.
    TBIT,
    TBITF,
    
    -- Output for DIVS function.
    DIVS
    
  );
  
  -- Integer result selection.
  type aluIntResultMux_type is (
    
    -- Forward the result from the adder unit.
    ADDER,
    
    -- Forward the result from the bitwise operation unit.
    BITWISE,
    
    -- Forward the result from the shift unit.
    SHIFTER,
    
    -- Forward the result from the CLZ unit.
    CLZ,
    
    -- Output either operand 1 unchanged or operand 2 unchanged, based on the
    -- branch output. Used for the SLCT and MIN/MAX operations.
    OP_SEL,
    
    -- Forward the branch output as a 32 bit integer.
    BOOL
    
  );
  
  -----------------------------------------------------------------------------
  -- ALU control signal record
  -----------------------------------------------------------------------------
  type aluCtrlSignals_type is record
    
    -- Pre-add operand modification muxing.
    op1Mux                      : aluOp1Mux_type;
    op2Mux                      : aluOp2Mux_type;
    opBrMux                     : aluOpBrMux_type;
    
    -- Division step select input. When this is set, the behavior of some of
    -- the logic units is altered slightly to perform the division step
    -- operation.
    divs                        : std_logic;
    
    -- Whether this operation is unsigned (high) or signed (low). This controls
    -- whether to zero extend or sign extend when extension is needed.
    unsignedOp                  : std_logic;
    
    -- Selects the bitwise operation to perform.
    bitwiseOp                   : aluBitwiseOp_type;
    
    -- Control signal to the shift unit, to have it shift left instead of
    -- right. It does so by bit-swapping the input and output so the actual
    -- barrel shifter doesn't get duplicated.
    shiftLeft                   : std_logic;
    
    -- Control signal for compare unit 1. When this is high, the unit will
    -- compare operand 1 and operand 2 for CMP operations. When this is low,
    -- the unit will compare operand 1 with 0 for boolean operations.
    compare                     : std_logic;
    
    -- Output muxing.
    intResultMux                : aluIntResultMux_type;
    brResultMux                 : aluBrResultMux_type;
    
  end record;
  
  -- Array type.
  type aluCtrlSignals_array is array (natural range <>) of aluCtrlSignals_type;
  
  -- Default value.
  constant ALU_CTRL_NOP         : aluCtrlSignals_type := (
    op1Mux                      => EXTEND32,
    op2Mux                      => ZERO,
    opBrMux                     => PASS,
    divs                        => '0',
    unsignedOp                  => '0',
    bitwiseOp                   => BITW_OR,
    shiftLeft                   => '0',
    compare                     => '0',
    intResultMux                => BITWISE,
    brResultMux                 => PASS
  );
  
end core_opcodeAlu_pkg;

package body core_opcodeAlu_pkg is
end core_opcodeAlu_pkg;
