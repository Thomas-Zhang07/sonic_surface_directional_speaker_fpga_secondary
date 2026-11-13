#Requires -Version 5.1
<#
.SYNOPSIS
    Compile and run the RTL suite for the primary-board build.

.DESCRIPTION
    Generates the phase-correction package and the three demo frames from
    ../demo (gen_assets.py), compiles src/*.vhd + the testbenches into
    sim/work, then runs each testbench headless and reports PASS/FAIL.

    tb_chain streams the real demo/* frames (0xFE + 256 phases + 0xFD) into
    UARTReader -> Distribute at 38.4 kBaud and checks every address/phase.
#>
$ErrorActionPreference = 'Stop'

$env:SALT_LICENSE_SERVER = 'C:\Users\12966\questa_lic.dat'
$questa = 'D:\altera\questa_fse\win64'
if (-not (Test-Path (Join-Path $questa 'vsim.exe'))) {
    throw "Questa not found at $questa"
}

$sim  = Split-Path -Parent $MyInvocation.MyCommand.Path
$fpga = Split-Path -Parent $sim
$work = Join-Path $sim 'work'
New-Item -ItemType Directory -Force $work | Out-Null
Set-Location $work

Write-Host 'Generating assets (phase table + demo frames)...'
python (Join-Path $sim 'gen_assets.py')
if ($LASTEXITCODE -ne 0) { throw 'gen_assets.py failed' }

& (Join-Path $questa 'vlib.exe') work | Out-Null

$sources = @(
    (Join-Path $work 'phase_correction_pkg.vhd'),
    (Join-Path $fpga 'src\UARTReader.vhd'),
    (Join-Path $fpga 'src\RSSFilter_1.vhd'),
    (Join-Path $fpga 'src\Counter.vhd'),
    (Join-Path $fpga 'src\PulseExpander.vhd'),
    (Join-Path $fpga 'src\LatchBuffer.vhd'),
    (Join-Path $fpga 'src\PhaseLine.vhd'),
    (Join-Path $fpga 'src\Mux8.vhd'),
    (Join-Path $fpga 'src\music_player.vhd'),
    (Join-Path $fpga 'src\AllChannels.vhd'),
    (Join-Path $fpga 'src\Distribute.vhd'),
    (Join-Path $sim  'tb_distribute.vhd'),
    (Join-Path $sim  'tb_phaseline.vhd'),
    (Join-Path $sim  'tb_allchannels.vhd'),
    (Join-Path $sim  'tb_music_player.vhd'),
    (Join-Path $sim  'tb_chain.vhd'),
    (Join-Path $sim  'tb_glue.vhd'),
    (Join-Path $sim  'tb_pulseexpander.vhd'),
    (Join-Path $sim  'tb_dist_primary.vhd'),
    (Join-Path $sim  'tb_phase_primary.vhd')
)

Write-Host 'Compiling...'
& (Join-Path $questa 'vcom.exe') -2008 -work work $sources
if ($LASTEXITCODE -ne 0) { throw 'vcom failed' }

$script:failures = 0

function Run-TB {
    param([string]$Top, [string]$RunTime, [string]$Label)
    $log = Join-Path $work "$Label.log"
    & (Join-Path $questa 'vsim.exe') -t 1ps -c -do "run $RunTime; quit -f" "work.$Top" 2>&1 |
        Out-File -FilePath $log -Encoding utf8
    if (Select-String -Path $log -Pattern 'TEST PASSED' -Quiet) {
        Write-Host "PASS  $Label"
    } else {
        $script:failures++
        Write-Host "FAIL  $Label  (see $log)"
        Get-Content $log -Tail 25 | ForEach-Object { Write-Host "      $_" }
    }
}

Write-Host ''
Run-TB -Top 'tb_dist_primary'  -RunTime '5 us'   -Label 'tb_dist_primary'
Run-TB -Top 'tb_phase_primary' -RunTime '2 ms'   -Label 'tb_phase_primary'
Run-TB -Top 'tb_distribute'    -RunTime '100 us' -Label 'tb_distribute'
Run-TB -Top 'tb_phaseline'     -RunTime '20 us'  -Label 'tb_phaseline'
Run-TB -Top 'tb_allchannels'   -RunTime '2 ms'   -Label 'tb_allchannels'
Run-TB -Top 'tb_music_player'  -RunTime '700 ms' -Label 'tb_music_player'
Run-TB -Top 'tb_glue'          -RunTime '2 ms'   -Label 'tb_glue'
Run-TB -Top 'tb_pulseexpander' -RunTime '20 us'  -Label 'tb_pulseexpander'

foreach ($demo in @('demo1', 'demo2', 'demo3')) {
    Copy-Item (Join-Path $work "frame_$demo.txt") (Join-Path $work 'frame_input.txt') -Force
    Run-TB -Top 'tb_chain' -RunTime '400 ms' -Label "tb_chain_$demo"
}

Write-Host ''
if ($script:failures -eq 0) {
    Write-Host 'ALL TESTS PASSED'
} else {
    Write-Host "$($script:failures) TEST(S) FAILED"
    exit 1
}
