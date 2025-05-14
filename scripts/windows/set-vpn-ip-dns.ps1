<#
.SYNOPSIS
  Configure IP et DNS pour un adaptateur TAP OpenVPN avec sélection d’une IP aléatoire dans un /16.

.DESCRIPTION
  - Recherche automatiquement le premier adaptateur TAP ("TAP-Windows Adapter V9").
  - Paramètres : dns1 (obligatoire) et dns2 (optionnel).
  - Masque fixe : 255.255.0.0 (/16).
  - Génère aléatoirement une IP dans le même /16 que dns1.
  - Vous demande en boucle si l’IP choisie vous convient ; si non, génère une autre IP.
  - Applique via New-NetIPAddress et Set-DnsClientServerAddress.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
    [string]$dns1,

    [Parameter(Mandatory=$false)]
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
    [string]$dns2
)

# 1. Recherche du TAP
$adapter = Get-NetAdapter |
    Where-Object InterfaceDescription -Match 'TAP-Windows Adapter V9' |
    Select-Object -First 1
if (-not $adapter) {
    Write-Error "Aucun adaptateur TAP-Windows Adapter V9 trouve."
    exit 1
}
$idx = $adapter.InterfaceIndex
Write-Host "Using adapter InterfaceIndex=$idx (Name='$($adapter.Name)')" -ForegroundColor Cyan

# 2. Calcul du préfixe et du réseau
$prefix = 16      # masque 255.255.0.0
$dnsOctets = $dns1.Split('.')
if ($dnsOctets.Count -ne 4) {
    Write-Error "Format dns1 invalide : $dns1"
    exit 1
}
$netPart = "$($dnsOctets[0]).$($dnsOctets[1])"

# 3. Boucle de sélection aléatoire d'IP
do {
    # Génère deux octets aléatoires (1-254 pour éviter .0 et .255)
    $r3 = Get-Random -Minimum 1 -Maximum 254
    $r4 = Get-Random -Minimum 1 -Maximum 254
    $candidateIp = "$netPart.$r3.$r4"
    Write-Host "Proposition d'IP : $candidateIp/$prefix" -ForegroundColor Yellow
    $ans = Read-Host "Cette IP convient-elle ? (O/N)"
} until ($ans.Trim().ToUpper() -eq 'O')

# 4. Suppression des anciennes IPv4
Write-Host "Removing existing IPv4 addresses..." -ForegroundColor DarkYellow
Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 `
  | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# 5. Création de la nouvelle IP
Write-Host "Creating new IP address $candidateIp/$prefix..." -ForegroundColor Green
New-NetIPAddress `
  -InterfaceIndex $idx `
  -IPAddress    $candidateIp `
  -PrefixLength $prefix `
  -ErrorAction Stop

# 6. Application des DNS
Write-Host "Setting DNS server(s)..." -ForegroundColor DarkCyan
$servers = if ($dns2) { @($dns1, $dns2) } else { @($dns1) }
Set-DnsClientServerAddress `
  -InterfaceIndex   $idx `
  -ServerAddresses  $servers `
  -ErrorAction Stop

# 7. Résultat final
Write-Host ""
Write-Host "Configuration terminee!" -ForegroundColor Green
Write-Host "  IP:   $candidateIp/$prefix" -ForegroundColor Gray
Write-Host "  Mask: 255.255.0.0" -ForegroundColor Gray
Write-Host "  DNS:  $($servers -join ', ')" -ForegroundColor Gray
