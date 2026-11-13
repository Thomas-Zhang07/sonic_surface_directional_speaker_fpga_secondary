library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Unit test for the audio gating block.
--
--   mode 00 : data passes through unchanged
--   mode 01 : 40 kHz data is gated by a 262 Hz (C4) square wave
--   mode 11 : gated by a 200 Hz square wave
--   mode 10 : the Little Star state machine -- first note C4 for 0.25 s,
--             then a 0.025 s silent gap, then the second note D4
entity tb_music_player is
end entity;

architecture sim of tb_music_player is

    constant CLK8_PERIOD : time := 195313 ps;   -- 5.12 MHz
    constant C4_HALF      : integer := 9771;
    constant G4_HALF      : integer := 6531;
    constant D4_HALF      : integer := 8707;
    constant HZ200_HALF   : integer := 12800;

    constant C4_PERIOD    : time := 2 * C4_HALF * CLK8_PERIOD;
    constant G4_PERIOD    : time := 2 * G4_HALF * CLK8_PERIOD;
    constant D4_PERIOD    : time := 2 * D4_HALF * CLK8_PERIOD;
    constant HZ200_PERIOD : time := 2 * HZ200_HALF * CLK8_PERIOD;

    signal clk8      : std_logic := '0';
    signal data_out  : std_logic_vector(31 downto 0) := (others => '1');
    signal swap      : std_logic := '0';
    signal mode      : std_logic_vector(1 downto 0) := "00";
    signal music_out : std_logic_vector(31 downto 0);
    signal finished  : boolean := false;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

    -- Wait for the output to reach a level, sampled once per clock.
    procedure wait_level(constant level : in std_logic) is
    begin
        loop
            wait until rising_edge(clk8);
            exit when music_out(0) = level;
        end loop;
    end procedure;

begin

    clk8 <= not clk8 after CLK8_PERIOD / 2 when not finished else '0';

    dut : entity work.music_player
        port map (
            clk8      => clk8,
            data_out  => data_out,
            swap      => swap,
            mode      => mode,
            music_out => music_out
        );

    stimulus : process
        variable t0, t1 : time;
        variable l0, l1 : time;
        variable gap_found : boolean;
    begin
        wait for 1 us;

        -- Mode 00: pass-through ---------------------------------------
        mode <= "00";
        wait for 10 us;
        check(music_out = x"FFFFFFFF", "mode 00 passes data through");
        wait for 10 us;
        check(music_out = x"FFFFFFFF", "mode 00 keeps passing data");

        -- Mode 01: C4 -------------------------------------------------
        mode <= "01";
        wait_level('1');
        check(music_out = x"FFFFFFFF", "C4 high phase drives all channels");
        wait_level('0');
        check(music_out = x"00000000", "C4 low phase silences all channels");
        wait_level('1');
        t0 := now;
        wait_level('0');
        wait_level('1');
        t1 := now;
        check(t1 - t0 > C4_PERIOD - C4_PERIOD / 50 and
              t1 - t0 < C4_PERIOD + C4_PERIOD / 50,
              "C4 gate period is about " & time'image(C4_PERIOD));

        -- Mode 11: 200 Hz ---------------------------------------------
        mode <= "11";
        wait_level('1');
        wait_level('0');
        wait_level('1');
        t0 := now;
        wait_level('0');
        wait_level('1');
        t1 := now;
        check(t1 - t0 > HZ200_PERIOD - HZ200_PERIOD / 50 and
              t1 - t0 < HZ200_PERIOD + HZ200_PERIOD / 50,
              "200 Hz gate period is about " & time'image(HZ200_PERIOD));

        -- Mode 10: Little Star ----------------------------------------
        mode <= "10";
        wait_level('1');
        wait_level('0');
        wait_level('1');
        t0 := now;
        wait_level('0');
        wait_level('1');
        t1 := now;
        check(t1 - t0 > C4_PERIOD - C4_PERIOD / 20 and
              t1 - t0 < C4_PERIOD + C4_PERIOD / 20,
              "Little Star first note is C4");

        -- The first note lasts 0.25 s, then a 0.025 s silent gap.
        gap_found := false;
        for i in 0 to 300 loop
            wait_level('0');
            l0 := now;
            wait_level('1');
            l1 := now;
            if l1 - l0 > 20 ms then
                gap_found := true;
                check(l1 - l0 > 24 ms and l1 - l0 < 28 ms,
                      "note gap is about 25 ms, measured " & time'image(l1 - l0));
                exit;
            end if;
        end loop;
        check(gap_found, "Little Star gap after the first note");

        -- The melody starts 1,1,5,...: the second note is also C4.
        t0 := now;
        wait_level('0');
        wait_level('1');
        t1 := now;
        check(t1 - t0 > C4_PERIOD - C4_PERIOD / 20 and
              t1 - t0 < C4_PERIOD + C4_PERIOD / 20,
              "Little Star second note is C4");

        -- The third note is 5 (G4); finding it proves the sequence advances.
        gap_found := false;
        for i in 0 to 300 loop
            wait_level('0');
            l0 := now;
            wait_level('1');
            l1 := now;
            if l1 - l0 > 20 ms then
                gap_found := true;
                exit;
            end if;
        end loop;
        check(gap_found, "second note gap");

        t0 := now;
        wait_level('0');
        wait_level('1');
        t1 := now;
        check(t1 - t0 > G4_PERIOD - G4_PERIOD / 20 and
              t1 - t0 < G4_PERIOD + G4_PERIOD / 20,
              "Little Star third note is G4");

        finished <= true;
        report "TEST PASSED: tb_music_player" severity note;
        wait;
    end process;

end architecture;
