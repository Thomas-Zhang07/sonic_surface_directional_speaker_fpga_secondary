library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Carrier-sync test for the secondary board.
--
-- The primary drives MISC_D with COUNT[6] (40 kHz).  On the secondary that
-- signal enters MISC_A, passes through RSSFilter_1 and resets the carrier
-- counter.  For a coherent combined array the two counters must be equal
-- (mod 128, the carrier period) after every sync edge.
--
-- The test models the primary with a free-running Counter and streams
-- COUNT(6) through the same RSSFilter_1 the schematic uses.  It then checks
-- that the filtered edge makes the secondary counter land on the primary
-- value instead of merely resetting to zero (which would leave a constant
-- carrier phase error).  tb_sync also proves that the filter latency is
-- included: a Counter with SYNC_LOAD => 0 shows the error.
entity tb_sync is
end entity;

architecture sim of tb_sync is

    constant CLK_PERIOD : time := 20 ns;      -- 5.12 MHz
    constant CARRIER    : integer := 128;     -- counts per 40 kHz period

    signal clk : std_logic := '0';
    signal finished : boolean := false;

    signal prim_count : std_logic_vector(7 downto 0);
    signal sync_raw   : std_logic;
    signal sync_f     : std_logic;
    signal sec_count  : std_logic_vector(7 downto 0);

    -- Second secondary counter with the legacy zero reset, used as the
    -- negative control.
    signal sec_zero   : std_logic_vector(7 downto 0);

    function phase_of(value : std_logic_vector(7 downto 0)) return integer is
    begin
        return to_integer(unsigned(value)) mod CARRIER;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2 when not finished else '0';

    -- Primary: free-running counter; bit 6 is the 40 kHz sync output.
    primary : entity work.Counter
        generic map (COUNTER_BITS => 8, SYNC_LOAD => 0)
        port map (clk_in => clk, sync_reset => '0', clk_out => prim_count);

    sync_raw <= prim_count(6);

    filter : entity work.RSSFilter_1
        generic map (TAPS => 8)
        port map (clk => clk, bit_in => sync_raw, bit_out => sync_f);

    -- Secondary: same RSSFilter output, default SYNC_LOAD from the entity.
    secondary : entity work.Counter
        generic map (COUNTER_BITS => 8)
        port map (clk_in => clk, sync_reset => sync_f, clk_out => sec_count);

    zero_load : entity work.Counter
        generic map (COUNTER_BITS => 8, SYNC_LOAD => 0)
        port map (clk_in => clk, sync_reset => sync_f, clk_out => sec_zero);

    stimulus : process
        variable mismatches : integer;
        variable zero_errors : integer;
    begin
        -- Let the majority filter settle over several sync periods.
        wait for 3 * CARRIER * CLK_PERIOD;

        mismatches := 0;
        zero_errors := 0;
        for i in 0 to 8 * CARRIER - 1 loop
            wait until rising_edge(clk);
            if phase_of(sec_count) /= phase_of(prim_count) then
                mismatches := mismatches + 1;
            end if;
            if phase_of(sec_zero) = phase_of(prim_count) then
                zero_errors := zero_errors + 1;
            end if;
        end loop;

        assert mismatches = 0
            report "FAIL: secondary counter is not in step with the primary (" &
                   integer'image(mismatches) & " mismatched clocks)"
            severity failure;

        assert zero_errors = 0
            report "FAIL: SYNC_LOAD => 0 accidentally aligned; the test no " &
                   "longer proves the filter latency is compensated"
            severity failure;

        finished <= true;
        report "TEST PASSED: tb_sync" severity note;
        wait;
    end process;

end architecture;
