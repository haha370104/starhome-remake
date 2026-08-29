param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExecutable
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$godot = [System.IO.Path]::GetFullPath($GodotExecutable)

if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    throw "Godot executable not found: $godot"
}

Write-Output "Testing staged change size policy"
& python (Join-Path $PSScriptRoot "tests/test_check_staged_change_size.py")
if ($LASTEXITCODE -ne 0) {
    throw "Staged change size policy tests failed"
}

Write-Output "Checking staged change size"
& python (Join-Path $PSScriptRoot "check_staged_change_size.py")
if ($LASTEXITCODE -ne 0) {
    throw "Staged change size check failed"
}

Write-Output "Checking large-asset Git LFS policy"
& python (Join-Path $PSScriptRoot "check_asset_size_policy.py")
if ($LASTEXITCODE -ne 0) {
    throw "Large-asset Git LFS policy failed"
}

function Assert-NoRuntimeLoadErrors([string]$LogFile) {
    $fatalPatterns = "SCRIPT ERROR:|Parse Error:|No loader found for resource:|Failed to load script|Invalid call\. Nonexistent"
    if (Select-String -LiteralPath $LogFile -Pattern $fatalPatterns -Quiet) {
        throw "Godot reported a runtime/script load error. See: $LogFile"
    }
}

Write-Output "Checking GDScript function documentation"
& python (Join-Path $PSScriptRoot "check_gdscript_doc_comments.py")
if ($LASTEXITCODE -ne 0) {
    throw "GDScript documentation check failed"
}

Write-Output "Importing project assets"
$importLog = Join-Path $projectRoot ".godot/check-import.log"
& $godot --headless --editor --path $projectRoot --log-file $importLog --quit
if ($LASTEXITCODE -ne 0) {
    throw "Godot asset import failed"
}
Assert-NoRuntimeLoadErrors $importLog

$testScripts = @(
    "res://tests/domain/run_domain_smoke_tests.gd",
    "res://tests/network/contracts/run_network_contract_tests.gd",
    "res://tests/client/network/client_network_smoke_test.gd",
	"res://tests/client/presentation/hall_multiplayer_presenter_smoke_test.gd",
	"res://tests/client/presentation/client_map_preloader_smoke_test.gd",
	"res://tests/client/presentation/combat/combat_visual_presenter_smoke_test.gd",
	"res://tests/client/presentation/combat/weapon_attack_visual_controller_test.gd",
	"res://tests/client/presentation/combat/monster_death_effect_controller_test.gd",
	"res://tests/client/presentation/combat/monster_attack_effect_controller_test.gd",
	"res://tests/client/presentation/combat/ground_loot_world_controller_test.gd",
	"res://tests/server/authoritative_server_smoke_test.gd",
	"res://tests/server/combat/authoritative_combat_module_test.gd",
	"res://tests/server/combat/combat_definition_catalog_test.gd",
	"res://tests/server/persistence/player_state_persistence_test.gd",
	"res://tests/server/persistence/authoritative_autosave_test.gd",
	"res://tests/server/player_panels/player_panel_service_test.gd",
	"res://tests/domain/player_rich_model_test.gd",
	"res://tests/integration/map_transition_scene_smoke_test.gd",
	"res://tests/integration/active_world_transition_view_smoke_test.gd",
	"res://tests/integration/client_state_seam_characterization_test.gd",
	"res://tests/integration/d04_player_vehicle_presentation_test.gd",
	"res://tests/integration/d04_authoritative_combat_test.gd",
	"res://tests/ui/runtime/hud_runtime_smoke_test.gd",
	"res://tests/ui/runtime/player_panels_runtime_test.gd",
    "res://tests/maps/map_runtime_smoke_test.gd",
	"res://tests/maps/glory_world_graph_data_test.gd",
    "res://tests/navigation/diamond_navigation_smoke_test.gd",
    "res://tests/world/semantic_scene_depth_smoke_test.gd"
)

$testIndex = 0
foreach ($testScript in $testScripts) {
    $testIndex += 1
    Write-Output "Running $testScript"
    $logFile = Join-Path $projectRoot ".godot/check-$testIndex.log"
    & $godot --headless --path $projectRoot --log-file $logFile --script $testScript
    if ($LASTEXITCODE -ne 0) {
        throw "Godot test failed: $testScript"
    }
    Assert-NoRuntimeLoadErrors $logFile
}

Write-Output "Running real ENet dual-client integration"
& (Join-Path $PSScriptRoot "run_enet_integration.ps1") -GodotExecutable $godot
if ($LASTEXITCODE -ne 0) {
    throw "Real ENet dual-client integration failed"
}

Write-Output "Running real ENet RoomSvr1-to-City1Svr map-transition integration"
& (Join-Path $PSScriptRoot "run_enet_map_transition_integration.ps1") -GodotExecutable $godot
if ($LASTEXITCODE -ne 0) {
    throw "Real ENet map-transition integration failed"
}

Write-Output "Running main scene smoke test"
$mainLog = Join-Path $projectRoot ".godot/check-main-scene.log"
& $godot --headless --path $projectRoot --log-file $mainLog --quit-after 3
if ($LASTEXITCODE -ne 0) {
    throw "Main scene smoke test failed"
}
Assert-NoRuntimeLoadErrors $mainLog

& (Join-Path $PSScriptRoot "check_asset_conventions.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Asset convention check failed"
}

Write-Output "Auditing Free HUD allowlisted sources"
& python (Join-Path $projectRoot "tests/ui/assets/test_free_hud_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Free HUD source audit failed"
}

Write-Output "Auditing Glory monster sources"
& python (Join-Path $PSScriptRoot "audit_monster_asset_sources.py")
if ($LASTEXITCODE -ne 0) {
    throw "Monster source audit failed"
}

Write-Output "Auditing Stage-2 Glory map presentations"
& python (Join-Path $PSScriptRoot "audit_map_presentation_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Stage-2 map presentation audit failed"
}

Write-Output "Auditing Glory hall exit transition"
& python (Join-Path $PSScriptRoot "audit_hall_exit_transition.py")
if ($LASTEXITCODE -ne 0) {
    throw "Hall exit transition audit failed"
}

Write-Output "Auditing source-bound transition markers"
& python (Join-Path $PSScriptRoot "audit_transition_marker_sources.py")
if ($LASTEXITCODE -ne 0) {
    throw "Transition marker source audit failed"
}

Write-Output "Auditing Stage-3 Glory combat content"
& python (Join-Path $PSScriptRoot "audit_stage3_content.py")
if ($LASTEXITCODE -ne 0) {
    throw "Stage-3 combat content audit failed"
}

Write-Output "Auditing Stage-3 Glory combat presentation assets"
& python (Join-Path $PSScriptRoot "import_glory_starter_combat_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Stage-3 combat presentation asset audit failed"
}

Write-Output "Auditing Glory ground-loot presentation assets"
& python (Join-Path $PSScriptRoot "import_glory_ground_loot_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Ground-loot presentation asset audit failed"
}

Write-Output "Auditing Glory self-repair presentation assets"
& python (Join-Path $PSScriptRoot "import_glory_self_repair_assets.py")
if ($LASTEXITCODE -ne 0) {
    throw "Self-repair presentation asset audit failed"
}

Write-Output "All project checks passed."
