function Get-BnqqChromiumAudit {
    # Diagnostics only: never append flags to shortcuts or change acceleration globally.
    $bad=@('--disable-background-timer-throttling','--disable-renderer-backgrounding')
    $shell=New-Object -ComObject WScript.Shell
    $roots=@([Environment]::GetFolderPath('Desktop'),(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
    foreach($dir in $roots){
        foreach($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)){
            try{
                $shortcut=$shell.CreateShortcut($file.FullName)
                if([IO.Path]::GetFileName($shortcut.TargetPath) -notin @('chrome.exe','msedge.exe','brave.exe','Discord.exe')){continue}
                $found=@($bad|Where-Object {$shortcut.Arguments -match ('(?<!\S)'+[regex]::Escape($_)+'(?!\S)')})
                if($found.Count){[pscustomobject]@{Shortcut=$file.FullName;Flags=$found;Action='Preview with apps -CleanLegacyFlags -DryRun; original arguments journalled before cleanup'}}
            }catch{Write-Warning ('Atalho inacessivel: '+$file.Name)}
        }
    }
}
function Assert-BnqqShortcutPath {
    param([string]$Path)
    $full=[IO.Path]::GetFullPath($Path);$ok=$false
    foreach($root in @([Environment]::GetFolderPath('Desktop'),(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))){
        if($full.StartsWith(([IO.Path]::GetFullPath($root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){$ok=$true}
    }
    if(-not $ok -or [IO.Path]::GetExtension($full) -ine '.lnk' -or -not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'Atalho fora das pastas auditadas ou ausente'}
}
function Remove-BnqqBadFlags {
    param([string]$Arguments)
    return [regex]::Replace($Arguments,'(?<!\S)--disable-(background-timer-throttling|renderer-backgrounding)(?!\S)','')
}
function Get-BnqqShortcutSnapshot {
    param([string]$Path)
    Assert-BnqqShortcutPath $Path
    $shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($Path)
    if([IO.Path]::GetFileName($shortcut.TargetPath) -notin @('chrome.exe','msedge.exe','brave.exe','Discord.exe')){throw 'Executavel de atalho nao auditado'}
    return [pscustomobject]@{Path=[IO.Path]::GetFullPath($Path);Target=$shortcut.TargetPath;Arguments=$shortcut.Arguments}
}
function Set-BnqqShortcutSnapshot {
    param($Snapshot)
    $current=Get-BnqqShortcutSnapshot $Snapshot.Path
    if($current.Target -cne $Snapshot.Target){throw 'Alvo do atalho mudou'}
    $shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($Snapshot.Path)
    $shortcut.Arguments=$Snapshot.Arguments;$shortcut.Save()
}
function Repair-BnqqChromiumFlags {
    param([switch]$DryRun)
    $ops=@(foreach($item in @(Get-BnqqChromiumAudit)){
        $before=Get-BnqqShortcutSnapshot $item.Shortcut;$after=$before|Select-Object *
        $after.Arguments=Remove-BnqqBadFlags $before.Arguments
        [pscustomobject]@{Kind='Shortcut';Before=$before;After=$after}
    })
    if($DryRun){return $ops}
    Assert-BnqqHeavyQa
    $lock=Enter-BnqqStateLock
    try{
        Assert-BnqqNoPendingJournal
        if(-not $ops.Count){Write-Host 'Nenhuma flag elegivel';return}
        $j=New-BnqqJournal 'chromium-repair'
        try{foreach($op in $ops){Invoke-BnqqJournalOperation $j $op};$j.Data.Status='Applied';Write-BnqqAtomicJson $j.Data $j.File}
        catch{$failure=$_;try{Restore-BnqqJournal $j.File|Out-Null}catch{Write-Warning $_};throw $failure}
        Write-Host ('Argumentos anteriores preservados em '+$j.File)
    }finally{$lock.Dispose()}
}
