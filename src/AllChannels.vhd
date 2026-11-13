
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity AllChannels is
    generic(
        NBLOCKS : integer := 256
    );

    port (
        clk8 : in STD_LOGIC;
        clk  : in STD_LOGIC;

        counter : in STD_LOGIC_VECTOR(7 downto 0);

        swap  : in STD_LOGIC := '0';
        phase : in STD_LOGIC_VECTOR(7 downto 0);
        set   : in STD_LOGIC := '0';

        -- 256个Phase地址：0~255
        address : in STD_LOGIC_VECTOR(7 downto 0);

        -- 音乐模式选择
        -- 00：模式0
        -- 01：模式1
        -- 10：模式2
        -- 11：模式3
        mode : in STD_LOGIC_VECTOR(1 downto 0) := "00";

        music_out : out STD_LOGIC_VECTOR(31 downto 0)
    );
end AllChannels;


architecture Behavioral of AllChannels is

    -- 256个PhaseLine写使能
    signal s_set : STD_LOGIC_VECTOR(NBLOCKS-1 downto 0);

    -- PhaseLine输出
    signal s_pulseToMux :
        STD_LOGIC_VECTOR(NBLOCKS-1 downto 0);

    -- 32路Mux输出
    signal data_out :
        STD_LOGIC_VECTOR(NBLOCKS/8-1 downto 0);

    -- One frame byte carries both controls:
    --   phase(3 downto 0)   -> phase bin 0..15
    --   phase(7 downto 4)   -> amplitude code 0..15 (0 = legacy full scale)
    --   byte 0x10           -> OFF (legacy code, unchanged)
    --
    -- The amplitude code and the centring lead are turned into the actual
    -- trigger step once, here, and shared by all 256 instances.
    signal s_amp_code : integer range 0 to 15;
    signal s_width_i  : integer range 0 to 8;
    signal s_lead     : integer range 0 to 4;
    signal s_on_i     : integer range 0 to 15;
    signal s_off_i    : integer range 0 to 15;
    signal s_on_step  : STD_LOGIC_VECTOR(3 downto 0);
    signal s_off_step : STD_LOGIC_VECTOR(3 downto 0);


    -- Amplitude code -> pulse width in 640 kHz steps.
    --
    -- Fundamental amplitude is sin(pi * width / 16), maximum at width 8
    -- (50 % duty), so only 1..8 is useful for weighting.  The code maps
    -- linearly: 0 -> 8 (legacy "no amplitude information"), 15 -> 8, and
    -- 1..15 -> 1..8 rounded.
    function pulse_width(code : integer) return integer is
    begin
        if code = 0 or code >= 15 then
            return 8;
        else
            return (code + 1) / 2;
        end if;
    end function;


    component PhaseLine is
        port (
            clk      : in STD_LOGIC;
            set      : in STD_LOGIC := '0';
            swap     : in STD_LOGIC := '0';
            on_step  : in STD_LOGIC_VECTOR(3 downto 0);
            off_step : in STD_LOGIC_VECTOR(3 downto 0);
            counter  : in STD_LOGIC_VECTOR(4 downto 0);
            pulse    : out STD_LOGIC := '0'
        );
    end component;


    component Mux8 is
        port (
            clk      : in STD_LOGIC;
            data_in  : in STD_LOGIC_VECTOR(7 downto 0);
            sel      : in STD_LOGIC_VECTOR(2 downto 0);
            data_out : out STD_LOGIC
        );
    end component;

begin

    --------------------------------------------------
    -- Frame byte decode (shared by all channels)
    -- 0x10 stays the legacy OFF code; any other byte splits into an
    -- amplitude nibble (high) and a phase nibble (low).
    --------------------------------------------------
    s_amp_code <= to_integer(unsigned(phase(7 downto 4)));
    s_width_i  <= 0 when phase = "00010000" else pulse_width(s_amp_code);
    -- Width-8 pulses start one step after the phase match; narrower pulses
    -- are moved later by this lead so that their centre stays at phase+5.
    s_lead  <= 4 - (s_width_i / 2);
    -- Pulse is high for [on_step, off_step).  Width 0 makes them equal,
    -- which PhaseLine treats as OFF.
    s_on_i  <= (to_integer(unsigned(phase(3 downto 0))) + s_lead + 1) mod 16;
    s_off_i <= (to_integer(unsigned(phase(3 downto 0))) + s_lead +
                s_width_i + 1) mod 16;

    s_on_step  <= std_logic_vector(to_unsigned(s_on_i, 4));
    s_off_step <= std_logic_vector(to_unsigned(s_off_i, 4));

    --------------------------------------------------
    -- 256个PhaseLine实例
    --------------------------------------------------
    insts : for i in 0 to NBLOCKS-1 generate
    begin

        PhaseLine_inst : PhaseLine
            port map (
                clk      => clk,
                set      => s_set(i),
                swap     => swap,
                on_step  => s_on_step,
                off_step => s_off_step,
                counter  => counter(7 downto 3),
                pulse    => s_pulseToMux(i)
            );

    end generate insts;


    --------------------------------------------------
    -- 32个Mux8实例
    --------------------------------------------------
    muxes : for i in 0 to NBLOCKS/8-1 generate
    begin

        Mux8_inst : Mux8
            port map (
                clk      => clk8,
                data_in  => s_pulseToMux(i*8+7 downto i*8),
                sel      => counter(2 downto 0),
                data_out => data_out(i)
            );

    end generate muxes;


    --------------------------------------------------
    -- Phase地址解码：仅0~255
    --------------------------------------------------
    phase_to_duty : for i in 0 to NBLOCKS-1 generate
    begin

        s_set(i) <= '1'
            when set = '1' and
            i = to_integer(unsigned(address))
            else '0';

    end generate phase_to_duty;


    --------------------------------------------------
    -- Music Player
    -- 音乐数据已经存储在music_player内部
    -- 不再从外部接收Note
    --------------------------------------------------
    u_music_player : entity work.music_player
        port map (
            clk8      => clk8,
            data_out  => data_out,
            swap      => swap,
            mode      => mode,
            music_out => music_out
        );


end Behavioral;
