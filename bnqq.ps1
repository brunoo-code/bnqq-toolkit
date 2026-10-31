#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command='menu',
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
    [ValidateSet('plan','run','restore')][string]$SessionAction='plan',[string[]]$SessionApps
)
$ErrorActionPreference='Stop'
$script:BnqqRoot=$PSScriptRoot
foreach($file in @('Core','Governance','Diagnostics','Topology','Optimize','NetworkAudit','Apps','RuntimeLatency','Watcher','HeavyQA','FrameBench','EffectiveBench','GameProfile','FramePacing','GameSession','RecoveryHub')){
    . (Join-Path $script:BnqqRoot ('lib\'+$file+'.ps1'))
}
try {
    if($Command -eq 'menu'){
        Write-Host 'BNQQ 1.8.5 | diagnostico e experimentos reversiveis | sem ganho presumido'
        if([Environment]::UserInteractive){
            Write-Host '[1] Diagnostico [2] Rede [3] Display [4] Atalhos Chromium [5] Perfil competitivo CS2 [6] Limitar FPS do menu [7] Sessao de jogo [8] Recuperacao [0] Sair'
            switch(Read-Host 'Opcao'){'1'{$Command='audit'}'2'{$Command='network'}'3'{$Command='display'}'4'{$Command='apps'}'5'{Show-BnqqCompetitiveMenu;return}'6'{Invoke-BnqqFramePacing -Action plan | Format-List;if((Read-Host 'Limitar menu a 120 FPS e preservar partida? Digite SIM') -ceq 'SIM'){Invoke-BnqqFramePacing -Action apply | Format-List};return}'7'{Show-BnqqSessionMenu;return}'8'{Show-BnqqRecoveryMenu;return}default{return}}
        }else{$Command='audit'}
    }
    if($DryRun -and $Command -in @('restore','heavyqa','watch')){
        [pscustomobject]@{DryRun=$true;Command=$Command;WatcherAction=$WatcherAction;BackupFile=$BackupFile;PinPhysical=[bool]$PinPhysical;AboveNormal=[bool]$AboveNormal;HeavyMinutes=$HeavyMinutes;Action='Preview only: no worker, process, journal or target changed'} | Format-List
        return
    }
    switch($Command){
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
            if($Effective){Invoke-BnqqEffectiveBench -BaselineFile $BaselineFile -PrepareCleanState:$PrepareCleanState -DryRun:$DryRun -Seconds $FrameSeconds -SwapChain $SwapChain -PresentMonPath $PresentMonPath | ConvertTo-Json -Depth 12;break}
            if(-not $Scenario -or -not $SettingsHash -or -not $ExperimentId){throw 'Informe -Scenario, -SettingsHash e -ExperimentId para captura controlada'}
            Invoke-BnqqFrameBench -Seconds $FrameSeconds -ProcessName $FrameProcess -SkipSeconds $FrameSkip -Hotkey $FrameHotkey -Scenario $Scenario -SettingsHash $SettingsHash -ExperimentId $ExperimentId -Variant $Variant -SwapChain $SwapChain -PresentMonPath $PresentMonPath | ConvertTo-Json -Depth 8
        }
        'compare' {if(-not $CaptureFiles){throw 'Informe -CaptureFiles com 3+3 rodadas'};Compare-BnqqFrameBench -Files $CaptureFiles | ConvertTo-Json -Depth 5}
        'help' {
            Write-Host @'
BNQQ 1.8.5 — Windows PowerShell 5.1 x64
audit | network | display | topology | apps | status | verdict | framepacing | session | recover | competitive
apply -Profile recording-off -DryRun             revisao, sem alteracoes
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
Pacotes legados (pro/god/ultimate/etc.) foram retirados. Veja docs/MIGRATION.md.
'@
        }
        default {throw ('Comando retirado ou desconhecido: '+$Command+'. Execute help e veja docs/MIGRATION.md; nenhum tweak legado foi aplicado.')}
    }
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
