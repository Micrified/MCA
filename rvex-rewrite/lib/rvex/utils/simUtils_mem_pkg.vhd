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
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.simUtils_pkg.all;

--=============================================================================
-- This package contains a way to make a universally accessible 2^32 byte
-- memory. The memory is obviously implemented in such a way not the entire
-- memory will be kept in physical simulation host memory - allocation is done
-- dynamically when needed. In addition, methods are provided to load the
-- initial contents of a synthesizable memory from an srec.
-------------------------------------------------------------------------------
package simUtils_mem_pkg is
--=============================================================================
  
  -- pragma translate_off
  
  -----------------------------------------------------------------------------
  -- Type declarations
  -----------------------------------------------------------------------------
  -- Size definitions for the number of words in a leaf and the number of child
  -- nodes for a node. In total, i*RVMEM_NODE_SIZE_LOG2 + RVMEM_LEAF_SIZE_LOG2
  -- should equal 30 for some integer i, where i is the number of non-leaf
  -- levels in the tree.
  constant RVMEM_LEAF_SIZE_LOG2 : natural := 8;
  constant RVMEM_NODE_SIZE_LOG2 : natural := 11;
  
  -- Dynamically allocated memory tree types.
  subtype rvmem_bank_type is rvex_data_array(0 to 2**RVMEM_LEAF_SIZE_LOG2-1);
  type rvmem_bank_ptr is access rvmem_bank_type;
  
  -- Pointer to a node list. The node list type is declared later. It's not
  -- an array directly, because ISim doesn't seem to approve of that, but
  -- rather a record containing the array.
  type rvmem_nodeList_type;
  type rvmem_nodeList_ptr is access rvmem_nodeList_type;
  
  -- Node type for the memory tree.
  type rvmem_node_type is record
    
    -- If this is a leaf node, this contains the data.
    leafData      : rvmem_bank_ptr;
    
    -- If this is not a leaf node, this contains pointers to the child nodes.
    children      : rvmem_nodeList_ptr;
    
  end record;
  
  -- Declare the node list type which was announced earlier.
  type rvmem_node_array is array (0 to 2**RVMEM_NODE_SIZE_LOG2-1) of rvmem_node_type;
  type rvmem_nodeList_type is record
    list          : rvmem_node_array;
  end record;

  -- Memory state type.
  type rvmem_memoryState_type is record
    
    -- Memory data access.
    root                        : rvmem_node_type;
    
    -- Default value.
    default                     : rvex_data_type;
    
  end record;
  
  -----------------------------------------------------------------------------
  -- Access methods
  -----------------------------------------------------------------------------
  -- Clears the memory specified by mem and sets the default read value of the
  -- memory to value.
  procedure rvmem_clear(
    mem   : inout rvmem_memoryState_type;
    value : in    std_logic := 'U'
  );
  
  -- Returns the word which is currently in the memory at the given address.
  -- The 2 LSB of the address are ignored.
  procedure rvmem_read(
    mem   : inout rvmem_memoryState_type;
    addr  : in    rvex_address_type;
    value : out   rvex_data_type
  );
  
  -- Writes the given value to memory. The 2 LSB of the address are ignored.
  procedure rvmem_write(
    mem   : inout rvmem_memoryState_type;
    addr  : in    rvex_address_type;
    value : in    rvex_data_type;
    mask  : in    rvex_mask_type := (others => '1')
  );
  
  -- Loads the specified s-record file into the memory, using the specified
  -- memory offset if specified.
  procedure rvmem_loadSRec(
    mem   : inout rvmem_memoryState_type;
    fname : in    string;
    offset: in    rvex_address_type := (others => '0')
  );
  
  -- Dumps the current memory contents to the specified s-record file.
  procedure rvmem_dumpSRec(
    mem   : inout rvmem_memoryState_type;
    fname : in    string
  );
  
  -- Dumps the current memory contents to a human-readable ASCII file.
  procedure rvmem_dump(
    mem   : inout rvmem_memoryState_type;
    fname : in    string
  );
  
  -- pragma translate_on
  
  -- NOTE: while the below function seems to work, it is amazingly slow. So
  -- slow in fact, that it seems to be faster to just synthesize and run a
  -- decent program on the board, just from static elaboration time. You have
  -- been warned.
  -- 
  -- Returns mem, updated with the contents of the specified s-record file.
  -- offset is added to every s-record address before assignment to mem. After
  -- adding, the word address is divided by stride to get an index within mem.
  -- Only if the srec word address + offset was divisible by stride will the
  -- word be saved. If fname is an empty string, this function is no-op.
  function rvmem_initFromSRec(
    mem   : rvex_data_array;
    fname : string;
    offset: rvex_address_type := (others => '0');
    stride: integer := 1
  ) return rvex_data_array;
  
