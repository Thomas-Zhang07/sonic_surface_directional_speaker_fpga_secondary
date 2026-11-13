library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;
use work.phase_correction_pkg.all;

-- End-to-end protocol test: serial bytes -> UARTReader -> Distribute.
--
-- Reads frame_input.txt (one decimal byte per line, produced by gen_assets.py)
-- and streams it into the UART at the hardware rate (5.12 MHz / 133 clocks
-- per bit = 38.4 kBaud). Every payload byte is checked against the address
-- and corrected phase Distribute must produce, and every 0xFD must produce a
-- swap with exactly 256 payload bytes in the preceding frame.
entity tb_chain is
end entity;

architecture sim of tb_chain is

    constant CLK_PERIOD   : time := 195313 ps;              -- 5.12 MHz
    constant CLKS_PER_BIT : integer := 133;                 -- 38.4 kBaud
    constant BIT_PERIOD   : time := CLKS_PER_BIT * CLK_PERIOD;
    constant MAX_BYTES    : integer := 4096;

    type byte_array is array (0 to MAX_BYTES - 1) of integer range 0 to 255;

    signal clk                 : std_logic := '0';
    signal rx                  : std_logic := '1';
    signal rx_dv               : std_logic;
    signal rx_byte             : std_logic_vector(7 downto 0);
    signal swap_out            : std_logic;
    signal set_out             : std_logic;
    signal multiplex_out       : std_logic;
    signal data_out            : std_logic_vector(7 downto 0);
    signal address             : std_logic_vector(7 downto 0);
    signal debug_swap          : std_logic;
    signal debug_reset         : std_logic;
    signal debug_onShiftClocks : std_logic;
    signal mode                : std_logic_vector(1 downto 0);
    signal frames_seen         : integer := 0;
    signal finished            : boolean := false;

    procedure check(cond : boolean; msg : string) is
    begin
        assert cond report "FAIL: " & msg severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2 when not finished else '0';

    uart : entity work.UARTReader
        generic map (g_CLKS_PER_BIT => CLKS_PER_BIT)
        port map (
            i_Clk     => clk,
            i_RX_Serial => rx,
            o_RX_DV   => rx_dv,
            o_RX_Byte => rx_byte
        );

    dut : entity work.Distribute
        port map (
            CLK                 => clk,
            byte_in             => rx_dv,
            q_in                => rx_byte,
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

    monitor : process (clk)
        variable payload_idx : integer := -1;   -- -1: waiting for 0xFE
        variable pending     : boolean := false;
        variable exp_addr    : std_logic_vector(7 downto 0);
        variable exp_data    : std_logic_vector(7 downto 0);
        variable mode_pending : boolean := false;
        variable exp_mode    : std_logic_vector(1 downto 0);
        variable frame_count : integer := 0;
        variable swap_count  : integer := 0;
        variable prev_swap   : std_logic := '0';
    begin
        if rising_edge(clk) then

            -- Verify the byte Distribute processed on the previous edge.
            if pending then
                assert set_out = '1'
                    report "FAIL: set_out not asserted for address " &
                           integer'image(to_integer(unsigned(exp_addr)))
                    severity failure;
                assert address = exp_addr
                    report "FAIL: address " &
                           integer'image(to_integer(unsigned(address))) &
                           " expected " & integer'image(to_integer(unsigned(exp_addr)))
                    severity failure;
                assert data_out = exp_data
                    report "FAIL: data at address " &
                           integer'image(to_integer(unsigned(exp_addr))) &
                           " was " & integer'image(to_integer(unsigned(data_out))) &
                           " expected " & integer'image(to_integer(unsigned(exp_data)))
                    severity failure;
                pending := false;
            end if;

            if mode_pending then
                assert mode = exp_mode
                    report "FAIL: mode byte not applied"
                    severity failure;
                mode_pending := false;
            end if;

            if swap_out = '1' and prev_swap = '0' then
                swap_count := swap_count + 1;
            end if;
            prev_swap := swap_out;

            -- Handle the byte that just arrived.
            if rx_dv = '1' then
                if rx_byte = x"FE" then
                    payload_idx := 0;
                elsif rx_byte = x"FD" then
                    assert payload_idx = 256
                        report "FAIL: frame had " & integer'image(payload_idx) &
                               " payload bytes"
                        severity failure;
                    payload_idx := -1;
                    frame_count := frame_count + 1;
                    frames_seen <= frame_count;
                elsif rx_byte = x"C8" then
                    exp_mode := "00"; mode_pending := true;
                elsif rx_byte = x"C9" then
                    exp_mode := "01"; mode_pending := true;
                elsif rx_byte = x"CA" then
                    exp_mode := "10"; mode_pending := true;
                elsif rx_byte = x"CB" then
                    exp_mode := "11"; mode_pending := true;
                elsif payload_idx >= 0 and payload_idx < 256 then
                    exp_addr := std_logic_vector(to_unsigned(payload_idx, 8));
                    exp_data := std_logic_vector(to_unsigned(
                        corrected(to_integer(unsigned(rx_byte)), payload_idx), 8));
                    pending := true;
                    payload_idx := payload_idx + 1;
                end if;
            end if;

        end if;
    end process;

    stimulus : process
        file input_file : text open read_mode is "frame_input.txt";
        variable line_in  : line;
        variable value    : integer;
        variable bytes    : byte_array;
        variable n        : integer := 0;
        variable u        : std_logic_vector(7 downto 0);
        variable expected_frames : integer := 0;
    begin
        while not endfile(input_file) loop
            readline(input_file, line_in);
            read(line_in, value);
            bytes(n) := value;
            n := n + 1;
        end loop;

        assert n > 0 report "FAIL: frame_input.txt is empty" severity failure;

        -- Command bytes (e.g. a mode command) may precede the frames, so
        -- count frame starts rather than assume the file is frame-aligned.
        for i in 0 to n - 1 loop
            if bytes(i) = 16#FE# then
                expected_frames := expected_frames + 1;
            end if;
        end loop;
        check(expected_frames > 0, "input contains no frame");

        wait for 1 us;
        for i in 0 to n - 1 loop
            rx <= '0';
            wait for BIT_PERIOD;

            u := std_logic_vector(to_unsigned(bytes(i), 8));
            for b in 0 to 7 loop
                rx <= u(b);
                wait for BIT_PERIOD;
            end loop;

            rx <= '1';
            wait for BIT_PERIOD;
            wait for BIT_PERIOD;
        end loop;

        wait for 20 us;
        check(frames_seen = expected_frames,
              "received " & integer'image(frames_seen) & " of " &
              integer'image(expected_frames) & " frames");

        finished <= true;
        report "TEST PASSED: tb_chain (" & integer'image(expected_frames) &
               " frames)" severity note;
        wait;
    end process;

end architecture;
