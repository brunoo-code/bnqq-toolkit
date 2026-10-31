function Get-BnqqTopology {
    if(-not ('Bnqq.Topology' -as [type])){Add-Type -Path (Join-Path $script:BnqqRoot 'lib\Topology.cs') -ErrorAction Stop}
    return @([Bnqq.Topology]::Read())
}
function Get-BnqqSafeGameMask {
    $cores=@(Get-BnqqTopology)
    if(@($cores | Where-Object Group -ne 0).Count){throw 'Mais de um grupo: nao aplicar mascara escalar'}
    if(@($cores | Where-Object {$_.Mask -gt [uint64][int64]::MaxValue}).Count){throw 'Bit 63 nao representavel pela politica escalar; manter scheduler sem restricoes'}
    if(@($cores | Select-Object -ExpandProperty EfficiencyClass -Unique).Count -gt 1){throw 'CPU hibrida: manter scheduler sem restricoes'}
    $mask=[uint64]0
    foreach($core in $cores){
        $bits=[uint64]$core.Mask
        for($bit=0;$bit -lt 63;$bit++){
            $one=[uint64]1 -shl $bit
            if(($bits -band $one) -ne 0){$mask=$mask -bor $one;break}
        }
    }
    if($mask -eq 0 -or $cores.Count -lt 4){throw 'Topologia inadequada para experimento de afinidade'}
    return [int64]$mask
}
