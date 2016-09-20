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
use rvex.simUtils_pkg.all;
use rvex.simUtils_scanner_pkg.all;
use rvex.core_intIface_pkg.all;
use rvex.core_opcode_pkg.all;
use rvex.core_trap_pkg.all;

--=============================================================================
-- This package contains simulation/elaboration-only methods for basic
-- assembly and disassembly. It also has a method which can pretty-print trap
-- information.
-------------------------------------------------------------------------------
package core_asDisas_pkg is
--=============================================================================
  
  -- Maximum number of syllables in an assembly file.
  constant RVSP_MAX_SYLLABLES : natural := 1024;
  
  -- Data types for a line in an assembly file and an assembly program.
  subtype rvsp_assemblyLine_type is string(1 to 70);
  type rvsp_assemblyProgram_type is array (natural range <>) of rvsp_assemblyLine_type;
  
  -- Assembler instruction memory output type.
  type rvsp_assembledProgram_type is array (0 to RVSP_MAX_SYLLABLES-1) of rvex_syllable_type;
  
  -- Attempts to assemble a single instruction.
  procedure assembleLine(
    source    : in string;
    line      : in positive;
    consts    : inout scan_intConsts_type;
    syllable  : out rvex_syllable_type;
    ok        : out boolean;
    error     : out rvex_string_builder_type
  );
  
  -- Attempts to assemble a program. errorLevel indicates what type of report
  -- should be made when a parse error occurs. Limitations:
  --  - Empty lines and comments are not allowed.
  --  - Maximum assembled program size is limited to RVSP_MAX_SYLLABLES.
  procedure assemble(
    source      : in  rvsp_assemblyProgram_type;
    imem        : out rvsp_assembledProgram_type;
    consts      : inout scan_intConsts_type;
    ok          : out boolean;
    errorLevel  : in  severity_level := failure
  );
  
  -- Disassembles a syllable. If limmh is defined, any arithmetic immediate is
  -- extended by that value. If PC_plusOne is defined, branch targets are
  -- evaluated.
  function disassemble(
    syllable    : in  rvex_syllable_type;
    limmh       : in  rvex_data_type := (others => 'U');
    PC_plusOne  : in  rvex_address_type := (others => 'U')
  ) return rvex_string_builder_type;
  
  -- Pretty print the given trap information using the syntax specifications
  -- in rvex_trap_pkg.
  function prettyPrintTrap(
    ti          : in  trap_info_type
  ) return rvex_string_builder_type;
  
end core_asDisas_pkg;

