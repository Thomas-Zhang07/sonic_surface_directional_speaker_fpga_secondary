library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Carrier-sync test for the secondary board with the new architecture:
--
--   primary Counter --carrier_sync--> MISC_A --> SyncTrim --> Counter sync
--
-- The primary emits a one-clock pulse at COUNT = 0 (mod 128).  SyncTrim
-- synchronizes it, delays it by the trim value (50 MHz steps) and produces a
-- one-cycle pulse in the 5.12 MHz domain.  The secondary Counter loads
-- SYNC_LOAD on that pulse.
--
-- Checks:
--   * with the default trim (127) the two counters stay in step;
--   * sending trim = 0 (less delay) leaves the secondary about 13 clocks
--     ahead of the primary;
--   * sending trim = 255 (more delay) leaves it about 13 clocks behind;
--   * the difference between those two settings is 255 * 20 ns, i.e. about
--     26 clocks of the 5.12 MHz clock.
entity tb_sync is
end entity;

architecture sim of tb_sync is

    constant FAST_PERIOD : time := 20 ns;          -- 50 MHz
    constant SLOW_PERIOD : time := 195.3125 ns;    -- 5.12 MHz
    constant CARRIER     : integer := 128;

    signal clk_fast : std_logic := '0';
    signal clk_slow : std_logic := '0';
    signal finished : boolean := false;

    signal prim_count : std_logic_vector(7 downto 0) := (others => '0');
    signal sync_pulse : std_logic;
    signal sync_out   : std_logic;
    signal sec_count  : std_logic_vector(7 downto 0);

    signal trim_bit    : std_logic := '0';
    signal trim_strobe : std_logic := '0';

    function phase_of(value : std_logic_vector(7 downto 0)) return integer is
    begin
        return to_integer(unsigned(value)) mod CARRIER;
    end function;

    -- Signed phase difference, in counts, wrapped to -64..63.
    function phase_delta(a, b : std_logic_vector(7 downto 0)) return integer is
        variable d : integer;
    begin
        d := (phase_of(a) - phase_of(b)) mod CARRIER;
        if d > CARRIER / 2 then
            d := d - CARRIER;
        end if;
        return d;
    end function;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

begin

    clk_fast <= not clk_fast after FAST_PERIOD / 2 when not finished else '0';
    clk_slow <= not clk_slow after SLOW_PERIOD / 2 when not finished else '0';

    -- Primary carrier counter and its phase-0 pulse.
    process (clk_slow)
    begin
        if rising_edge(clk_slow) then
            prim_count <= std_logic_vector(unsigned(prim_count) + 1);
        end if;
    end process;
    sync_pulse <= '1' when prim_count(6 downto 0) = "0000000" else '0';

    dut : entity work.SyncTrim
        port map (
            clk_fast => clk_fast,
            clk_slow => clk_slow,
            sync_in => sync_pulse,
            trim_bit => trim_bit,
            trim_strobe => trim_strobe,
            sync_out => sync_out
        );

    secondary : entity work.Counter
        generic map (COUNTER_BITS => 8)   -- default SYNC_LOAD = 16
        port map (clk_in => clk_slow, sync_reset => sync_out, clk_out => sec_count);

    stimulus : process
        procedure send_trim(constant value : integer) is
            variable v : std_logic_vector(7 downto 0);
        begin
            v := std_logic_vector(to_unsigned(value, 8));
            for i in 7 downto 0 loop
                trim_bit <= v(i);
                wait until falling_edge(clk_slow);
                trim_strobe <= '1';
                wait until falling_edge(clk_slow);
                trim_strobe <= '0';
            end loop;
            trim_bit <= '0';
        end procedure;

        procedure measure(variable delta : out integer) is
        begin
            wait until rising_edge(clk_slow);
            delta := phase_delta(sec_count, prim_count);
        end procedure;

        variable mismatches : integer;
        variable delta_default : integer;
        variable delta_zero : integer;
        variable delta_max : integer;
    begin
        -- Let the synchronizers settle over several carrier periods.
        wait for 5 * CARRIER * SLOW_PERIOD;

        measure(delta_default);
        report "default delta = " & integer'image(delta_default) severity note;

        mismatches := 0;
        for i in 0 to 4 * CARRIER - 1 loop
            wait until rising_edge(clk_slow);
            if phase_delta(sec_count, prim_count) /= 0 then
                mismatches := mismatches + 1;
            end if;
        end loop;
        check(mismatches = 0,
              "default trim is not aligned (" & integer'image(mismatches) &
              " mismatched clocks)");

        measure(delta_default);
        check(delta_default = 0, "default trim phase offset is not zero");

        -- trim = 0: 127 * 20 ns earlier than the default.
        send_trim(0);
        wait for 5 * CARRIER * SLOW_PERIOD;
        measure(delta_zero);
        check(delta_zero >= 11 and delta_zero <= 15,
              "trim 0 offset " & integer'image(delta_zero) &
              " is not about +13 clocks");

        -- trim = 255: 128 * 20 ns later than the default.
        send_trim(255);
        wait for 5 * CARRIER * SLOW_PERIOD;
        measure(delta_max);
        check(delta_max <= -11 and delta_max >= -15,
              "trim 255 offset " & integer'image(delta_max) &
              " is not about -13 clocks");

        -- The full trim range must span about 255 * 20 ns = 26 clocks.
        check(delta_zero - delta_max >= 24 and delta_zero - delta_max <= 28,
              "trim range " & integer'image(delta_zero - delta_max) &
              " is not about 26 clocks");

        report "trim offsets: default=" & integer'image(delta_default) &
               " zero=" & integer'image(delta_zero) &
               " max=" & integer'image(delta_max) severity note;

        finished <= true;
        report "TEST PASSED: tb_sync" severity note;
        wait;
    end process;

end architecture;
