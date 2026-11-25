$ErrorActionPreference = 'Stop'

# 把自签名证书装进「受信任的根证书颁发机构」，之后 Tessera.Launcher.msix 就能像商店应用一样
# 用 Add-AppxPackage 标准安装（不需要开发者模式）。需要管理员权限。

$cer = Join-Path $PSScriptRoot '..\cert\MineLauncherUwp.cer'
if (-not (Test-Path $cer)) { throw "找不到证书：$cer（先跑 tools\build-all.ps1 生成）" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    .IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '需要管理员权限：右键 PowerShell「以管理员身份运行」，再执行本脚本。' -ForegroundColor Yellow
    exit 1
}

Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null

Write-Host '证书已导入。现在可以用 install.bat 走标准安装流程。' -ForegroundColor Green