end simUtils_mem_pkg;

--=============================================================================
package body simUtils_mem_pkg is
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Private methods for tree walking in the dynamically allocated memory
  -----------------------------------------------------------------------------
  -- pragma translate_off
  
  -- Deallocates everything in a node.
  procedure clearNode(
    node  : inout rvmem_node_type
  ) is
  begin
    
    -- If this was a leaf, deallocate the memory bank.
    if node.leafData /= null then
      deallocate(node.leafData);
      node.leafData := null;
    end if;
    
    -- If this was not a leaf, deallocate the children.
    if node.children /= null then
      
      -- Walk over the array of children and deallocate their contents.
      for i in node.children.all.list'range loop
        clearNode(node.children.all.list(i));
      end loop;
      
      -- Deallocate the array of children.
      deallocate(node.children);
      node.children := null;
      
    end if;
    
  end clearNode;
  
  -- Reads from a node at the specified address. def is returned if the
  -- addressed location has not been allocated.
  procedure readFromNode(
    node  : inout rvmem_node_type;
    addr  : in    std_logic_vector;
    def   : in    rvex_data_type;
    res   : out   rvex_data_type
  ) is
    variable addrInt  : natural;
    variable memVal   : rvex_data_type;
  begin
    
    -- Default to returning the default value.
    res := def;
    
    if addr'length < RVMEM_LEAF_SIZE_LOG2 then
      
      -- We must end up at RVMEM_LEAF_SIZE_LOG2, or something went wrong.
      report "Leaf/node size configuration error or faulty code in "
           & "rvex_simUtils_mem_pkg!"
        severity failure;
      
    elsif addr'length = RVMEM_LEAF_SIZE_LOG2 then
      
      -- We're reading from a leaf node now. Make sure the leaf data is
      -- initialized.
      if node.leafData = null then
        return;
      end if;
      
      -- Read the value.
      addrInt := to_integer(unsigned(addr));
      res := node.leafData.all(addrInt);
      
    elsif addr'length < RVMEM_NODE_SIZE_LOG2 then
      
      -- We must end up at RVMEM_LEAF_SIZE_LOG2, or something went wrong.
      report "Leaf/node size configuration error or faulty code in "
           & "rvex_simUtils_mem_pkg!"
        severity failure;
      
    else
      
      -- We're still in a non-leaf node. Make sure the array of child nodes is
      -- initialized.
      if node.children = null then
        return;
      end if;
      
      -- Make a recursive call to ourselves to handle the child node.
      addrInt := to_integer(unsigned(addr(addr'high downto (addr'high - RVMEM_NODE_SIZE_LOG2) + 1)));
      readFromNode(
        node  => node.children.all.list(addrInt),
        addr  => addr(addr'high - RVMEM_NODE_SIZE_LOG2 downto 0),
        def   => def,
        res   => res
      );
      
    end if;
    
  end readFromNode;
  
  -- Writes to a node, creating child nodes when needed. def specifies the
  -- default value for the memory, in case a new leaf needs to be initialized.
  procedure writeToNode(
    node  : inout rvmem_node_type;
    addr  : in    std_logic_vector;
    value : in    rvex_data_type;
    mask  : in    rvex_mask_type;
    def   : in    rvex_data_type
  ) is
    variable addrInt  : natural;
    variable memVal   : rvex_data_type;
  begin
    
    if addr'length < RVMEM_LEAF_SIZE_LOG2 then
      
      -- We must end up at RVMEM_LEAF_SIZE_LOG2, or something went wrong.
      report "Leaf/node size configuration error or faulty code in "
           & "rvex_simUtils_mem_pkg!"
        severity failure;
      
    elsif addr'length = RVMEM_LEAF_SIZE_LOG2 then
      
      -- We're writing to a leaf node. Make sure the leaf is initialized.
      if node.leafData = null then
        node.leafData := new rvmem_bank_type;
        node.leafData.all := (0 to 2**RVMEM_LEAF_SIZE_LOG2-1 => def);
      end if;
      
      -- Read the current value of the memory.
      addrInt := to_integer(unsigned(addr));
      memVal := node.leafData.all(addrInt);
      
      -- Modify the bytes with mask set.
      for i in 0 to 3 loop
        if to_X01(mask(i)) = '1' then
          memVal(i*8+7 downto i*8) := value(i*8+7 downto i*8);
        elsif to_X01(mask(i)) = 'X' then
          memVal(i*8+7 downto i*8) := (others => 'X');
        end if;
      end loop;
      
      -- Write back to the memory.
      node.leafData.all(addrInt) := memVal;
      
    elsif addr'length < RVMEM_NODE_SIZE_LOG2 then
      
      -- We must end up at RVMEM_LEAF_SIZE_LOG2, or something went wrong.
      report "Leaf/node size configuration error or faulty code in "
           & "rvex_simUtils_mem_pkg!"
        severity failure;
      
    else
      
      -- We're still in a non-leaf node. Make sure the array of child nodes is
      -- initialized.
      if node.children = null then
        node.children := new rvmem_nodeList_type;
        node.children.all.list := (others => (
          leafData => null,
          children => null
        ));
      end if;
      
      -- Make a recursive call to ourselves to handle the child node.
      addrInt := to_integer(unsigned(addr(addr'high downto (addr'high - RVMEM_NODE_SIZE_LOG2) + 1)));
      writeToNode(
        node  => node.children.all.list(addrInt),
        addr  => addr(addr'high - RVMEM_NODE_SIZE_LOG2 downto 0),
        value => value,
        mask  => mask,
        def   => def
      );
      
    end if;
    
  end writeToNode;
  
  -- pragma translate_on
  
  -----------------------------------------------------------------------------
  -- Private types and methods for SREC parsing and generation
  -----------------------------------------------------------------------------
  -- Byte array type.
  subtype byte_type is std_logic_vector(7 downto 0);
  type byte_array is array (natural range <>) of byte_type;
  
  -- S-record types.
  type srec_record_type is (UNKNOWN_REC, HEADER_REC, DATA_REC, COUNT_REC, TERMINATION_REC);
  
  -- Describes a line in an S-record. For the count record, addr holds the
  -- count value.
  type srec_line_type is record
    rec       : srec_record_type;
    addr      : rvex_address_type;
    data      : byte_array(0 to 255);
    dataCount : natural;
  end record;
  
  -- Parses a byte in an s-record.
  function str2srecByte(s: string; pos: positive) return byte_type is
    variable b : byte_type;
  begin
    b := charToStdLogic(s(pos)) & charToStdLogic(s(pos+1));
    return b;
  end str2srecByte;
  
  -- Returns the checksum for a parsed s-record.
  function srecChecksum(rec: srec_line_type) return byte_type is
    variable sum      : unsigned(7 downto 0);
    variable result   : std_logic_vector(7 downto 0);
  begin
    
    -- Start at 0.
    sum := (others => '0');
    
    -- Determine length byte and add to sum.
    sum := to_unsigned(5 + rec.dataCount, 8);
    if rec.addr(31 downto 24) = X"00" then
      sum := sum - 1;
      if rec.addr(23 downto 16) = X"00" then
        sum := sum - 1;
      end if;
    end if;
    
    -- Accumulate all address and data bytes.
    sum := sum + unsigned(rec.addr(31 downto 24));
    sum := sum + unsigned(rec.addr(23 downto 16));
    sum := sum + unsigned(rec.addr(15 downto  8));
    sum := sum + unsigned(rec.addr( 7 downto  0));
    for i in 0 to rec.dataCount-1 loop
      if not is_X(rec.data(i)) then
        sum := sum + unsigned(rec.data(i));
      end if;
    end loop;
    
    -- Return the one's complement of the sum.
    result := not std_logic_vector(sum);
    return result;
    
  end srecChecksum;
  
  -- Parses an S-record line.
  function str2srec(s: string; line: positive) return srec_line_type is
    variable result   : srec_line_type;
    variable addrSize : natural;
    variable slen     : integer;
    variable count    : integer;
    variable dataOff  : positive;
  begin
    
    -- Determine string length, trimming away any stray /r or /n.
    slen := s'length;
    if (slen > 0) and (s(slen) = LF) then
      slen := slen - 1;
    end if;
    if (slen > 0) and (s(slen) = CR) then
      slen := slen - 1;
    end if;
    
    -- Sanity checking.
    if slen = 0 then
      result.rec := UNKNOWN_REC;
      return result;
    elsif slen < 4 then
      report "Line " & integer'image(line) & " in SREC is invalid, ignoring."
        severity warning;
      result.rec := UNKNOWN_REC;
      return result;
    end if;
    
    -- Test for record type.
    if s(1) = 'S' then
      case s(2) is
        when '0' => result.rec := HEADER_REC;       addrSize := 2;
        when '1' => result.rec := DATA_REC;         addrSize := 2;
        when '2' => result.rec := DATA_REC;         addrSize := 3;
        when '3' => result.rec := DATA_REC;         addrSize := 4;
        when '5' => result.rec := COUNT_REC;        addrSize := 2;
        when '6' => result.rec := COUNT_REC;        addrSize := 3;
        when '7' => result.rec := TERMINATION_REC;  addrSize := 4;
        when '8' => result.rec := TERMINATION_REC;  addrSize := 3;
        when '9' => result.rec := TERMINATION_REC;  addrSize := 2;
        when others => result.rec := UNKNOWN_REC;
      end case;
    else
      result.rec := UNKNOWN_REC;
    end if;
    
    -- Return now if the record type is unknown.
    if result.rec = UNKNOWN_REC then
      report "Unknown record " & s(1 to 2) & " on line " & integer'image(line)
           & " in SREC file, ignoring."
        severity warning;
      return result;
    end if;
    
    -- Check the length of the record.
    count := to_integer(unsigned(str2srecByte(s, 3)));
    if slen /= count*2 + 4 then
      report "Record " & s(1 to 2) & " on line " & integer'image(line)
           & " in SREC file has incorrect length, ignoring."
        severity warning;
      result.rec := UNKNOWN_REC;
      return result;
    end if;
    
    -- Turn the count into a data byte count by getting rid of the size of the
    -- address and checksum.
    count := count - (addrSize + 1);
    
    -- This count should be 0 for COUNT and TERMINATION records and greater
    -- than or equal to zero for HEADER and DATA records.
    if (count < 0) or ((count > 0) and (result.rec = COUNT_REC or result.rec = TERMINATION_REC)) then
      report "Record " & s(1 to 2) & " on line " & integer'image(line)
           & " in SREC file has incorrect length, ignoring."
        severity warning;
      result.rec := UNKNOWN_REC;
      return result;
    end if;
    
    -- Store the byte count (can't do this earlier, because the computed byte
    -- count can be negative for invalid records and dataCount is a natural).
    result.dataCount := count;
    
    -- Parse the address field.
    case addrSize is
      when 2 => result.addr := X"0000" & str2srecByte(s, 5) & str2srecByte(s, 7);
      when 3 => result.addr := X"00" & str2srecByte(s, 5) & str2srecByte(s, 7) & str2srecByte(s, 9);
      when others => result.addr := str2srecByte(s, 5) & str2srecByte(s, 7) & str2srecByte(s, 9) & str2srecByte(s, 11);
    end case;
    
    -- Determine at which character in the string the data starts.
    dataOff := 5 + addrSize * 2;
    
    -- Parse the data.
    for i in 0 to result.dataCount-1 loop
      result.data(i) := str2srecByte(s, dataOff + 2*i);
    end loop;
    
    -- Verify checksum.
    if str2srecByte(s, dataOff + 2*result.dataCount) /= srecChecksum(result) then
      report "Record " & s(1 to 2) & " on line " & integer'image(line)
           & " in SREC file has incorrect checksum."
        severity warning;
    end if;
    
    -- Return the parsed record.
    return result;
    
  end str2srec;
  
  -- pragma translate_off
  
  -- Output file format for srec2str and dumpNode.
  type dumpFormat_type is (DUMP_SREC, DUMP_HUMAN);
  
  -- Converts a parsed s-record to a string. The DUMP_HUMAN format assumes that
  -- addresses are aligned to 16 byte boundaries and that each record holds 16
  -- bytes, otherwise the header won't look nice. When an empty line is
  -- returned, it should not be added to the file.
  function srec2str(sr: srec_line_type; format: dumpFormat_type) return rvex_string_builder_type is
    variable sb       : rvex_string_builder_type;
    variable addrSize : natural;
  begin
    rvs_clear(sb);
    
    if format = DUMP_SREC then
      
      -- Dump as line in SREC file.
      
      -- Determine the number of bytes to use for the address field.
      addrSize := 4;
      if sr.addr(31 downto 24) = X"00" then
        addrSize := addrSize - 1;
        if sr.addr(23 downto 16) = X"00" then
          addrSize := addrSize - 1;
        end if;
      end if;
      
      -- Write the record type.
      case sr.rec is
        when UNKNOWN_REC =>
          return to_rvs("");
          
        when HEADER_REC =>
          sb := to_rvs("S0");
          
        when DATA_REC =>
          case addrSize is
            when 2 => sb := to_rvs("S1");
            when 3 => sb := to_rvs("S2");
            when others => sb := to_rvs("S3");
          end case;
          
        when COUNT_REC =>
          case addrSize is
            when 2 => sb := to_rvs("S5");
            when others => sb := to_rvs("S6");
          end case;
          
        when TERMINATION_REC =>
          case addrSize is
            when 2 => sb := to_rvs("S9");
            when 3 => sb := to_rvs("S8");
            when others => sb := to_rvs("S7");
          end case;
          
      end case;
      
      -- Write the length field.
      rvs_append(sb, rvs_hex_no0x(std_logic_vector(to_unsigned(
        addrSize + sr.dataCount + 1, 8
      )), 2));
      
      -- Write the address field.
      for i in addrSize-1 downto 0 loop
        rvs_append(sb, rvs_hex_no0x(sr.addr(i*8+7 downto i*8), 2));
      end loop;
      
      -- Write the data.
      for i in 0 to sr.dataCount-1 loop
        if is_X(sr.data(i)) then
          rvs_append(sb, "00");
        else
          rvs_append(sb, rvs_hex_no0x(sr.data(i), 2));
        end if;
      end loop;
      
      -- Write the checksum.
      rvs_append(sb, rvs_hex_no0x(srecChecksum(sr), 2));
      
    elsif format = DUMP_HUMAN then
      
      -- Dump in human readable form.
      case sr.rec is
        when HEADER_REC =>
          return to_rvs("Address       00 01 02 03   04 05 06 07   08 09 0A 0B   0C 0D 0E 0F");
          
        when DATA_REC =>
          rvs_append(sb, rvs_hex(sr.addr, 8));
          rvs_append(sb, " => ");
          for i in 0 to sr.dataCount-1 loop
            rvs_append(sb, rvs_hex_no0x(sr.data(i), 2));
            if i mod 4 = 3 then
              rvs_append(sb, "   ");
            else
              rvs_append(sb, " ");
            end if;
          end loop;
          
        when others =>
          return to_rvs("");
          
      end case;
      
    end if;
    
    -- Return.
    return sb;
    
  end srec2str;
  
  -- Dumps a node to a file.
  procedure dumpNode(
    node    : inout rvmem_node_type;
    file f  :       text;
    format  : in    dumpFormat_type;
    count   : inout natural;
    def     : in    rvex_data_type;
    addr    : in    std_logic_vector := ""
  ) is
    variable sb : rvex_string_builder_type;
    variable s  : line;
  begin
    
    -- If this is a leaf, dump its contents.
    if node.leafData /= null then
      for i in 0 to 2**(RVMEM_LEAF_SIZE_LOG2-2)-1 loop
        if node.leafData.all(i*4+0) /= def or node.leafData.all(i*4+1) /= def or
           node.leafData.all(i*4+2) /= def or node.leafData.all(i*4+3) /= def
        then
          sb := srec2str((
            rec => DATA_REC,
            addr => addr & std_logic_vector(to_unsigned(i, RVMEM_LEAF_SIZE_LOG2-2)) & "0000",
            data => (
              0  => node.leafData.all(i*4+0)(31 downto 24),
              1  => node.leafData.all(i*4+0)(23 downto 16),
              2  => node.leafData.all(i*4+0)(15 downto  8),
              3  => node.leafData.all(i*4+0)( 7 downto  0),
              4  => node.leafData.all(i*4+1)(31 downto 24),
              5  => node.leafData.all(i*4+1)(23 downto 16),
              6  => node.leafData.all(i*4+1)(15 downto  8),
              7  => node.leafData.all(i*4+1)( 7 downto  0),
              8  => node.leafData.all(i*4+2)(31 downto 24),
              9  => node.leafData.all(i*4+2)(23 downto 16),
              10 => node.leafData.all(i*4+2)(15 downto  8),
              11 => node.leafData.all(i*4+2)( 7 downto  0),
              12 => node.leafData.all(i*4+3)(31 downto 24),
              13 => node.leafData.all(i*4+3)(23 downto 16),
              14 => node.leafData.all(i*4+3)(15 downto  8),
              15 => node.leafData.all(i*4+3)( 7 downto  0),
              others => X"00"
            ),
            dataCount => 16
          ), format);
          if sb.len /= 0 then
            write(s, rvs2str(sb));
            writeline(f, s);
            count := count + 1;
          end if;
        end if;
      end loop;
    end if;
    
    -- If this is not a leaf, dump the children recursively.
    if node.children /= null then
      for i in node.children.all.list'range loop
        dumpNode(
          node    => node.children.all.list(i),
          f       => f,
          format  => format,
          count   => count,
          def     => def,
          addr    => addr & std_logic_vector(to_unsigned(i, RVMEM_NODE_SIZE_LOG2))
        );
      end loop;
    end if;
    
  end dumpNode;
  
  -- Dumps the current memory contents to the specified file in the specified
  -- format.
  procedure dumpMem(
    mem     : inout rvmem_memoryState_type;
    fname   : in    string;
    format  : in    dumpFormat_type
  ) is
    file     f      : text;
    variable count  : natural;
    variable sb     : rvex_string_builder_type;
    variable s      : line;
  begin
    file_open(f, fname, write_mode);
    
    -- Write header.
    sb := srec2str((
      rec => HEADER_REC,
      addr => X"00000000",
      data => (
        0  => X"72", -- r
        1  => X"76", -- v
        2  => X"65", -- e
        3  => X"78", -- x
        4  => X"20",
        5  => X"64", -- d
        6  => X"75", -- u
        7  => X"6D", -- m
        8  => X"70", -- p
        others => X"00"
      ),
      dataCount => 10 -- Include null termination.
    ), format);
    if sb.len /= 0 then
      write(s, rvs2str(sb));
      writeline(f, s);
    end if;
    
    -- Store the number of data records written for the count record.
    count := 0;
    
    -- Dump the memory.
    dumpNode(
      node    => mem.root,
      f       => f,
      format  => format,
      count   => count,
      def     => mem.default,
      addr    => ""
    );
    
    -- Write the count record.
    sb := srec2str((
      rec => COUNT_REC,
      addr => std_logic_vector(to_unsigned(count, 32)),
      data => (others => X"00"),
      dataCount => 0
    ), format);
    if sb.len /= 0 then
      write(s, rvs2str(sb));
      writeline(f, s);
    end if;
    
    -- Write the termination record.
    sb := srec2str((
      rec => TERMINATION_REC,
      addr => X"00000000",
      data => (others => X"00"),
      dataCount => 0
    ), format);
    if sb.len /= 0 then
      write(s, rvs2str(sb));
      writeline(f, s);
    end if;
    
    file_close(f);
  end dumpMem;
  
  -- pragma translate_on
  
  -----------------------------------------------------------------------------
  -- Public methods
  -----------------------------------------------------------------------------
  -- pragma translate_off
  
  -- Clears the memory specified by mem and sets the default read value of the
  -- memory to value.
  procedure rvmem_clear(
    mem   : inout rvmem_memoryState_type;
    value : in    std_logic := 'U'
  ) is
  begin
    
    -- Deallocate the memory structure.
    clearNode(mem.root);
    
    -- Set the default value.
    mem.default := (others => value);
    
  end rvmem_clear;
  
  -- Returns the word which is currently in the memory at the given address.
  -- The 2 LSB of the address are ignored.
  procedure rvmem_read(
    mem   : inout rvmem_memoryState_type;
    addr  : in    rvex_address_type;
    value : out   rvex_data_type
  ) is
  begin
    
    -- If we're reading from an undefined address, always return X.
    if is_X(addr(31 downto 2)) then
      value := (others => 'X');
      return;
    end if;
    
    -- Defer to the private tree-walking read method. Ignore the two LSBs in
    -- the memory address because the memory is word-aligned.
    readFromNode(
      node  => mem.root,
      addr  => norm(addr(31 downto 2)),
      def   => mem.default,
      res   => value
    );
    
  end rvmem_read;
  
  -- Writes the given value to memory. The 2 LSB of the address are ignored.
  procedure rvmem_write(
    mem   : inout rvmem_memoryState_type;
    addr  : in    rvex_address_type;
    value : in    rvex_data_type;
    mask  : in    rvex_mask_type := (others => '1')
  ) is
  begin
    
    -- An undefined address while writing is bad.
    if is_X(addr(31 downto 2)) then
      rvmem_clear(mem, 'X');
      report "System attempted to write to an undefined address! Entire "
           & "memory is reset to X!"
        severity warning;
      return;
    end if;
    
    -- Defer to the private tree-walking write method. Ignore the two LSBs in
    -- the memory address because the memory is word-aligned.
    writeToNode(
      node  => mem.root,
      addr  => norm(addr(31 downto 2)),
      value => value,
      mask  => mask,
      def   => mem.default
    );
    
  end rvmem_write;
  
  -- Loads the specified s-record file into the memory, using the specified
  -- memory offset if specified.
  procedure rvmem_loadSRec(
    mem   : inout rvmem_memoryState_type;
    fname : in    string;
    offset: in    rvex_address_type := (others => '0')
  ) is
    file     f    : text;
    variable l    : line;
    variable sr   : srec_line_type;
    variable lNr  : positive;
    variable addr : unsigned(31 downto 0);
    variable index: natural;
    variable data : rvex_data_type;
    variable mask : rvex_mask_type;
  begin
    file_open(f, fname, read_mode);
    lNr := 1;
    while not endfile(f) loop
      
      -- Parse the s-record on this line.
      readline(f, l);
      sr := str2srec(l.all, lNr);
      
      -- Increment line number.
      lNr := lNr + 1;
      
      -- Ignore non-DATA s-records.
      if sr.rec /= DATA_REC then
        next;
      end if;
      
      -- Write the bytes to the memory.
      index := 0;
      addr := unsigned(sr.addr) + unsigned(offset);
      while index < sr.dataCount loop
        
        -- Do a word access if we can, otherwise do byte accesses. This can be
        -- done a bit nicer but lazy.
        if (addr(1 downto 0) = 0) and index + 4 <= sr.dataCount then
          
          -- Put the data together.
          data := sr.data(index)
                & sr.data(index + 1)
                & sr.data(index + 2)
                & sr.data(index + 3);
          
          -- Determine the mask.
          mask := "1111";
          
          -- Perform the write.
          rvmem_write(mem, std_logic_vector(addr), data, mask);
          
          -- Increment address and index.
          index := index + 4;
          addr := addr + 4;
          
        else
          
          -- Put the data together.
          data := sr.data(index)
                & sr.data(index)
                & sr.data(index)
                & sr.data(index);
          
          -- Determine the mask.
          case addr(1 downto 0) is
            when "00" =>   mask := "1000";
            when "01" =>   mask := "0100";
            when "10" =>   mask := "0010";
            when "11" =>   mask := "0001";
            when others => mask := "0000";
          end case;
          
          -- Perform the write.
          rvmem_write(mem, std_logic_vector(addr), data, mask);
          
          -- Increment address and index.
          index := index + 1;
          addr := addr + 1;
          
        end if;
        
      end loop;
      
    end loop;
    file_close(f);
  end rvmem_loadSRec;
  
  -- Dumps the current memory contents to the specified s-record file.
  procedure rvmem_dumpSRec(
    mem   : inout rvmem_memoryState_type;
    fname : in    string
  ) is
  begin
    dumpMem(
      mem     => mem,
      fname   => fname,
      format  => DUMP_SREC
    );
  end rvmem_dumpSRec;
  
  -- Dumps the current memory contents to a human-readable ASCII file.
  procedure rvmem_dump(
    mem   : inout rvmem_memoryState_type;
    fname : in    string
  ) is
  begin
    dumpMem(
      mem     => mem,
      fname   => fname,
      format  => DUMP_HUMAN
    );
  end rvmem_dump;
  
  -- pragma translate_on
  
  -- Returns mem, updated with the contents of the specified s-record file.
  -- offset is added to every s-record address before assignment to mem. After
  -- adding, the word address is divided by stride to get an index within mem.
  -- Only if the srec word address + offset was divisible by stride will the
  -- word be saved. If fname is an empty string, this function is no-op.
  function rvmem_initFromSRec(
    mem   : rvex_data_array;
    fname : string;
    offset: rvex_address_type := (others => '0');
    stride: integer := 1
  ) return rvex_data_array is
    variable res  : rvex_data_array(mem'range);
    file     f    : text;
    variable l    : line;
    variable sr   : srec_line_type;
    variable lNr  : positive;
    variable addr : unsigned(31 downto 0);
    variable index: natural;
    variable di   : integer;
  begin
    
    -- If fname is an empty string, don't do anything.
    if fname = "" then
      return mem;
    end if;
    
    -- Initialize result with the given memory array.
    res := mem;
    
    -- Read the s-record file.
    file_open(f, fname, read_mode);
    report "Reading s-rec file " & fname & " while elaborating initial "
         & "contents for " & integer'image(res'length) & "-word memory."
      severity note;
    lNr := 1;
    while not endfile(f) loop
      
      -- Parse the s-record on this line.
      readline(f, l);
      sr := str2srec(l.all, lNr);
      
      -- Increment line number.
      lNr := lNr + 1;

      -- Ignore non-DATA s-records.
      if sr.rec /= DATA_REC then
        next;
      end if;
      
      -- Write the bytes to the memory.
      index := 0;
      addr := unsigned(sr.addr) + unsigned(offset);
      
      while index < sr.dataCount loop
        
        -- Do a word access if we can, otherwise do byte accesses. This can be
        -- done a bit nicer but lazy.
        if (addr(1 downto 0) = 0) and index + 4 <= sr.dataCount then
          
          -- Determine the index to update.
          di := to_integer(shift_right(addr(31 downto 0), 2));
          if di mod stride = 0 then
            di := di / stride;
            if (di >= res'low) and (di <= res'high) then
              
              -- Perform the update.
              res(di) := sr.data(index)
                       & sr.data(index + 1)
                       & sr.data(index + 2)
                       & sr.data(index + 3);
              
            end if;
          end if;
          
          -- Increment address and index.
          index := index + 4;
          addr := addr + 4;
          
        else
          
          -- Determine the index to update.
          di := to_integer(shift_right(addr(31 downto 0), 2));
          if di mod stride = 0 then
            di := di / stride;
            if (di >= res'low) and (di <= res'high) then
              
              -- Perform the update.
              case addr(1 downto 0) is
                when "00" => res(di)(31 downto 24) := sr.data(index);
                when "01" => res(di)(23 downto 16) := sr.data(index);
                when "10" => res(di)(15 downto  8) := sr.data(index);
                when "11" => res(di)( 7 downto  0) := sr.data(index);
                when others => null;
              end case;
              
            end if;
          end if;
          
          -- Increment address and index.
          index := index + 1;
          addr := addr + 1;
          
        end if;
        
      end loop;
      
    end loop;
    file_close(f);
    
    return res;
  end rvmem_initFromSRec;
  
end simUtils_mem_pkg;
