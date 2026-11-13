library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity Counter is
	 generic(
		COUNTER_BITS: integer := 8;
		-- Value loaded when a sync edge arrives.  The secondary board
		-- resets its carrier counter from MISC_A instead of free-running.
		--
		-- The 40 kHz sync is the primary's COUNT[6].  It passes through
		-- RSSFilter_1 (a majority filter clocked at 5.12 MHz) before it
		-- reaches this input, and that filter raises its output six clocks
		-- after the input edge.  The primary counter is therefore at 70
		-- when the filtered edge is seen (64 + 6); the secondary counter
		-- loads on the following clock edge, when the primary has advanced
		-- to 71.  Loading 71 therefore puts the two counters in step.  The
		-- carrier period is 128 counts, so any constant offset here is a
		-- carrier phase error; do not change it without re-checking tb_sync.
		SYNC_LOAD: integer := 71
	 );
    port (
        clk_in : in  STD_LOGIC;
		  sync_reset : in STD_LOGIC;
        clk_out: out STD_LOGIC_VECTOR (COUNTER_BITS-1 downto 0)
	 );
end Counter;

architecture Behavioral of Counter is
    signal sCounter : STD_LOGIC_VECTOR (COUNTER_BITS-1 downto 0) := (others => '0');
	 signal prev_res : STD_LOGIC := '0';
begin
    pCounter: process (clk_in) begin
        if rising_edge(clk_in) then
				prev_res <= sync_reset;
				if (sync_reset = '1' and prev_res = '0') then
					sCounter <= conv_std_logic_vector(SYNC_LOAD, COUNTER_BITS);
				else
					sCounter <= sCounter + 1;
				end if;
        end if;
    end process;

    clk_out <= sCounter;
end Behavioral;
