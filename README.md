# QuadrupleBuffer — primary board, 16 phases, 40 kHz, demo host

Clean build of the SonicSurface **FPGA primary** design, ported to Quartus
Prime Lite 25.1 and adapted to the PC host in `../demo`.

## Configuration

| Item | Value |
|---|---|
| Board | primary (port D generates the sync clock; port A is not used) |
| PLL | 50 MHz × 128/1250 = **5.12 MHz** |
| Phase bins | **16** (22.5° per bin) |
| OFF code | **0x10** |
| Carrier | 16 slots × 8 clk8 = 128 clk8 = **25 µs → 40 kHz**, 50 % duty |
| UART | 5.12 MHz / 133 = **38.4 kBaud**, 8N1 (`g_CLKS_PER_BIT = 133`) |
| Frame | `0xFE + 256 payload bytes + 0xFD` (see `../demo/protocol.py`) |
| Payload | low nibble = phase 0..15; high nibble = amplitude code 0..15; `0x10` = OFF |
| Amplitude | pulse width 1..8 of the 16 carrier steps, centred on the phase; code `0` = legacy full scale |
| Port D (`MISC_D`) | **COUNT[6]** → 40 kHz, one pulse per carrier period |
| `PHASE_CORRECTION` | **boardsPrimary** active, boardsSecondary commented out |

## Changes relative to `../fpga_code`

1. `src/Distribute.vhd` — restored the **primary** board-select polarity
   (`0xC0` enables, `0xC1` disables). The fpga_code file had the secondary
   board's version (`0xC0` disables), although the top level is the primary
   variant. Also `0xFE` starts a frame regardless of the enable state, as in
   the upstream primary.
