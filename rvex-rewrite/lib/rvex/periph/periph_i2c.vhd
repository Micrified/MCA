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
-- This is an I2C master/slave device with support for multi-master
-- arbitration. Standard-mode, fast-mode, and fast-mode plus are supported. It
-- will initialize in standard-mode based on the CLK_KHZ generic. CLK_KHZ MUST
-- be correct even if the reset state isn't used, because it also specifies the
-- length of the input glitch filter. The software interface is very similar to
-- the microcontrollers produced by NXP (they all have the same interface
-- AFAIK; if not, use LPC13xx as reference).
-------------------------------------------------------------------------------
entity periph_i2c is
--=============================================================================
  generic (
    
    -- Clock frequency in kHz.
    CLK_KHZ                     : natural := 37500
    
  );
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
    -- Slave bus
    ---------------------------------------------------------------------------
    -- Bus interface for register access.
    bus2iic                     : in  bus_mst2slv_type;
    iic2bus                     : out bus_slv2mst_type;
    
    -- Interrupt request output. Active high using one-cycle strobes.
    irq                         : out std_logic;
    
    ---------------------------------------------------------------------------
    -- External I2C pins
    ---------------------------------------------------------------------------
    -- SDA/SCL inputs, non-inverted.
    sda_in                      : in  std_logic;
    scl_in                      : in  std_logic;
    
    -- SDA/SCL outputs. When high, the respective signal should be pulled low.
    -- When low, the output should be hi-Z.
    sda_oen                     : out std_logic;
    scl_oen                     : out std_logic
    
  );
end periph_i2c;

--=============================================================================
architecture Behavioral of periph_i2c is
--=============================================================================
  
  -- Internal reset signal. Asserted when the master reset signal is high or
  -- when the peripheral is disabled.
  signal i2c_reset    : std_logic;
  
  -- SDA pin control signals.
  signal sda_rise     : std_logic;
  signal sda_fall     : std_logic;
  signal sda_read     : std_logic;
  signal sda_release  : std_logic;
  signal sda_assert   : std_logic;
  
  -- SCL pin control signals.
  signal scl_rise     : std_logic;
  signal scl_fall     : std_logic;
  signal scl_read     : std_logic;
  signal scl_release  : std_logic;
  signal scl_assert   : std_logic;
  
  -- Pin manual override for resolving errors.
  signal ovr_enable   : std_logic;
  signal ovr_sda_oen  : std_logic;
  signal ovr_scl_oen  : std_logic;
  
  -- Bit/byte state machine handshake signals.
  signal bit_request  : std_logic_vector(2 downto 0);
  signal bit_ack      : std_logic;
  signal bit_read     : std_logic;
  signal arb_lost     : std_logic;
  
  -- Timing control registers.
  signal time_low     : std_logic_vector(11 downto 0);
  signal time_high    : std_logic_vector(11 downto 0);
  signal time_edge    : std_logic_vector(7 downto 0);
  
--=============================================================================
begin -- architecture
--=============================================================================
  
  -- Reset everything when the master reset is active or when the peripheral is
  -- disabled.
  i2c_reset <= reset; -- TODO
  
  -----------------------------------------------------------------------------
  -- Pin input glitch filters and output stages
  -----------------------------------------------------------------------------
  sda_pin: entity rvex.periph_i2c_pin
    generic map (
      CLK_KHZ     => CLK_KHZ
    )
    port map (
      reset       => i2c_reset,
      clk         => clk,
      clkEn       => clkEn,
      pin_in      => sda_in,
      pin_oen     => sda_oen,
      in_rise     => sda_rise,
      in_fall     => sda_fall,
      in_read     => sda_read,
      out_release => sda_release,
      out_assert  => sda_assert,
      ovr_enable  => ovr_enable,
      ovr_oen     => ovr_sda_oen
    );
  
  scl_pin: entity rvex.periph_i2c_pin
    generic map (
      CLK_KHZ     => CLK_KHZ
    )
    port map (
      reset       => i2c_reset,
      clk         => clk,
      clkEn       => clkEn,
      pin_in      => scl_in,
      pin_oen     => scl_oen,
      in_rise     => scl_rise,
      in_fall     => scl_fall,
      in_read     => scl_read,
      out_release => scl_release,
      out_assert  => scl_assert,
      ovr_enable  => ovr_enable,
      ovr_oen     => ovr_scl_oen
    );
  
  -----------------------------------------------------------------------------
  -- Bit-level state machine
  -----------------------------------------------------------------------------
  bit_state: entity rvex.periph_i2c_bit
    port map (
      reset       => i2c_reset,
      clk         => clk,
      clkEn       => clkEn,
      sda_rise    => sda_rise,
      sda_fall    => sda_fall,
      sda_read    => sda_read,
      sda_release => sda_release,
      sda_assert  => sda_assert,
      scl_rise    => scl_rise,
      scl_fall    => scl_fall,
      scl_read    => scl_read,
      scl_release => scl_release,
      scl_assert  => scl_assert,
      bit_request => bit_request,
      bit_ack     => bit_ack,
      bit_read    => bit_read,
      arb_lost    => arb_lost,
      time_low    => time_low,
      time_high   => time_high,
      time_edge   => time_edge
    );
  
  -----------------------------------------------------------------------------
  -- Byte-level state machine
  -----------------------------------------------------------------------------
  -- TODO
  
  -- idle:
  --   if master start request:
  --     bit start
  --     transfer byte DAT
  --     receive ACK
  --   elsif start detected:
  --     bit wait scl low
  --     transfer byte 0xFF
  --     transmit ACK/NACK depending on received byte
  --
  -- just follow the state machine in the NXP user manual at this point, fuck it
  
end Behavioral;

