library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.ALL;

entity Distribute is
    port (
		  CLK : in  STD_LOGIC;
		  
		  byte_in : in  STD_LOGIC := '0';
		  q_in : in STD_LOGIC_VECTOR (7 downto 0);
		  swap_out : out  STD_LOGIC := '0';
		  set_out : out STD_LOGIC := '0';
		  multiplex_out : out STD_LOGIC := '0';
		  data_out: out STD_LOGIC_VECTOR (7 downto 0); 
		  address : out std_logic_vector(7 downto 0); --256 addresses
		  
		  debug_swap : out STD_LOGIC := '0';
		  debug_reset : out STD_LOGIC := '0';
		  debug_onShiftClocks : out STD_LOGIC := '1';
		  mode : out STD_LOGIC_VECTOR(1 downto 0) := "00"; -- 2位模式输出，默认模式00
		  -- Fine inter-board phase trim, in 50 MHz steps (20 ns = 0.288 deg
		  -- at 40 kHz).  127 is the centred default; the host can override
		  -- it with the 0xE0 0x5A <value> command between frames.  The
		  -- value is sent serially (MSB first, one bit per trim_strobe) so
		  -- the schematic needs no 8-bit bus between the two blocks.
		  trim_bit : out STD_LOGIC := '0';
		  trim_strobe : out STD_LOGIC := '0';
		  -- Sync path (SyncTrim is instantiated here so the trim value
		  -- never has to cross an 8-bit bus in the schematic).
		  clk_fast : in STD_LOGIC := '0';     -- 50 MHz
		  sync_in : in STD_LOGIC := '0';      -- MISC_A
		  sync_out : out STD_LOGIC := '0'     -- to Counter sync_reset
	 );
end Distribute;

architecture Behavioral of Distribute is

type T_PHASE_CORRECTION is array (0 to 255) of integer range 0 to 255;
	constant PHASE_CORRECTION : T_PHASE_CORRECTION := (
	-- boardsPrimary -- inactive on the secondary board
	--0, 0, 0, 0, 0, 0, 8, 0, 8, 8, 0, 0, 8, 8, 8, 0, 8, 0, 8, 0, 8, 8, 8, 8, 0, 8, 0, 8, 0, 8, 0, 8, 0, 8, 0, 0, 8, 8, 8, 8, 0, 8, 8, 0, 0, 0, 8, 8, 0, 0, 8, 8, 8, 0, 8, 8, 8, 8, 0, 0, 0, 0, 8, 8, 8, 0, 0, 8, 8, 8, 8, 8, 0, 0, 0, 8, 8, 0, 0, 8, 0, 0, 8, 8, 8, 8, 0, 0, 8, 0, 0, 0, 8, 0, 0, 0, 8, 0, 8, 8, 0, 0, 0, 0, 0, 8, 0, 8, 8, 0, 8, 0, 0, 0, 0, 0, 0, 0, 8, 0, 8, 8, 0, 8, 8, 0, 0, 8, 0, 0, 8, 8, 8, 8, 0, 0, 8, 0, 0, 8, 8, 0, 0, 8, 8, 0, 0, 0, 0, 0, 0, 0, 8, 0, 8, 0, 0, 0, 0, 0, 8, 0, 0, 0, 8, 8, 0, 8, 8, 0, 0, 0, 8, 8, 0, 0, 0, 0, 0, 8, 0, 0, 0, 8, 0, 0, 8, 0, 8, 0, 0, 0, 0, 8, 0, 8, 8, 0, 8, 8, 8, 0, 8, 8, 8, 0, 8, 8, 8, 8, 0, 0, 8, 0, 0, 0, 8, 8, 0, 8, 0, 0, 8, 8, 8, 8, 8, 0, 0, 8, 0, 8, 0, 0, 0, 0, 8, 0, 0, 8, 0, 8, 0, 8, 0, 8, 0, 0, 0, 8, 0, 8, 8, 8, 8, 8);
	-- boardsSecondary -- permuted to wire order via EMITTERS_ORDER
	8,8,0,0,8,8,0,0,0,0,8,0,0,0,0,0,0,0,0,8,8,8,8,0,8,0,0,8,8,8,0,0,8,0,0,0,8,0,0,8,0,8,0,8,0,0,8,8,8,8,8,0,0,0,8,0,0,0,8,0,8,0,0,8,0,8,0,0,0,0,0,8,8,0,0,0,8,8,0,8,0,8,8,0,8,0,0,0,0,8,0,8,8,0,8,0,8,0,0,8,0,0,8,8,0,8,8,0,0,0,8,8,8,8,8,8,8,0,8,8,8,8,8,0,8,0,0,8,8,8,8,0,0,0,0,0,8,0,0,8,0,0,8,8,8,0,8,0,0,0,8,8,8,0,0,8,8,0,0,8,0,8,8,0,0,0,8,0,8,8,0,8,0,8,8,8,0,0,8,8,0,0,0,8,8,0,0,0,0,0,8,0,0,0,8,0,0,8,0,0,8,8,8,0,0,8,8,8,0,0,0,8,8,8,0,0,8,0,0,8,0,0,0,0,0,0,8,8,8,0,0,0,8,8,0,8,8,8,8,0,0,0,0,0,0,0,8,0,0,0,0,0,8,8,8,0
	-- all-zero reference
	--0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
	 );
 signal s_boardEnable : STD_LOGIC := '1';
	 signal s_ByteCounter : integer range 0 to 256 := 0;
	  
	 signal s_data_out : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
	 signal s_address : std_logic_vector(7 downto 0) := (others => '0');
	 signal s_swap_out :  STD_LOGIC := '0';
	 signal s_set_out : STD_LOGIC := '0';
	 
	 signal s_debug_swap : STD_LOGIC := '0';
	 signal s_debug_onShiftClocks : STD_LOGIC := '1';
		-- 模式寄存器，默认值为00
		-- 接收到200：模式00
		-- 接收到201：模式01
		-- 接收到202：模式10
		-- 接收到203：模式11
		signal s_mode : STD_LOGIC_VECTOR(1 downto 0) := "00";

		-- Fine trim command state: 0 = idle, 1 = saw 0xE0, 2 = saw 0xE0 0x5A.
		signal s_trim_state : integer range 0 to 2 := 0;
		signal s_trim : STD_LOGIC_VECTOR(7 downto 0) := "01111111";
		signal s_trim_shift : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
		signal s_trim_count : integer range 0 to 8 := 0;
		signal s_trim_bit : STD_LOGIC := '0';
		signal s_trim_strobe : STD_LOGIC := '0';
		-- 1 between 0xFE and 0xFD.  The trim command is only recognised
		-- outside a frame so a payload byte 0xE0 can never be mistaken for it.
		signal s_inFrame : STD_LOGIC := '0';
