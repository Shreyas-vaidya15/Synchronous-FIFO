# Run from the folder containing synchronous_FIFO.sv and tb.sv:
#   powershell -ExecutionPolicy Bypass -File run_checks.ps1

$rtl = "rtl\synchronous_FIFO.sv"
$tb  = "tb\tb.sv"
$report = @()

# raw output of every simulation goes here (gitignored), nothing gets cut off
New-Item -ItemType Directory -Force logs | Out-Null
Set-Content logs\all_runs.log ""

function Say($s) { Write-Host $s; $script:report += $s }

function Simulate($label, $rtlFile, $extraArgs) {
    Remove-Item sim -ErrorAction SilentlyContinue
    $cout = & iverilog -g2012 @extraArgs -o sim $rtlFile $tb 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Add-Content logs\all_runs.log ("===== " + $label + " (COMPILE ERROR) =====`n" + $cout)
        return @("COMPILE ERROR", $cout)
    }
    $out = & vvp sim 2>&1 | Out-String
    Add-Content logs\all_runs.log ("===== " + $label + " =====`n" + $out)
    return @("OK", $out)
}

# ---------------------------------------------------------------
# Part 1: parameter sweep
# ---------------------------------------------------------------
$sweep = @(
    @("depth 32, width 32 (default)", @()),
    @("depth 4, width 32",  @("-Ptb.DEPTH=4")),
    @("depth 8, width 32",  @("-Ptb.DEPTH=8")),
    @("depth 16, width 32", @("-Ptb.DEPTH=16")),
    @("depth 64, width 32", @("-Ptb.DEPTH=64")),
    @("depth 8, width 8",   @("-Ptb.DEPTH=8", "-Ptb.DATA_WIDTH=8")),
    @("depth 6",            @("-Ptb.DEPTH=6")),
    @("depth 2",            @("-Ptb.DEPTH=2"))
)

Say "### Parameter sweep"
Say ""
Say "| Config | Result |"
Say "|---|---|"
foreach ($s in $sweep) {
    $r = Simulate ("sweep: " + $s[0]) $rtl $s[1]
    $out = $r[1]
    if ($r[0] -ne "OK") {
        $res = "COMPILE ERROR (see below)"
        Write-Host $out
    }
    elseif ($out -match "ALL CHECKS PASSED") { $res = "pass" }
    elseif ($out -match "MEM_DEPTH must be|Bad thresholds") { $res = "rejected by `$error" }
    else { $res = "FAIL (run it by hand to see why)" }
    Say ("| " + $s[0] + " | " + $res + " |")
}

# ---------------------------------------------------------------
# Part 2: mutation testing on the current RTL (default config)
# ---------------------------------------------------------------
$orig = Get-Content $rtl -Raw

# name, exact text to find, replacement
$mutations = @(
    @("remove ~full from do_write",
      "assign do_write = (write_en && ~full);",
      "assign do_write = (write_en);"),
    @("remove ~empty from do_read",
      "assign do_read  = (read_en  && ~empty);",
      "assign do_read  = (read_en);"),
    @("full compares only lower pointer bits",
      "assign full  = (write_ptr[ADDRESS_WIDTH] != read_ptr[ADDRESS_WIDTH]) && (",
      "assign full  = ("),
    @("remove ~full from almost_full",
      "assign almost_full  = ~full  && (difference >= ALMOST_FULL);",
      "assign almost_full  = (difference >= ALMOST_FULL);"),
    @("almost_empty uses < instead of <=",
      "(difference <= ALMOST_EMPTY)",
      "(difference < ALMOST_EMPTY)"),
    @("difference one bit too narrow",
      "logic [ADDRESS_WIDTH:0] difference;",
      "logic [ADDRESS_WIDTH-1:0] difference;"),
    @("underflow = empty && read_en && write_en",
      "assign underflow = empty && read_en;",
      "assign underflow = empty && read_en && write_en;"),
    @("overflow = full && write_en && ~read_en",
      "assign overflow  = full  && write_en;",
      "assign overflow  = full  && write_en && ~read_en;"),
    @("write_ptr increments by 2",
      "write_ptr + 1'b1",
      "write_ptr + 2'd2"),
    @("no reset of read_data",
      "read_data <= '0;",
      "")
)

Say ""
Say "### Mutation testing (current RTL, default config)"
Say ""
Say "| Mutation | First failure | Caught by |"
Say "|---|---|---|"

foreach ($m in $mutations) {
    $mutated = $orig.Replace($m[1], $m[2])
    if ($mutated -eq $orig) {
        Say ("| " + $m[0] + " | MUTATION DID NOT APPLY (text not found) | |")
        continue
    }
    Set-Content -Path "mut.sv" -Value $mutated -NoNewline
    $r = Simulate ("mutation: " + $m[0]) "mut.sv" @()
    $out = $r[1]
    if ($r[0] -ne "OK") {
        Say ("| " + $m[0] + " | COMPILE ERROR (mutation is invalid) | |")
        continue
    }
    $lines = $out -split "`r?`n"
    if ($out -match "FIRST FAILURE at (\d+)") {
        $t = $Matches[1]
        $idx = [array]::IndexOf($lines, ($lines | Where-Object { $_ -match "FIRST FAILURE" } | Select-Object -First 1))
        $why = ""
        if ($idx -gt 1) {
            $why = $lines[$idx - 1].Trim()
            # iverilog prints "Time: ... Scope: ..." after the message, so step back one more
            if ($why -match "^Time:") { $why = $lines[$idx - 2].Trim() }
            $why = $why -replace "^ERROR:\s*", ""
        }
        Say ("| " + $m[0] + " | t=" + $t + " | " + $why + " |")
    }
    elseif ($out -match "ALL CHECKS PASSED") {
        Say ("| " + $m[0] + " | NOT CAUGHT (testbench passed) | testbench gap |")
    }
    else {
        $f = ($lines | Where-Object { $_ -match "FAILED|never exercised" } | Select-Object -First 1)
        Say ("| " + $m[0] + " | caught at end of run | " + $f + " |")
    }
}

Remove-Item mut.sv, sim -ErrorAction SilentlyContinue
$report | Set-Content results.md
Write-Host ""
Write-Host "Summary tables saved to results.md"
Write-Host "Full raw output of every run saved to logs\all_runs.log"