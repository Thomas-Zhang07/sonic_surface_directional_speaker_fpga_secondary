library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.ALL;


-- One channel of the 40 kHz drive.
--
-- `on_step` and `off_step` are 640 kHz step numbers within the 16-step
-- carrier period.  The pulse is high from on_step up to (but excluding)
-- off_step, so its width and centre are fixed entirely by those two values.
-- AllChannels computes them once from the frame byte, so this entity needs
-- only two comparators per channel.  When on_step = off_step the channel is
-- OFF (the clear branch wins).
entity PhaseLine is
    port (
          clk : in  STD_LOGIC;
          set : in  STD_LOGIC := '0';
          swap : in  STD_LOGIC := '0';
          on_step : in STD_LOGIC_VECTOR (3 downto 0);
          off_step : in STD_LOGIC_VECTOR (3 downto 0);
          counter : in STD_LOGIC_VECTOR (4 downto 0); -- external interface unchanged

          pulse : out STD_LOGIC := '0'
     );
end PhaseLine;

architecture Behavioral of PhaseLine is
     signal s_onCurrent : integer range 0 to 15 := 1;
     signal s_onPrev : integer range 0 to 15 := 1;
     signal s_offCurrent : integer range 0 to 15 := 9;
     signal s_offPrev : integer range 0 to 15 := 9;
     signal s_prevSet : std_logic := '0';
     signal s_prevSwap : std_logic := '0';
begin
    PhaseLine: process (clk) begin
        if (rising_edge(clk)) then
                s_prevSet <= set;
                s_prevSwap <= swap;

                if (set = '1' AND s_prevSet = '0') then
                    s_onPrev <= to_integer(unsigned(on_step));
                    s_offPrev <= to_integer(unsigned(off_step));
                end if;

                if (swap = '1' AND s_prevSwap = '0') then
                    s_onCurrent <= s_onPrev;
                    s_onPrev <= s_onCurrent;
                    s_offCurrent <= s_offPrev;
                    s_offPrev <= s_offCurrent;
                end if;

                -- Clear first so on_step = off_step (OFF) stays low.
                if (to_integer(unsigned(counter(3 downto 0))) = s_offCurrent) then
                    pulse <= '0';
                elsif (to_integer(unsigned(counter(3 downto 0))) = s_onCurrent) then
                    pulse <= '1';
                end if;

          end if;
 end process;

end Behavioral;
