library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Unit test for PhaseLine: the phase bin must place the pulse at a precise
-- step of the 16-step drive cycle.
--
-- PhaseLine is clocked once per step (in the design, on COUNT(2)) and
-- compares counter(3 downto 0) with the loaded phase. A match at step p
-- makes the pulse rise at step p+1 and stay high for eight steps, so the
-- pulse is a 50 % square wave whose edge position is the phase.
--
-- The entity receives the already-centred on/off step pair.  AllChannels
-- computes them from the frame byte; this test drives them directly.  A
-- width-w pulse for phase p is high for [p+lead+1, p+lead+w+1) with
-- lead = 4 - w/2, so its centre stays at p+5.  Equal steps mean OFF.
-- Amplitude and phase both take effect at swap.
--
-- The test also pins down two behaviours that matter for the frame format:
--   * a trigger written with set is inactive until swap is pulsed
--   * swap *exchanges* the two buffers, so a second swap without a new set
--     reverts the channel to its previous trigger
entity tb_phaseline is
end entity;

architecture sim of tb_phaseline is

    constant CLK_PERIOD : time := 20 ns;
    constant HIGH_STEPS : integer := 8;
    constant CYCLE_STEPS : integer := 16;

    signal clk     : std_logic := '0';
    signal set     : std_logic := '0';
    signal swap    : std_logic := '0';
    signal on_step  : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(1, 4));
    signal off_step : std_logic_vector(3 downto 0) := std_logic_vector(to_unsigned(9, 4));
    signal counter  : std_logic_vector(4 downto 0) := (others => '0');
    signal pulse   : std_logic;
    signal finished : boolean := false;

    signal rise_count  : integer := 0;
    signal rise_pos    : integer := 0;
    signal high_time   : time := 0 ns;
    signal pulse_period : time := 0 ns;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2 when not finished else '0';

    -- Five-bit counter, as the design feeds COUNT(7 downto 3). The module
    -- uses counter(3 downto 0), which cycles through the 16 phase steps.
    counter_process : process (clk)
    begin
        if rising_edge(clk) then
            counter <= std_logic_vector(unsigned(counter) + 1);
        end if;
    end process;

    dut : entity work.PhaseLine
        port map (
            clk     => clk,
            set     => set,
            swap    => swap,
            on_step  => on_step,
            off_step => off_step,
            counter  => counter,
            pulse    => pulse
        );

    -- Record, for every pulse edge, the phase step at which it happened.
    -- The counter is read before the edge (its pre-edge value is the step
    -- the DUT compared against); pulse is read one delta later.
    monitor : process
        variable prev       : std_logic := '0';
        variable step       : integer;
        variable cnt        : integer := 0;
        variable pos        : integer := 0;
        variable last_rise  : time := 0 ns;
        variable high_start : time := 0 ns;
        variable high_v     : time := 0 ns;
        variable per_v      : time := 0 ns;
    begin
        loop
            wait until rising_edge(clk);
            step := to_integer(unsigned(counter(3 downto 0)));
            wait for 1 ns;
            if pulse = '1' and prev = '0' then
                cnt := cnt + 1;
                pos := step;
                if cnt > 1 then
                    per_v := now - last_rise;
                end if;
                last_rise := now;
                high_start := now;
            elsif pulse = '0' and prev = '1' then
                high_v := now - high_start;
            end if;
            prev := pulse;

            rise_count   <= cnt;
            rise_pos     <= pos;
            high_time    <= high_v;
            pulse_period <= per_v;
        end loop;
    end process;

    stimulus : process
        variable base : integer;
    begin
        wait for 100 ns;

        -- Reset state: phase 0, pulse rises at step 1. -------------------
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 1, "phase 0 rise step, got " & integer'image(rise_pos));
        check(high_time = HIGH_STEPS * CLK_PERIOD,
              "phase 0 high time, got " & time'image(high_time));
        check(pulse_period = CYCLE_STEPS * CLK_PERIOD,
              "phase 0 period, got " & time'image(pulse_period));

        -- Load phase 5: rise moves to step 6. ----------------------------
        on_step  <= std_logic_vector(to_unsigned(6, 4));
        off_step <= std_logic_vector(to_unsigned(14, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk);
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 6, "phase 5 rise step, got " & integer'image(rise_pos));

        -- Load phase 15: rise moves to step 0 (wraps). -------------------
        on_step  <= std_logic_vector(to_unsigned(0, 4));
        off_step <= std_logic_vector(to_unsigned(8, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk);
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 0, "phase 15 rise step, got " & integer'image(rise_pos));

        -- Write phase 3 without swapping: output must not change. --------
        on_step  <= std_logic_vector(to_unsigned(4, 4));
        off_step <= std_logic_vector(to_unsigned(12, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 0,
              "pending phase must not apply before swap, got " &
              integer'image(rise_pos));

        -- Swap: the pending phase 3 becomes active (rise at step 4). -----
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 4, "swap applies phase 3, got " & integer'image(rise_pos));

        -- Second swap without a new set exchanges the buffers back. ------
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 0,
              "second swap reverts to phase 15, got " & integer'image(rise_pos));

        -- Amplitude weighting: narrower pulses stay centred on the phase.
        -- Phase 15, width 4 -> high for steps 2..5, centre = 15+5 mod 16.
        on_step  <= std_logic_vector(to_unsigned(2, 4));
        off_step <= std_logic_vector(to_unsigned(6, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 2, "width-4 rise step, got " & integer'image(rise_pos));
        check(high_time = 4 * CLK_PERIOD,
              "width-4 high time, got " & time'image(high_time));

        -- Width 1: high only at step 4.
        on_step  <= std_logic_vector(to_unsigned(4, 4));
        off_step <= std_logic_vector(to_unsigned(5, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 4, "width-1 rise step, got " & integer'image(rise_pos));
        check(high_time = 1 * CLK_PERIOD,
              "width-1 high time, got " & time'image(high_time));

        -- Legacy full-scale pulse: high for steps 0..7.
        on_step  <= std_logic_vector(to_unsigned(0, 4));
        off_step <= std_logic_vector(to_unsigned(8, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait for 40 * CLK_PERIOD;
        check(rise_pos = 0, "legacy width rise step, got " & integer'image(rise_pos));
        check(high_time = HIGH_STEPS * CLK_PERIOD,
              "legacy width high time, got " & time'image(high_time));

        -- Off: equal on/off steps must produce no pulses at all. ----------
        on_step  <= std_logic_vector(to_unsigned(5, 4));
        off_step <= std_logic_vector(to_unsigned(5, 4));
        set <= '1'; wait until rising_edge(clk); set <= '0';
        wait until rising_edge(clk);
        swap <= '1'; wait until rising_edge(clk); swap <= '0';
        wait until rising_edge(clk);
        wait for 40 * CLK_PERIOD;
        base := rise_count;
        wait for 100 * CLK_PERIOD;
        check(rise_count = base,
              "width-0 channel pulses " & integer'image(rise_count - base) & " times");

        finished <= true;
        report "TEST PASSED: tb_phaseline" severity note;
        wait;
    end process;

end architecture;
