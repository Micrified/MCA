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
use IEEE.math_real.all;

library rvex;

--=============================================================================
-- This is part of the debug section of the UART peripheral. It serves as a
-- packet buffer for either the outgoing or incoming debug packet stream. The
-- buffer is filled by pushing bytes into it on the write side and by popping
-- bytes from it on the read side. Each side operates on a different 32-byte
-- buffer, which is swapped when both sides indicate that they are done with
-- their buffer.
-------------------------------------------------------------------------------
entity periph_uart_packetBuffer is
--=============================================================================
  port (
    
    ---------------------------------------------------------------------------
    -- System control
    ---------------------------------------------------------------------------
    -- Active high synchronous reset input.
    reset                       : in  std_logic;
    
    -- Clock input, registers are rising edge triggered.
    clk                         : in  std_logic;
    
    -- Active high global clock enable input.
    clkEn                       : in  std_logic;
    
    ---------------------------------------------------------------------------
    -- Buffer write interface
    ---------------------------------------------------------------------------
    -- Data write interface. When push is high and full and swapping are low,
    -- data is pushed into the buffer.
    src2buf_data                : in  std_logic_vector(7 downto 0);
    src2buf_push                : in  std_logic;
    bus2src_full                : out std_logic;
    
    -- When high for one cycle, the last byte on the buffer is discarded.
    src2buf_pop                 : in  std_logic;
    
    -- When high, the source buffer will be cleared.
    src2buf_reset               : in  std_logic;
    
    -- When more than one of reset, pop or push are high, the order of
    -- precedence is (from highest priority to lowest):
    --  - reset
    --  - pop
    --  - push
    -- Any of those three commands can be serviced concurrently with a swap
    -- request.
    
    -- Buffer swap signal. When this is high for at least one cycle and the
    -- read interface is also ready for a swap, the buffers are swapped. When
    -- the read side is not ready yet, swapping will be asserted high until
    -- both sides are ready and the buffers are swapped.
    src2buf_swap                : in  std_logic;
    bus2src_swapping            : out std_logic;
    
    ---------------------------------------------------------------------------
    -- Buffer read interface
    ---------------------------------------------------------------------------
    -- Data read interface. When pop is high and empty and swapping are low,
    -- data is set to the next byte in the buffer, or, if the buffer does not
    -- contain any more bytes, empty will be asserted high and data will be
    -- invalid.
    buf2sink_data               : out std_logic_vector(7 downto 0);
    sink2buf_pop                : in  std_logic;
    buf2sink_empty              : out std_logic;
    
    -- Buffer swap signal. When this is high for at least one cycle and the
    -- write interface is also ready for a swap, the buffers are swapped. When
    -- the write side is not ready yet, swapping will be asserted high until
    -- both sides are ready and the buffers are swapped.
    sink2buf_swap               : in  std_logic;
    bus2sink_swapping           : out std_logic
    
  );
end periph_uart_packetBuffer;

