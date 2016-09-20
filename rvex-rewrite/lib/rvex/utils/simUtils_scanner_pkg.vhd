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

library std;
use std.textio.all;

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library rvex;
use rvex.simUtils_pkg.all;

--=============================================================================
-- This package contains simulation/elaboration-only methods for string
-- scanning (parsing).
-------------------------------------------------------------------------------
package simUtils_scanner_pkg is
--=============================================================================
  
  -- Type declarations for a string -> integer registry.
  type scan_stringIntPair_type is record
    s     : std.textio.line;
    i     : signed(32 downto 0);
  end record;
  type scan_stringIntPair_array is array (natural range <>) of scan_stringIntPair_type;
  type scan_stringIntPair_array_ptr is access scan_stringIntPair_array;
  type scan_intConsts_type is record
    pairs : scan_stringIntPair_array_ptr;
  end record;
  
  -- Overload for the internal deallocate method to properly deallocate a
  -- string to integer registry.
  procedure deallocate(
    consts: inout scan_intConsts_type
  );
  
  -- Registers an integer constant into the given registry.
  procedure registerConstant(
    consts: inout scan_intConsts_type;
    str   : in string;
    val   : in signed(32 downto 0)
  );
  
  -- Scans until the start of the next token, ignoring whitespace.
  procedure scanToEndOfWhitespace(
    line  : in string;
    pos   : inout positive
  );
  
  -- Compares and scans an identifier. Identifiers start with an alphabetical
  -- character and can contain any alphanumerical or underscore character after
  -- the first one.
  procedure scanAndCompareIdentifier(
    line1 : in string;
    pos1  : inout positive;
    line2 : in string;
    pos2  : inout positive;
    ok    : out boolean
  );
  
  -- Compares and scans a single special character or digit.
  procedure scanAndCompareCharacter(
    line1 : in string;
    pos1  : inout positive;
    line2 : in string;
    pos2  : inout positive;
    ok    : out boolean
  );
  
  -- Attempts to scan a numeric value. Supports decimal, octal (prefix with 0),
  -- hexadecimal (prefix with 0x) and binary (prefix with 0b), as well as
  -- unary negate operator. Assumes that the position starts at the number,
  -- and scans beyond trailing whitespace before returning.
  procedure scanNumeric(
    line  : in string;
    pos   : inout positive;
    consts: inout scan_intConsts_type;
    val   : inout signed(32 downto 0);
    ok    : out boolean
  );
  procedure scanNumeric(
    line  : in string;
    pos   : inout positive;
    val   : inout signed(32 downto 0);
    ok    : out boolean
  );
  
  -- Attempts to scan a token. A token is a connected string of alphanumeric
  -- characters or underscores, or a single special character. Assumes that the
  -- position starts at the number, and scans beyond trailing whitespace before
  -- returning. Returns null for token when the end of the line has been
  -- reached.
  procedure scanToken(
    line  : in string;
    pos   : inout positive;
    token : inout std.textio.line
  );
  
end simUtils_scanner_pkg;

