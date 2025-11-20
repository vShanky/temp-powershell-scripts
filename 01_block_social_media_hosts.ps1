# Blocks popular social media via hosts file. Run as admin.
$entries = @(
  "0.0.0.0 facebook.com","0.0.0.0 www.facebook.com","0.0.0.0 m.facebook.com",
  "0.0.0.0 instagram.com","0.0.0.0 www.instagram.com",
  "0.0.0.0 tiktok.com","0.0.0.0 www.tiktok.com",
  "0.0.0.0 snapchat.com","0.0.0.0 www.snapchat.com",
  "0.0.0.0 x.com","0.0.0.0 twitter.com","0.0.0.0 www.twitter.com",
  "0.0.0.0 threads.net","0.0.0.0 www.threads.net",
  "0.0.0.0 reddit.com","0.0.0.0 www.reddit.com"
)

$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
Copy-Item $hosts "$hosts.bak" -Force

foreach ($e in $entries) {
    if (-not (Select-String -Path $hosts -Pattern ([regex]::Escape($e)) -Quiet)) {
        Add-Content -Path $hosts -Value $e
    }
}

Write-Host "Hosts entries added. Flushing DNS..."
ipconfig /flushdns
