$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($n in @('Core','Governance')){. (Join-Path $root ('lib\'+$n+'.ps1'))}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('bnqq-scope-'+[guid]::NewGuid().ToString('N'))
$script:BnqqDataRoot=$temp;$script:checks=0;$script:boot=[datetime]::UtcNow.AddHours(-2);$script:events=@();$script:probeError=$null
function Check($v,$m){if(-not $v){throw $m};$script:checks++}
function MustThrow([scriptblock]$c){$hit=$false;try{& $c|Out-Null}catch{$hit=$true};Check $hit 'Expected refusal'}
function Get-BnqqBootUtc {return $script:boot}
function Get-BnqqWheaEvents {param([datetime]$Since=[datetime]::UtcNow.AddHours(-72));[pscustomobject]@{Events=@($script:events|Where-Object {$_.TimeCreated -ge $Since});Error=$script:probeError}}
function Get-BnqqConfigurationFingerprint {param([switch]$WorkloadOnly);if($WorkloadOnly){return $script:resource};return $script:full}
function Certificate {
 $script:full='full-code-v1';$script:resource='boot-hardware-and-test-v1'
 [pscustomobject]@{Schema=3;Owner=(Get-BnqqOwner);Started=[datetime]::UtcNow.AddMinutes(-11).ToString('o');Generated=[datetime]::UtcNow.ToString('o');Verdict='PASS';CpuVerified=$true;IoVerified=$true;Completed=$true;Seconds=600;IdleTailSeconds=30;WheaCount=0;KernelPower41Count=0;StrictConfigurationVerified=$true;Fingerprint=$script:full;ResourceFingerprint=$script:resource}
}
function Save($c){Write-BnqqAtomicJson $c (Join-Path $temp 'heavyqa.json')}
try{
 $c=Certificate;Save $c;Assert-BnqqHeavyQa -WorkloadOnly;Assert-BnqqHeavyQa
 $script:events=@([pscustomobject]@{Id=18;TimeCreated=$script:boot.AddHours(-10)})
 Assert-BnqqHeavyQa -WorkloadOnly;MustThrow {Assert-BnqqHeavyQa}
 $script:full='new-unrelated-module';Assert-BnqqHeavyQa -WorkloadOnly;Check (-not (Get-BnqqLatestHeavyQa).Passed) 'Full-source binding lost'
 $script:resource='changed-driver-hardware-or-test';MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $script:resource=$c.ResourceFingerprint;$script:events=@([pscustomobject]@{Id=18;TimeCreated=$script:boot.AddMinutes(5)})
 MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $script:events=@();$script:probeError='denied';MustThrow {Assert-BnqqHeavyQa -WorkloadOnly};$script:probeError=$null
 $c.Schema=2;Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.Started=$script:boot.AddMinutes(-1).ToString('o');Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.KernelPower41Count=1;Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.Generated=[datetime]::UtcNow.AddHours(1).ToString('o');Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.Generated=[datetime]::UtcNow.AddHours(-25).ToString('o');Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.Owner='other';Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.IoVerified=$false;Save $c;MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 $c=Certificate;$c.StrictConfigurationVerified=$false;Save $c;Assert-BnqqHeavyQa -WorkloadOnly;Check (-not (Get-BnqqLatestHeavyQa).Passed) 'Resource-only proof unlocked clock path'
 $script:boot=$script:boot.AddHours(3);MustThrow {Assert-BnqqHeavyQa -WorkloadOnly}
 ('PASS: '+$script:checks+' governance scope checks; old events retained, current-boot faults blocked, legacy proof rejected, source domains and clock gate separated')
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