--=============================================================================
package body simUtils_scanner_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Deallocates an integer constant registry
  -----------------------------------------------------------------------------
  procedure deallocate(
    consts: inout scan_intConsts_type
  ) is
  begin
    if consts.pairs /= null then
      for i in consts.pairs.all'range loop
        if consts.pairs.all(i).s /= null then
          deallocate(consts.pairs.all(i).s);
        end if;
      end loop;
      deallocate(consts.pairs);
      consts.pairs := null;
    end if;
  end deallocate;
  
  -----------------------------------------------------------------------------
  -- Registers an integer constant into the given registry
  -----------------------------------------------------------------------------
  procedure registerConstant(
    consts: inout scan_intConsts_type;
    str   : in string;
    val   : in signed(32 downto 0)
  ) is
    variable cnt      : natural;
    variable newPairs : scan_stringIntPair_array_ptr;
  begin
    
    -- Make a new list of pairs which has room for one more pair than the
    -- registry contains.
    if consts.pairs = null then
      cnt := 0;
    else
      cnt := consts.pairs.all'length;
    end if;
    newPairs := new scan_stringIntPair_array(0 to cnt);
    
    -- Copy the existing pairs into the new list.
    if cnt > 0 then
      newPairs.all(0 to cnt-1) := consts.pairs.all(0 to cnt-1);
    end if;
    
    -- Add the new pair to the new list.
    newPairs.all(cnt).s := new string(1 to str'length);
    newPairs.all(cnt).s.all := str;
    newPairs.all(cnt).i := val;
    
    -- Deallocate the old list and replace it with the new one.
    deallocate(consts.pairs);
    consts.pairs := newPairs;
    
  end registerConstant;
  
  -----------------------------------------------------------------------------
  -- Increases pos until it points to the first non-whitespace character
  -- encountered
  -----------------------------------------------------------------------------
  procedure scanToEndOfWhitespace(
    line  : in string;
    pos   : inout positive
  ) is
  begin
    while pos <= line'length loop
      exit when not isWhitespaceChar(line(pos));
      pos := pos + 1;
    end loop;
  end scanToEndOfWhitespace;
  
  -----------------------------------------------------------------------------
  -- Compares and scans an identifier
  -----------------------------------------------------------------------------
  procedure scanAndCompareIdentifier(
    line1 : in string;
    pos1  : inout positive;
    line2 : in string;
    pos2  : inout positive;
    ok    : out boolean
  ) is
    variable line1ended : boolean;
    variable line2ended : boolean;
  begin
    
    -- Make sure that an identifier is beginning on both inputs.
    if (not isAlphaChar(line1(pos1))) or (not isAlphaChar(line2(pos2))) then
      ok := false;
      return;
    end if;
    
    -- Scan the identifier.
    line1ended := false;
    line2ended := false;
    loop
      
      -- See if line 1 ended.
      if (pos1 > line1'length) or not (isAlphaNumericChar(line1(pos1)) or line1(pos1) = '_') then
        line1ended := true;
        scanToEndOfWhitespace(line1, pos1);
      end if;
      
      -- See if line 2 ended.
      if (pos2 > line2'length) or not (isAlphaNumericChar(line2(pos2)) or line2(pos2) = '_') then
        line2ended := true;
        scanToEndOfWhitespace(line2, pos2);
      end if;
      
      -- If both lines ended, succeed.
      if line1ended and line2ended then
        ok := true;
        return;
      end if;
      
      -- If only one of the two lines ended, the identifiers have different
      -- lengths, so fail.
      if line1ended and line2ended then
        ok := false;
        return;
      end if;
      
      -- Fail if the characters are not equal or not alphanumeric.
      if not charsEqual(line1(pos1), line2(pos2)) then
        ok := false;
        return;
      end if;
      
      -- Increment positions.
      pos1 := pos1 + 1;
      pos2 := pos2 + 1;
      
    end loop;
    
    -- One of the strings ended before the other, fail.
    ok := false;
    
  end scanAndCompareIdentifier;
  
  -----------------------------------------------------------------------------
  -- Compares and scans a single character
  -----------------------------------------------------------------------------
  procedure scanAndCompareCharacter(
    line1 : in string;
    pos1  : inout positive;
    line2 : in string;
    pos2  : inout positive;
    ok    : out boolean
  ) is
  begin
    
    -- Make sure that a normal character is present on both lines.
    if isWhitespaceChar(line1(pos1)) or isWhitespaceChar(line2(pos2)) then
      ok := false;
      return;
    end if;
    
    -- Fail if the characters are not equal.
    if line1(pos1) /= line2(pos2) then
      ok := false;
      return;
    end if;
    
    -- Increment scanner positions by one.
    pos1 := pos1 + 1;
    pos2 := pos2 + 1;
    
    -- Read to end of whitespace.
    scanToEndOfWhitespace(line1, pos1);
    scanToEndOfWhitespace(line2, pos2);
    
    -- Success.
    ok := true;
    
  end scanAndCompareCharacter;
  
  -----------------------------------------------------------------------------
  -- Attempts to scan a numeric value (0xHEX and decimal are allowed)
  -----------------------------------------------------------------------------
  procedure scanNumeric(
    line  : in string;
    pos   : inout positive;
    consts: inout scan_intConsts_type;
    val   : inout signed(32 downto 0);
    ok    : out boolean
  ) is
    variable radix    : natural;
    variable negative : boolean;
    variable charVal  : integer;
    variable token    : std.textio.line;
    variable const    : std.textio.line;
  begin
    val := (others => '0');
    ok := false;
    
    -- Make sure we're not at the end of the line already.
    if pos > line'length then
      return;
    end if;
    
    -- Test for negative number marker.
    if matchAt(line, pos, "-") then
      radix := 10;
      negative := true;
      pos := pos + 1;
    end if;
    
    -- Skip whitespace between unary minus and number.
    scanToEndOfWhitespace(line, pos);
    
    -- Make sure the previous did not place us at the end of the string.
    if pos > line'length then
      return;
    end if;
    
    -- Test if the next character is a digit. If yes, this is an integer
    -- literal. If no, we must try to match against the strings in the constant
    -- registry.
    if isNumericChar(line(pos)) then
    
      -- Test for radix specifiers.
      if matchAt(line, pos, "0x") then
        
        -- Hexadecimal entry.
        radix := 16;
        pos := pos + 2;
        
      elsif matchAt(line, pos, "0b") then
        
        -- Binary entry.
        radix := 2;
        pos := pos + 2;
        
      elsif matchAt(line, pos, "0") then
        
        -- Octal entry.
        radix := 8;
        pos := pos + 1;
        
        -- In this case we've already processed a digit, so the result is valid.
        ok := true;
        
      else
        
        -- Decimal entry.
        radix := 10;
        
      end if;
      
      -- Make sure the previous did not place us at the end of the string.
      if pos > line'length then
        return;
      end if;
      
      -- Scan the remainder of the literal.
      while pos <= line'length loop
        
        -- Break if the current character is not alphanumeric.
        exit when not isAlphaNumericChar(line(pos));
        
        -- Get the value of the current digit.
        charVal := charToDigitVal(line(pos));
        
        -- Make sure the character is valid for the current radix.
        if (charVal = -1) or (charVal >= radix) then
          ok := false;
          return;
        end if;
        
        -- Add the digit to the value.
        val := resize(val * to_signed(radix, 33), 33) + to_signed(charVal, 33);
        
        -- We've processed at least one digit, so this is a valid number unless
        -- there is garbage at the end.
        ok := true;
        
        -- Increase scanner position.
        pos := pos + 1;
        
      end loop;
      
      -- Scan past trailing whitespace.
      scanToEndOfWhitespace(line, pos);
      
    else
      
      -- Scan the next token, to match against the list of constants.
      scanToken(
        line  => line,
        pos   => pos,
        token => token
      );
      
      -- If there are no constants to match against or if we could not read a
      -- token from the input stream, return an error.
      if consts.pairs = null or token = null then
        return;
      end if;
      
      -- Try to match.
      for i in consts.pairs.all'range loop
        const := consts.pairs.all(i).s;
        if const /= null and matchStr(const.all, token.all) then
          
          -- Found a matching constant name; return its value.
          ok := true;
          val := consts.pairs.all(i).i;
          return;
          
        end if;
      end loop;
      
      -- Could not find a token to match against.
      return;
      
    end if;
    
    -- Negate result if we started with a dash.
    if negative then
      val := -val;
    end if;
    
  end scanNumeric;
  procedure scanNumeric(
    line  : in string;
    pos   : inout positive;
    val   : inout signed(32 downto 0);
    ok    : out boolean
  ) is
    variable consts : scan_intConsts_type;
  begin
    consts := (pairs => null);
    scanNumeric(line, pos, consts, val, ok);
  end scanNumeric;
  
  -----------------------------------------------------------------------------
  -- Attempts to scan a token
  -----------------------------------------------------------------------------
  procedure scanToken(
    line  : in string;
    pos   : inout positive;
    token : inout std.textio.line
  ) is
    variable start  : positive;
  begin
    
    -- Deallocate the incoming token if it is allocated already, because we'll
    -- be overriding it.
    if token /= null then
      deallocate(token);
      token := null;
    end if;
    
    -- Return if we're at the end of the line already.
    if pos > line'length then
      return;
    end if;
    
    -- Assume that the token starts here (precondition) and that the token will
    -- be at least a single character.
    start := pos;
    pos := pos + 1;
    
    -- Scan the token.
    while pos <= line'length loop
      exit when not (isAlphaNumericChar(line(pos)) or line(pos) = '_');
      pos := pos + 1;
    end loop;
    
    -- Allocate a new string for the token.
    token := new string(1 to pos - start);
    token.all := line(start to pos - 1);
    
    -- Scan beyond trailing whitespace.
    scanToEndOfWhitespace(line, pos);
    
  end scanToken;
  
end simUtils_scanner_pkg;
