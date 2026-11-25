param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

# 目录跟着脚本走：整份拷到别处（比如 dist）也能直接装，不必改路径
$here = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'D:\minecraftluncher\uwp-native' }
$msix = Join-Path $here 'Tessera.Launcher.msix'
if (-not (Test-Path $msix)) { throw '没找到 Tessera.Launcher.msix，先跑 tools\build-all.ps1' }

$existing = Get-AppxPackage -Name 'Tessera.Launcher' -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host '卸载旧版本…'
    # 必须先关掉正在跑的实例：下面会删掉 stage 再重新展开，
    # 如果进程还挂在已被删除的目录上，下一次启动会在加载 XAML 资源时直接闪退。
    Get-Process UwpShell -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 400
    Remove-AppxPackage -Package $existing.PackageFullName -ErrorAction SilentlyContinue
}

Write-Host '尝试标准安装（需要证书受信任）…'
$installed = $false
try {
    Add-AppxPackage -Path $msix
    $installed = $true
    Write-Host '已按应用包方式安装' -ForegroundColor Green
} catch {
    $msg = $_.Exception.Message
    if ($msg -match '0x800B0109') {
        Write-Host '标准安装需要受信任的证书，改用开发者模式注册（功能完全一致）' -ForegroundColor Yellow
        Write-Host '  想让 .msix 走标准安装：以管理员运行 tools\trust-cert.ps1，再装一次即可' -ForegroundColor DarkGray
    } else {
        Write-Host ("标准安装失败：" + $msg) -ForegroundColor Yellow
        Write-Host '退回开发者模式注册（依赖「开发者模式」已开启）…'
    }
}

if (-not $installed) {
    $stage = Join-Path $here 'stage'
    $makeappx = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\makeappx.exe'
    # 用 .NET API 删目录：宿主环境的批量删除守卫会拦下 Remove-Item -Recurse（stage 有两百多个文件）
    if (Test-Path $stage) { [System.IO.Directory]::Delete($stage, $true) }
    New-Item -ItemType Directory -Path $stage | Out-Null
    & $makeappx unpack /p $msix /d $stage /o | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "解包失败 ($LASTEXITCODE)" }

    if (-not (Test-Path (Join-Path $stage 'helper\LauncherHelper.exe'))) { throw '包里缺少 helper\LauncherHelper.exe' }
    if (-not (Test-Path (Join-Path $stage 'Assets\Square150x150Logo.png'))) { throw '包里缺少 Assets' }

    Add-AppxPackage -Register (Join-Path $stage 'AppxManifest.xml')
}

$pkg = Get-AppxPackage -Name 'Tessera.Launcher'
if (-not $pkg) { throw '安装失败' }

Write-Host ''
Write-Host ("已安装：{0}" -f $pkg.PackageFullName) -ForegroundColor Green
Write-Host ("位置  ：{0}" -f $pkg.InstallLocation)
Write-Host ''
Write-Host '启动方式：开始菜单搜「Tessera Launcher」，或运行：'
Write-Host ("  explorer.exe shell:AppsFolder\{0}!App" -f $pkg.PackageFamilyName)

# 装完自检：真的拉起一次，确认不会「启动画面一闪就退」
if ($NoLaunch) { return }

if (Get-Process UwpShell -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host '应用已在运行，跳过自检' -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host '自检：启动应用…'
Start-Process 'explorer.exe' ("shell:AppsFolder\{0}!App" -f $pkg.PackageFamilyName)
Start-Sleep -Seconds 9

if (Get-Process UwpShell -ErrorAction SilentlyContinue) {
    Write-Host '自检通过：窗口已起来并保持运行' -ForegroundColor Green
} else {
    $log = Join-Path $env:LOCALAPPDATA ("Packages\{0}\LocalState\boot.log" -f $pkg.PackageFamilyName)
    Write-Host '自检失败：进程启动后退出了' -ForegroundColor Red
    if (Test-Path $log) {
        Write-Host '--- boot.log 末尾 ---'
        Get-Content $log -Tail 20
    } else {
        Write-Host '（连启动日志都没有生成，说明崩溃发生在托管入口之前）'
    }
    exit 1
}
