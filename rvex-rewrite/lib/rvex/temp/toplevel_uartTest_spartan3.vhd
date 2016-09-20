library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library rvex;
use rvex.common_pkg.all;
use rvex.utils_pkg.all;
use rvex.simUtils_pkg.all;
use rvex.bus_pkg.all;
use rvex.bus_addrConv_pkg.all;

entity toplevel_uartTest_spartan3 is
  port (
    reset   : in  std_logic;
    clk     : in  std_logic;
    rx      : in  std_logic;
    tx      : out std_logic;
    leds    : out std_logic_vector(7 downto 0)
  );
end toplevel_uartTest_spartan3;

architecture behavioral of toplevel_uartTest_spartan3 is
  constant addrMap              : addrRangeAndMapping_array(0 to 1) := (
    0 => addrRangeAndMap(match => "----0000------------------------"),
    1 => addrRangeAndMap(match => "----1111------------------------")
  );
  
  signal uart2dbg_busA          : bus_mst2slv_type;
  signal dbg2uart_busA          : bus_slv2mst_type;
  signal uart2dbg_busB          : bus_mst2slv_type;
  signal dbg2uart_busB          : bus_slv2mst_type;
  signal uart2dbg_busC          : bus_mst2slv_type;
  signal dbg2uart_busC          : bus_slv2mst_type;
  signal tx_s                   : std_logic;
  signal irq                    : std_logic;
begin
  
  -- Instantiate unit under test.
  uut: entity rvex.periph_uart
    generic map (
      F_CLK                     => 50000000.0,
      F_BAUD                    => 115200.0
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => '1',
      
      -- UART pins.
      rx                        => rx,
      tx                        => tx_s,
      
      -- Slave bus.
      bus2uart                  => uart2dbg_busC,
      uart2bus                  => dbg2uart_busC,
      irq                       => irq,
      
      -- Debug interface.
      uart2dbg_bus              => uart2dbg_busA,
      dbg2uart_bus              => dbg2uart_busA
      
    );
  
  -- Instantiate the bus demuxer.
  demux_inst: entity rvex.bus_demux
    generic map (
      ADDRESS_MAP               => addrMap,
      OOR_FAULT_CODE            => X"12345678"
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => '1',
      
      -- Busses.
      mst2demux                 => uart2dbg_busA,
      demux2mst                 => dbg2uart_busA,
      demux2slv(0)              => uart2dbg_busB,
      demux2slv(1)              => uart2dbg_busC,
      slv2demux(0)              => dbg2uart_busB,
      slv2demux(1)              => dbg2uart_busC
      
    );
  
  -- Instantiate a memory for the unit under test to access.
  memory_inst: entity work.bus_ramBlock_singlePort_spartan3
    generic map (
      DEPTH_LOG2B               => 10
    )
    port map (
      
      -- System control.
      reset                     => reset,
      clk                       => clk,
      clkEn                     => '1',
      
      -- Memory port.
      mst2mem_port              => uart2dbg_busB,
      mem2mst_port              => dbg2uart_busB
      
    );
  
  leds <= (
    7 => not rx,
    6 => not tx_s,
    0 => irq,
    others => '0'
  );
  tx <= tx_s;
  
end behavioral;

