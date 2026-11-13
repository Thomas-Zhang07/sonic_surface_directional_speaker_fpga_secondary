library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.phase_correction_pkg.all;

-- Unit test for the byte-level protocol decoder.
--
-- Drives one byte at a time into Distribute and checks:
--   * 0xFE starts a frame and does not write a channel
--   * payload bytes advance the address 0..255 and apply the correction
--   * 0x10 is stored as "off" and never corrected
--   * 0xFD swaps and restarts the address counter
--   * 0x96 / 0x97 toggle the shift clocks
--   * 0xC0 enables the primary board, 0xC1 disables it
--   * 0xC8..0xCB select modes 00..11
--   * no channel is written after the 256th payload byte
entity tb_distribute is
end entity;

architecture sim of tb_distribute is

    constant CLK_PERIOD : time := 20 ns;

    signal clk                  : std_logic := '0';
    signal byte_in              : std_logic := '0';
    signal q_in                 : std_logic_vector(7 downto 0) := (others => '0');
    signal swap_out             : std_logic;
    signal set_out              : std_logic;
    signal multiplex_out        : std_logic;
    signal data_out             : std_logic_vector(7 downto 0);
    signal address              : std_logic_vector(7 downto 0);
    signal debug_swap           : std_logic;
    signal debug_reset          : std_logic;
    signal debug_onShiftClocks  : std_logic;
    signal mode                 : std_logic_vector(1 downto 0);
    signal finished             : boolean := false;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

    procedure send(signal q  : out std_logic_vector(7 downto 0);
                   signal bi : out std_logic;
                   constant value : in integer) is
    begin
        q <= std_logic_vector(to_unsigned(value, 8));
        bi <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        bi <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2 when not finished else '0';

    dut : entity work.Distribute
        port map (
            CLK                 => clk,
            byte_in             => byte_in,
            q_in                => q_in,
            swap_out            => swap_out,
            set_out             => set_out,
            multiplex_out       => multiplex_out,
            data_out            => data_out,
            address             => address,
            debug_swap          => debug_swap,
            debug_reset         => debug_reset,
            debug_onShiftClocks => debug_onShiftClocks,
            mode                => mode
        );

    stimulus : process
    begin
        wait for 100 ns;

        -- Idle state ---------------------------------------------------
        check(set_out = '0', "set_out idle");
        check(swap_out = '0', "swap_out idle");
        check(mode = "00", "mode idle");
        check(debug_onShiftClocks = '1', "shift clocks idle on");
        check(debug_reset = '1', "board enabled at reset");

        -- Frame start --------------------------------------------------
        send(q_in, byte_in, 16#FE#);
        check(set_out = '0', "0xFE must not write a channel");
        check(to_integer(unsigned(address)) = 0, "0xFE resets address");

        -- Payload bytes ------------------------------------------------
        send(q_in, byte_in, 3);
        check(set_out = '1', "payload asserts set_out");
        check(to_integer(unsigned(address)) = 0, "first payload address 0");
        check(to_integer(unsigned(data_out)) = corrected(3, 0),
              "payload 0 corrected");

        send(q_in, byte_in, 16#10#);
        check(set_out = '1', "off byte asserts set_out");
        check(to_integer(unsigned(address)) = 1, "off byte address 1");
        check(to_integer(unsigned(data_out)) = 16, "0x10 stored as off");

        send(q_in, byte_in, 15);
        check(to_integer(unsigned(address)) = 2, "third payload address 2");
        check(to_integer(unsigned(data_out)) = corrected(15, 2),
              "payload 2 corrected");

        -- Swap ---------------------------------------------------------
        send(q_in, byte_in, 16#FD#);
        check(swap_out = '1', "0xFD asserts swap");
        check(set_out = '0', "0xFD clears set");
        check(debug_swap = '1', "debug_swap toggles");

        -- Frame start clears swap and restarts the counter --------------
        send(q_in, byte_in, 16#FE#);
        check(swap_out = '0', "0xFE clears swap");
        send(q_in, byte_in, 1);
        check(to_integer(unsigned(address)) = 0, "address restarts after swap");

        -- Shift-clock commands -----------------------------------------
        send(q_in, byte_in, 16#96#);
        check(debug_onShiftClocks = '0', "0x96 turns shift clocks off");
        send(q_in, byte_in, 16#97#);
        check(debug_onShiftClocks = '1', "0x97 turns shift clocks on");

        -- Board select (primary variant) --------------------------------
        send(q_in, byte_in, 16#C0#);
        check(debug_reset = '1', "0xC0 enables the primary board");
        send(q_in, byte_in, 16#FE#);
        send(q_in, byte_in, 3);
        check(set_out = '1', "enabled board accepts payload");
        check(to_integer(unsigned(address)) = 0, "enabled board writes at 0");
        send(q_in, byte_in, 16#C1#);
        check(debug_reset = '0', "0xC1 disables the primary board");
        send(q_in, byte_in, 16#FE#);
        send(q_in, byte_in, 4);
        check(set_out = '0', "disabled board ignores payload");
        check(to_integer(unsigned(address)) = 0, "disabled board keeps address");

        -- Mode commands -------------------------------------------------
        send(q_in, byte_in, 16#C8#); check(mode = "00", "0xC8 selects mode 00");
        send(q_in, byte_in, 16#C9#); check(mode = "01", "0xC9 selects mode 01");
        send(q_in, byte_in, 16#CA#); check(mode = "10", "0xCA selects mode 10");
        send(q_in, byte_in, 16#CB#); check(mode = "11", "0xCB selects mode 11");

        -- 256-byte limit ------------------------------------------------
        send(q_in, byte_in, 16#C0#);   -- re-enable the primary board
        send(q_in, byte_in, 16#FE#);
        for i in 0 to 255 loop
            send(q_in, byte_in, 0);
            check(to_integer(unsigned(address)) = i,
                  "payload index " & integer'image(i) & " address");
        end loop;
        send(q_in, byte_in, 0);
        check(set_out = '0', "no write after the 256th payload byte");

        finished <= true;
        report "TEST PASSED: tb_distribute" severity note;
        wait;
    end process;

end architecture;
