param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExecutable
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$godot = [System.IO.Path]::GetFullPath($GodotExecutable)
$port = 30000 + ($PID % 2000)
$resultDir = Join-Path $projectRoot ".godot/enet-integration-$PID"
$worker = "res://tests/integration/enet_process_worker.gd"

New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

function Start-EnetWorker([string]$Role) {
    $stdout = Join-Path $resultDir "$Role.stdout.log"
    $stderr = Join-Path $resultDir "$Role.stderr.log"
    $arguments = @(
        "--headless", "--path", $projectRoot,
        "--log-file", (Join-Path $resultDir "$Role.godot.log"),
        "--script", $worker, "--",
        "--role=$Role", "--port=$port", "--result-dir=$resultDir"
    )
    return Start-Process -FilePath $godot -ArgumentList $arguments -PassThru `
        -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
}

function Wait-EnetWorker([System.Diagnostics.Process]$Process, [string]$Role, [int]$TimeoutMsec) {
    if (-not $Process.WaitForExit($TimeoutMsec)) {
        $Process.Kill($true)
        throw "ENet $Role worker timed out. Logs: $resultDir"
    }
    if ($Process.ExitCode -ne 0) {
        throw "ENet $Role worker failed with exit code $($Process.ExitCode). Logs: $resultDir"
    }
    $resultPath = Join-Path $resultDir "${Role}_result.json"
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "ENet $Role worker did not write a result. Logs: $resultDir"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (-not $result.ok) {
        throw "ENet $Role assertions failed: $($result.failures -join '; ')"
    }
    return $result
}

$server = $null
$clientA = $null
$clientB = $null
try {
    $server = Start-EnetWorker "server"
    $readyPath = Join-Path $resultDir "server_ready.json"
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $readyDeadline) {
            throw "ENet server did not become ready. Logs: $resultDir"
        }
        Start-Sleep -Milliseconds 50
    }
    $clientB = Start-EnetWorker "client_b"
    Start-Sleep -Milliseconds 150
    $clientA = Start-EnetWorker "client_a"
    $clientAResult = Wait-EnetWorker $clientA "client_a" 15000
    $clientBResult = Wait-EnetWorker $clientB "client_b" 15000
    $serverResult = Wait-EnetWorker $server "server" 15000
    if ($clientAResult.entity_id -eq $clientBResult.entity_id) {
        throw "ENet clients received the same entity ID"
    }
    if ($clientBResult.remote_entity_id -ne $clientAResult.entity_id) {
        throw "Client B did not identify client A in authoritative snapshots"
    }
    if ($serverResult.entity_ids.Count -lt 2) {
        throw "Server did not retain two distinct entity IDs"
    }
    Write-Output "ENET_DUAL_CLIENT_INTEGRATION_OK (server + 2 clients + reconnect)"
}
finally {
    foreach ($process in @($clientA, $clientB, $server)) {
        if ($null -ne $process -and -not $process.HasExited) {
            $process.Kill($true)
        }
    }
}
