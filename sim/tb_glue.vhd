library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Integration test for the top-level glue between Distribute and the array.
--
-- The RTL suites test Distribute and AllChannels separately; this test wires
-- them together exactly as the schematic does:
--
--   serial -> RSSFilter_1 -> UARTReader -> Distribute
--          -> PulseExpander -> LatchBuffer(COUNT(2)) -> AllChannels set
--          -> PulseExpander -> LatchBuffer(COUNT(2)) -> AllChannels swap
--
-- It sends the same 10-byte frame used by the top-level netlist test
-- (0xFE, eight 0x10, 0xFD) and checks that channels 0..7 actually stop.
--
-- clk8 is generated directly (no PLL), so the whole run is short. Every
-- frequency scales together, so the logic behaves exactly as on hardware.
entity tb_glue is
end entity;

architecture sim of tb_glue is

    constant CLK8_PERIOD  : time := 20 ns;
    constant CLKS_PER_BIT : integer := 133;
    constant BIT_PERIOD   : time := CLKS_PER_BIT * CLK8_PERIOD;

    signal clk8      : std_logic := '0';
    signal serial_in : std_logic := '1';
    signal serial_f  : std_logic;
    signal count     : std_logic_vector(7 downto 0);
    signal clk2      : std_logic;
    signal rx_dv     : std_logic;
    signal rx_byte   : std_logic_vector(7 downto 0);
    signal swap_raw  : std_logic;
    signal set_raw   : std_logic;
    signal swap_exp  : std_logic;
    signal set_exp   : std_logic;
    signal swap_e    : std_logic;
    signal set_e     : std_logic;
    signal data_out  : std_logic_vector(7 downto 0);
    signal address   : std_logic_vector(7 downto 0);
    signal mode      : std_logic_vector(1 downto 0);
    signal music_out : std_logic_vector(31 downto 0);
    signal dbg_swap  : std_logic;
    signal dbg_reset : std_logic;
    signal dbg_clk   : std_logic;
    signal finished  : boolean := false;

    signal d0_edges : integer := 0;
    signal d1_edges : integer := 0;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

begin

    clk8 <= not clk8 after CLK8_PERIOD / 2 when not finished else '0';
    clk2 <= count(2);

    counter : entity work.Counter
        generic map (COUNTER_BITS => 8)
        port map (clk_in => clk8, sync_reset => '0', clk_out => count);

    filter : entity work.RSSFilter_1
        generic map (TAPS => 8)
        port map (clk => clk8, bit_in => serial_in, bit_out => serial_f);

    uart : entity work.UARTReader
        generic map (g_CLKS_PER_BIT => CLKS_PER_BIT)
        port map (
            i_Clk => clk8, i_RX_Serial => serial_f,
            o_RX_DV => rx_dv, o_RX_Byte => rx_byte
        );

    dist : entity work.Distribute
        port map (
            CLK => clk8, byte_in => rx_dv, q_in => rx_byte,
            swap_out => swap_raw, set_out => set_raw,
            multiplex_out => open,
            data_out => data_out, address => address,
            debug_swap => dbg_swap, debug_reset => dbg_reset,
            debug_onShiftClocks => dbg_clk, mode => mode
        );

    set_expander : entity work.PulseExpander
        generic map (OUTPUT_LENGTH_CYCLES => 16)
        port map (clk_in => clk8, pulse_in => set_raw, pulse_out => set_exp);

    swap_expander : entity work.PulseExpander
        generic map (OUTPUT_LENGTH_CYCLES => 16)
        port map (clk_in => clk8, pulse_in => swap_raw, pulse_out => swap_exp);

    set_latch : entity work.LatchBuffer
        port map (clk_in => clk2, signal_in => set_exp, signal_out => set_e);

    swap_latch : entity work.LatchBuffer
        port map (clk_in => clk2, signal_in => swap_exp, signal_out => swap_e);

    channel_array : entity work.AllChannels
        generic map (NBLOCKS => 256)
        port map (
            clk8 => clk8, clk => clk2, counter => count,
            swap => swap_e, phase => data_out, set => set_e,
            address => address, mode => mode, music_out => music_out
        );

    -- Continuous transition count on two DATA lines, as in tb_top.
    activity : process (clk8)
        variable p0, p1 : std_logic := '0';
        variable c0, c1 : integer := 0;
    begin
        if rising_edge(clk8) then
            if music_out(0) /= p0 then c0 := c0 + 1; p0 := music_out(0); end if;
            if music_out(1) /= p1 then c1 := c1 + 1; p1 := music_out(1); end if;
        end if;
        d0_edges <= c0;
        d1_edges <= c1;
    end process;

    stimulus : process
        variable base0, base1 : integer;
        variable u : std_logic_vector(7 downto 0);
        type byte_array is array (natural range <>) of integer range 0 to 255;
        constant frame : byte_array := (
            254,
            16, 16, 16, 16, 16, 16, 16, 16,
            253
        );
    begin
        wait for 20 us;

        base0 := d0_edges;
        base1 := d1_edges;
        wait for 200 us;
        check(d0_edges - base0 > 10, "DATA(0) active before frame");
        check(d1_edges - base1 > 10, "DATA(1) active before frame");

        for i in frame'range loop
            serial_in <= '0';
            wait for BIT_PERIOD;

            u := std_logic_vector(to_unsigned(frame(i), 8));
            for b in 0 to 7 loop
                serial_in <= u(b);
                wait for BIT_PERIOD;
            end loop;

            serial_in <= '1';
            wait for BIT_PERIOD;
            wait for BIT_PERIOD;
        end loop;

        wait for 50 us;
        check(dbg_swap = '1', "0xFD toggled debug_swap");

        base0 := d0_edges;
        base1 := d1_edges;
        wait for 200 us;
        report "post-frame: DATA0=" & integer'image(d0_edges - base0) &
               " DATA1=" & integer'image(d1_edges - base1) severity note;
        check(d0_edges = base0,
              "DATA(0) quiet after channels 0..7 off, edges=" &
              integer'image(d0_edges - base0));
        check(d1_edges - base1 > 10, "DATA(1) still active");

        finished <= true;
        report "TEST PASSED: tb_glue" severity note;
        wait;
    end process;

end architecture;