begin
    Distribute: process (clk) begin
        if (rising_edge(clk)) then
				if (byte_in = '1') then --a byte of data is ready
					
					if (s_trim_state = 1) then
						-- second byte of the trim command
						if (q_in = "01011010") then --0x5A
							s_trim_state <= 2;
						else
							s_trim_state <= 0;
						end if;
					elsif (s_trim_state = 2) then
						-- third byte: load the value and serialise it
						s_trim <= q_in;
						s_trim_shift <= q_in;
						s_trim_count <= 8;
						s_trim_state <= 0;
					elsif (q_in = "11100000") and (s_inFrame = '0') then --224
						-- Trim command prefix, only between frames.
						s_trim_state <= 1;
					elsif (q_in = "11111110") then --254 is start phases
						s_trim_state <= 0;
						s_inFrame <= '1';
						s_ByteCounter <= 0;
						s_swap_out <= '0';
						s_set_out <= '0';
					elsif (q_in = "11111101") then --253 is swap
						s_inFrame <= '0';
						s_debug_swap <= not s_debug_swap;
						s_set_out <= '0';
						s_swap_out <= '1';
						s_ByteCounter <= 0;
						
					elsif (q_in = "10010110") then --150 is switch off clocks
						s_debug_onShiftClocks <= '0';
					elsif (q_in = "10010111") then --151 is switch on clocks
						s_debug_onShiftClocks <= '1';
						
					elsif (q_in = "11000000") then --192 board primary select
						-- Secondary role: the primary select byte DISABLES
						-- this board.  A host that enables both boards sends
						-- 0xC0 to the primary and 0xC1 to the secondary.
						s_boardEnable <= '0';
					elsif (q_in = "11000001") then --193 board secondary select
						s_boardEnable <= '1';
					elsif (q_in = "11001000") then -- 200：切换到模式0
						 s_mode <= "00";

					elsif (q_in = "11001001") then -- 201：切换到模式1
						 s_mode <= "01";

					elsif (q_in = "11001010") then -- 202：切换到模式2
						 s_mode <= "10";

					elsif (q_in = "11001011") then -- 203：切换到模式3
						 s_mode <= "11";
						
					elsif (s_boardEnable = '1') then

						 s_swap_out <= '0';

						 -- 只接收256个Phase数据
						if s_ByteCounter < 256 then

							 s_address <= std_logic_vector(
								  to_unsigned(s_ByteCounter, 8)
							 );

							 s_set_out <= '1';
							 s_ByteCounter <= s_ByteCounter + 1;

							 -- Frame byte: high nibble = amplitude code,
							 -- low nibble = phase bin.  The phase
							 -- correction table applies to the low
							 -- nibble only; the amplitude nibble is
							 -- passed through unchanged (0 = legacy
							 -- full scale, so old frames are identical).
							 -- 0x10 remains the legacy OFF code.
							 if q_in = "00010000" then
								  s_data_out <= q_in;
							 else
								  s_data_out <= q_in(7 downto 4) &
										std_logic_vector(
											 to_unsigned(
												  (to_integer(unsigned(q_in(3 downto 0))) +
													PHASE_CORRECTION(s_ByteCounter)) mod 16,
												  4
											 )
										);
							 end if;

						else
							 -- 收完256个数据，不再写入
							 s_set_out <= '0';
						end if;
					else
							s_swap_out <= '0';
							s_set_out <= '0';
					end if;
				end if;

				-- Serialise the latched trim value, MSB first.
				if (s_trim_count > 0) then
					s_trim_bit <= s_trim_shift(7);
					s_trim_shift <= s_trim_shift(6 downto 0) & '0';
					s_trim_strobe <= '1';
					s_trim_count <= s_trim_count - 1;
				else
					s_trim_strobe <= '0';
				end if;

		  end if;
 end process;
 debug_swap <= s_debug_swap;
 debug_reset <= s_boardEnable;
 debug_onShiftClocks <= s_debug_onShiftClocks;
 
 data_out <= s_data_out;
 address <= s_address;
 swap_out <= s_swap_out;
 set_out <= s_set_out;
 mode <= s_mode;
	 trim_bit <= s_trim_bit;
	 trim_strobe <= s_trim_strobe;
 
	 -- Carrier-sync detector and fine trim.  It shares s_trim_bit /
	 -- s_trim_strobe with the serialiser above.
	 sync_trim : entity work.SyncTrim
		  port map (
				clk_fast => clk_fast,
				clk_slow => clk,
				sync_in => sync_in,
				trim_bit => s_trim_bit,
				trim_strobe => s_trim_strobe,
				sync_out => sync_out
		  );

end Behavioral;
