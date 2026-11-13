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
| `MISC_A` (port A) | **input**: primary `MISC_D` pulse → `SyncTrim` (inside `Distribute`) → Counter sync |
| `MISC_D` (port D) | **not present**: the secondary must not drive the shared sync line |
| Fine trim | `0xE0 0x5A <value>` command, 50 MHz steps (**20 ns = 0.288°**), default **127** |
| Board select | **`0xC1` enables, `0xC0` disables** (reverse of the primary) |
| `PHASE_CORRECTION` | **boardsSecondary** active, boardsPrimary commented out |

## Changes relative to `../primary`

1. `src/QuadrupleBuffer.bdf` — added the `MISC_A` input pin and wired it
   to the new `SyncTrim` block, which is instantiated **inside**
   `Distribute`.  The old GND/RST wire and the `RSSFilter_1` sync path are
   gone; the UART `RSSFilter` (`MISC_B`) is untouched.
2. `src/QuadrupleBuffer.bdf` — removed the `MISC_D` output pin.  Only the
   primary may drive the sync cable.
3. `src/SyncTrim.vhd` — new.  A 2-flop synchronizer in the 50 MHz domain
   removes metastability, the edge is delayed by the trim value (20 ns
   steps), and a toggle crosses into the 5.12 MHz domain through a second
   synchronizer.  A toggle is used because the delay can exceed one
   5.12 MHz period.  The fixed latency is absorbed by `SYNC_LOAD`.
4. `src/Counter.vhd` — a sync edge loads `SYNC_LOAD` (17) instead of zero.
   With the default trim (127) the primary is at 17 when the secondary
   loads, so the counters are identical (mod 128, the carrier period).
   Resetting to zero would leave a 180° carrier error and the two boards
   would cancel at broadside.
5. `src/Distribute.vhd` — reversed the board-select polarity: `0xC0` now
   disables this board and `0xC1` enables it.  `0xFE` still starts a frame
   and `0xFD` still swaps, as on the primary.
6. `src/Distribute.vhd` — the trim command `0xE0 0x5A <value>` is decoded
   **only between frames** (after `0xFD`, before the next `0xFE`), so a
   payload byte `0xE0` is never mistaken for it.  The value is serialised
   to `SyncTrim` (MSB first, `trim_bit` / `trim_strobe`) to keep the
   schematic free of an 8-bit bus.  Reset value: 127.
7. `src/Distribute.vhd` — activated the **boardsSecondary** phase
   calibration table, permuted to wire order with `EMITTERS_ORDER` exactly
   as the primary table is.  The primary table stays commented for
   reference.
8. `sim/tb_dist_secondary.vhd` replaces `tb_dist_primary.vhd`;
   `sim/tb_phase_secondary.vhd` replaces `tb_phase_primary.vhd`;
   `sim/tb_sync.vhd` is new and checks the synchronizers, the default
   alignment and the trim range.

Unchanged from the primary: 5.12 MHz PLL, 16 phase bins, OFF `0x10`,
38.4 kBaud, `PulseExpander` glitch fix, `music_player` modes (`00` =
pass-through), and the duty amplitude weighting below.

## Sync cable

| Primary pin | Secondary pin | Purpose |
|---|---|---|
| `MISC_D` (PIN_120) | `MISC_A` (PIN_65) | 40 kHz carrier sync |
| GND | GND | Common ground |

Keep the cable short and connect the grounds.  The primary emits a
**one-clock pulse at `COUNT = 0`** (once per 25 µs), not the old
`COUNT[6]` square wave.  The secondary synchronizes that pulse, delays it
by the trim value and loads the carrier counter with 17.  At power-up
without a sync input the secondary free-runs; the next pulse pulls it into
step.

Verification and trimming:

```
# Scope the two pins: the MISC_A edge should follow MISC_D with a fixed
# delay, and both should be 25 us apart.
python dual_directional_speaker.py --board-a-port COM6 --board-b-port COM7 --trim 127

# Sweep the secondary trim while watching the broadside level / grating null
python dual_directional_speaker.py --board-a-port COM6 --board-b-port COM7 --trim-sweep 0:255:8 --trim-dwell 2
```

Each trim step is 20 ns (0.288° at 40 kHz); the full range is about ±36°
around 127.  Send the command between frames only.  If the primary sync
source changes, update `SyncTrim`, `SYNC_LOAD` and `tb_sync` together.

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
| `tb_sync` | default trim leaves the secondary counter in step with the primary; trim 0 is about +13 clocks, trim 255 about −13, and the full range spans ≈26 clocks |
| `tb_chain_demo1/2/3` | the actual demo frames (`0xFE` + 256 payload bytes + `0xFD`) streamed at 38.4 kBaud, every address/phase checked |

## Verification performed

- Quartus fit: successful, **5,679 / 6,272 LE (91 %)**, 4,736 combinational
  (76 %), 4,845 registers (77 %), 44 pins.
- Full RTL suite (`sim/run_sim.ps1`): **ALL TESTS PASSED**.
- `tb_sync`: with the default trim the secondary counter matches the
  primary on every checked clock; trim 0 gives +13 clocks and trim 255
  −13 clocks, i.e. 255 × 20 ns ≈ 26 clocks of the 5.12 MHz clock.
- `tb_dist_secondary`: the serial trim stream reconstructs `0x20` in 8
  strobes, a payload `0xE0` inside a frame is not treated as a command, and
  a bad prefix aborts the command without changing the trim.

## Notes

- There is no SDC in this project (same as upstream).  The analyzer reports
  unconstrained-clock warnings for the counter-derived clocks
  `COUNT[2]` / `COUNT[7]`, and for the asynchronous `MISC_A` input.  The
  sync path is intentionally asynchronous; `SyncTrim` uses a 2-flop
  synchronizer in the 50 MHz domain and a toggle synchronizer in the
  5.12 MHz domain.
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
  the fine 50 MHz phase trim **is implemented** (`0xE0 0x5A <value>`); a
  frame-staging strobe is not — start with parallel host writes to both
  boards.  A future strobe
  cannot use `MISC_B`: on both boards that pin is the UART RX line
  (`MISC_B` → `RSSFilter_1` → `UARTReader.i_RX_Serial`).  Use `MISC_F`
  (PIN_115) instead.
