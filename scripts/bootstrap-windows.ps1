# Bootstrap the WINDOWS PC (32GB+, GPU) as the HEAVY / Dockerized-services node.
# Run in an elevated PowerShell. Installs Docker Desktop + WSL2 + Foundry (via WSL) + tooling.

Write-Host "==> WSL2 (needed for Docker + a Linux-native Foundry)" -ForegroundColor Cyan
wsl --install -d Ubuntu   # reboot if this is the first install

Write-Host "==> Docker Desktop (enable WSL2 backend)" -ForegroundColor Cyan
winget install -e --id Docker.DockerDesktop

Write-Host "==> Node + git + pnpm" -ForegroundColor Cyan
winget install -e --id OpenJS.NodeJS.LTS
winget install -e --id Git.Git
npm install -g pnpm

Write-Host "==> Foundry inside WSL (run these in the Ubuntu shell):" -ForegroundColor Yellow
Write-Host '   curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup'

Write-Host "==> Open inbound firewall for the service ports" -ForegroundColor Cyan
$ports = 8000,8020,5001,5432,4000,9090,3001,8545
foreach ($p in $ports) {
  New-NetFirewallRule -DisplayName "stablecoin-lab $p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "==> LAN IP of this Windows box (share with the Mac):" -ForegroundColor Cyan
(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' -or $_.IPAddress -like '192.168.*' }).IPAddress

Write-Host "`nNEXT (infra-devops): docker compose up  (graph-node + IPFS + Postgres + explorer + monitoring), pointed at http://<MAC_LAN_IP>:8545" -ForegroundColor Green
