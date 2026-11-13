library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity music_player is
    port (
        clk8      : in  STD_LOGIC;                      -- 5.12 MHz 时钟
        data_out  : in  STD_LOGIC_VECTOR(31 downto 0);  -- 32 路原始信号
        swap      : in  STD_LOGIC;                      -- 保留原有接口，当前模式不使用
        mode      : in  STD_LOGIC_VECTOR(1 downto 0) := "00"; -- 模式选择
        music_out : out STD_LOGIC_VECTOR(31 downto 0)   -- 32 路输出
    );
end entity music_player;

architecture Behavioral of music_player is

    -- 时钟频率为 5,120,000 Hz。
    -- 半周期计数值 = 时钟频率 / (2 * 音符频率)。
    constant C4_HALF_PERIOD  : integer := 9771;  -- C4，约 262 Hz
    constant D4_HALF_PERIOD  : integer := 8707;  -- D4，约 294 Hz
    constant E4_HALF_PERIOD  : integer := 7758;  -- E4，约 330 Hz
    constant F4_HALF_PERIOD  : integer := 7335;  -- F4，约 349 Hz
    constant G4_HALF_PERIOD  : integer := 6531;  -- G4，约 392 Hz
    constant A4_HALF_PERIOD  : integer := 5818;  -- A4，约 440 Hz
    constant B4_HALF_PERIOD  : integer := 5182;  -- B4，约 494 Hz
    constant HZ200_HALF_PERIOD : integer := 12800; -- 200 Hz（精确）

    -- 小星星节奏参数（clk8 = 5.12 MHz）
    constant SHORT_TIME : integer := 1280000; -- 0.25 秒
    constant LONG_TIME  : integer := 2560000; -- 0.50 秒
    constant GAP_TIME   : integer := 128000;  -- 0.025 秒，音符之间的静音
    constant PAUSE_TIME : integer := 5120000; -- 1 秒，整曲结束后的暂停

    -- 数字简谱：1=C4, 2=D4, 3=E4, 4=F4, 5=G4, 6=A4, 7=B4
    -- 六句《小星星》，共 42 个音符；播放完后循环。
    type melody_type is array (0 to 41) of integer range 1 to 7;
    constant MELODY : melody_type := (
        1,1,5,5,6,6,5,
        4,4,3,3,2,2,1,
        5,5,4,4,3,3,2,
        5,5,4,4,3,3,2,
        1,1,5,5,6,6,5,
        4,4,3,3,2,2,1
    );

    -- 旋律播放状态：发声、音符间隔、整曲暂停
    type state_type is (S_PLAY, S_GAP, S_PAUSE);
    signal state : state_type := S_PLAY;

    signal note_index : integer range 0 to 41 := 0;
    signal time_cnt   : integer range 0 to PAUSE_TIME - 1 := 0;
    signal half_cnt   : integer range 0 to HZ200_HALF_PERIOD - 1 := 0;
    signal wave_high  : STD_LOGIC := '1';
    signal mode_prev  : STD_LOGIC_VECTOR(1 downto 0) := "00";

    signal current_half_period : integer range 1 to HZ200_HALF_PERIOD := C4_HALF_PERIOD;
    signal current_note_time   : integer range SHORT_TIME to LONG_TIME := SHORT_TIME;

begin

    -- 根据当前模式与音符，选择方波半周期。
    process(mode, note_index)
    begin
        if mode = "11" then
            current_half_period <= HZ200_HALF_PERIOD; -- 200 Hz
        elsif mode = "01" then
            current_half_period <= C4_HALF_PERIOD;    -- 持续 C4
        else
            -- mode=10 使用当前的小星星音符。
            case MELODY(note_index) is
                when 1 => current_half_period <= C4_HALF_PERIOD;
                when 2 => current_half_period <= D4_HALF_PERIOD;
                when 3 => current_half_period <= E4_HALF_PERIOD;
                when 4 => current_half_period <= F4_HALF_PERIOD;
                when 5 => current_half_period <= G4_HALF_PERIOD;
                when 6 => current_half_period <= A4_HALF_PERIOD;
                when 7 => current_half_period <= B4_HALF_PERIOD;
                when others => current_half_period <= C4_HALF_PERIOD;
            end case;
        end if;
    end process;

    -- 每句最后一个音符延长到 0.5 秒，其余音符为 0.25 秒。
    current_note_time <= LONG_TIME when
        note_index = 6  or note_index = 13 or
        note_index = 20 or note_index = 27 or
        note_index = 34 or note_index = 41
        else SHORT_TIME;

    -- 四种模式统一控制 32 路输出。
    -- 00：原样输出，不增加任何音频调制。
    -- 01：使用 C4 方波对 32 路 data_out 进行开关调制。
    -- 10：使用小星星旋律调制；音符间隔和暂停期间输出 0。
    -- 11：使用 200 Hz 方波对 32 路 data_out 进行开关调制。
    music_out <= data_out when
        mode = "00" or
        ((mode = "01" or mode = "11") and wave_high = '1') or
        (mode = "10" and state = S_PLAY and wave_high = '1')
        else (others => '0');

    process(clk8)
    begin
        if rising_edge(clk8) then

            -- 检测模式改变：重置方波和小星星播放状态。
            -- 因此重新进入 mode=10 时，小星星从头开始演奏。
            mode_prev <= mode;
            if mode /= mode_prev then
                state      <= S_PLAY;
                note_index <= 0;
                time_cnt   <= 0;
                half_cnt   <= 0;
                wave_high  <= '1';
            else
                case mode is
                    when "00" =>
                        -- 直接透传 data_out，无需运行音频计数器。
                        null;

                    when "01" | "11" =>
                        -- 连续输出 C4 或 200 Hz 方波；不插入静音间隔。
                        if half_cnt = current_half_period - 1 then
                            half_cnt  <= 0;
                            wave_high <= not wave_high;
                        else
                            half_cnt <= half_cnt + 1;
                        end if;

                    when "10" =>
                        -- 小星星播放状态机。
                        case state is
                            when S_PLAY =>
                                -- 当前音符达到预定时长后，进入静音间隔。
                                if time_cnt = current_note_time - 1 then
                                    time_cnt  <= 0;
                                    half_cnt  <= 0;
                                    wave_high <= '1';
                                    state     <= S_GAP;
                                else
                                    time_cnt <= time_cnt + 1;
                                    -- 当前音符的方波生成。
                                    if half_cnt = current_half_period - 1 then
                                        half_cnt  <= 0;
                                        wave_high <= not wave_high;
                                    else
                                        half_cnt <= half_cnt + 1;
                                    end if;
                                end if;

                            when S_GAP =>
                                -- 音符之间保持 0.025 秒静音。
                                if time_cnt = GAP_TIME - 1 then
                                    time_cnt <= 0;
                                    half_cnt <= 0;
                                    wave_high <= '1';
                                    if note_index = 41 then
                                        state <= S_PAUSE;
                                    else
                                        note_index <= note_index + 1;
                                        state <= S_PLAY;
                                    end if;
                                else
                                    time_cnt <= time_cnt + 1;
                                end if;

                            when S_PAUSE =>
                                -- 全曲播放完成后静音 1 秒，再循环播放。
                                if time_cnt = PAUSE_TIME - 1 then
                                    time_cnt   <= 0;
                                    half_cnt   <= 0;
                                    note_index <= 0;
                                    wave_high  <= '1';
                                    state      <= S_PLAY;
                                else
                                    time_cnt <= time_cnt + 1;
                                end if;
                        end case;

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end architecture Behavioral;
