# QuadrupleBuffer — secondary board, 16 phases, 40 kHz, demo host

Secondary-board build of the SonicSurface FPGA design, derived from
`../primary` (Quartus Prime Lite 25.1) and adapted to the PC host in
`../../demo`.  It keeps the primary's 5.12 MHz / 16-phase / 38.4 kBaud /
duty-weighting / music-player design and changes only the board role.

## Configuration

| Item | Value |
|---|---|
| Board | **secondary** (port A receives the 40 kHz sync; port D is not driven) |
| PLL | 50 MHz × 128/1250 = **5.12 MHz** |
| Phase bins | **16** (22.5° per bin) |
| OFF code | **0x10** |
| Carrier | 16 slots × 8 clk8 = 128 clk8 = **25 µs → 40 kHz**, 50 % duty |
| UART | 5.12 MHz / 133 = **38.4 kBaud**, 8N1 (`g_CLKS_PER_BIT = 133`) |
| Frame | `0xFE + 256 payload bytes + 0xFD` (see `../../demo/protocol.py`) |
| Payload | low nibble = phase 0..15; high nibble = amplitude code 0..15; `0x10` = OFF |
| Amplitude | pulse width 1..8 of the 16 carrier steps, centred on the phase; code `0` = legacy full scale |
| `MISC_A` (port A) | **input**: primary `MISC_D` → RSSFilter → Counter sync |
| `MISC_D` (port D) | **not present**: the secondary must not drive the shared sync line |
| Board select | **`0xC1` enables, `0xC0` disables** (reverse of the primary) |
| `PHASE_CORRECTION` | **boardsSecondary** active, boardsPrimary commented out |

## Changes relative to `../primary`

1. `src/QuadrupleBuffer.bdf` — added the `MISC_A` input pin.  Its anchor
   lands directly on `RSSFilter_1`'s `bit_in`, so the filtered sync drives
   the Counter `sync_reset`.  The primary's GND/RST wire on that net was
   removed.
2. `src/QuadrupleBuffer.bdf` — removed the `MISC_D` output pin and its
   `COUNT[6]` wire.  Only the primary may drive the sync cable.
3. `src/Counter.vhd` — a sync edge loads `SYNC_LOAD` (71) instead of zero.
   The 40 kHz sync is the primary's `COUNT[6]`; the majority filter delays
   the edge six 5.12 MHz clocks, and the counter samples it one clock later,
   so the primary is at 71 when the secondary loads.  Loading 71 makes the
   two counters identical (mod 128, the carrier period).  Resetting to zero
   (the old design) leaves a constant 180° carrier error and the two boards
   cancel at broadside.
4. `src/Distribute.vhd` — reversed the board-select polarity: `0xC0` now
   disables this board and `0xC1` enables it.  `0xFE` still starts a frame
   and `0xFD` still swaps, as on the primary.
5. `src/Distribute.vhd` — activated the **boardsSecondary** phase
   calibration table, permuted to wire order with `EMITTERS_ORDER` exactly
   as the primary table is.  The primary table stays commented for
   reference.
6. `sim/tb_dist_secondary.vhd` replaces `tb_dist_primary.vhd`;
   `sim/tb_phase_secondary.vhd` replaces `tb_phase_primary.vhd`;
   `sim/tb_sync.vhd` is new and checks carrier alignment through the real
   `RSSFilter_1`.

Unchanged from the primary: 5.12 MHz PLL, 16 phase bins, OFF `0x10`,
38.4 kBaud, `PulseExpander` glitch fix, `music_player` modes (`00` =
pass-through), and the duty amplitude weighting below.

## Sync cable

| Primary pin | Secondary pin | Purpose |
|---|---|---|
| `MISC_D` (PIN_120) | `MISC_A` (PIN_65) | 40 kHz carrier sync |
| GND | GND | Common ground |

Keep the cable short and connect the grounds.  At power-up without a sync
input the secondary free-runs; the next sync edge pulls it into step.
`SYNC_LOAD = 71` is calibrated against the 5.12 MHz filter clock and the
primary's `COUNT[6]`; if the primary sync source or the filter taps change,
update `tb_sync` and the constant together.

## Per-channel duty amplitude weighting

Each payload byte carries both controls:

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
(50 % duty) is full scale and the useful weighting range is 1..8.  The pulse
is centred on the phase bin: for width `w` the lead is `4 - w/2`, so widths
8, 4 and 1 all keep their centre at step `phase+5`.

Because the low nibble is the phase, **legacy frames are bit-for-bit
unchanged** (their high nibble is zero).