--=============================================================================
package body core_asDisas_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Attempts to assemble the given instruction with the given pattern
  -----------------------------------------------------------------------------
  procedure asAttemptPattern(
    
    -- Line of source code.
    source    : in string;
    
    -- Pattern to match with.
    pattern   : in string;
    
    -- List of integer constants which can be used in place of immediate
    -- literals.
    consts    : inout scan_intConsts_type;
    
    -- Syllable input/output. Before calling, the opcode and imm select bits
    -- should be set to the values belonging to the pattern.
    syllable  : inout rvex_syllable_type;
    
    -- Whether parsing was successful.
    ok        : out boolean;
    
    -- If parsing was not successful, how far the scanner got before a
    -- discrepency between source and pattern was found.
    charsValid: out natural;
    
    -- String identifying the error if ok is false.
    error     : out rvex_string_builder_type
    
  ) is
    
    -- Scanner positions.
    variable sourcePos      : positive;
    variable patternPos     : positive;
    
    variable val            : signed(32 downto 0);
    variable stepOk         : boolean;
    
  begin
    
    -- Assume parsing failed until we're done.
    ok := false;
    charsValid := 1;
    error := to_rvs("unknown error");
    
    -- Scan beyond any initial whitespace.
    sourcePos := 1;
    patternPos := 1;
    scanToEndOfWhitespace(source, sourcePos);
    scanToEndOfWhitespace(pattern, patternPos);
    
    -- Scan tokens until one or both of the scanners reach the end of their
    -- respective strings.
    while (sourcePos <= source'length) and (patternPos <= pattern'length) loop
      
      -- Scan according to the next token in the pattern.
      if matchAt(pattern, patternPos, "%r1") then
        
        -- General purpose register, stored in bit 22..17.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 6)) /= 0)  then
          error := to_rvs("unknown register");
          return;
        end if;
        syllable(22 downto 17) := std_logic_vector(val(5 downto 0));
        
      elsif matchAt(pattern, patternPos, "%r2") then
        
        -- General purpose register, stored in bit 16..11.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 6)) /= 0)  then
          error := to_rvs("unknown register");
          return;
        end if;
        syllable(16 downto 11) := std_logic_vector(val(5 downto 0));
        
      elsif matchAt(pattern, patternPos, "%r3") then
        
        -- General purpose register, stored in bit 10..5.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 6)) /= 0)  then
          error := to_rvs("unknown register");
          return;
        end if;
        syllable(10 downto 5) := std_logic_vector(val(5 downto 0));
        
      elsif matchAt(pattern, patternPos, "%id")
         or matchAt(pattern, patternPos, "%iu")
         or matchAt(pattern, patternPos, "%ih") then
        
        -- 9-bit low part of the immediate, stored in bit 10..2. We're okay
        -- with immediates being out of range so you can enter the same large
        -- number for the LIMMH and target syllable.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, consts, val, stepOk);
        if not stepOk then
          error := to_rvs("failed to parse immediate numeric");
          return;
        end if;
        syllable(10 downto 2) := std_logic_vector(val(8 downto 0));
        
      elsif matchAt(pattern, patternPos, "%i2") then
        
        -- 23-bit high part of the immediate, stored in bit 24..2, for LIMMH
        -- syllables.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, consts, val, stepOk);
        if not stepOk then
          error := to_rvs("failed to parse long immediate numeric");
          return;
        end if;
        syllable(24 downto 2) := std_logic_vector(val(31 downto 9));
        
      elsif matchAt(pattern, patternPos, "%i1") then
        
        -- Long immediate target lane.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 3)) /= 0) then
          error := to_rvs("invalid LIMMH target lane");
          return;
        end if;
        syllable(27 downto 25) := std_logic_vector(val(2 downto 0));
        
      elsif matchAt(pattern, patternPos, "%b1") then
        
        -- Branch register, stored in bit 26..24.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 3)) /= 0)  then
          error := to_rvs("unknown branch register");
          return;
        end if;
        syllable(26 downto 24) := std_logic_vector(val(2 downto 0));
        
      elsif matchAt(pattern, patternPos, "%b2") then
        
        -- Branch register, stored in bit 19..17.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 3)) /= 0)  then
          error := to_rvs("unknown branch register");
          return;
        end if;
        syllable(19 downto 17) := std_logic_vector(val(2 downto 0));
        
      elsif matchAt(pattern, patternPos, "%b3") then
        
        -- Branch register, stored in bit 4..2.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if (not stepOk) or (to_integer(val(32 downto 3)) /= 0)  then
          error := to_rvs("unknown branch register");
          return;
        end if;
        syllable(4 downto 2) := std_logic_vector(val(2 downto 0));
        
      elsif matchAt(pattern, patternPos, "%bi") then
        
        -- Stack offset for RETURN and RFI, stored in bit 23..5.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if not stepOk then
          error := to_rvs("failed to parse stack offset numeric");
          return;
        end if;
        if resolved(std_ulogic_vector(val(32 downto 18))) = 'X' then
          error := to_rvs("stack offset out of range");
          return;
        end if;
        syllable(23 downto 5) := std_logic_vector(val(18 downto 0));
        
      elsif matchAt(pattern, patternPos, "%bt") then
        
        -- Relative branch target, stored in bit 23..5.
        patternPos := patternPos + 3;
        scanToEndOfWhitespace(pattern, patternPos);
        scanNumeric(source, sourcePos, val, stepOk);
        if not stepOk then
          error := to_rvs("failed to parse stack offset numeric");
          return;
        end if;
        if BRANCH_OFFS_SHIFT = 2 then
          if resolved(std_ulogic_vector(val(32 downto 20))) = 'X' then
            error := to_rvs("branch offset out of range");
            return;
          end if;
          if to_integer(val(1 downto 0)) /= 0 then
            error := to_rvs("branch offset not aligned to syllable");
            return;
          end if;
          syllable(23 downto 5) := std_logic_vector(val(20 downto 2));
        elsif BRANCH_OFFS_SHIFT = 3 then
          if resolved(std_ulogic_vector(val(32 downto 21))) = 'X' then
            error := to_rvs("branch offset out of range");
            return;
          end if;
          if to_integer(val(2 downto 0)) /= 0 then
            error := to_rvs("branch offset not aligned to syllable pair");
            return;
          end if;
          syllable(23 downto 5) := std_logic_vector(val(21 downto 3));
        else
          report "BRANCH_OFFS_SHIFT (core_intIface_pkg.vhd) must be either 2 "
               & "or 3." severity failure;
        end if;
        
      elsif matchAt(pattern, patternPos, "r#")
         or matchAt(pattern, patternPos, "b#")
         or matchAt(pattern, patternPos, "l#") then
        
        -- Match the first character.
        if not charsEqual(source(sourcePos), pattern(patternPos)) then
          error := to_rvs("unknown register");
          return;
        end if;
        
        -- Ignore cluster specifier.
        patternPos := patternPos + 2;
        sourcePos := sourcePos + 2;
        scanToEndOfWhitespace(pattern, patternPos);
        scanToEndOfWhitespace(source, sourcePos);
        
      elsif isAlphaChar(pattern(patternPos)) then
        
        -- Match text literals/identifiers (like the instruction name).
        scanAndCompareIdentifier(source, sourcePos, pattern, patternPos, stepOk);
        if not stepOk then
          error := to_rvs("invalid token");
          return;
        end if;
        
      else
        
        -- Match special characters and digits.
        scanAndCompareCharacter(source, sourcePos, pattern, patternPos, stepOk);
        if not stepOk then
          error := to_rvs("invalid token");
          return;
        end if;
      end if;
      
      -- Detect stop marker.
      if matchAt(source, sourcePos, ";;") then
        sourcePos := sourcePos + 2;
        scanToEndOfWhitespace(source, sourcePos);
        syllable(1) := '1';
      end if;
        
      -- Update number of valid characters in source.
      charsValid := sourcePos;
      
    end loop;
    
    -- If both scanners end up at the end of their respective strings, this is
    -- a match.
    if sourcePos <= source'length then
      error := to_rvs("garbage at end of line");
    elsif patternPos <= pattern'length then
      error := to_rvs("incomplete syllable");
    else
      ok := true;
    end if;
    
  end asAttemptPattern;
  
  -----------------------------------------------------------------------------
  -- Attempts to assemble an instruction with all patterns in the opcode list
  -----------------------------------------------------------------------------
  procedure assembleLine(
    
    -- Line of source code.
    source    : in string;
    
    -- Line number for the error message.
    line      : in positive;
    
    -- List of constant literals which can be used in place of immediates.
    consts    : inout scan_intConsts_type;
    
    -- Syllable output if OK.
    syllable  : out rvex_syllable_type;
    
    -- Whether parsing was successful.
    ok        : out boolean;
    
    -- String identifying the error if ok is false.
    error     : out rvex_string_builder_type
    
  ) is
    
    variable tempSyllable       : rvex_syllable_type;
    variable bestMatchSyllable  : rvex_syllable_type;
    variable tempOK             : boolean;
    variable tempCharsValid     : natural;
    variable bestMatchCharsValid: integer;
    variable tempError          : rvex_string_builder_type;
    variable bestMatchError     : rvex_string_builder_type;
    variable errorBuilder       : rvex_string_builder_type;
    
  begin
    
    -- Set bestCharsValid to -1 so pattern-matching with any possible
    -- instruction will at least override this.
    bestMatchCharsValid := -1;
    
    -- Loop over all opcodes.
    for opcode in 0 to 255 loop
      
      -- Try the syllable using a register for operand 2.
      if OPCODE_TABLE(opcode).valid(0) = '1' then
        tempSyllable := (others => '0');
        tempSyllable(31 downto 24) := uint2vect(opcode, 8);
        asAttemptPattern(
          source, OPCODE_TABLE(opcode).syntax_reg, consts, tempSyllable,
          tempOK, tempCharsValid, tempError
        );
        if tempOK then
          
          -- Complete match, return it greedily.
          syllable := tempSyllable;
          ok := true;
          return;
          
        elsif tempCharsValid > bestMatchCharsValid then
          
          -- Incomplete match, but it's better than what we've found so far.
          bestMatchSyllable := tempSyllable;
          bestMatchCharsValid := tempCharsValid;
          bestMatchError := tempError;
          
        end if;
      end if;
      
      -- Try the syllable using an immediate.
      if OPCODE_TABLE(opcode).valid(1) = '1' then
        tempSyllable := (others => '0');
        tempSyllable(31 downto 24) := uint2vect(opcode, 8);
        tempSyllable(23) := '1';
        asAttemptPattern(
          source, OPCODE_TABLE(opcode).syntax_imm, consts, tempSyllable,
          tempOK, tempCharsValid, tempError
        );
        if tempOK then
          
          -- Complete match, return it greedily.
          syllable := tempSyllable;
          ok := true;
          return;
          
        elsif tempCharsValid > bestMatchCharsValid then
          
          -- Incomplete match, but it's better than what we've found so far.
          bestMatchSyllable := tempSyllable;
          bestMatchCharsValid := tempCharsValid;
          bestMatchError := tempError;
          
        end if;
      end if;
      
    end loop;
    
    -- No match found. Try to return a sensible error.
    rvs_clear(errorBuilder);
    errorBuilder
      := errorBuilder & "Failed to parse line " & integer'image(line) & ": "
       & bestMatchError & " at " & source(1 to bestMatchCharsValid-1) & "<here>"
       & source(bestMatchCharsValid to source'length);
    error := errorBuilder;
    ok := false;
    return;
    
  end assembleLine;
  
  -----------------------------------------------------------------------------
  -- Assembles a program
  -----------------------------------------------------------------------------
  procedure assemble(
    source      : in  rvsp_assemblyProgram_type;
    imem        : out rvsp_assembledProgram_type;
    consts      : inout scan_intConsts_type;
    ok          : out boolean;
    errorLevel  : in  severity_level := failure
  ) is
    variable okTemp : boolean;
    variable error  : rvex_string_builder_type;
  begin
    
    -- Not done yet, set OK to false until we are.
    ok := false;
    
    -- Make sure the source isn't too large.
    if source'length > RVSP_MAX_SYLLABLES then
      report "Source size is greater than RVSP_MAX_SYLLABLES. Please increase "
           & "that number of you need bigger programs." severity errorLevel;
      return;
    end if;
    
    -- Assemble line by line.
    for line in source'range loop
      
      -- Attempt to assemble.
      assembleLine(
        source    => source(line),
        consts    => consts,
        line      => line + 1,
        syllable  => imem(line),
        ok        => okTemp,
        error     => error
      );
      
      -- Check for errors.
      if not okTemp then
        report rvs2str(error) severity errorLevel;
        return;
      end if;
      
    end loop;
    
    -- Done, set OK to true.
    ok := true;
    
  end assemble;
  
  -----------------------------------------------------------------------------
  -- Disassembles a syllable
  -----------------------------------------------------------------------------
  function disassemble(
    syllable    : in  rvex_syllable_type;
    limmh       : in  rvex_data_type := (others => 'U');
    PC_plusOne  : in  rvex_address_type := (others => 'U')
  ) return rvex_string_builder_type is
    
    -- Syntax specification for the given opcode and immediate switch.
    variable syntax       : syllable_syntax_type;
    variable pos          : positive;
    variable disassembly  : rvex_string_builder_type;
    variable imm          : std_logic_vector(8 downto 0);
    variable branchOff    : rvex_address_type;
    
  begin
    
    -- Look up the syntax specification for this syllable.
    if syllable(23) = '0' then
      syntax := OPCODE_TABLE(vect2uint(syllable(31 downto 24))).syntax_reg;
    else
      syntax := OPCODE_TABLE(vect2uint(syllable(31 downto 24))).syntax_imm;
    end if;
    
    -- Loop through the syntax and perform replacements as we go.
    rvs_clear(disassembly);
    pos := 1;
    while pos <= syntax'length loop
      
      -- Handle replace sequences.
      if syntax(pos) = '%' then
        if matchAt(syntax, pos+1, "r1") then
          
          -- "%r1" --> Bit 22..17 in unsigned decimal.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(22 downto 17)));
          next;
          
        elsif matchAt(syntax, pos+1, "r2") then
          
          -- "%r2" --> Bit 16..11 in unsigned decimal.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(16 downto 11)));
          next;
          
        elsif matchAt(syntax, pos+1, "r3") then
          
          -- "%r3" --> Bit 10..5 in unsigned decimal.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(10 downto 5)));
          next;
          
        elsif matchAt(syntax, pos+1, "id") then
          
          -- "%id" --> immediate, respecting long immediates. Displays the immediate
          --           in signed decimal form.
          pos := pos + 3;
          imm := syllable(10 downto 2);
          if limmh(31) /= 'U' then
            rvs_append(disassembly, rvs_int(limmh(31 downto 9) & imm));
          else
            rvs_append(disassembly, rvs_int(imm));
          end if;
          next;
          
        elsif matchAt(syntax, pos+1, "iu") then
          
          -- "%iu" --> Same as above, but in unsigned decimal form.
          pos := pos + 3;
          imm := syllable(10 downto 2);
          if limmh(31) /= 'U' then
            rvs_append(disassembly, rvs_uint(limmh(31 downto 9) & imm));
          else
            rvs_append(disassembly, rvs_uint(imm));
          end if;
          next;
          
        elsif matchAt(syntax, pos+1, "ih") then
          
          -- "%ih" --> Same as above, but in hex form.
          pos := pos + 3;
          imm := syllable(10 downto 2);
          if limmh(31) /= 'U' then
            rvs_append(disassembly, rvs_hex(limmh(31 downto 9) & imm));
          else
            rvs_append(disassembly, rvs_hex(imm));
          end if;
          next;
          
        elsif matchAt(syntax, pos+1, "i1") then
          
          -- "%i1" --> Bit 27..25 in unsigned decimal for LIMMH target lane.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(27 downto 25)));
          next;
          
        elsif matchAt(syntax, pos+1, "i2") then
          
          -- "%i2" --> Bit 24..02 in hex for LIMMH.
          pos := pos + 3;
          rvs_append(disassembly, rvs_hex(syllable(24 downto 2) & "000000000"));
          next;
          
        elsif matchAt(syntax, pos+1, "b1") then
          
          -- "%b1" --> Bit 26..24 in unsigned decimal.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(26 downto 24)));
          next;
          
        elsif matchAt(syntax, pos+1, "b2") then
          
          -- "%b2" --> Bit 19..17 in unsigned decimal.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(19 downto 17)));
          next;
          
        elsif matchAt(syntax, pos+1, "b3") then
          
          -- "%b3" --> Bit 4..2 in unsigned decimal.
          pos := pos + 3;
          rvs_append(disassembly, rvs_uint(syllable(4 downto 2)));
          next;
          
        elsif matchAt(syntax, pos+1, "bi") then
          
          -- "%bi" --> Bit 23..5 in signed decimal (rfi/return stack offset).
          pos := pos + 3;
          rvs_append(disassembly, rvs_int(syllable(23 downto 5)));
          next;
          
        elsif matchAt(syntax, pos+1, "bt") then
          
          -- "%bt" --> Next PC + bit 23..5 in hex (branch target).
          pos := pos + 3;
          if BRANCH_OFFS_SHIFT = 2 then
            branchOff(31 downto 21) := (others => syllable(23));
            branchOff(20 downto 2) := syllable(23 downto 5);
            branchOff(1 downto 0) := (others => '0');
          elsif BRANCH_OFFS_SHIFT = 3 then
            branchOff(31 downto 22) := (others => syllable(23));
            branchOff(21 downto 3) := syllable(23 downto 5);
            branchOff(2 downto 0) := (others => '0');
          else
            report "BRANCH_OFFS_SHIFT (core_intIface_pkg.vhd) must be either 2 "
                 & "or 3." severity failure;
          end if;
          if PC_plusOne(31) /= 'U' then
            rvs_append(disassembly, '=');
            rvs_append(disassembly, rvs_hex(std_logic_vector(
              vect2signed(PC_plusOne) + vect2signed(branchOff)
            )));
          else
            if syllable(23) = '0' then
              rvs_append(disassembly, '+');
              rvs_append(disassembly, rvs_hex(branchOff(21 downto 0)));
            else
              rvs_append(disassembly, '-');
              rvs_append(disassembly, rvs_hex(std_logic_vector(
                -vect2signed(branchOff(21 downto 0))
              )));
            end if;
          end if;
          next;
          
        end if;
      elsif syntax(pos) = '#' then
        
        -- "#"   --> Cluster specifier (0).
        rvs_append(disassembly, '0');
        pos := pos + 1;
        next;
        
      end if;
      
      -- Handle literal characters.
      rvs_append(disassembly, syntax(pos));
      pos := pos + 1;
      next;
      
    end loop;
    
    -- Remove trailing spaces and return.
    rvs_trimTrailingSpaces(disassembly);
    
    -- Append bundle stop token if stop bit is set.
    if syllable(1) = '1' then
      rvs_append(disassembly, " ;;");
    end if;
    
    return disassembly;
    
  end disassemble;
  
  -----------------------------------------------------------------------------
  -- Pretty print the given trap information using the syntax specifications
  -- in rvex_trap_pkg
  -----------------------------------------------------------------------------
  function prettyPrintTrap(
    ti          : in  trap_info_type
  ) return rvex_string_builder_type is
    
    -- Syntax specification for the given opcode and immediate switch.
    variable syntax       : string(1 to TRAP_TABLE(RVEX_TRAP_NONE).name'length);
    variable pos          : positive;
    variable output       : rvex_string_builder_type;
    
  begin
    
    -- Look up the syntax specification for this trap.
    if ti.active = '0' then
      syntax := TRAP_TABLE(RVEX_TRAP_NONE).name;
    else
      syntax := TRAP_TABLE(vect2uint(ti.cause)).name;
    end if;
    
    -- Loop through the syntax and perform replacements as we go.
    rvs_clear(output);
    pos := 1;
    while pos <= syntax'length loop
      
      -- Handle replace sequences.
      if syntax(pos) = '%' then
        if matchAt(syntax, pos+1, "c") then
          
          -- "%c" --> Trap cause represented as an unsigned integer.
          pos := pos + 3;
          rvs_append(output, rvs_uint(ti.cause));
          next;
          
        elsif matchAt(syntax, pos+1, "x") then
          
          -- "%x" --> Trap argument in hex.
          pos := pos + 3;
          rvs_append(output, rvs_hex(ti.arg, 8));
          next;
          
        elsif matchAt(syntax, pos+1, "d") then
          
          -- "%d" --> Trap argument in signed decimal.
          pos := pos + 3;
          rvs_append(output, rvs_int(ti.arg));
          next;
          
        elsif matchAt(syntax, pos+1, "u") then
          
          -- "%u" --> Trap argument in unsigned decimal.
          pos := pos + 3;
          rvs_append(output, rvs_uint(ti.arg));
          next;
          
        end if;
      elsif syntax(pos) = '@' then
        
        -- "@" --> Trap point, if specified.
        -- It's not specified, so ignore this character.
        pos := pos + 1;
        next;
        
      end if;
      
      -- Handle literal characters.
      rvs_append(output, syntax(pos));
      pos := pos + 1;
      next;
      
    end loop;
    
    -- Remove trailing spaces and return.
    rvs_trimTrailingSpaces(output);
    
    return output;
  end prettyPrintTrap;
  
end core_asDisas_pkg;
