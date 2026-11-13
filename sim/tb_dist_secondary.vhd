library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.phase_correction_pkg.all;

-- Secondary-board variant of the Distribute check: the board-select polarity
-- is the reverse of the primary (0xC0 disables, 0xC1 enables) and the active
-- PHASE_CORRECTION table is the secondary board's.
entity tb_dist_secondary is end entity;
architecture sim of tb_dist_secondary is
    constant T : time := 20 ns;
    signal clk, byte_in, swap_out, set_out, multiplex_out,
           debug_swap, debug_reset, debug_onShiftClocks : std_logic := '0';
    signal q_in, data_out, address : std_logic_vector(7 downto 0) := (others=>'0');
    signal mode : std_logic_vector(1 downto 0);
    signal done : boolean := false;
    signal clk_fast, sync_in, trim_bit, trim_strobe, sync_out : std_logic := '0';
    signal trim_received : std_logic_vector(7 downto 0) := (others => '0');
    signal strobe_count : integer := 0;

    procedure ck(c: boolean; m: string) is begin
        assert c report "FAIL: " & m severity failure;
    end procedure;

    procedure send(signal q : out std_logic_vector(7 downto 0);
                   signal bi: out std_logic;
                   constant v: in integer) is begin
        q <= std_logic_vector(to_unsigned(v,8));
        bi <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        bi <= '0';
        wait until rising_edge(clk); wait for 1 ns;
    end procedure;
begin
    clk <= not clk after T/2 when not done else '0';
    clk_fast <= not clk_fast after 10 ns when not done else '0';

    -- Reconstruct the serial trim stream for checking.
    trim_rx : process (clk)
    begin
        if rising_edge(clk) then
            if (trim_strobe = '1') then
                trim_received <= trim_received(6 downto 0) & trim_bit;
                strobe_count <= strobe_count + 1;
            end if;
        end if;
    end process;

    dut: entity work.Distribute port map(
        CLK=>clk, byte_in=>byte_in, q_in=>q_in, swap_out=>swap_out,
        set_out=>set_out, multiplex_out=>multiplex_out, data_out=>data_out,
        address=>address, debug_swap=>debug_swap, debug_reset=>debug_reset,
        debug_onShiftClocks=>debug_onShiftClocks, mode=>mode,
        trim_bit=>trim_bit, trim_strobe=>trim_strobe,
        clk_fast=>clk_fast, sync_in=>sync_in, sync_out=>sync_out);

    stim: process begin
        wait for 10*T;
        -- frame start
        send(q_in, byte_in, 16#FE#);
        ck(swap_out='0' and set_out='0', "0xFE resets frame");
        -- secondary role: the primary select byte must DISABLE this board
        send(q_in, byte_in, 16#C0#);
        ck(debug_reset='0', "0xC0 disables the secondary board");
        send(q_in, byte_in, 5);
        ck(set_out='0', "disabled board ignores payload");
        ck(to_integer(unsigned(address))=0, "disabled board keeps address");
        -- secondary select: must ENABLE
        send(q_in, byte_in, 16#C1#);
        ck(debug_reset='1', "0xC1 enables the secondary board");
        -- payload 0 at idx0
        send(q_in, byte_in, 0);
        ck(set_out='1', "payload written"); ck(to_integer(unsigned(address))=0,"addr0");
        ck(to_integer(unsigned(data_out))=corrected(0, 0), "corr idx0 follows active table");
        -- payload 2 at idx1
        send(q_in, byte_in, 2);
        ck(to_integer(unsigned(address))=1,"addr1");
        ck(to_integer(unsigned(data_out))=corrected(2, 1), "corr idx1 follows active table");
        -- payload 2 at idx2: the secondary table differs from the primary one
        send(q_in, byte_in, 2);
        ck(to_integer(unsigned(address))=2,"addr2");
        ck(to_integer(unsigned(data_out))=corrected(2, 2),
           "corr idx2 follows active secondary table");
        -- amplitude nibble passes through, phase nibble is corrected
        send(q_in, byte_in, 16#A2#);
        ck(to_integer(unsigned(address))=3,"addr3");
        ck(to_integer(unsigned(data_out))=16#A0# + corrected(2, 3),
           "amplitude nibble preserved, phase corrected");
        -- off value passes through untouched
        send(q_in, byte_in, 16#10#);
        ck(to_integer(unsigned(address))=4,"addr4");
        ck(to_integer(unsigned(data_out))=16, "off 0x10 preserved");
        -- frame restart always recognised
        send(q_in, byte_in, 16#FE#);
        ck(set_out='0', "0xFE clears set");
        send(q_in, byte_in, 16#FD#);
        ck(swap_out='1', "0xFD asserts swap");
        ck(to_integer(unsigned(address))=4, "0xFD keeps last address output");
        -- Trim command: 0xE0 0x5A 0x20 between frames.
        send(q_in, byte_in, 16#E0#);
        send(q_in, byte_in, 16#5A#);
        send(q_in, byte_in, 16#20#);
        wait for 30*T;
        report "trim_received = " & integer'image(to_integer(unsigned(trim_received))) &
               " strobes = " & integer'image(strobe_count) severity note;
        ck(trim_received = std_logic_vector(to_unsigned(16#20#, 8)),
           "trim command produces the serial stream 0x20");

        -- 0xE0 inside a frame must be a payload byte, not a command.
        send(q_in, byte_in, 16#FE#);
        send(q_in, byte_in, 16#E0#);
        ck(set_out='1', "0xE0 inside a frame is payload");
        ck(to_integer(unsigned(address))=0, "frame payload address 0");
        ck(to_integer(unsigned(data_out(7 downto 4)))=16#E#,
           "0xE0 amplitude nibble preserved");
        send(q_in, byte_in, 16#FD#);
        wait for 30*T;
        ck(trim_received = std_logic_vector(to_unsigned(16#20#, 8)),
           "payload 0xE0 does not change the trim");

        -- A bad second byte must abort the command, not change the trim.
        send(q_in, byte_in, 16#E0#);
        send(q_in, byte_in, 16#00#);
        wait for 30*T;
        ck(trim_received = std_logic_vector(to_unsigned(16#20#, 8)),
           "bad trim prefix leaves the trim unchanged");

        report "TEST PASSED: tb_dist_secondary" severity note;
        done <= true;
        wait;
    end process;
end architecture;
