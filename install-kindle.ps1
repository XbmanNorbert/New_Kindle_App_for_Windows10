# Kindle for Windows 10 - install script (run as Administrator)
# 这套文件可以直接拷到另一台 Windows 10 电脑上用，不需要原机器上的私钥。
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$cer  = Join-Path $root 'Kindle-SigningCert.cer'
$rt   = Join-Path $root 'WindowsAppRuntimeInstall-x64.exe'
$vc   = Join-Path $root 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
# 自动挑最新生成的一个包，这样 Kindle 升级后不用改脚本
$pkg = (Get-ChildItem -Path $root -Filter 'Kindle-Win10-*.msix' |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1).FullName
if (-not $pkg) {
    Write-Host '[!] 目录下找不到 Kindle-Win10-*.msix，请先运行 port-to-win10.ps1' -ForegroundColor Red
    Read-Host '按回车键关闭'; exit 1
}

# ---------- 0. 管理员检查 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ''
    Write-Host '[!] 当前不是管理员权限，无法写入本机证书存储。' -ForegroundColor Red
    Write-Host '    请右键 Install-Kindle.bat -> 以管理员身份运行' -ForegroundColor Yellow
    Write-Host ''
    Read-Host '按回车键关闭'; exit 1
}
Write-Host '[OK] 已获取管理员权限' -ForegroundColor Green

# ---------- 0b. 系统版本检查 ----------
$build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
Write-Host ('      系统内部版本: ' + $build)
if ($build -lt 17763) {
    Write-Host '[!] 需要 Windows 10 1809 (17763) 或更高，当前版本过低。' -ForegroundColor Red
    Read-Host '按回车键关闭'; exit 1
}
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    Write-Host '[!] 这个包是 x64 的，当前机器不是 64 位。' -ForegroundColor Red
    Read-Host '按回车键关闭'; exit 1
}

# ---------- 1. VCLibs 依赖 ----------
Write-Host ''
Write-Host '[1/4] 检查 VCLibs 依赖 ...' -ForegroundColor Cyan
$vcPkg = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -ErrorAction SilentlyContinue
$vcBase = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00' -ErrorAction SilentlyContinue
if ($vcPkg) { Write-Host '      UWPDesktop 已存在: ' $vcPkg.Version }
elseif (Test-Path $vc) {
    Write-Host '      安装 UWPDesktop ...'
    Add-AppxPackage -Path $vc
} else {
    Write-Host '      缺少 Microsoft.VCLibs.x64.14.00.Desktop.appx，跳过' -ForegroundColor Yellow
}
if ($vcBase) { Write-Host '      VCLibs.140.00 已存在: ' $vcBase.Version }
else { Write-Host '      注意：Microsoft.VCLibs.140.00 未预装，若后面报依赖缺失请从微软下载' -ForegroundColor Yellow }

# ---------- 2. Windows App Runtime 1.8 ----------
Write-Host ''
Write-Host '[2/4] 检查 Windows App Runtime 1.8 ...' -ForegroundColor Cyan
$hasRt = Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.1.8' -ErrorAction SilentlyContinue
if ($hasRt) {
    Write-Host '      已存在，跳过：' $hasRt.Version
} elseif (Test-Path $rt) {
    Write-Host '      未安装，正在部署运行时（约 1 分钟）...'
    & $rt -q
    Start-Sleep -Seconds 8
    $chk = Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.1.8' -ErrorAction SilentlyContinue
    if ($chk) { Write-Host '      运行时就绪：' $chk.Version -ForegroundColor Green }
    else      { Write-Host '      运行时状态未知，继续尝试安装应用...' -ForegroundColor Yellow }
} else {
    Write-Host '      缺少 WindowsAppRuntimeInstall-x64.exe，跳过' -ForegroundColor Yellow
}

# ---------- 3. 导入签名证书 ----------
Write-Host ''
Write-Host '[3/4] 导入自签名证书到本机受信任存储 ...' -ForegroundColor Cyan
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import($cer)
foreach ($s in @('Root', 'TrustedPeople')) {
    $st = New-Object System.Security.Cryptography.X509Certificates.X509Store($s, 'LocalMachine')
    $st.Open('ReadWrite')
    $st.Add($cert)
    $st.Close()
    Write-Host ("      LocalMachine\" + $s)
}

# 自检：证书没真的进去的话，后面安装必然报 0x800B0109（看不懂的错误码）。
# 这里提前拦下，直接告诉用户该怎么办。
$th = $cert.Thumbprint
$rs = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
$rs.Open('ReadOnly')
$ok = @($rs.Certificates | Where-Object { $_.Thumbprint -eq $th }).Count -gt 0
$rs.Close()
if (-not $ok) {
    Write-Host ''
    Write-Host '[!] 证书未能写入本机受信任根存储，继续安装会失败。' -ForegroundColor Red
    Write-Host '    请手动导入：Win+R 输入 certlm.msc ->' -ForegroundColor Yellow
    Write-Host '    受信任的根证书颁发机构 -> 证书 -> 右键所有任务 -> 导入 ->' -ForegroundColor Yellow
    Write-Host '    选择 Kindle-SigningCert.cer（"受信任人"里也导入一次）' -ForegroundColor Yellow
    Write-Host ''
    Read-Host '按回车键关闭'; exit 1
}
Write-Host '      证书就绪' -ForegroundColor Green

# ---------- 4. 安装应用包 ----------
Write-Host ''
Write-Host ('[4/4] 安装 Kindle（' + (Split-Path $pkg -Leaf) + '，请稍候）...') -ForegroundColor Cyan
Add-AppxPackage -Path $pkg -ForceApplicationShutdown

Write-Host ''
$app = Get-AppxPackage | Where-Object { $_.Name -like '*Kindle*' }
if ($app) {
    Write-Host '安装成功！开始菜单搜索 Kindle 即可启动。' -ForegroundColor Green
    Write-Host ('  ' + $app.Name + '  v' + $app.Version)
} else {
    Write-Host '安装未完成，请查看上方红色错误信息。' -ForegroundColor Red
}
Write-Host ''
Read-Host '按回车键关闭'
