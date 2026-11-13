library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Test for the channel array: address decoding, time multiplexing and the
-- on/off behaviour of a programmed phase.
--
-- Each of the 32 DATA lines carries eight channels in time slots selected by
-- counter(2 downto 0). The monitor samples one (group, slot) pair and counts
-- rising edges of that channel's 40 kHz pulse train (one period is 128 clk8
-- cycles, about 25 us).
--
-- The stimulus drives address/phase/set/swap directly rather than through a
-- procedure: VHDL creates a driver for a signal parameter only for the
-- duration of a call, which makes later calls behave as if the signals were
-- undriven.
entity tb_allchannels is
end entity;

architecture sim of tb_allchannels is

    constant CLK8_PERIOD : time := 195313 ps;   -- 5.12 MHz
    constant PULSE_PERIOD : time := 128 * CLK8_PERIOD;

    signal clk8      : std_logic := '0';
    signal clk       : std_logic;
    signal count     : std_logic_vector(7 downto 0) := (others => '0');
    signal counter   : std_logic_vector(7 downto 0);
    signal swap      : std_logic := '0';
    signal set       : std_logic := '0';
    signal phase     : std_logic_vector(7 downto 0) := (others => '0');
    signal address   : std_logic_vector(7 downto 0) := (others => '0');
    signal mode      : std_logic_vector(1 downto 0) := "00";
    signal music_out : std_logic_vector(31 downto 0);
    signal finished  : boolean := false;

    -- Observation point, selected by the stimulus.
    signal obs_group   : integer := 0;
    signal obs_slot    : integer := 0;
    signal clear       : std_logic := '0';
    signal edge_count  : integer := 0;
    signal edge_period : time := 0 ns;
    signal high_samples : integer := 0;   -- longest run of high slot samples

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

begin

    clk8 <= not clk8 after CLK8_PERIOD / 2 when not finished else '0';

    count_process : process (clk8)
    begin
        if rising_edge(clk8) then
            count <= std_logic_vector(unsigned(count) + 1);
        end if;
    end process;

    clk     <= count(2);
    counter <= count;

    dut : entity work.AllChannels
        generic map (NBLOCKS => 256)
        port map (
            clk8      => clk8,
            clk       => clk,
            counter   => counter,
            swap      => swap,
            phase     => phase,
            set       => set,
            address   => address,
            mode      => mode,
            music_out => music_out
        );

    -- One channel's sampled output: count edges and measure the period.
    -- Mux8 registers its output, so the value read at an edge reflects the
    -- slot selected one edge earlier (prev_sel).
    monitor : process (clk8)
        variable prev       : std_logic := '0';
        variable prev_sel   : integer := 0;
        variable last_edge  : time := 0 ns;
        variable first      : boolean := true;
        variable cnt        : integer := 0;
        variable per        : time := 0 ns;
        variable run        : integer := 0;
        variable run_max    : integer := 0;
    begin
        if rising_edge(clk8) then
            if clear = '1' then
                cnt := 0;
                per := 0 ns;
                run := 0;
                run_max := 0;
                first := true;
                prev := '0';
            elsif prev_sel = obs_slot then
                if music_out(obs_group) = '1' then
                    if prev = '0' then
                        cnt := cnt + 1;
                        if not first then
                            per := now - last_edge;
                        end if;
                        last_edge := now;
                        first := false;
                    end if;
                    run := run + 1;
                    if run > run_max then
                        run_max := run;
                    end if;
                else
                    run := 0;
                end if;
                prev := music_out(obs_group);
            end if;
            prev_sel := to_integer(unsigned(count(2 downto 0)));
        end if;
        edge_count  <= cnt;
        edge_period <= per;
        high_samples <= run_max;
    end process;

    stimulus : process
    begin
        wait for 20 us;

        -- Channel 0 (group 0, slot 0) powers up at phase 0 and pulses. ----
        obs_group <= 0;
        obs_slot  <= 0;
        wait for 30 us;
        clear <= '1'; wait for 1 us; clear <= '0';
        wait for 200 us;
        check(edge_count >= 4, "channel 0 pulses, count=" & integer'image(edge_count));
        check(edge_period > PULSE_PERIOD - 2 us and
              edge_period < PULSE_PERIOD + 2 us,
              "channel 0 pulse period, measured " & time'image(edge_period));

        -- Amplitude nibble (high 4 bits) narrows the pulse, centred on the
        -- phase.  Channel 0, phase 5, amplitude code 8 -> width 4 of the
        -- 8-step full pulse; one sample per mux cycle, so 4 high samples.
        address <= x"00";
        phase   <= x"85";
        set <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        wait for 30 us;
        clear <= '1'; wait for 1 us; clear <= '0';
        wait for 200 us;
        check(edge_count >= 4, "amplitude-coded channel pulses, count=" &
              integer'image(edge_count));
        check(high_samples >= 3 and high_samples <= 5,
              "amplitude code 8 = 4-step pulse, got " &
              integer'image(high_samples));

        -- Amplitude code 0 keeps the legacy full-scale 8-step pulse.
        phase <= x"05";
        set <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        wait for 30 us;
        clear <= '1'; wait for 1 us; clear <= '0';
        wait for 200 us;
        check(high_samples >= 7 and high_samples <= 9,
              "legacy full-width pulse stays 8 steps, got " &
              integer'image(high_samples));

        -- Programming channel 0 off must stop it. ------------------------
        address <= x"00";
        phase   <= x"10";
        set <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);

        wait for 30 us;
        clear <= '1'; wait for 1 us; clear <= '0';
        wait for 200 us;
        check(edge_count = 0, "channel 0 off, count=" & integer'image(edge_count));

        -- Address decode: channel 1 off, channel 8 (same slot, group 1) on.
        -- Like a real frame, write every changed channel first and issue a
        -- single swap afterwards: swap exchanges the buffers, so an extra
        -- swap would revert channels that were not written again.
        set <= '1';
        address <= x"00"; phase <= x"00"; wait until rising_edge(clk); wait for 1 ns;
        address <= x"01"; phase <= x"10"; wait until rising_edge(clk); wait for 1 ns;
        address <= x"08"; phase <= x"00"; wait until rising_edge(clk); wait for 1 ns;
        set <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk); wait until rising_edge(clk);

        obs_group <= 0;
        obs_slot  <= 1;
        wait for 30 us;
        clear <= '1'; wait for 1 us; clear <= '0';
        wait for 200 us;
        check(edge_count = 0, "channel 1 off, count=" & integer'image(edge_count));

        obs_group <= 1;
        obs_slot  <= 0;
        wait for 30 us;
        clear <= '1'; wait for 1 us; clear <= '0';
        wait for 200 us;
        check(edge_count >= 4, "channel 8 pulses, count=" & integer'image(edge_count));

        finished <= true;
        report "TEST PASSED: tb_allchannels" severity note;
        wait;
    end process;

end architecture;
