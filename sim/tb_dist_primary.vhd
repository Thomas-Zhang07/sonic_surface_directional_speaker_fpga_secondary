library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.phase_correction_pkg.all;

entity tb_dist_primary is end entity;
architecture sim of tb_dist_primary is
    constant T : time := 20 ns;
    signal clk, byte_in, swap_out, set_out, multiplex_out,
           debug_swap, debug_reset, debug_onShiftClocks : std_logic := '0';
    signal q_in, data_out, address : std_logic_vector(7 downto 0) := (others=>'0');
    signal mode : std_logic_vector(1 downto 0);
    signal done : boolean := false;

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

    dut: entity work.Distribute port map(
        CLK=>clk, byte_in=>byte_in, q_in=>q_in, swap_out=>swap_out,
        set_out=>set_out, multiplex_out=>multiplex_out, data_out=>data_out,
        address=>address, debug_swap=>debug_swap, debug_reset=>debug_reset,
        debug_onShiftClocks=>debug_onShiftClocks, mode=>mode);

    stim: process begin
        wait for 10*T;
        -- frame start
        send(q_in, byte_in, 16#FE#);
        ck(swap_out='0' and set_out='0', "0xFE resets frame");
        -- primary select: must ENABLE
        send(q_in, byte_in, 16#C0#);
        ck(debug_reset='1', "0xC0 enables primary board");
        -- payload 0 at idx0
        send(q_in, byte_in, 0);
        ck(set_out='1', "payload written"); ck(to_integer(unsigned(address))=0,"addr0");
        ck(to_integer(unsigned(data_out))=corrected(0, 0), "corr idx0 follows active table");
        -- payload 2 at idx1
        send(q_in, byte_in, 2);
        ck(to_integer(unsigned(address))=1,"addr1");
        ck(to_integer(unsigned(data_out))=corrected(2, 1), "corr idx1 follows active table");
        -- payload 2 at idx2
        send(q_in, byte_in, 2);
        ck(to_integer(unsigned(address))=2,"addr2");
        ck(to_integer(unsigned(data_out))=corrected(2, 2),
           "corr idx2 follows active primary table");
        -- amplitude nibble passes through, phase nibble is corrected
        send(q_in, byte_in, 16#A2#);
        ck(to_integer(unsigned(address))=3,"addr3");
        ck(to_integer(unsigned(data_out))=16#A0# + corrected(2, 3),
           "amplitude nibble preserved, phase corrected");
        -- off value passes through untouched
        send(q_in, byte_in, 16#10#);
        ck(to_integer(unsigned(address))=4,"addr4");
        ck(to_integer(unsigned(data_out))=16, "off 0x10 preserved");
        -- secondary select: must DISABLE this (primary) board
        send(q_in, byte_in, 16#C1#);
        ck(debug_reset='0', "0xC1 disables primary board");
        send(q_in, byte_in, 5);
        ck(set_out='0', "disabled board ignores payload");
        ck(to_integer(unsigned(address))=4, "disabled board keeps address");
        -- frame restart always recognised
        send(q_in, byte_in, 16#FE#);
        ck(set_out='0', "0xFE clears set");
        send(q_in, byte_in, 16#FD#);
        ck(swap_out='1', "0xFD asserts swap");
        ck(to_integer(unsigned(address))=4, "0xFD keeps last address output");
        report "TEST PASSED: tb_dist_primary" severity note;
        done <= true;
        wait;
    end process;
end architecture;