Implementation notes:

- `Distribute.vhd` applies `PHASE_CORRECTION` to `q_in(3 downto 0)` and
  passes the amplitude nibble through untouched.
- `AllChannels.vhd` decodes amplitude code → width → centred `on_step` /
  `off_step` once and shares the two 4-bit busses with all 256 instances.
- `PhaseLine.vhd` stores the pair in its existing double buffer and uses two
  4-bit comparators; equal steps mean OFF.  Both phase and amplitude switch
  at `0xFD`, so a frame update is atomic.

## Build

Open `QuadrupleBuffer.qpf` in Quartus Prime Lite 25.1 and run **Start
Compilation**, or from a shell:

```
quartus_sh --flow compile QuadrupleBuffer
```

Outputs:

- `output_files/QuadrupleBuffer.sof` — JTAG programming
- `QuadrupleBuffer_secondary.jic` (project root) — EPCS16 active-serial image

The JIC is generated with:

```
quartus_cpf -c -d EPCS16 -s EP4CE6 output_files/QuadrupleBuffer.sof \
    QuadrupleBuffer_secondary.jic
```

Flash it with the same SFL-first procedure as the primary (see the
`epcs16-programming-workflow` notes in the host docs): program the factory
Serial Flash Loader, then the JIC.

## Tests

`sim/run_sim.ps1` generates the phase package + the three frames from
`../../demo` (`gen_assets.py`), compiles the RTL and runs:

| Test | Checks |
|---|---|
| `tb_dist_secondary` | secondary polarity (`0xC1` enables, `0xC0` disables), secondary correction table, OFF |
| `tb_phase_secondary` | 40 kHz carrier period and OFF behaviour |
| `tb_distribute` | full byte protocol (frame, correction, OFF, modes, 256-byte limit) |
| `tb_phaseline` | exact phase-slot timing, centred duty widths, set/swap double buffer |
| `tb_allchannels` | address decode, 8-slot multiplexing, OFF |
| `tb_music_player` | mode 00 pass-through and audio gating |
| `tb_glue` | UARTReader → RSSFilter → Distribute → PulseExpander → LatchBuffer → AllChannels |
| `tb_pulseexpander` | no glitch while the input is held high, one clean pulse per input |
| `tb_sync` | filtered `MISC_A` edge leaves the secondary counter in step with the primary (`SYNC_LOAD` = 71); `SYNC_LOAD` = 0 does not |
| `tb_chain_demo1/2/3` | the actual demo frames (`0xFE` + 256 payload bytes + `0xFD`) streamed at 38.4 kBaud, every address/phase checked |

## Verification performed

- Quartus fit: successful, **5,624 / 6,272 LE (90 %)**, 4,710 combinational
  (75 %), 4,819 registers (77 %), 44 pins.
- Full RTL suite (`sim/run_sim.ps1`): **ALL TESTS PASSED**.
- `tb_sync`: 1024 consecutive clocks with zero phase error between the
  reference primary counter and the synced secondary counter; the
  `SYNC_LOAD => 0` control fails as expected.

## Notes

- There is no SDC in this project (same as upstream).  The analyzer reports
  unconstrained-clock warnings for the counter-derived clocks
  `COUNT[2]` / `COUNT[7]`, and for the asynchronous `MISC_A` input.  The
  sync path is intentionally asynchronous; the RSSFilter and the
  edge-triggered reload handle it.
- The host must send `0xC1` to this board before a frame if a board-select
  byte is used; `0xC0` disables it.
- The correction table is the **secondary raw** table permuted to wire order
  with `EMITTERS_ORDER`, mirroring the primary build.  The raw-vs-permuted
  orientation has not been re-verified for this board: run the same
  scope/acoustic A/B used on the primary (`table_test.py`, `wire_probe.py`)
  before trusting the absolute phases.  The table compensates transducer
  polarity only; it does not change the inter-board phase.
- `LED[2]` = board enable, `LED[1]` = frame swap (toggles once per `0xFD`),
  `LED[3]` = shift-clock enable.  `MISC_D` is not driven by this build.
- `fpga/PLAN.md` in the parent directory tracks the two-board bring-up;
  the fine 50 MHz phase trim and a frame-staging strobe are not implemented
  yet — start with parallel host writes to both boards.  A future strobe
  cannot use `MISC_B`: on both boards that pin is the UART RX line
  (`MISC_B` → `RSSFilter_1` → `UARTReader.i_RX_Serial`).  Use `MISC_F`
  (PIN_115) instead.
