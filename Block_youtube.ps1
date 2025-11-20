# Sometimes it not work so do run windows-refresh-script

# Blocks YouTube by hosts
$entries = @(
    "0.0.0.0 youtube.com",
    "0.0.0.0 www.youtube.com",
    "0.0.0.0 m.youtube.com",
    "0.0.0.0 youtu.be"
)

$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
Copy-Item $hosts "$hosts.bak" -Force

foreach ($e in $entries) {
    if (-not (Select-String -Path $hosts -Pattern ([regex]::Escape($e)) -Quiet)) {
        Add-Content -Path $hosts -Value $e
    }
}

ipconfig /flushdns
Write-Host "YouTube blocked via hosts."
