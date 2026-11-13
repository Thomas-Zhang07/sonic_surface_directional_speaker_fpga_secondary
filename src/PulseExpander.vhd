library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity PulseExpander is
	 generic(OUTPUT_LENGTH_CYCLES: integer := 8);
    port (
        clk_in : in  STD_LOGIC;
		  pulse_in : in STD_LOGIC;
        pulse_out: out STD_LOGIC
	 );
end PulseExpander;

architecture Behavioral of PulseExpander is
    signal sCounter : integer range 0 to OUTPUT_LENGTH_CYCLES := 0;
	 signal s_pulse_out: STD_LOGIC := '0';
begin
    pPulseExpander: process (clk_in) begin
        if rising_edge(clk_in) then
				-- While the input is high the output stays high and the
				-- counter is reloaded. The earlier version reloaded and
				-- decremented in the same cycle; the decrement won, so a
				-- held-high input produced a one-clock low glitch every
				-- OUTPUT_LENGTH_CYCLES+1 cycles.
        -- good it works !
				if (pulse_in = '1') then
					sCounter <= OUTPUT_LENGTH_CYCLES;
					s_pulse_out <= '1';
				elsif (sCounter = 0) then
					s_pulse_out <= '0';
				else
					s_pulse_out <= '1';
					sCounter <= sCounter - 1;
				end if;
        end if;
    end process;
    
    pulse_out <= s_pulse_out;
end Behavioral;
