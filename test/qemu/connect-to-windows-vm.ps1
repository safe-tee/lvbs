<#
.SYNOPSIS
Forward a remote Windows VM's localhost VNC listener over SSH.
.EXAMPLE
.\connect-to-windows-vm.ps1 -SshHost user@linux-host
.EXAMPLE
.\connect-to-windows-vm.ps1 -SshHost user@linux-host -VncDisplay 2 -LocalPort 5902
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$SshHost,

    [ValidateRange(0, 59635)]
    [int]$VncDisplay = 1,

    [ValidateRange(1, 65535)]
    [int]$LocalPort = 5901,

    [ValidateRange(1, 65535)]
    [int]$SshPort = 22
)

$ErrorActionPreference = 'Stop'
$sshCommand = Get-Command ssh -CommandType Application -ErrorAction Stop
$remotePort = 5900 + $VncDisplay
$sshArguments = @(
    '-N'
    '-T'
    '-o', 'ExitOnForwardFailure=yes'
    '-o', 'ServerAliveInterval=30'
    '-o', 'ServerAliveCountMax=3'
    '-p', "$SshPort"
    '-L', "127.0.0.1:${LocalPort}:127.0.0.1:${remotePort}"
    '--', $SshHost
)

Write-Host "Forwarding remote VNC port $remotePort through SSH to $SshHost."
Write-Host "Connect VNC Viewer to 127.0.0.1, port $LocalPort."
Write-Host 'Keep this terminal open; press Ctrl+C to close the tunnel.'

& ($sshCommand.Source) @sshArguments
exit $LASTEXITCODE