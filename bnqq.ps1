#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command='menu',
    [ValidateSet('plan','run','stop','status')][string]$StartAction='plan',[ValidateSet('Priority','CpuSets')][string]$StartPolicy='Priority',[string[]]$KeepApps=@('Discord','Spotify'),[switch]$LaunchGame,
    [ValidateSet('plan','apply','restore')][string]$LiteAction='plan',[ValidateSet('Edge','Chrome')][string[]]$LiteApps=@('Edge','Chrome'),
    [ValidateSet('plan','apply')][string]$CleanupAction='plan',[ValidateRange(2,90)][int]$CleanupAgeDays=2,[switch]$EmptyRecycleBin,
    [ValidateSet('plan','apply','restore')][string]$StartupAction='plan',[string[]]$StartupApps,
    [ValidateSet('plan','apply','restore')][string]$ValorantAction='plan',[string[]]$ValorantProfilePath,[switch]$AllValorantProfiles,
    [ValidateSet('plan','apply','restore')][string]$EngineAction='plan',
    [ValidateSet('CompetitiveLow','Minimum')][string]$EngineMode='CompetitiveLow',
    [ValidateSet(0,1,2)][int]$EngineBufferTicks=0,[string]$GameCfgDirectory,[string]$SteamExe,
    [string]$Profile='recording-off',[string]$BackupFile,
    [ValidateSet('status','run','stop')][string]$WatcherAction='status',
    [switch]$PinPhysical,[switch]$AboveNormal,[switch]$ObserveWmi,[switch]$Once,
    [switch]$ForceDeepIdleDisable,[switch]$DryRun,[switch]$CleanLegacyFlags,
    [ValidateSet('status','apply')][string]$LatencyAction='status',
    [ValidateRange(10,30)][int]$HeavyMinutes=10,[ValidateRange(0,128)][int]$HeavyThreads=0,
    [ValidateRange(10,300)][int]$FrameSeconds=60,[string]$FrameProcess='cs2.exe',
    [ValidateRange(0,30)][int]$FrameSkip=5,[string]$FrameHotkey='',
    [string]$Scenario,[string]$SettingsHash,[string]$ExperimentId,
    [ValidateSet('baseline','candidate')][string]$Variant='baseline',
    [string]$SwapChain,[string]$PresentMonPath,[string[]]$CaptureFiles,
    [switch]$Effective,[switch]$PrepareCleanState,[string]$BaselineFile,
    [string]$GameConfigDirectory,[ValidateSet('plan','apply','restore')][string]$CompetitiveAction='plan',
    [ValidateSet(0,2,4,8)][int]$Msaa=2,
    [int]$GameCap=-1,[int]$MenuCap=120,
    [ValidateSet('plan','run','restore')][string]$SessionAction='plan',[string[]]$SessionApps,
    [ValidateSet('plan','apply','restore')][string]$LegacyAction='plan',[string[]]$LegacyFiles,
    [ValidateSet('plan','run','restore')][string]$NetworkAction='plan',[string[]]$NetworkApps,
    [ValidateRange(64,1000000)][int]$UploadKbps=512,
    [ValidateSet('plan','run','restore')][string]$CpuAction='plan',
    [ValidateRange(1,16)][int]$BackgroundCores=2,[switch]$UnparkCpu,
    [ValidateSet('status','plan','apply','restore')][string]$GpuAction='plan',
    [string]$GameExecutable,[switch]$GpuTelemetry,
    [ValidateSet('plan','apply','restore')][string]$NvmeAction='plan',
    [ValidateSet('plan','stage','restore','activate','restore-active')][string]$NicAction='plan',[string]$AdapterName,
    [ValidateSet('plan','run','stop','status')][string]$FocusAction='plan',
    [ValidateSet('CpuSets','Priority')][string]$FocusPolicy='CpuSets',
    [string]$DpcCsv,[string]$DpcMetadata,
    [ValidateSet('plan','run','stop','status')][string]$CompetitionAction='plan',
    [ValidateSet('plan','run')][string]$SyntheticAction='plan',
    [ValidateRange(0,16)][int]$SyntheticThreads=0,[ValidateRange(1,120)][int]$SyntheticSeconds=30,
    [ValidateRange(10,90)][int]$SyntheticDuty=50,[ValidateRange(20,1000)][int]$SyntheticCycleMs=100,
    [ValidateRange(1,16)][int]$SyntheticMemoryMiB=4,[ValidateRange(0,30)][int]$SyntheticIdleSeconds=10,[string]$SyntheticReference,
    [switch]$PauseAfterOptimize,[switch]$PauseSearch,[switch]$DeferMaintenance,[ValidateRange(1,240)][int]$SessionMinutes=120
)
$ErrorActionPreference='Stop'
$script:BnqqRoot=$PSScriptRoot
foreach($file in @('Core','PowerPlan','AppLite','Cleanup','Startup','ConsoleUI','Governance','Readiness','Diagnostics','DriverAudit','DpcAnalysis','PlatformAudit','Topology','Optimize','NetworkAudit','Apps','RuntimeLatency','Watcher','HeavyQA','SyntheticBench','FrameBench','EffectiveBench','GameProfile','ValorantProfile','Cs2Engine','FramePacing','GameSession','CpuSession','ProcessSampling','BackgroundBudget','StorageMemory','Maintenance','FocusSession','CompetitionSession','CompetitiveStart','NicPolicy','GpuDriver','NetworkSession','LegacyMigration','RecoveryHub')){
    . (Join-Path $script:BnqqRoot ('lib\'+$file+'.ps1'))
}
$menuPause=$false;$menuError=$false
try {
    if($Command -eq 'menu' -and $DryRun){Write-Host 'DryRun: menu sem interacao ou alteracoes. Selecione um comando explicito para ver seu plano.';return}
    if($Command -eq 'menu'){
        Show-BnqqConsoleMenu -Version '2.6.1' -Edition 'PUBLIC'
        if([Environment]::UserInteractive){
            $choice=Read-Host 'Escolha'
            $menuPause=$choice -match '^(?:[1-9]|[12][0-9]|3[0-5]|0|O)$'
            switch($choice){{ $_ -in @('0','O') }{Invoke-BnqqQuickOptimizer;return}'1'{$Command='audit'}'2'{$Command='network'}'3'{$Command='display'}'4'{$Command='apps'}'5'{Show-BnqqCompetitiveMenu;return}'6'{Show-BnqqFramePacingMenu;return}'7'{Show-BnqqSessionMenu;return}'8'{Show-BnqqRecoveryMenu;return}'9'{Show-BnqqLegacyMigrationMenu;return}'10'{Show-BnqqNetworkSessionMenu;return}'11'{Show-BnqqCpuSessionMenu;return}'12'{Show-BnqqGpuMenu;return}'13'{Show-BnqqStorageMenu;return}'14'{Show-BnqqNicMenu;return}'15'{Show-BnqqFocusMenu;return}'16'{$Command='drivers'}'17'{$Command='compete'}'18'{$Command='synthetic'}'19'{$Command='readiness'}'20'{$Command='timers'}'21'{$Command='usb-topology'}'22'{$Command='security'}'23'{$Command='dpc'}'24'{$Command='help'}'25'{Show-BnqqStartupMenu;return}'26'{Show-BnqqCs2EngineMenu;return}'27'{Show-BnqqValorantProfileMenu;return}'28'{Show-BnqqCleanupMenu;return}'29'{Show-BnqqCompetitiveStartMenu;return}'30'{Show-BnqqAppLiteMenu;return}'31'{Show-BnqqPowerPlanMenu;return}'32'{Write-Host 'Pausa temporaria do Windows Search. No Focus, escolha SIM para parar o indexador durante o jogo.';Show-BnqqFocusMenu;return}'33'{Set-BnqqOptionalServices -Restore;return}'34'{Set-BnqqPointerAcceleration -Restore;return}'35'{Set-BnqqWidgetsPolicy -Restore;return}default{return}}
        }else{$Command='audit'}
    }
    if($DryRun -and $Command -in @('restore','heavyqa','watch')){
        [pscustomobject]@{DryRun=$true;Command=$Command;WatcherAction=$WatcherAction;BackupFile=$BackupFile;PinPhysical=[bool]$PinPhysical;AboveNormal=[bool]$AboveNormal;HeavyMinutes=$HeavyMinutes;Action='Preview only: no worker, process, journal or target changed'} | Format-List
        return
    }
    if ($Command -eq 'optimize') {
        if ($DryRun) {
            Write-Host 'DryRun: energia, navegadores, apps opcionais, Recall, ponteiro, Widgets, servicos e armazenamento.'
            return
        }
        if (-not (Test-BnqqAdmin)) { throw 'Abra o BNQQ como administrador.' }
        $failures = Invoke-BnqqQuickOptimizer -ReturnFailureCount
        if ($PauseAfterOptimize) { [void](Read-Host 'Pressione Enter para voltar') }
        if ($failures -gt 0) { exit 1 }
        return
    }
    switch($Command){
        'start-competitive' {if($DryRun){$StartAction='plan'};Invoke-BnqqCompetitiveStart -Action $StartAction -Game $FrameProcess -KeepApps $KeepApps -Policy $StartPolicy -BackgroundCores $BackgroundCores -LaunchGame:$LaunchGame -MaxMinutes $SessionMinutes | ConvertTo-Json -Depth 10}
        'app-lite' {if($DryRun){$LiteAction='plan'};Invoke-BnqqAppLite -Action $LiteAction -Apps $LiteApps -BackupFile $BackupFile | ConvertTo-Json -Depth 8}
        'cleanup' {if($DryRun){$CleanupAction='plan'};Invoke-BnqqCleanup -Action $CleanupAction -MinimumAgeDays $CleanupAgeDays -EmptyRecycleBin:$EmptyRecycleBin | ConvertTo-Json -Depth 8}
        'valorant' {if($DryRun){$ValorantAction='plan'};Invoke-BnqqValorantProfile -Action $ValorantAction -ProfilePath $ValorantProfilePath -AllProfiles:$AllValorantProfiles -BackupFile $BackupFile | ConvertTo-Json -Depth 8}
        'cs2-engine' {if($DryRun){$EngineAction='plan'};Invoke-BnqqCs2Engine -Action $EngineAction -Mode $EngineMode -BufferTicks $EngineBufferTicks -Directory $GameConfigDirectory -GameCfgDirectory $GameCfgDirectory -SteamExe $SteamExe -BackupFile $BackupFile | ConvertTo-Json -Depth 8}
        'startup' {if($DryRun){$StartupAction='plan'};Invoke-BnqqStartup -Action $StartupAction -Apps $StartupApps -File $BackupFile | ConvertTo-Json -Depth 8}
        'menu-preview' {Show-BnqqConsoleMenu -Version '2.6.1' -Edition 'PUBLIC'}
        'audit' {Get-BnqqHardware | ConvertTo-Json -Depth 5}
        'scan' {Get-BnqqHardware | ConvertTo-Json -Depth 5}
        'report' {Get-BnqqHardware | ConvertTo-Json -Depth 5}
        'network' {Get-BnqqNetworkAudit | ConvertTo-Json -Depth 5}
        'display' {Show-BnqqDisplayGuidance}
        'apps' {if($CleanLegacyFlags){Repair-BnqqChromiumFlags -DryRun:$DryRun}else{Get-BnqqChromiumAudit | Format-List}}
        'topology' {Get-BnqqTopology | Format-Table Group,Mask,EfficiencyClass}
        'verdict' {Write-Host 'Nenhum tweak e declarado efetivo sem baseline comparativo. Veja docs/MODULES.md.'}
        'status' {
            $whea=Get-BnqqWheaEvents
            [pscustomobject]@{WheaCount=@($whea.Events).Count;WheaError=$whea.Error;Certificate=(Get-BnqqLatestHeavyQa);DataRoot=(Get-BnqqDataRoot);LegacyTasks=@(Get-ScheduledTask -TaskName 'BNQQ*' -ErrorAction SilentlyContinue | Select-Object TaskName,State)} | ConvertTo-Json -Depth 6
        }
        'apply' {Invoke-BnqqApply -Profile $Profile -DryRun:$DryRun -ForceDeepIdleDisable:$ForceDeepIdleDisable}
        'latency' {
            Show-BnqqDisplayGuidance
            if($LatencyAction -eq 'apply'){Invoke-BnqqApply -Profile latency -DryRun:$DryRun -ForceDeepIdleDisable:$ForceDeepIdleDisable}
        }
        'restore' {
            if(-not $BackupFile){throw 'Informe -BackupFile com journal v2. Sem reset para defaults presumidos.'}
            if(-not (Test-BnqqAdmin)){throw 'Restauracao exige administrador'}
            $lock=Enter-BnqqStateLock
            try{Restore-BnqqJournal $BackupFile | ConvertTo-Json -Depth 8}finally{$lock.Dispose()}
        }
        'legacy' {if($DryRun){$LegacyAction='plan'};Invoke-BnqqLegacyMigration -Action $LegacyAction -Files $LegacyFiles -BackupFile $BackupFile | ConvertTo-Json -Depth 9}
        'compete' {
            if($DryRun){$CompetitionAction='plan'}
            Invoke-BnqqCompetitionSession -Action $CompetitionAction -Apps $SessionApps -UploadApps $NetworkApps -UploadKbps $UploadKbps -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance -Game $FrameProcess -MaxMinutes $SessionMinutes|ConvertTo-Json -Depth 12
        }
        'synthetic' {
            if($DryRun){$SyntheticAction='plan'}
            Invoke-BnqqSyntheticBench -Action $SyntheticAction -Threads $SyntheticThreads -Seconds $SyntheticSeconds -DutyPercent $SyntheticDuty -CycleMs $SyntheticCycleMs -MemoryMiB $SyntheticMemoryMiB -IdleTailSeconds $SyntheticIdleSeconds -ReferenceFile $SyntheticReference|ConvertTo-Json -Depth 9
        }
        'timers' {Get-BnqqTimerAudit|ConvertTo-Json -Depth 7}
        'usb-topology' {Get-BnqqUsbTopologyAudit|ConvertTo-Json -Depth 9}
        'security' {Get-BnqqSecurityAudit|ConvertTo-Json -Depth 5}
        'drivers' {
            if($DryRun){[pscustomobject]@{Status='Preview';Action='Read-only CIM inventory; no driver/IRQ changes'}|ConvertTo-Json}
            else{Get-BnqqDriverAudit|ConvertTo-Json -Depth 9}
        }
        'dpc' {
            if($DryRun -or (-not $DpcCsv -and -not $DpcMetadata)){Get-BnqqDpcImportContract|ConvertTo-Json -Depth 5}
            elseif(-not $DpcCsv -or -not $DpcMetadata){throw 'Informe -DpcCsv e -DpcMetadata juntos; nao inicia captura'}
            else{Get-BnqqDpcReport -Csv $DpcCsv -Metadata $DpcMetadata|ConvertTo-Json -Depth 9}
        }
        'memory' {Get-BnqqMemoryReport | ConvertTo-Json -Depth 5}
        'nvme' {if($DryRun){$NvmeAction='plan'};Invoke-BnqqNvmePolicy -Action $NvmeAction -File $BackupFile | ConvertTo-Json -Depth 9}
        'readiness' {Get-BnqqReadiness | ConvertTo-Json -Depth 8}
        'focus' {if($DryRun){$FocusAction='plan'};Invoke-BnqqFocusSession -Action $FocusAction -Apps $SessionApps -BackgroundCores $BackgroundCores -Game $FrameProcess -PauseSearch:$PauseSearch -DeferMaintenance:$DeferMaintenance -MaxMinutes $SessionMinutes -Policy $FocusPolicy -UploadApps $NetworkApps -UploadKbps $UploadKbps | ConvertTo-Json -Depth 10}
        'nic' {if($DryRun){$NicAction='plan'};Invoke-BnqqNicPolicy -Action $NicAction -Name $AdapterName -File $BackupFile | ConvertTo-Json -Depth 9}
        'gpu' {if($DryRun){$GpuAction='plan'};Invoke-BnqqGpuProfile -Action $GpuAction -Game $FrameProcess -GameExecutable $GameExecutable -File $BackupFile | ConvertTo-Json -Depth 10}
        'gpu-cache' {Get-BnqqShaderCacheAudit | ConvertTo-Json -Depth 5}
        'cpu-session' {if($DryRun){$CpuAction='plan'};Invoke-BnqqCpuSession -Action $CpuAction -Apps $SessionApps -BackgroundCores $BackgroundCores -UnparkCpu:$UnparkCpu -Game $FrameProcess -File $BackupFile | ConvertTo-Json -Depth 12}
        'phase-health' {Get-BnqqPhaseHealth -Since (Get-Date).AddHours(-72) | ConvertTo-Json -Depth 5}
        'net-session' {if($DryRun){$NetworkAction='plan'};Invoke-BnqqNetworkSession -Action $NetworkAction -Apps $NetworkApps -UploadKbps $UploadKbps -Game $FrameProcess -File $BackupFile | ConvertTo-Json -Depth 9}
        'session' {if($DryRun){$SessionAction='plan'};Invoke-BnqqGameSession -Action $SessionAction -Apps $SessionApps -Game $FrameProcess -File $BackupFile | ConvertTo-Json -Depth 8}
        'recover' {if($DryRun -or -not $BackupFile){Get-BnqqRecoveryCatalog | ConvertTo-Json -Depth 4}else{Invoke-BnqqRecovery $BackupFile | ConvertTo-Json -Depth 8}}
        'framepacing' {if($DryRun){$CompetitiveAction='plan'};Invoke-BnqqFramePacing -Directory $GameConfigDirectory -Action $CompetitiveAction -GameCap $GameCap -MenuCap $MenuCap -BackupFile $BackupFile | ConvertTo-Json -Depth 6}
        'competitive' {if($DryRun){$CompetitiveAction='plan'};Invoke-BnqqGameProfile -Directory $GameConfigDirectory -Action $CompetitiveAction -Msaa $Msaa -BackupFile $BackupFile | ConvertTo-Json -Depth 6}
        'heavyqa' {Test-BnqqHeavyQA -Minutes $HeavyMinutes -Threads $HeavyThreads | ConvertTo-Json -Depth 6}
        'watch' {
            switch($WatcherAction){
                'run' {Start-BnqqWatcher -PinPhysical:$PinPhysical -AboveNormal:$AboveNormal -ObserveWmi:$ObserveWmi -Once:$Once}
                'stop' {Stop-BnqqWatcher}
                'status' { $path=Join-Path (Get-BnqqDataRoot) 'watcher.json';if(Test-Path $path){Get-Content $path -Raw}else{Write-Host 'Sem heartbeat v2; tarefas legadas nao foram alteradas.'} }
            }
        }
        'framebench' {
            if($Effective -and $GpuTelemetry){throw 'Use novas capturas baseline/candidate com a mesma instrumentacao; Effective legado nao recebe telemetria GPU'};if($Effective){Invoke-BnqqEffectiveBench -BaselineFile $BaselineFile -PrepareCleanState:$PrepareCleanState -DryRun:$DryRun -Seconds $FrameSeconds -SwapChain $SwapChain -PresentMonPath $PresentMonPath | ConvertTo-Json -Depth 12;break}
            if(-not $Scenario -or -not $SettingsHash -or -not $ExperimentId){throw 'Informe -Scenario, -SettingsHash e -ExperimentId para captura controlada'}
            Invoke-BnqqFrameBench -Seconds $FrameSeconds -ProcessName $FrameProcess -SkipSeconds $FrameSkip -Hotkey $FrameHotkey -Scenario $Scenario -SettingsHash $SettingsHash -ExperimentId $ExperimentId -Variant $Variant -SwapChain $SwapChain -PresentMonPath $PresentMonPath -GpuTelemetry:$GpuTelemetry | ConvertTo-Json -Depth 8
        }
        'compare' {if(-not $CaptureFiles){throw 'Informe -CaptureFiles com 3+3 rodadas'};Compare-BnqqFrameBench -Files $CaptureFiles | ConvertTo-Json -Depth 5}
        'help' {
            Write-Host @'
BNQQ 2.6.1 — Windows PowerShell 5.1 x64
audit | network | display | topology | apps | status | verdict | framepacing | session | memory | nvme | nic | readiness | focus | gpu | gpu-cache | cpu-session | phase-health | net-session | recover | legacy | competitive
apply -Profile recording-off -DryRun             revisao, sem alteracoes
valorant -ValorantAction plan|apply|restore [-AllValorantProfiles] [-ValorantProfilePath ARQUIVO] [-BackupFile JOURNAL]
cs2-engine -EngineAction plan|apply|restore -EngineMode CompetitiveLow|Minimum [-BackupFile JOURNAL]
start-competitive -StartAction plan|run|stop|status [-FrameProcess cs2.exe] [-LaunchGame] [-KeepApps Discord,Spotify]
app-lite -LiteAction plan|apply|restore [-LiteApps Edge,Chrome] [-BackupFile JOURNAL]
cleanup -CleanupAction plan|apply [-CleanupAgeDays 2] [-EmptyRecycleBin]
startup -StartupAction apply -StartupApps RobloxPlayerBeta
startup -StartupAction restore -BackupFile arquivo.json
heavyqa -HeavyMinutes 10                        carga explicita; nao certifica hardware
apply -Profile recording-off                    exige QA e journal sem pendencias
latency -LatencyAction apply -ForceDeepIdleDisable -DryRun
restore -BackupFile CAMINHO                     estado anterior capturado, sem defaults
watch -WatcherAction run [-Once]                somente observacao
watch -WatcherAction run -AboveNormal [-PinPhysical] [-ObserveWmi]
watch -WatcherAction stop                       saida cooperativa
framebench -Scenario MAPA_CENA -SettingsHash HASH -ExperimentId ID -Variant baseline
framebench -Effective -BaselineFile result.json -PrepareCleanState [-DryRun]
compare -CaptureFiles A1.json,B1.json,A2.json,B2.json,A3.json,B3.json
competitive -GameConfigDirectory PASTA_CFG -CompetitiveAction plan|apply|restore [-Msaa 2] [-BackupFile JOURNAL]
net-session -NetworkAction plan|run|restore -NetworkApps OneDrive.exe [-UploadKbps 512] [-BackupFile JOURNAL]
cpu-session -CpuAction plan|run|restore -SessionApps msedge [-BackgroundCores 2] [-UnparkCpu] [-BackupFile JOURNAL]
gpu -GpuAction status|plan|apply|restore [-FrameProcess cs2.exe] [-GameExecutable CAMINHO] [-BackupFile JOURNAL]
gpu-cache | framebench ... -GpuTelemetry
compete -CompetitionAction plan|run|stop|status [-SessionApps msedge,chrome,firefox,OneDrive] [-NetworkApps OneDrive.exe] [-UploadKbps 512]
synthetic -SyntheticAction plan|run [-SyntheticThreads 4] [-SyntheticSeconds 30] [-SyntheticDuty 50] [-SyntheticReference result.json]
timers | usb-topology | security (read-only)
drivers [-DryRun] | dpc [-DpcCsv EVENTOS.csv -DpcMetadata METADATA.json] [-DryRun]
memory | nvme -NvmeAction plan|apply|restore [-BackupFile JOURNAL]
focus -FocusAction plan|run|stop|status [-FocusPolicy Priority|CpuSets] [-SessionApps msedge,chrome,OneDrive] [-PauseSearch] [-DeferMaintenance]
nic -NicAction plan|stage|restore|activate|restore-active [-AdapterName NOME] [-BackupFile JOURNAL]
Pacotes legados (pro/god/ultimate/etc.) foram retirados. Veja docs/MIGRATION.md.
'@
        }
        default {throw ('Comando retirado ou desconhecido: '+$Command+'. Execute help e veja docs/MIGRATION.md; nenhum tweak legado foi aplicado.')}
    }
}catch{$menuError=$true;Write-Error $_ -ErrorAction Continue;exit 1}
finally{if($menuPause -and -not $menuError){[void](Read-Host 'Pressione Enter para fechar')}}
