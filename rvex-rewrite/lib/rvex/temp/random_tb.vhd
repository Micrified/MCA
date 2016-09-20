library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library std;
use std.textio.all;

library rvex;
--use work.rvex_pkg.all;
--use work.rvex_simUtils_pkg.all;
--use work.rvex_simUtils_asDisas_pkg.all;
--use work.rvex_simUtils_mem_pkg.all;

entity random_tb is
end random_tb;

architecture behavioral of random_tb is
--  signal imem       : rvsp_assembledProgram_type;
--  signal disas      : rvex_string_type;
begin
  
--  test: process is
--    variable imem_v : rvsp_assembledProgram_type;
--    variable ok_v   : boolean;
--    variable test   : std_logic_vector(31 downto 0);
--  begin
--    
--    assemble(
--      source => (
--        -- 0x00000000
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "addcg r0.3, b0.4 = b0.5, r0.6, r0.63                                  ",
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "ldb r0.33 = 42[r0.0]                                                  ",
--        "nop ;;                                                                ",
--
--        -- 0x00000020
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "nop                                                                   ",
--        "stb 33[r0.0] = r0.33                                                  ",
--        "goto -0x40 ;;                                                         "
--      ),
--      imem => imem_v,
--      ok => ok_v
--    );
--    imem <= imem_v;
--    
--    for i in 0 to 15 loop
--      report integer'image(i) & ": " & rvs2str(disassemble(imem_v(i))) severity warning;
--    end loop;
--    
--    test := X"76543210";
--    report "So will this give 3 or 0x3000? " & integer'image(to_integer(unsigned(test(15 downto 12)))) severity warning;
--    report "And this will give zero, right? " & integer'image(to_integer(unsigned(test(11 downto 12)))) severity warning;
--    for i in 1 to 5 loop
--      report "Will it keep spamming null range warnings? " & integer'image(to_integer(unsigned(test(11 downto 12)))) severity warning;
--    end loop;
--    for i in 1 to 5 loop
--      if true or to_integer(unsigned(test(11 downto 12))) = 1 then
--        report "Will it at least not spam null range warnings here?" severity warning;
--      end if;
--    end loop;
--    for i in 1 to 5 loop
--      if to_integer(unsigned(test(11 downto 12))) = 1 or true then
--        report "And it will here?" severity warning;
--      end if;
--    end loop;
--    report "So at least lazy evaluation is a thing. Note to self: add checks all over the place to prevent massive spam in static core designs." severity failure;
--    
--    wait;
--  end process;
  
--  more_tests: process is
--    file f : text;
--    variable l : line;
--  begin
--    file_open(f, "../readme.txt", read_mode);
--    while not endfile(f) loop
--      readline(f, l);
--      report "I read: " & l.all severity note;
--    end loop;
--    file_close(f);
--    wait;
--  end process;
  
--  memtest: process is
--    variable mem          : rvmem_memoryState_type;
--    variable seed1, seed2 : positive;
--    variable addr         : rvex_address_type;
--    variable val          : rvex_data_type;
--    variable readval      : rvex_data_type;
--  begin
--    
--    -- Clear the memory.
--    rvmem_clear(mem);
--    
--    -- Perform random (but repeatable) writes to the memory.
--    seed1 := 1;
--    seed2 := 1;
--    for i in 1 to 1024 loop
--      rvs_randomVect(seed1, seed2, addr);
--      rvs_randomVect(seed1, seed2, val);
--      rvmem_write(mem, addr, val);
--    end loop;
--    
--    -- Now perform the same random accesses and verify that the memory returns
--    -- the correct value.
--    seed1 := 1;
--    seed2 := 1;
--    for i in 1 to 1024 loop
--      rvs_randomVect(seed1, seed2, addr);
--      rvs_randomVect(seed1, seed2, val);
--      readval := rvmem_read(mem, addr);
--      if readval /= val then
--        report "Inconsistency: addr " & rvs_hex(addr, 8) & " should "
--             & "be " & rvs_hex(val, 8) & " bus was "
--             & rvs_hex(readval, 8)
--          severity failure;
--        wait;
--      end if;
--    end loop;
--    
--    report "Memory seems to be sane!" severity note;
--    
--    -- Try to load an srec file.
--    rvmem_clear(mem);
--    rvmem_loadSRec(mem, "../test/from_wikipedia.srec");
--    rvmem_dumpSRec(mem, "../test/output.srec");
--    rvmem_dump(mem, "../test/output.txt");
--    
--    wait;
--    
--  end process;
  
