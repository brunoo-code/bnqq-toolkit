function Get-BnqqHardware {
    $errors=New-Object 'Collections.Generic.List[string]'
    $values=@{}
    foreach($class in @('Win32_Processor','Win32_BaseBoard','Win32_BIOS','Win32_VideoController','Win32_PhysicalMemory','Win32_OperatingSystem','Win32_PnPEntity')){
        try{$values[$class]=@(Get-CimInstance $class -ErrorAction Stop)}catch{$values[$class]=@();$errors.Add($class+': '+$_.Exception.Message)}
    }
    $cpu=$values.Win32_Processor | Select-Object -First 1
    $board=$values.Win32_BaseBoard | Select-Object -First 1
    $amdPci=@($values.Win32_PnPEntity | Where-Object {$_.PNPDeviceID -like 'PCI\VEN_1022*'})
    $expected=Get-Content (Join-Path $script:BnqqRoot 'config\hardware.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $matchingCpu=$null
    if($expected.CPU){$matchingCpu=$cpu -and $cpu.Name.Trim() -eq $expected.CPU -and $cpu.NumberOfCores -eq $expected.Cores -and $cpu.NumberOfLogicalProcessors -eq $expected.Threads}
    return [pscustomobject]@{
        ObservedCPU=$cpu;ObservedBoard=$board;ObservedBIOS=$values.Win32_BIOS
        GPU=$values.Win32_VideoController;Memory=$values.Win32_PhysicalMemory;OS=$values.Win32_OperatingSystem
        Declared=$expected;AmdPciEvidence=$amdPci.Count;CpuMatchesDeclared=$matchingCpu
        BoardConfidence='Unverified: SMBIOS can be altered; PCI vendor/CPU count cannot prove B550 model'
        FclkConfidence='Not measured by WMI; any configured value is user-declared'
        Errors=$errors.ToArray();PerformanceClaim='None: observations are not a benchmark'
    }
}
function Show-BnqqDisplayGuidance {
    Write-Host 'CS2: compare Tela cheia exclusiva e janela/flip model usando o mesmo cenario.'
    Write-Host 'Use PresentMode no CSV: Independent Flip pode evitar composicao mesmo em janela.'
    Write-Host 'Confirme o Hz no Windows e monitor. Sensacao de 60 Hz nao diagnostica DWM/MPO.'
    Write-Host 'OverlayTestMode nao e alterado: MPO off e workaround especifico, nao otimizacao universal.'
}
