function Get-BnqqNetworkAudit {
    $errors=@();$adapters=@();$tcp=@();$udp=@();$range=@()
    try{$adapters=@(Get-NetAdapter -Physical -ErrorAction Stop | Select-Object InterfaceDescription,Status,LinkSpeed)}catch{$errors+=$_.Exception.Message}
    try{$tcp=@(Get-NetTCPConnection -ErrorAction Stop)}catch{$errors+=$_.Exception.Message}
    try{$udp=@(Get-NetUDPEndpoint -ErrorAction Stop)}catch{$errors+=$_.Exception.Message}
    try{$range=@(& netsh.exe int ipv4 show dynamicport tcp);if($LASTEXITCODE -ne 0){throw 'netsh falhou'}}catch{$errors+=$_.Exception.Message}
    return [pscustomobject]@{Adapters=$adapters;TcpStates=@($tcp|Group-Object State|Select-Object Name,Count);TopTcpOwners=@($tcp|Group-Object OwningProcess|Sort-Object Count -Descending|Select-Object -First 10 Name,Count);UdpEndpoints=$udp.Count;DynamicTcpRange=$range;Errors=$errors;Note='ACK/NoDelay sao TCP; CS2 usa UDP no gameplay. Sem alteracao de buffers, portas, offloads, DNS, DSCP ou rotas. Contagem alta nao prova esgotamento.'}
}