--  do_math: process is
--    procedure dump(s: string) is
--      variable ln : std.textio.line;
--    begin
--      ln := new string(1 to s'length);
--      ln.all := s;
--      writeline(std.textio.output, ln);
--      if ln /= null then
--        deallocate(ln);
--      end if;
--      
--      -- If writing to stdout does not work, you can also use reports:
--      --report s severity note;
--    end procedure;
--    
--    variable op1, op2: unsigned(31 downto 0);
--    variable clz: natural;
--  begin
    
--    op1 := X"F0F0F0F0";
--    op2 := X"FF00FF00";
--    dump("Operating on " & rvs_hex(std_logic_vector(op1)) & " and " & rvs_hex(std_logic_vector(op2)));
--    dump("wait    400 write *  0  " & rvs_hex(std_logic_vector(op1 and op2), 8) & " exclusive");
--    dump("wait    40  write *  4  " & rvs_hex(std_logic_vector(not op1 and op2), 8) & " exclusive");
--    dump("wait    40  write *  8  " & rvs_hex(std_logic_vector(op1 or op2), 8) & " exclusive");
--    dump("wait    40  write * 12  " & rvs_hex(std_logic_vector(not op1 or op2), 8) & " exclusive");
--    dump("wait    40  write * 16  " & rvs_hex(std_logic_vector(op1 xor op2), 8) & " exclusive");
--    dump("");
--    
--    op1 := X"6560d079";
--    op2 := X"2cff892c";
--    dump("Operating on " & rvs_hex(std_logic_vector(op1)) & " and " & rvs_hex(std_logic_vector(op2)));
--    dump("wait    400 write *  0  " & rvs_hex(std_logic_vector(op1 and op2), 8) & " exclusive");
--    dump("wait    40  write *  4  " & rvs_hex(std_logic_vector(not op1 and op2), 8) & " exclusive");
--    dump("wait    40  write *  8  " & rvs_hex(std_logic_vector(op1 or op2), 8) & " exclusive");
--    dump("wait    40  write * 12  " & rvs_hex(std_logic_vector(not op1 or op2), 8) & " exclusive");
--    dump("wait    40  write * 16  " & rvs_hex(std_logic_vector(op1 xor op2), 8) & " exclusive");
--    dump("");
--    
--    op1 := X"6900957a";
--    op2 := X"ed8dc2cc";
--    dump("Operating on " & rvs_hex(std_logic_vector(op1)) & " and " & rvs_hex(std_logic_vector(op2)));
--    dump("wait    400 write *  0  " & rvs_hex(std_logic_vector(op1 and op2), 8) & " exclusive");
--    dump("wait    40  write *  4  " & rvs_hex(std_logic_vector(not op1 and op2), 8) & " exclusive");
--    dump("wait    40  write *  8  " & rvs_hex(std_logic_vector(op1 or op2), 8) & " exclusive");
--    dump("wait    40  write * 12  " & rvs_hex(std_logic_vector(not op1 or op2), 8) & " exclusive");
--    dump("wait    40  write * 16  " & rvs_hex(std_logic_vector(op1 xor op2), 8) & " exclusive");
--    dump("");
    
--    op1 := X"6560D079";
--    op2 := X"6560D079";
--    for i in 33 downto 0 loop
--      dump("-- After testing and modifying bit " & integer'image(i));
--      clz := 0;
--      for i in 31 downto 0 loop
--        exit when op1(i) = '1';
--        clz := clz + 1;
--      end loop;
--      dump("wait    40 write * 4 " & integer'image(clz) & " exclusive");
--      if i < 32 and op1(i) = '1' then
--        dump("read    dmem byte 0 1");
--      else
--        dump("read    dmem byte 0 2");
--      end if;
--      if i < 32 then
--        op1(i) := '0';
--        op2(i) := '1';
--      end if;
--      dump("wait    40 write * 8  " & rvs_hex(std_logic_vector(op1)) & " exclusive");
--      dump("wait    40 write * 12 " & rvs_hex(std_logic_vector(op2)) & " exclusive");
--      dump("");
--    end loop;
--    
--    wait;
--  end process;
  
--  banana: block is
--    signal clk   : std_logic;
--    signal clkEn : std_logic;
--    signal refA   : std_logic;
--    signal refB   : std_logic;
--  begin
--    
--    -- Clock divider.
--    clkDiv: entity rvex.utils_fracDiv
--      generic map (
--        F_CLK     => 10000000.0,
--        F_DESIRED =>  1843200.0,
--        MAX_DEVIATION => 0.0
--      )
--      port map ('0', clk, '1', clkEn);
--    
--    -- 10 MHz.
--    process is
--    begin
--      clk <= '1';
--      wait for 50 ns;
--      clk <= '0';
--      wait for 50 ns;
--    end process;
--    
--    -- 1.8432 MHz ref, rounded down due to sim accuracy.
--    process is
--    begin
--      wait until rising_edge(clkEn);
--      loop
--        refA <= '1';
--        wait for 100 ns;
--        refA <= '0';
--        wait for 442535 ps;
--      end loop;
--    end process;
--    
--    -- 1.8432 MHz ref, rounded up due to sim accuracy.
--    process is
--    begin
--      wait until rising_edge(clkEn);
--      loop
--        refB <= '1';
--        wait for 100 ns;
--        refB <= '0';
--        wait for 442534 ps;
--      end loop;
--    end process;
--    
--  end block;
  
  packetBuf_test: block is
    signal reset                       : std_logic;
    signal clk                         : std_logic;
    signal clkEn                       : std_logic;
    
    -- Buffer write interface.
    signal src2buf_data                : std_logic_vector(7 downto 0);
    signal src2buf_push                : std_logic;
    signal bus2src_full                : std_logic;
    signal src2buf_pop                 : std_logic;
    signal src2buf_reset               : std_logic;
    signal src2buf_swap                : std_logic;
    signal bus2src_swapping            : std_logic;
    
    -- Buffer read interface.
    signal buf2sink_data               : std_logic_vector(7 downto 0);
    signal sink2buf_pop                : std_logic;
    signal buf2sink_empty              : std_logic;
    signal sink2buf_swap               : std_logic;
    signal bus2sink_swapping           : std_logic;
    
  begin
  
    uut: entity rvex.periph_uart_packetBuffer
      port map (
        reset,
        clk,
        clkEn,
        
        -- Buffer write interface.
        src2buf_data,
        src2buf_push,
        bus2src_full,
        src2buf_pop,
        src2buf_reset,
        src2buf_swap,
        bus2src_swapping,
        
        -- Buffer read interface.
        buf2sink_data,
        sink2buf_pop,
        buf2sink_empty,
        sink2buf_swap,
        bus2sink_swapping
      );
    
    clkEn <= '1';
    
    clk_proc: process is
    begin
      clk <= '1';
      wait for 5 ns;
      clk <= '0';
      wait for 5 ns;
    end process;
    
    write_proc: process is
    begin
      src2buf_data <= "UUUUUUUU";
      src2buf_push <= '0';
      src2buf_pop <= '0';
      src2buf_swap <= '0';
      src2buf_reset <= '0';
      
      reset <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      reset <= '0';
      
      for i in 0 to 255 loop
        if i mod 10 = 9 then --bus2src_full = '1' then
          src2buf_swap <= '1';
          wait until rising_edge(clk);
          src2buf_swap <= '0';
          wait until rising_edge(clk);
          while bus2src_swapping = '1' loop
            wait until rising_edge(clk);
          end loop;
          wait until rising_edge(clk);
        end if;
        
        src2buf_data <= std_logic_vector(to_unsigned(i, 8));
        src2buf_push <= '1';
        wait until rising_edge(clk);
        src2buf_data <= "UUUUUUUU";
        src2buf_push <= '0';
        
        wait until rising_edge(clk);
        
      end loop;
      
    end process;
    
    read_proc: process is
    begin
      sink2buf_pop <= '0';
      sink2buf_swap <= '0';
      
      --reset <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      --reset <= '0';
      
      loop
        
        if buf2sink_empty = '1' then
          sink2buf_swap <= '1';
          wait until rising_edge(clk);
          sink2buf_swap <= '0';
        end if;
        
        wait until rising_edge(clk);
        while bus2sink_swapping = '1' loop
          wait until rising_edge(clk);
        end loop;
        
        report "Received " & integer'image(to_integer(unsigned(buf2sink_data))) severity note;
        sink2buf_pop <= '1';
        wait until rising_edge(clk);
        sink2buf_pop <= '0';
        
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
      end loop;
      
    end process;
    
  end block;
  
--  crc_test: block is
--    constant CRC_ORDER                 : natural := 8;
--    constant POLYNOMIAL                : natural := 16#07#;
--    signal reset                       : std_logic;
--    signal clk                         : std_logic;
--    signal clkEn                       : std_logic;
--    signal data                        : std_logic_vector(CRC_ORDER-1 downto 0);
--    signal update                      : std_logic;
--    signal clear                       : std_logic;
--    signal crc                         : std_logic_vector(CRC_ORDER-1 downto 0);
--    signal correct                     : std_logic;
--    
--  begin
--  
--    uut: entity rvex.utils_crc
--      generic map (
--        CRC_ORDER,
--        POLYNOMIAL
--      )
--      port map (
--        reset,
--        clk,
--        clkEn,
--        data,
--        update,
--        clear,
--        crc,
--        correct
--      );
--    
--    clkEn <= '1';
--    
--    clk_proc: process is
--    begin
--      clk <= '1';
--      wait for 5 ns;
--      clk <= '0';
--      wait for 5 ns;
--    end process;
--    
--    crc_proc: process is
--    begin
--      data <= (others => '0');
--      update <= '0';
--      clear <= '0';
--      
--      reset <= '1';
--      wait until rising_edge(clk);
--      wait until rising_edge(clk);
--      reset <= '0';
--      
--      update <= '1';
--      data <= X"30"; -- ASCII 0
--      wait until rising_edge(clk);
--      data <= X"31"; -- ASCII 1
--      wait until rising_edge(clk);
--      data <= X"32"; -- ASCII 2
--      wait until rising_edge(clk);
--      data <= X"33"; -- ASCII 3
--      wait until rising_edge(clk);
--      data <= X"34"; -- ASCII 4
--      wait until rising_edge(clk);
--      data <= X"35"; -- ASCII 5
--      wait until rising_edge(clk);
--      data <= X"36"; -- ASCII 6
--      wait until rising_edge(clk);
--      data <= X"37"; -- ASCII 7
--      wait until rising_edge(clk);
--      data <= X"21"; -- Correct CRC
--      wait until rising_edge(clk);
--      update <= '0';
--      
--      wait;
--      
--    end process;
--    
--  end block;

end behavioral;

