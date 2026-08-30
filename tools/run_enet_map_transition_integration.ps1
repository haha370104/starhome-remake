param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExecutable
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$godot = [System.IO.Path]::GetFullPath($GodotExecutable)
$port = 32000 + ($PID % 1000)
$resultDir = Join-Path $projectRoot ".godot/enet-map-transition-$PID"
$worker = "res://tests/integration/enet_map_transition_worker.gd"

New-Item -ItemType Directory -Path $resultDir -Force | Out-Null

function Start-MapTransitionWorker([string]$Role) {
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

function Wait-MapTransitionWorker(
    [System.Diagnostics.Process]$Process,
    [string]$Role,
    [int]$TimeoutMsec
) {
    if (-not $Process.WaitForExit($TimeoutMsec)) {
        $Process.Kill()
        throw "ENet map-transition $Role worker timed out. Logs: $resultDir"
    }
    # Windows PowerShell 5.1 需要无参等待完成重定向流刷新，之后才能读取 ExitCode。
    $Process.WaitForExit()
    $Process.Refresh()
    if ($null -ne $Process.ExitCode -and $Process.ExitCode -ne 0) {
        throw "ENet map-transition $Role worker failed with exit code $($Process.ExitCode). Logs: $resultDir"
    }
    $resultPath = Join-Path $resultDir "${Role}_result.json"
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "ENet map-transition $Role worker did not write a result. Logs: $resultDir"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (-not $result.ok) {
        throw "ENet map-transition $Role assertions failed: $($result.failures -join '; ')"
    }
    return $result
}

$server = $null
$client = $null
try {
    $server = Start-MapTransitionWorker "server"
    $readyPath = Join-Path $resultDir "server_ready.json"
    # 荣耀版内容装载会在低速磁盘或冷缓存下占用数秒；这里只放宽进程启动阶段，
    # 客户端握手和业务断言仍由 worker 内各自的短超时约束。
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
        if ($server.HasExited) {
            throw "ENet map-transition server exited before becoming ready with exit code $($server.ExitCode). Logs: $resultDir"
        }
        if ([DateTime]::UtcNow -ge $readyDeadline) {
            throw "ENet map-transition server did not become ready. Logs: $resultDir"
        }
        Start-Sleep -Milliseconds 50
    }
    $client = Start-MapTransitionWorker "client"
    $clientResult = Wait-MapTransitionWorker $client "client" 20000
    $serverResult = Wait-MapTransitionWorker $server "server" 20000
    if ($clientResult.entity_id -ne $serverResult.entity_id) {
        throw "Client and server observed different transferred entity IDs"
    }
    if (-not $clientResult.map_joined_valid -or -not $serverResult.session_switched) {
        throw "MapJoined validation or authoritative session switch did not complete"
    }
    if (-not $clientResult.latest_snapshots_isolated -or -not $serverResult.target_snapshot_isolated) {
        throw "Post-transition snapshots were not isolated to City1Svr"
    }
    Write-Output "ENET_MAP_TRANSITION_INTEGRATION_OK (RoomSvr1 -> City1Svr)"
}
finally {
    foreach ($process in @($client, $server)) {
        if ($null -ne $process -and -not $process.HasExited) {
            $process.Kill()
        }
    }
}
