Write-Host "Starting Safe4Sure removal..."

# Stop possible services
$services = Get-Service | Where-Object {$_.Name -like "*safe4sure*" -or $_.DisplayName -like "*safe4sure*"}
foreach ($service in $services) {
    Write-Host "Stopping service $($service.Name)"
    Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
}

# Find installed MSI
$app = Get-WmiObject Win32_Product | Where-Object {$_.Name -like "*Safe4Sure*"}

if ($app) {
    Write-Host "Uninstalling Safe4Sure..."
    $app.Uninstall()
}

# Remove leftover folders
$paths = @(
"C:\Program Files\Safe4Sure",
"C:\Program Files (x86)\Safe4Sure",
"C:\ProgramData\Safe4Sure"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Write-Host "Removing $path"
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove registry entries
$registryPaths = @(
"HKLM:\Software\Safe4Sure",
"HKLM:\Software\WOW6432Node\Safe4Sure"
)

foreach ($reg in $registryPaths) {
    if (Test-Path $reg) {
        Write-Host "Removing registry $reg"
        Remove-Item $reg -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Safe4Sure removal completed."
