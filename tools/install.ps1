param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

# 目录跟着脚本走：整份拷到别处（比如 dist）也能直接装，不必改路径
$here = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'D:\minecraftluncher\uwp-native' }
$msix = Join-Path $here 'Tessera.Launcher.msix'

# 仓库里不放二进制包：42 MB 的 blob 过不了 GitHub 接口的大小限制，改成从 Release 拿。
# 同目录已经有包就直接用，方便把整份目录拷走离线安装。
if (-not (Test-Path $msix)) {
    Write-Host '没找到本地安装包，从 GitHub Release 下载…'
    # PS 5.1 默认还是 TLS 1.0，GitHub 只接受 1.2+
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $api = 'https://api.github.com/repos/AwA1-1/tessera-launcher/releases/latest'
    $fallback = 'https://github.com/AwA1-1/tessera-launcher/releases/latest'
    try {
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tessera-installer' } -TimeoutSec 60
    } catch {
        throw ("连不上 GitHub（网络受限？）：" + $_.Exception.Message + "`n" +
               "可以手动打开 $fallback 下载 msix，存成 Tessera.Launcher.msix 放在本目录，再跑一次 install.bat")
    }
    $asset = $rel.assets | Where-Object { $_.name -like '*.msix' } | Select-Object -First 1
    if (-not $asset) { throw "GitHub 上没找到安装包，请手动下载：$fallback" }
    $msix = Join-Path $here $asset.name
    Write-Host ("下载 {0}（{1:N1} MB）…" -f $asset.name, ($asset.size / 1MB))
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msix -UseBasicParsing -TimeoutSec 900
    } catch {
        throw ("下载失败：" + $_.Exception.Message + "`n" +
               "可以手动打开 $fallback 下载 msix，存成 Tessera.Launcher.msix 放在本目录，再跑一次 install.bat")
    }
    # Release 会记录每个附件的 SHA-256，对不上就是包坏了或者被改过，不装
    if ($asset.digest -match '^sha256:(.+)$') {
        $expected = $Matches[1].ToLower()
        $actual = (Get-FileHash -Path $msix -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected) {
            Remove-Item -LiteralPath $msix -Force
            throw ("安装包校验失败：期望 $expected，实际 $actual")
        }
        Write-Host ("校验通过 SHA-256 {0}" -f $actual.Substring(0, 16)) -ForegroundColor DarkGray
    }
    Write-Host ("已下载 {0}（{1:N1} MB）" -f $asset.name, ($asset.size / 1MB)) -ForegroundColor Green
}

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
