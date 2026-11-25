$ErrorActionPreference = 'Continue'

# 卸载应用包，但保留 data\ 与 game\（存档和已下载的版本不会被删）

$pkg = Get-AppxPackage -Name 'Tessera.Launcher' -ErrorAction SilentlyContinue
if (-not $pkg) {
    Write-Host '没有安装 Tessera.Launcher。'
    exit 0
}

Write-Host ("卸载 {0}" -f $pkg.PackageFullName)
Remove-AppxPackage -Package $pkg.PackageFullName

Write-Host '已卸载。data\ 与 game\ 里的内容保持原样。' -ForegroundColor Green
