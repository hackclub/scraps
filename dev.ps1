# Starts Redis (Docker), Rails API (:3000), and the SvelteKit dev server
# (:5173), all in THIS terminal. Ctrl+C stops everything. Run from the repo root:
#   .\dev.ps1
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# 0. Free ports from any orphaned run
foreach ($port in 3000, 5173) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object { taskkill /T /F /PID $_.OwningProcess *> $null }
}

# 1. Redis
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker Desktop is not running. Start it, then re-run .\dev.ps1" -ForegroundColor Yellow
    exit 1
}
if (docker ps -aq -f name=scraps-redis) { docker start scraps-redis | Out-Null }
else { docker run -d -p 6379:6379 --name scraps-redis redis | Out-Null }
Write-Host "Redis up on :6379" -ForegroundColor Green

if (docker ps -aq -f name=scraps-postgres) { docker start scraps-postgres | Out-Null }
else { docker run -d -p 5433:5432 -e POSTGRES_PASSWORD=postgres --name scraps-postgres postgres:16 | Out-Null }
Write-Host "Postgres up on :5433" -ForegroundColor Green
if (-not (Test-Path "$root\backend\.env.development.local")) {
    Write-Host "backend\.env.development.local missing - Airtable is NOT blanked" -ForegroundColor Red
    exit 1
}
if (Select-String -Path "$root\backend\.env.development.local" -Pattern "^DATABASE_URL=" -Quiet) { Write-Host "DB: local (scraps_dev on :5433)" -ForegroundColor Green }
else { Write-Host "DB: PROD - admin actions hit real users" -ForegroundColor Red }

# 2. Rails  3. Frontend — all in this console
$procs = @(
    Start-Process powershell -PassThru -NoNewWindow -ArgumentList `
        "-NoProfile", "-Command", "cd '$root\backend'; bundle exec rails server -p 3000"
    Start-Process powershell -PassThru -NoNewWindow -ArgumentList `
        "-NoProfile", "-Command", "cd '$root\frontend'; bun run dev"
)

Write-Host "Backend  -> http://localhost:3000" -ForegroundColor Green
Write-Host "Frontend -> http://localhost:5173" -ForegroundColor Green
Write-Host "Ctrl+C to stop all." -ForegroundColor Green

try {
    Wait-Process -Id ($procs.Id)
} finally {
    foreach ($p in $procs) { taskkill /T /F /PID $p.Id *> $null }
    Write-Host "`nStopped Rails + frontend. (Redis container left running.)" -ForegroundColor Yellow
}
