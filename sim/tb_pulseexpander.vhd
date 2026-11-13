library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Unit test for PulseExpander (the swap/set stretcher in front of LatchBuffer).
--
-- Checks:
--   * idle output low
--   * a single-cycle input produces exactly one output pulse of ~LENGTH cycles
--   * an input held high produces a steady high output (no low glitch)
--   * releasing the input produces exactly one falling edge and no re-trigger
entity tb_pulseexpander is
end entity;

architecture sim of tb_pulseexpander is
    constant CLK_PERIOD : time := 20 ns;
    constant LENGTH     : integer := 16;

    signal clk      : std_logic := '0';
    signal pulse_in : std_logic := '0';
    signal pulse_out: std_logic;
    signal done     : boolean := false;

    signal rises : integer := 0;
    signal falls : integer := 0;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut : entity work.PulseExpander
        generic map (OUTPUT_LENGTH_CYCLES => LENGTH)
        port map (clk_in => clk, pulse_in => pulse_in, pulse_out => pulse_out);

    monitor : process (clk)
        variable prev : std_logic := '0';
    begin
        if rising_edge(clk) then
            if pulse_out = '1' and prev = '0' then rises <= rises + 1; end if;
            if pulse_out = '0' and prev = '1' then falls <= falls + 1; end if;
            prev := pulse_out;
        end if;
    end process;

    stimulus : process
        variable r0, r1, f0 : integer;
        variable t_rise, t_fall : time;
    begin
        wait for 100 ns;
        check(pulse_out = '0', "idle output low");
        check(pulse_in /= '1', "idle input low");

        -- Single-cycle input -------------------------------------------
        wait until rising_edge(clk);
        pulse_in <= '1';
        wait until rising_edge(clk);
        pulse_in <= '0';
        r0 := rises;
        wait until pulse_out = '1';
        t_rise := now;
        wait until pulse_out = '0';
        t_fall := now;
        check(t_fall - t_rise >= (LENGTH - 1) * CLK_PERIOD and
              t_fall - t_rise <= (LENGTH + 1) * CLK_PERIOD,
              "single-pulse width, measured " & time'image(t_fall - t_rise));
        check(rises = r0 + 1, "single pulse -> exactly one rising edge");
        wait for 40 * CLK_PERIOD;
        check(pulse_out = '0', "output quiet after single pulse");

        -- Input held high -------------------------------------------------
        wait until rising_edge(clk);
        pulse_in <= '1';
        f0 := falls;
        for i in 1 to 100 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            check(pulse_out = '1', "no low glitch while input held high");
            check(falls = f0, "no falling edge while input held high");
        end loop;
        r1 := rises;   -- one rise for the held-high pulse
        pulse_in <= '0';
        wait until pulse_out = '0';
        wait until rising_edge(clk);   -- let the edge monitor update
        wait for 1 ns;
        check(falls = f0 + 1, "exactly one falling edge after release");
        wait for 40 * CLK_PERIOD;
        check(pulse_out = '0', "output stays low after release");
        check(rises = r1, "no re-trigger after release");

        report "TEST PASSED: tb_pulseexpander" severity note;
        done <= true;
        wait;
    end process;
end architecture;
