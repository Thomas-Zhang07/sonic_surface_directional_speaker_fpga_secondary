library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Checks: 16-phase 40 kHz carrier on DATA(0), and OFF (0x10) silences a group.
entity tb_phase_secondary is end entity;
architecture sim of tb_phase_secondary is
    constant CK8 : time := 195313 ps;   -- 5.12 MHz
    signal clk8 : std_logic := '0';
    signal clk  : std_logic;
    signal count: std_logic_vector(7 downto 0) := (others=>'0');
    signal swap, set : std_logic := '0';
    signal phase : std_logic_vector(7 downto 0) := (others=>'0');
    signal address : std_logic_vector(7 downto 0) := (others=>'0');
    signal mode : std_logic_vector(1 downto 0) := "00";
    signal music_out : std_logic_vector(31 downto 0);
    signal done : boolean := false;
    signal measuring : std_logic := '0';
    signal rises : integer := 0;
    signal period : time := 0 ns;
    signal prev : std_logic := '0';
begin
    clk8 <= not clk8 after CK8/2 when not done else '0';
    process(clk8) begin
        if rising_edge(clk8) then count <= std_logic_vector(unsigned(count)+1); end if;
    end process;
    clk <= count(2);

    mon: process(clk8)
        variable last : time := 0 ns;
        variable first : boolean := true;
        variable p : std_logic := '0';
        variable n : integer := 0;
        variable per : time := 0 ns;
    begin
        if rising_edge(clk8) then
            if measuring='1' then
                if music_out(0)='1' and p='0' then
                    if not first then per := now - last; end if;
                    last := now; first := false; n := n+1;
                end if;
                p := music_out(0);
            else
                n := 0; first := true; p := music_out(0);
            end if;
            rises <= n; period <= per;
        end if;
    end process;

    dut: entity work.AllChannels generic map(NBLOCKS=>256)
        port map(clk8=>clk8, clk=>clk, counter=>count, swap=>swap,
                 phase=>phase, set=>set, address=>address,
                 mode=>mode, music_out=>music_out);

    stim: process
        procedure setch(addr: integer; ph: integer) is begin
            address <= std_logic_vector(to_unsigned(addr,8));
            phase   <= std_logic_vector(to_unsigned(ph,8));
            set <= '1'; wait until rising_edge(clk); wait for 1 ns;
            set <= '0'; wait until rising_edge(clk);
        end procedure;
    begin
        wait for 50 us;
        measuring <= '1';
        wait for 300 us;
        assert rises >= 8 report "FAIL: no carrier edges" severity failure;
        assert period > 24 us and period < 26 us
            report "FAIL: carrier period " & time'image(period) severity failure;
        measuring <= '0';
        wait for 5 us;
        -- turn channels 0..7 off, single swap
        for i in 0 to 7 loop setch(i, 16#10#); end loop;
        wait until rising_edge(clk); wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        wait for 30 us;
        measuring <= '1';
        wait for 300 us;
        assert rises = 0 report "FAIL: DATA0 not quiet after OFF, rises=" & integer'image(rises) severity failure;
        report "TEST PASSED: tb_phase_secondary (period=" & time'image(period) & ")" severity note;
        done <= true;
        wait;
    end process;
end architecture;
