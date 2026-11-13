library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity Counter is
	 generic(
		COUNTER_BITS: integer := 8;
		-- Value loaded on a sync edge.  SyncTrim synchronizes the primary's
		-- COUNT=0 pulse, delays it by the 50 MHz trim value and produces a
		-- one-cycle pulse in this clock domain.  The fixed synchronizer
		-- latency puts the primary at 17 when the secondary loads, so 17
		-- aligns the counters at the default trim (127).  Each trim step
		-- adds 20 ns (0.288 deg at 40 kHz); the host sweeps it for the
		-- deepest null.  The carrier period is 128 counts.
		SYNC_LOAD: integer := 17
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
