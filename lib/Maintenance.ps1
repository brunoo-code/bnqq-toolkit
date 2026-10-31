# Temporary leases: no startup-type changes, no task deletion, no forced stops.
function Get-BnqqMaintenanceTasks {
    @([pscustomobject]@{TaskPath='\Microsoft\Windows\Defrag\';TaskName='ScheduledDefrag'},
      [pscustomobject]@{TaskPath='\Microsoft\Windows\DiskCleanup\';TaskName='SilentCleanup'})
}
function Get-BnqqTextHash {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-BnqqTaskState {
    param($Identity)
    $task=Get-ScheduledTask -TaskPath $Identity.TaskPath -TaskName $Identity.TaskName -ErrorAction Stop
    $xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null
    $xml.LoadXml((Export-ScheduledTask -TaskPath $Identity.TaskPath -TaskName $Identity.TaskName -ErrorAction Stop))
    # Enabled can be absent (default true); remove only that field from the identity hash.
    foreach($node in @($xml.SelectNodes('/*[local-name()="Task"]/*[local-name()="Settings"]/*[local-name()="Enabled"]'))){[void]$node.ParentNode.RemoveChild($node)}
    [pscustomobject]@{TaskPath=$Identity.TaskPath;TaskName=$Identity.TaskName;Enabled=[bool]$task.Settings.Enabled;DefinitionHash=(Get-BnqqTextHash $xml.OuterXml)}
}
function Get-BnqqSearchState {
    if(-not ('Bnqq.SearchService' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\SearchService.cs') -ErrorAction Stop}
    $config=@(Get-CimInstance Win32_Service -Filter "Name='WSearch'" -OperationTimeoutSec 5 -ErrorAction Stop)
    if($config.Count -ne 1){throw 'WSearch indisponivel; nao inferir servico generico'}
    $c=$config[0]
    $identity=[ordered]@{Name=$c.Name;PathName=$c.PathName;StartMode=$c.StartMode;StartName=$c.StartName;DelayedAutoStart=$c.DelayedAutoStart}
    [pscustomobject]@{Name='WSearch';State=[int][Bnqq.SearchService]::State();ConfigurationHash=(Get-BnqqTextHash ($identity|ConvertTo-Json -Compress))}
}
function Assert-BnqqMaintenanceOperation {
    param($Op)
    if($Op.Kind -eq 'ScheduledTask'){
        $allowed=@(Get-BnqqMaintenanceTasks|Where-Object {$_.TaskName -ceq $Op.Before.TaskName -and $_.TaskPath -ceq $Op.Before.TaskPath})
        if($allowed.Count -ne 1 -or $Op.Before.Enabled -isnot [bool] -or -not $Op.Before.Enabled -or $Op.After.Enabled -isnot [bool] -or $Op.After.Enabled){throw 'Transicao/tarefa nao admitida'}
        $copy=$Op.After|Select-Object *;$copy.Enabled=$true
    }elseif($Op.Kind -eq 'Service'){
        if($Op.Before.Name -cne 'WSearch' -or $Op.Before.State -ne 4 -or $Op.After.State -ne 1){throw 'Servico/transicao nao admitido'}
        $copy=$Op.After|Select-Object *;$copy.State=4
    }else{throw 'Tipo de manutencao nao admitido'}
    $hash=if($Op.Kind -eq 'Service'){$Op.Before.ConfigurationHash}else{$Op.Before.DefinitionHash}
    if($hash -cnotmatch '^[0-9A-F]{64}$' -or -not (Test-BnqqSameValue $copy $Op.Before)){throw 'Identidade de manutencao invalida'}
}
function Invoke-BnqqSearchControl {
    param([bool]$Running)
    [Bnqq.SearchService]::SetRunning($Running)
}
function Set-BnqqMaintenanceState {
    param($Op,$State)
    Assert-BnqqMaintenanceOperation $Op
    $live=Get-BnqqOperationState $Op
    if(-not (Test-BnqqSameValue $live $Op.Before) -and -not (Test-BnqqSameValue $live $Op.After) -and -not (Test-BnqqPartialState $Op $live)){throw 'Manutencao alterada externamente'}
    if($Op.Kind -eq 'Service'){Invoke-BnqqSearchControl ($State.State -eq 4);return}
    $task=Get-ScheduledTask -TaskPath $State.TaskPath -TaskName $State.TaskName -ErrorAction Stop
    # Only prevent future launches; never interrupt a task already running.
    if(-not $State.Enabled -and [string]$task.State -eq 'Running'){throw 'Tarefa iniciou; nao interromper execucao'}
    if($State.Enabled){Enable-ScheduledTask -InputObject $task -ErrorAction Stop|Out-Null}
    else{Disable-ScheduledTask -InputObject $task -ErrorAction Stop|Out-Null}
}
function Get-BnqqMaintenancePlan {
    param([switch]$PauseSearch,[switch]$DeferMaintenance)
    $ops=@();$notes=@()
    if($PauseSearch){
        try{
            $before=Get-BnqqSearchState
            $s=Get-Service -Name WSearch -ErrorAction Stop
            try{
                if($before.State -eq 4 -and $s.CanStop -and [string]$s.StartType -in @('Automatic','Manual')){
                    $after=$before|Select-Object *;$after.State=1;$ops+=@([pscustomobject]@{Kind='Service';Before=$before;After=$after})
                }else{$notes+=('WSearch preservado: estado='+$before.State+'; inicio='+$s.StartType)}
            }finally{if($s -is [IDisposable]){$s.Dispose()}}
        }catch{$notes+=('WSearch ignorado: '+$_.Exception.Message)}
    }
    if($DeferMaintenance){
        foreach($id in @(Get-BnqqMaintenanceTasks)){
            try{
                $task=Get-ScheduledTask -TaskPath $id.TaskPath -TaskName $id.TaskName -ErrorAction Stop
                if([string]$task.State -eq 'Running' -or $task.Settings.RunOnlyIfIdle){$notes+=($id.TaskName+': ja ociosa/em execucao; preservada');continue}
                $before=Get-BnqqTaskState $id
                if($before.Enabled){$after=$before|Select-Object *;$after.Enabled=$false;$ops+=@([pscustomobject]@{Kind='ScheduledTask';Before=$before;After=$after})}
                else{$notes+=($id.TaskName+': ja desabilitada; preservada')}
            }catch{$notes+=($id.TaskName+': ignorada: '+$_.Exception.Message)}
        }
    }
    [pscustomobject]@{Operations=$ops;Notes=$notes;RequiresAdmin=($ops.Count -gt 0)}
}
