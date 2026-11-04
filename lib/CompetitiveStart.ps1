# One-click preparation reuses the bounded, journalled focus controller.
function Get-BnqqCompetitiveProcesses {Get-Process -ErrorAction Stop}
function Write-BnqqCompetitiveStopSignal {
 Write-BnqqAtomicJson @{Schema='BNQQ.CompetitiveStop.1';Owner=(Get-BnqqOwner);Requested=[datetime]::UtcNow.ToString('o')} (Join-Path (Get-BnqqDataRoot) 'competitive-start-stop.json')
}
function Assert-BnqqCompetitiveNotCancelled {
 if(-not $script:BnqqCompetitiveRequestedUtc){return}
 $file=Join-Path (Get-BnqqDataRoot) 'competitive-start-stop.json'
 if(-not (Test-Path -LiteralPath $file)){return}
 if((Get-Item -LiteralPath $file).Length -gt 4096){throw 'Sinal de parada invalido'}
 $s=Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop|ConvertFrom-Json
 if($s.Schema -cne 'BNQQ.CompetitiveStop.1' -or $s.Owner -cne (Get-BnqqOwner)){throw 'Sinal de parada de outro usuario/invalido'}
 if(([datetime]$s.Requested).ToUniversalTime() -ge $script:BnqqCompetitiveRequestedUtc){throw 'Preparacao cancelada cooperativamente'}
}
function Get-BnqqOtherOptimizers {
 @(Get-Process -Name 'PRACC Performance',exmtweaksservice,ProcessGovernor,ProcessLasso -ErrorAction SilentlyContinue|Select-Object ProcessName,Id)
}
function Assert-BnqqNoOtherOptimizer {
 $other=@(Get-BnqqOtherOptimizers)
 if($other.Count){throw ('Outro controlador detectado; saia pelo proprio aplicativo, sem matar servicos: '+(($other.ProcessName|Sort-Object -Unique)-join ', '))}
}
function Get-BnqqCompetitiveLaunch {
 param([ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game)
 if($Game -eq 'cs2.exe'){
  $root=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
  if(-not $root){throw 'Steam nao localizado'}
  $file=Join-Path $root 'steam.exe';$arguments=@('-applaunch','730');$publisher='Valve'
 }else{
  $file=$null;$meta=Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
  if(Test-Path -LiteralPath $meta){if((Get-Item $meta).Length -gt 1048576){throw 'Metadados Riot grandes demais'};$data=Get-Content -LiteralPath $meta -Raw -ErrorAction Stop|ConvertFrom-Json;$file=[string]$data.rc_default}
  if(-not $file){$file='C:\Riot Games\Riot Client\RiotClientServices.exe'}
  $arguments=@('--launch-product=valorant','--launch-patchline=live');$publisher='Riot Games'
 }
 if(-not [IO.Path]::IsPathRooted($file) -or $file.StartsWith('\\')){throw 'Launcher local exigido'}
 $file=[IO.Path]::GetFullPath($file);$expected=if($Game -eq 'cs2.exe'){'steam.exe'}else{'RiotClientServices.exe'}
 if([IO.Path]::GetFileName($file) -ine $expected -or -not [IO.File]::Exists($file) -or ((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Launcher nao reconhecido'}
 $sig=Get-AuthenticodeSignature -LiteralPath $file -ErrorAction Stop
 if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($publisher)){throw 'Assinatura do launcher nao validada'}
 [pscustomobject]@{File=$file;Arguments=$arguments;Publisher=$publisher}
}
function Start-BnqqCompetitiveGame {
 param([ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game)
 $launch=Get-BnqqCompetitiveLaunch $Game
 # Explicit interactive game launch, not a hidden optimizer or anti-cheat bypass.
 Start-Process -FilePath $launch.File -ArgumentList $launch.Arguments -WindowStyle Normal -ErrorAction Stop|Out-Null
}
function Get-BnqqCompetitiveStartPlan {
 param([ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string[]]$KeepApps=@('Discord','Spotify'),[ValidateSet('Priority','CpuSets')][string]$Policy='Priority',[int]$BackgroundCores=2)
 foreach($app in @($KeepApps)){if($app -notmatch '^[a-zA-Z0-9 _.\-]{1,80}$'){throw 'Nome de app a preservar invalido'}}
 $keep=@(@('Discord','DiscordSystemHelper','discord_clips','Spotify','explorer','msedgewebview2')+@($KeepApps)|Sort-Object -Unique)
 $apps=@(Get-BnqqBudgetAllowedApps|Where-Object {$_ -notin $keep})
 $processes=@(Get-BnqqCompetitiveProcesses);$games=@($processes|Where-Object ProcessName -ieq ([IO.Path]::GetFileNameWithoutExtension($Game)))
 if($games.Count -gt 1){throw 'Multiplas instancias do jogo; selecao ambigua'}
 $present=@($processes|Where-Object {$_.ProcessName -in $apps}|Select-Object ProcessName,Id)
 $other=@(Get-BnqqOtherOptimizers);$ready=Get-BnqqReadiness;$reasons=@()
 if($other.Count){$reasons+='OtherOptimizerRunning'}
 if(-not $ready.WorkloadReady){$reasons+='HeavyQaOrHardwareNotReady'}
 if(Get-BnqqFocusStatus){$reasons+='BnqqControllerAlreadyRunning'}
 if(-not $apps.Count){$reasons+='NoBackgroundTargetsSelected'}
 $focus=Get-BnqqFocusPlan -Apps $apps -Policy $Policy -BackgroundCores $BackgroundCores
 [pscustomobject]@{Schema='BNQQ.CompetitiveStart.1';Status='Preview';Game=$Game;GameAlreadyOpen=($games.Count -eq 1);Apps=$apps;KeepApps=$keep;PresentParticipants=$present;Policy=$Policy;Focus=$focus;OtherOptimizers=$other;Readiness=$ready;CanRun=($reasons.Count -eq 0 -and $apps.Count -gt 0);BlockedReasons=$reasons;EndsProcesses=$false;ChangesGameAffinity=$false;TouchesAntiCheat=$false;PurgesMemory=$false;FpsGainProven=$false;InputLatencyMeasured=$false;Note='Only selected browser/OneDrive work gets a temporary background policy. Discord/music/shell/WebView stay untouched. No physical-core odd/even mask.'}
}
function Invoke-BnqqCompetitiveStart {
 param([ValidateSet('plan','run','stop','status')][string]$Action='plan',[ValidateSet('cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='cs2.exe',[string[]]$KeepApps=@('Discord','Spotify'),[ValidateSet('Priority','CpuSets')][string]$Policy='Priority',[ValidateRange(1,16)][int]$BackgroundCores=2,[switch]$LaunchGame,[ValidateRange(1,240)][int]$MaxMinutes=120)
 if($Action -eq 'stop'){Write-BnqqCompetitiveStopSignal;return (Stop-BnqqFocusSession)}
 if($Action -eq 'status'){return (Get-BnqqFocusStatus)}
 if($Action -eq 'run'){$script:BnqqCompetitiveRequestedUtc=[datetime]::UtcNow}
 $plan=Get-BnqqCompetitiveStartPlan -Game $Game -KeepApps $KeepApps -Policy $Policy -BackgroundCores $BackgroundCores
 if($Action -eq 'plan'){return $plan}
 if(-not $plan.CanRun){throw ('Preparacao bloqueada: '+($plan.BlockedReasons -join ', ')+'. Veja a previa; nenhum processo sera encerrado para contornar isso.')}
 Assert-BnqqNoOtherOptimizer;Assert-BnqqHeavyQa -WorkloadOnly;Assert-BnqqCompetitiveNotCancelled
 if(-not $plan.GameAlreadyOpen){
  if(-not $LaunchGame){throw 'Abra o jogo normalmente ou selecione LaunchGame explicitamente'}
  Start-BnqqCompetitiveGame $Game;$clock=[Diagnostics.Stopwatch]::StartNew()
  while(-not @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Game)) -ErrorAction SilentlyContinue).Count){
   Assert-BnqqCompetitiveNotCancelled
   if($clock.Elapsed.TotalSeconds -ge 120){throw 'Jogo nao apareceu em 120s; nenhuma politica de processo aplicada'}
   Start-Sleep -Seconds 1
  }
 }
 Assert-BnqqNoOtherOptimizer;Assert-BnqqCompetitiveNotCancelled
 # Existing engine restores on Alt+Tab, game exit, health failure, cooperative stop or timeout.
 Invoke-BnqqFocusSession -Action run -Apps $plan.Apps -Policy $Policy -BackgroundCores $BackgroundCores -Game $Game -MaxMinutes $MaxMinutes -SessionGuard {Assert-BnqqNoOtherOptimizer;Assert-BnqqCompetitiveNotCancelled}
}
function Show-BnqqCompetitiveStartMenu {
 $selection=Read-Host 'Start Competitivo: 1=CS2, 2=Valorant; outro cancela'
 if($selection -notin @('1','2')){return};$game=if($selection -eq '1'){'cs2.exe'}else{'VALORANT-Win64-Shipping.exe'}
 $plan=Invoke-BnqqCompetitiveStart -Game $game
 $plan|Select-Object Game,GameAlreadyOpen,Apps,KeepApps,Policy,CanRun,BlockedReasons,OtherOptimizers|Format-List
 Write-Host 'Mantem Discord/musica/Explorer. Restauracao no Alt+Tab/saida. Nao garante ganho de FPS ou latencia.'
 if(-not $plan.CanRun){Write-Host 'Preparacao bloqueada pelos motivos acima; nao inicia benchmark ou mata outro otimizador.';return}
 if((Read-Host 'Iniciar ou usar jogo aberto e controlar background? Digite INICIAR') -ceq 'INICIAR'){Invoke-BnqqCompetitiveStart -Action run -Game $game -LaunchGame|Format-List}
}
