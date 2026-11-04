# Interactive front end only. All resource writes remain in the tested Focus controller.
function Get-BnqqCompetitiveConsoleKey {
 try{if(-not [Console]::IsInputRedirected -and [Console]::KeyAvailable){return [Console]::ReadKey($true).Key.ToString()}}catch{}
 return $null
}
function Test-BnqqCompetitiveConsoleStop {return ((Get-BnqqCompetitiveConsoleKey) -in @('Q','Escape'))}
function Write-BnqqCompetitiveConsoleState {
 param($State)
 $key=$State.Phase+'|'+$State.TrackedParticipants+'|'+$State.Changes
 if($script:BnqqCompetitiveLastDisplay -ceq $key){return};$script:BnqqCompetitiveLastDisplay=$key
 if($State.Phase -eq 'Desktop'){Write-Host '  PAUSADO: jogo sem foco; ajustes do periodo restaurados. Q encerra a sessao.' -ForegroundColor Yellow}
 elseif($State.TrackedParticipants -gt 0){Write-Host ('  EM FOCO | participantes registrados: '+$State.TrackedParticipants+' | alteracoes acumuladas: '+$State.Changes) -ForegroundColor Cyan}
 else{Write-Host '  EM FOCO: aguardando trabalho concorrente elegivel; nenhuma alteracao neste periodo.' -ForegroundColor Gray}
}
function Read-BnqqCompetitiveGameChoice {Read-Host '1 = VALORANT | 2 = CS2 | Q = sair'}
function Wait-BnqqCompetitiveConsoleExit {Read-Host 'Enter para fechar'|Out-Null}
function Show-BnqqCompetitiveConsole {
 param([ValidateSet('','cs2.exe','VALORANT-Win64-Shipping.exe')][string]$Game='',[string[]]$KeepApps=@('Discord','Spotify'),[ValidateRange(1,240)][int]$MaxMinutes=240,[switch]$DryRun)
 $active=@(Get-BnqqCompetitiveProcesses|Where-Object ProcessName -in @('cs2','VALORANT-Win64-Shipping')|Select-Object -ExpandProperty ProcessName -Unique)
 if(-not $Game -and $active.Count -eq 1){$Game=$active[0]+'.exe'}
 if($DryRun){
  if(-not $Game){return [pscustomobject]@{Status='SelectGame';Choices=@('VALORANT','CS2');WouldLaunch=$false;WouldModify=$false}}
  return (Invoke-BnqqCompetitiveStart -Game $Game -KeepApps $KeepApps)
 }
 try{[Console]::Title='BNQQ Competitive v2.6.0'}catch{}
 Write-Host '';Write-Host '  BNQQ  COMPETITIVE' -ForegroundColor Cyan
 Write-Host '  Sessao temporaria para CS2 / VALORANT' -ForegroundColor Gray
 Write-Host '  Q ou Esc neste console: parar e restaurar. O jogo continua aberto.'
 Write-Host '  Alt+Tab pausa os ajustes; voltar ao jogo retoma a observacao.'
 Write-Host '  Discord, musica, Explorer e anti-cheat preservados.'
 Write-Host ''
 if(-not $Game){
  switch(Read-BnqqCompetitiveGameChoice){'1'{$Game='VALORANT-Win64-Shipping.exe'}'2'{$Game='cs2.exe'}default{return}}
 }
 $script:BnqqCompetitiveLastDisplay=$null
 try{
  $plan=Invoke-BnqqCompetitiveStart -Game $Game -KeepApps $KeepApps
  Write-Host ('  Jogo: '+$Game+' | limite da sessao: '+$MaxMinutes+' minutos')
  if(-not $plan.CanRun){
   Write-Host ('  BLOQUEADO: '+($plan.BlockedReasons -join ', ')) -ForegroundColor Yellow
   if($plan.OtherOptimizers.Count){Write-Host ('  Outros controladores: '+(($plan.OtherOptimizers.ProcessName|Sort-Object -Unique)-join ', '))}
   Write-Host '  Confira o menu de prontidao no Optimizer. Nenhum teste de estresse sera iniciado aqui.'
   Wait-BnqqCompetitiveConsoleExit;return
  }
  Write-Host ('  Background elegivel: '+($plan.Apps -join ', '))
  Write-Host '  Apenas apps com atividade medida recebem ajuste. Sem promessa de FPS/latencia.'
  if($plan.GameAlreadyOpen){Write-Host '  Usando o jogo aberto. Volte para ele para iniciar o periodo de foco.'}else{Write-Host '  Abrindo pelo cliente oficial; Q cancela a espera.'}
  $result=Invoke-BnqqCompetitiveStart -Action run -Game $Game -KeepApps $KeepApps -LaunchGame -MaxMinutes $MaxMinutes -StopRequested {Test-BnqqCompetitiveConsoleStop} -SessionObserver {param($state);Write-BnqqCompetitiveConsoleState $state}
  $file=Join-Path (Get-BnqqDataRoot) ('competitive-reports\'+[guid]::NewGuid().ToString('N')+'.json')
  Write-BnqqAtomicJson ([pscustomobject]@{Schema='BNQQ.CompetitiveReport.1';Owner=(Get-BnqqOwner);Generated=[datetime]::UtcNow.ToString('o');Game=$Game;Result=$result;FpsGainMeasured=$false}) $file
  Write-Host '';Write-Host '  SESSAO ENCERRADA: ajustes restaurados pelo controlador.' -ForegroundColor Green
  Write-Host ('  Relatorio: '+$file)
 }catch{
  Write-Host ('  '+$_.Exception.Message) -ForegroundColor Red
  Write-Host '  Se houver recuperacao pendente, consulte os backups no BNQQ Optimizer.'
 }
 Wait-BnqqCompetitiveConsoleExit
}