2. `src/Distribute.vhd` — activated the **boardsPrimary** phase-calibration
   table (the fpga_code build applied the secondary board's table).
3. `src/QuadrupleBuffer.bdf` — `MISC_D` (port D) moved from `COUNT[7]` to
   `COUNT[6]`. With 16 phases the carrier period is 128 clk8, so `COUNT[6]`
   is the 40 kHz carrier-period signal; `COUNT[7]` was 20 kHz and would break
   the primary→secondary clock sync.
4. Project cleanup: removed SignalTap, the EDA testbench, stale
   partition/incremental assignments and the missing `Chain2.cdf` reference.
   The design now fits in 5,416 / 6,272 LEs (86 %) instead of 5,647 (90 %).
5. `src/Masterclock.vhd` — stale wizard comments corrected to 5.12 MHz / 1250.
6. Per-channel **duty amplitude weighting**: `PhaseLine` now takes a centred
   on/off step pair, `AllChannels` decodes the payload high nibble, and
   `Distribute` corrects only the phase nibble. See below.

Unchanged from fpga_code: 5.12 MHz PLL, 16 phase bins, off `0x10`, 38.4 kBaud,
`PulseExpander` glitch fix, `music_player` modes (`00` = pass-through).

## Per-channel duty amplitude weighting

Each payload byte now carries both controls:

```
bit 7..4  amplitude code 0..15   (0 = legacy full scale)
bit 3..0  phase bin 0..15
0x10      OFF (legacy code, still takes precedence)
```

Code-to-width mapping (16-step, 40 kHz period):

| code | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| width | 8 | 1 | 1 | 2 | 2 | 3 | 3 | 4 | 4 | 5 | 5 | 6 | 6 | 7 | 7 | 8 |

The fundamental amplitude of a width-`w` pulse is `sin(pi*w/16)`, so width 8
(50 % duty) is full scale and the useful weighting range is 1..8. The pulse is
centred on the phase bin: for width `w` the lead is `4 - w/2`, so widths 8, 4
and 1 all keep their centre at step `phase+5`.

Because the low nibble is the phase, **legacy frames are bit-for-bit
unchanged** (their high nibble is zero). Old firmware also ignores a high
nibble (its `Distribute` masks with `0x0F`), so amplitude frames sent to the
old bitstream degrade gracefully to phase-only.

Implementation notes:

- `Distribute.vhd` applies `PHASE_CORRECTION` to `q_in(3 downto 0)` and passes
  the amplitude nibble through untouched.
- `AllChannels.vhd` decodes amplitude code -> width -> centred `on_step` /
  `off_step` **once** and shares the two 4-bit busses with all 256 instances.
- `PhaseLine.vhd` stores the pair in its existing double buffer and uses two
  4-bit comparators; equal steps mean OFF. Both phase and amplitude switch at
  `0xFD`, so a frame update is atomic.
- Resource cost: 5,628 / 6,272 LEs (90 %), 4,707 combinational (75 %), 4,819
  registers (77 %). The shared decode keeps the array inside the EP4CE6.

## Build

Open `QuadrupleBuffer.qpf` in Quartus Prime Lite 25.1 and run **Start
Compilation**, or from a shell:

```
quartus_sh --flow compile QuadrupleBuffer
```

Outputs (in `output_files/`):

- `QuadrupleBuffer.sof` — JTAG programming
- `QuadrupleBuffer_primary.jic` (project root) — EPCS16 active-serial image

Both were generated from the verified source state.

## Tests

`sim/run_sim.ps1` generates the phase package + the three frames from
`../demo` (`gen_assets.py`), compiles the RTL and runs:

| Test | Checks |
|---|---|
| `tb_dist_primary` | primary board-select polarity, primary correction table, OFF |
| `tb_phase_primary` | 40 kHz carrier period and OFF behaviour |
| `tb_distribute` | full byte protocol (frame, correction, OFF, modes, 256-byte limit) |
| `tb_phaseline` | exact phase-slot timing, centred duty widths, set/swap double buffer |
| `tb_allchannels` | address decode, 8-slot multiplexing, OFF |
| `tb_music_player` | mode 00 pass-through and audio gating |
| `tb_glue` | UARTReader → RSSFilter → Distribute → PulseExpander → LatchBuffer → AllChannels |
| `tb_pulseexpander` | no glitch while the input is held high, one clean pulse per input |
| `tb_chain_demo1/2/3` | the actual **demo/** frames (`0xFE` + 256 payload bytes + `0xFD`) streamed at 38.4 kBaud, every address/phase checked |

## Verification performed

- Quartus fit: successful, 5,628 / 6,272 LE (90 %), 4,819 registers, 44 pins.
- Full RTL suite (`sim/run_sim.ps1`): **ALL TESTS PASSED**, including
  `tb_chain_demo1/2/3` — the real `demo/` frames are streamed through
  UARTReader → Distribute at 38.4 kBaud and every address/phase matches.
- `tb_dist_primary`: `0xC0` enables, `0xC1` disables; the active correction
  table is applied to the phase nibble (checked via the generated package),
  while an amplitude nibble passes through untouched; `0x10` passes through as
  OFF; `0xFE` restarts.
- `tb_phaseline`: widths 4 and 1 rise later and stay centred on step `p+5`;
  width 8 keeps the legacy rise at `p+1`; equal on/off steps are silent.
- `tb_allchannels`: amplitude code 8 produces a 4-step pulse and code 0 the
  legacy 8-step pulse (measured as consecutive high mux samples).
- `tb_phase_primary`: carrier period **25.000 µs** (40 kHz); programming
  channels 0..7 to `0x10` and swapping makes `DATA(0)` quiet.
- Gate-level (post-fit `QuadrupleBuffer.vho`): `MISC_D` period **25.000 µs**
  and `DATA(0)` period **25.000 µs**.

## Notes

- There is no SDC in this project (same as upstream). The analyzer reports
  unconstrained-clock warnings for the counter-derived clocks
  `COUNT[2]` / `COUNT[7]`. Add a 50 MHz `create_clock` + `derive_pll_clocks`
  + `derive_clock_uncertainty` before timing sign-off.
- For the **secondary** board, use the secondary variant instead: table =
  `boardsSecondary`, `0xC0` disable / `0xC1` enable, and the top level with
  `MISC_A` (sync input). Do not flash this image to the secondary board.
- `LED[2]` = board enable, `LED[1]` = frame swap (toggles once per `0xFD`),
  `LED[3]` = shift-clock enable, `MISC_D` = 40 kHz sync.
