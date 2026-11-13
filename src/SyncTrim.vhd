library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- Synchronize the primary's 40 kHz carrier-start pulse and delay it by a
-- programmable number of 50 MHz clocks (20 ns = 0.288 degrees at 40 kHz).
--
-- The input is asynchronous to both clocks.  A 2-flop synchronizer in the
-- 50 MHz domain removes metastability; the delayed edge is converted into a
-- toggle that the 5.12 MHz domain samples with another 2-flop synchronizer.
-- A toggle (not a pulse) is used because the 50 MHz delay can be longer than
-- one 5.12 MHz period, and a short pulse could be missed by the slow domain.
--
-- The trim value arrives serially from Distribute (trim_bit / trim_strobe,
-- MSB first, eight strobes) to avoid an 8-bit bus in the schematic.  Both
-- modules use the same 5.12 MHz clock, so the shift needs no CDC; the stable
-- register is then sampled by the 50 MHz domain at the next sync edge.
--
-- The resulting one-cycle pulse in the 5.12 MHz domain resets the carrier
-- counter.  Its latency through the synchronizers is fixed and is absorbed by
-- the Counter's SYNC_LOAD constant; the trim adds 0..255 * 20 ns on top.
entity SyncTrim is
    port (
        clk_fast     : in  STD_LOGIC;                  -- 50 MHz
        clk_slow     : in  STD_LOGIC;                  -- 5.12 MHz
        sync_in      : in  STD_LOGIC;                  -- from MISC_A
        trim_bit     : in  STD_LOGIC := '0';
        trim_strobe  : in  STD_LOGIC := '0';
        sync_out     : out STD_LOGIC := '0'
    );
end SyncTrim;

architecture Behavioral of SyncTrim is
    -- 5.12 MHz domain
    signal s_trim_reg    : STD_LOGIC_VECTOR(7 downto 0) := "01111111";

    -- 50 MHz domain
    signal s_meta        : STD_LOGIC := '0';
    signal s_sync        : STD_LOGIC := '0';
    signal s_sync_prev   : STD_LOGIC := '0';
    signal s_delay       : unsigned(7 downto 0) := (others => '0');
    signal s_pending     : STD_LOGIC := '0';
    signal s_toggle      : STD_LOGIC := '0';

    -- 5.12 MHz domain, toggle synchronizer
    signal s_toggle_meta : STD_LOGIC := '0';
    signal s_toggle_slow : STD_LOGIC := '0';
    signal s_toggle_prev : STD_LOGIC := '0';
begin

    -- Serial trim receiver (Distribute and this module share clk_slow).
    process (clk_slow)
    begin
        if rising_edge(clk_slow) then
            if (trim_strobe = '1') then
                s_trim_reg <= s_trim_reg(6 downto 0) & trim_bit;
            end if;
        end if;
    end process;

    process (clk_fast)
    begin
        if rising_edge(clk_fast) then
            -- two-flop synchronizer for the asynchronous sync input
            s_meta <= sync_in;
            s_sync <= s_meta;
            s_sync_prev <= s_sync;

            if (s_sync = '1' and s_sync_prev = '0') then
                -- new carrier-start edge: arm the delay.  s_trim_reg is
                -- stable long before this edge (the host sends the command
                -- between frames).
                s_delay <= unsigned(s_trim_reg);
                s_pending <= '1';
            elsif (s_pending = '1') then
                if (s_delay = 0) then
                    s_toggle <= not s_toggle;
                    s_pending <= '0';
                else
                    s_delay <= s_delay - 1;
                end if;
            end if;
        end if;
    end process;

    process (clk_slow)
    begin
        if rising_edge(clk_slow) then
            -- two-flop synchronizer for the toggle, then edge detect
            s_toggle_meta <= s_toggle;
            s_toggle_slow <= s_toggle_meta;
            s_toggle_prev <= s_toggle_slow;
            if (s_toggle_slow /= s_toggle_prev) then
                sync_out <= '1';
            else
                sync_out <= '0';
            end if;
        end if;
    end process;

end Behavioral;