--=============================================================================
architecture Behavioral of periph_uart_packetBuffer is
--=============================================================================
  
  -- Swap signal. This is asserted for one cycle when the buffers are swapped
  -- in order to reset the buffer logic.
  signal swap                   : std_logic;
  
  -- Buffer select signal. This is toggled every time swap is high. When low,
  -- the write side has access to the lower buffer and the read side has access
  -- to the high buffer. When high, it's the other way around.
  signal bufSel                 : std_logic;
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -----------------------------------------------------------------------------
  -- Generate buffer swapping logic
  -----------------------------------------------------------------------------
  buf_swap_block: block is
    
    -- Source and sink ready signals. These signals are set when swap is high.
    signal srcReady             : std_logic;
    signal sinkReady            : std_logic;
    
  begin
    
    -- Generate the source/sink ready registers and the bufSel signal.
    buf_swap_regs: process (clk) is
    begin
      if rising_edge(clk) then
        if reset = '1' then
          srcReady <= '0';
          sinkReady <= '1';
          bufSel <= '0';
        elsif clkEn = '1' then
          
          -- Generate source ready register.
          if swap = '1' then
            srcReady <= '0';
          elsif src2buf_swap = '1' then
            srcReady <= '1';
          end if;
          
          -- Generate sink ready register.
          if swap = '1' then
            sinkReady <= '0';
          elsif sink2buf_swap = '1' then
            sinkReady <= '1';
          end if;
          
          -- Generate buffer selection register.
          if swap = '1' then
            bufSel <= not bufSel;
          end if;
          
        end if;
      end if;
    end process;
    
    -- When both sides are ready, assert the swap signal.
    swap <= (srcReady or src2buf_swap) and (sink2buf_swap or sinkReady);
    
    -- Drive the swapping output signals.
    bus2src_swapping <= srcReady;
    bus2sink_swapping <= sinkReady;
    
  end block;
  
  -----------------------------------------------------------------------------
  -- Instantiate the actual buffers
  -----------------------------------------------------------------------------
  buffer_block: block is
    
    -- Buffer RAM. This may be implemented in 8 distributed RAM cells on a
    -- Virtex 6.
    subtype byte_type is std_logic_vector(7 downto 0);
    type byte_array is array (natural range <>) of byte_type;
    signal bufMem   : byte_array(0 to 63);
    
    -- Byte counters and pointers for each buffer. These will just be 
    -- instantiated as a couple LUT registers.
    subtype counter_type is unsigned(5 downto 0);
    type counter_array is array (natural range <>) of counter_type;
    signal count    : counter_array(0 to 1);
    signal ptr      : counter_array(0 to 1);
    
    -- High when the source buffer is empty (count = 0).
    signal sourceEmpty  : std_logic;
    
    -- High when the source buffer is full (count = 32).
    signal sourceFull   : std_logic;
    
    -- High when the sink buffer is empty (ptr = count).
    signal sinkEmpty    : std_logic;
      
  begin
    
    -- Handle data buffer reads.
    buf_read_port_proc: process (bufMem, ptr, bufSel) is
      variable addr : natural;
    begin
      if bufSel = '0' then
        addr := to_integer("1" & ptr(1)(4 downto 0));
      else
        addr := to_integer("0" & ptr(0)(4 downto 0));
      end if;
      buf2sink_data <= bufMem(addr);
    end process;
    
    -- Handle data buffer writes.
    buf_write_port_proc: process (clk) is
      variable addr : natural;
    begin
      if rising_edge(clk) then
        if clkEn = '1' and src2buf_push = '1' and sourceFull = '0' then
          if bufSel = '0' then
            addr := to_integer("0" & ptr(0)(4 downto 0));
          else
            addr := to_integer("1" & ptr(1)(4 downto 0));
          end if;
          bufMem(addr) <= src2buf_data;
        end if;
      end if;
    end process;
    
    -- Update pointer/counter registers.
    buf_ptr_reg_proc: process (clk) is
      variable srcIndex   : natural;
      variable sinkIndex  : natural;
    begin
      if rising_edge(clk) then
        if reset = '1' then
          count <= (others => (others => '0'));
          ptr <= (others => (others => '0'));
        elsif clkEn = '1' then
          
          -- Determine which registers to use for the source and sink sides.
          if bufSel = '0' then
            srcIndex := 0;
            sinkIndex := 1;
          else
            srcIndex := 1;
            sinkIndex := 0;
          end if;
          
          -- Update the source count register.
          if src2buf_reset = '1' then
            count(srcIndex) <= (others => '0');
          elsif src2buf_pop = '1' and sourceEmpty = '0' then
            count(srcIndex) <= count(srcIndex) - 1;
          elsif src2buf_push = '1' and sourceFull = '0' then
            count(srcIndex) <= count(srcIndex) + 1;
          end if;
          
          -- Update the source pointer register.
          if swap = '1' then
            ptr(srcIndex) <= (others => '0');
          elsif src2buf_reset = '1' then
            ptr(srcIndex) <= (others => '0');
          elsif src2buf_pop = '1' and sourceEmpty = '0' then
            ptr(srcIndex) <= ptr(srcIndex) - 1;
          elsif src2buf_push = '1' and sourceFull = '0' then
            ptr(srcIndex) <= ptr(srcIndex) + 1;
          end if;
          
          -- Update the sink count register.
          if swap = '1' then
            count(sinkIndex) <= (others => '0');
          end if;
          
          -- Update the sink ptr register.
          if swap = '1' then
            ptr(sinkIndex) <= (others => '0');
          elsif sink2buf_pop = '1' and sinkEmpty = '0' then
            ptr(sinkIndex) <= ptr(sinkIndex) + 1;
          end if;
          
        end if;
      end if;
    end process;
    
    -- Generate buffer status signals.
    buf_ptr_status_proc: process (bufSel, count, ptr) is
      variable srcIndex   : natural;
      variable sinkIndex  : natural;
    begin
      
      -- Determine which registers to use for the source and sink sides.
      if bufSel = '0' then
        srcIndex := 0;
        sinkIndex := 1;
      else
        srcIndex := 1;
        sinkIndex := 0;
      end if;
      
      -- Generate the control signals.
      if count(srcIndex) = 0 then
        sourceEmpty <= '1';
      else
        sourceEmpty <= '0';
      end if;
      if count(srcIndex) >= 32 then
        sourceFull <= '1';
      else
        sourceFull <= '0';
      end if;
      if ptr(sinkIndex) = count(sinkIndex) then
        sinkEmpty <= '1';
      else
        sinkEmpty <= '0';
      end if;
      
    end process;
    
    -- Forward control signals.
    bus2src_full <= sourceFull;
    buf2sink_empty <= sinkEmpty;
    
  end block;
  
end Behavioral;

