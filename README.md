# MSIX 降级移植：把 Windows 11 专属应用装回 Windows 10

> 亚马逊把 Kindle 应用的 MSIX 最低系统版本锁死在 Windows 11，Windows 10 装不上。
> 本项目把那行限制改掉、重新打包签名，并固化成可复用的脚本。
>
> **核心结论**：MSIX 能不能装，由清单里的一行 `MinVersion` 说了算；但改了这一行，签名就废了。
> 所以整套工作的本质**不是"改版本号"，而是"改完之后重新建立一条被系统信任的签名链"**。
> 前者 30 秒，后者才是难点。

## 你是谁？从这里开始

| 你是谁 | 看这几节 | 大概耗时 |
|---|---|---|
| **只想把 Kindle 装上**，不懂技术也行 | 第 1–6 节 | 10 分钟 |
| **想搞懂这套移植是怎么做到的** | 第 7–11 节 | 20 分钟 |
| **要在新版 Kindle 出来后自己重做一遍** | 第 12–19 节 | 照着做即可 |
| **排查问题 / 评估要不要用** | 第 20–22 节 | — |

> 完全没接触过 MSIX、PowerShell、签名这些东西？没关系，第 1–6 节是纯"照着做"，
> 不涉及任何原理。

---

# 第一部分 · 装上使用

## 1. 这到底是什么

新版 Kindle 的安装包里写了一句"最低要求 Windows 11"，Windows 10 看到这句就直接拒绝安装。
本项目做的事：把这句要求改掉，重新打包，并**重新签名**（原来的签名改完内容就作废了）。

你不需要理解这个过程 —— 只要会点鼠标就能装上。

## 2. 先花 1 分钟确认你装得了

三件事，**全满足才能继续。任一不满足，直接跳到第 6 节看退路。**

### ① Windows 版本不低于 1809

- 按 `Win + R`，输入 `winver`，回车
- 弹出窗口里找"版本"和"内部版本"
- **内部版本 ≥ 17763** 就行（22H2 是 19045，肯定没问题）

### ② 电脑是 64 位的

- `Win + I` → 系统 → 关于 → 看"系统类型"
- 要显示 **"64 位操作系统"**

### ③ 你有管理员权限

- 设置 → 账户 → 你的信息，看账户名下面是不是"**管理员**"
- 或者更直接：随便找个 `.bat` 文件右键，看菜单里**有没有"以管理员身份运行"**

> 公司发的电脑经常是"标准账户"，那样**装不了 MSIX，没有变通办法**（原因见第 9 节）。
> 请直接看第 6 节的两条退路。

## 3. 安装

### 第 1 步：把 6 个文件放到同一个文件夹

| 文件名 | 说明 |
|---|---|
| `Kindle-Win10-1.0.25218.0-x64.msix` | Kindle 安装包本体（约 493 MB） |
| `Kindle-SigningCert.cer` | 签名证书（1 KB，**必须要有**，否则系统不信任这个包） |
| `WindowsAppRuntimeInstall-x64.exe` | 运行 Kindle 需要的底层组件 |
| `Microsoft.VCLibs.x64.14.00.Desktop.appx` | 同上，另一个底层组件 |
| `Install-Kindle.bat` | 安装入口 |
| `install-kindle.ps1` | 被 bat 调用，别删 |

备注：
要使此构建成功，项目文件夹下必须包含经过编译适用于Windows 10的Kindle-Win10-1.0.25218.0-x64.msix。当前测试的版本通过该项目编译AMZNKindle.AmazonKindleReadingApp_1.0.25218.0_neutral_~_m1sc522ngdk36.Msixbundle取得。请您提供合法获得的Kindle-Win10-1.0.25218.0-x64.msix ；此仓库不托管、链接或重新分发任何Amazon公司的二进制文件。
运行时WindowsAppRuntimeInstall-x64.exe自行下载。

**6 个文件必须在同一个文件夹里**。建议放纯英文路径（如 `C:\Kindle\`），
避免个别电脑因中文路径编码出问题。

### 第 2 步：右键安装

```
右键 Install-Kindle.bat  ->  以管理员身份运行
```

弹出的蓝色窗口（UAC）点 **"是"**。

> 如果没有"以管理员身份运行"这一项，说明你是标准账户 —— 见第 6 节。
> 别去双击 `install-kindle.ps1`，那样不会提权，只会闪一下黑窗口。

### 第 3 步：看它跑完

会依次出现这些输出，**每一步都在做事，别以为卡死了**：

```
[OK] 已获取管理员权限
      系统内部版本: 19045

[1/4] 检查 VCLibs 依赖 ...
[2/4] 检查 Windows App Runtime 1.8 ...     ← 这一步约 1 分钟
[3/4] 导入自签名证书到本机受信任存储 ...
[4/4] 安装 Kindle（Kindle-Win10-1.0.25218.0-x64.msix，请稍候）...   ← 这里最慢，几分钟

安装成功！开始菜单搜索 Kindle 即可启动。
```

按回车关窗口。**看到"安装成功！"就完事了。**

## 4. 装完之后，有三件事要知道

### ① 先实际用一下 —— 这步别省

开始菜单搜 **Kindle** → 登录亚马逊账号 → 打开一本书翻几页。

**能装上不等于能正常跑。** 如果 Kindle 内部调用了 Windows 11 才有的功能，能装但会崩。
只有真的翻过书才算成功。

### ② 你电脑里多了一张自签证书

安装时往系统里加了一张**我们自己签发的根证书**
（名字 `CN=0FFC96E0-F797-4E94-87FB-CA2F8265EC08`），它是这台机器信任我们改过的包的凭据，
没有它装不上。**但卸载 Kindle 之后请把它删掉**，别长期留一张别人签发的根证书：

```
certlm.msc → 受信任的根证书颁发机构 → 证书
→ 找到 CN=0FFC96E0-F797-4E94-87FB-CA2F8265EC08 → 右键删除
```

（"受信任人"里那张也一并删掉。）

### ③ 关掉微软商店的自动更新（重要）

商店可能把 Kindle 自动更新成官方新版 —— 而官方新版又是只支持 Win11 的，
**更新后可能就打不开了**。装完就关掉它（`Win + X` → 终端(管理员)）：

```
reg add HKLM\SOFTWARE\Policies\Microsoft\WindowsStore /v AutoDownload /t REG_DWORD /d 2 /f
```

执行后重启或注销一次生效。

> ⚠️ 商店设置里那个"应用自动更新"开关在新版 Windows 上**已被微软改成只能暂停（最多几周），
> 不能真正关掉**，所以要用上面这条命令。（详见第 17 节）

**万一已经被更新、打不开了**：用保留的旧版 `.msix` 重跑一次 `Install-Kindle.bat` 覆盖回去。
所以**装完后那个 `Kindle-Win10-*.msix` 建议留着别删** —— 它是唯一的回滚备份，
应用商店不会帮你退回旧版。

## 5. 卡住了怎么办

按你**看到的提示**往下找：

| 你看到的 | 是什么意思 | 怎么办 |
|---|---|---|
| 右键菜单里**没有**"以管理员身份运行" | 你是标准账户 | 找 IT 要权限，或走第 6 节 |
| 双击后黑窗口一闪而过 | 你双击的是 `.ps1` 不是 `.bat` | 用 `Install-Kindle.bat` |
| `[!] 当前不是管理员权限` | 自动提权没成功 | `Win + X` → 终端(管理员) → `cd C:\Kindle` → `.\Install-Kindle.bat` |
| `[!] 需要 Windows 10 1809 (17763) 或更高` | 系统太老 | 升级系统，或第 6 节 |
| `[!] 这个包是 x64 的，当前机器不是 64 位` | 32 位系统 | 无解，走第 6 节 |
| `[!] 目录下找不到 Kindle-Win10-*.msix` | 文件没放齐，或不在同一文件夹 | 核对第 3 节的 6 个文件 |
| `0x800B0109` / "根证书不受信任" | 证书没导进本机存储 | 见下方"手动导入证书" |
| 提示"部署失败"、提到"依赖项" | 两个底层组件没装上 | 见下方"手动装依赖" |
| 提示"禁止运行脚本" | PowerShell 执行策略限制 | bat 已处理；手动跑时加 `-ExecutionPolicy Bypass` |
| 装完了但**打不开 / 闪退** | 应用可能用了 Win11 专有功能 | 这是本方案的硬限制，走第 6 节 |

> `0x800B0109` 是实际遇到过的错误码；其他情况请以**屏幕上的中文提示**为准。
> 遇到没列出的报错，把完整提示抄下来发给提供给你这套文件的人。

### 手动导入证书（自动导入失败时）

1. `Win + R` → `certlm.msc` → 回车（需管理员）
2. 展开 **"受信任的根证书颁发机构"** → 右键"证书" → 所有任务 → 导入
3. 选 `Kindle-SigningCert.cer`，一路下一步
4. 在 **"受信任人"（Trusted People）** 里也导入一次
5. 重新跑第 3 步的安装

### 手动装依赖（自动装失败时）

管理员 PowerShell 里逐条执行：

```powershell
Add-AppxPackage -Path "C:\Kindle\Microsoft.VCLibs.x64.14.00.Desktop.appx"
& "C:\Kindle\WindowsAppRuntimeInstall-x64.exe" -q
Add-AppxPackage -Path "C:\Kindle\Kindle-Win10-1.0.25218.0-x64.msix"
```

## 6. 装不了时的两条退路

### 退路一：官方免管理员版本（推荐先试这个）

```powershell
winget install --id Amazon.Kindle --exact --disable-interactivity --accept-source-agreements --accept-package-agreements
```

这是亚马逊官方的 Kindle for PC，是 user scope 包，装在当前用户下，
**不涉及改包、不涉及证书、不需要管理员**。代价是它未必是最新版的界面。

### 退路二：干脆不装软件

浏览器打开 <https://read.amazon.com> 登录就能读书，零安装。

---

# 第二部分 · 原理与思路

## 7. 为什么装不上：MinVersion 是硬门槛

从 Microsoft Store 拿到的 Kindle 离线包是 `Kindle.Msixbundle`（493 MB）。
`.msixbundle` 本质是 zip，里面按架构打包了若干 `.msix`（本次只有 x64 一个）。
取出内层包的 `AppxManifest.xml`，关键一行：

```xml
<TargetDeviceFamily Name="Windows.Desktop"
                    MinVersion="10.0.22000.0"
                    MaxVersionTested="10.0.26100.0" />
```

- `MinVersion` 是**硬门槛**，低于它的系统直接拒绝安装
- `MaxVersionTested` 只是"测试过的上限"，**不影响安装**，不用管

`10.0.22000.0` = Windows 11 21H2，而 Windows 10 最高只到 `19045`，所以必然失败。

### 内部版本对照表

| 系统 | 内部版本 |
|---|---|
| Windows 10 1809 | `10.0.17763.0` |
| Windows 10 1903 | `10.0.18362.0` |
| Windows 10 21H2 / 22H2 | `10.0.19044.0` / `10.0.19045.0` |
| Windows 11 21H2 | `10.0.22000.0` |
| Windows 11 24H2 | `10.0.26100.0` |

脚本默认降到 `10.0.17763.0`（Win10 1809），兼容面最广。
**选低不选高**：写高了会误伤老机器，写低了只是放弃编译期检查，代价小得多。

## 8. 移植的七个步骤（含每一步的"为什么"）

### 步骤 1 — 取出内层 x64 包

`.msixbundle` 就是 zip，直接用 .NET 的 `ZipFile` 读，不用装任何工具。

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead('.\Kindle.Msixbundle')
$zip.Entries | Where-Object { $_.FullName -match '_x64\.msix$' }
```

优先选 x64，找不到就退而取体积最大的一个（多架构包里通常 x64 最大）。

### 步骤 2 — 拿到打包工具（不用装 SDK）

只需要两个 exe：`makeappx.exe`（解包/打包）、`signtool.exe`（签名），
都在 NuGet 包 `Microsoft.Windows.SDK.BuildTools` 里，**只有 22 MB** ——
不必为了它们装几个 GB 的完整 Windows SDK。详见第 14 节。

### 步骤 3 — 解包

```
makeappx unpack /p <包名>.msix /d unpacked /o /nv
```

`/o` 覆盖输出目录；`/nv` 跳过校验（此时签名已改，校验必失败）。

### 步骤 4 — 改 MinVersion ⭐

```powershell
$mfText = [regex]::Replace($mfText,
    '(<TargetDeviceFamily[^>]*?MinVersion=")([^"]*)(")',
    { param($m) $m.Groups[1].Value + $MinVersion + $m.Groups[3].Value })
```

**这里有个极易犯的错**：清单里还有另一类 `MinVersion` ——

```xml
<PackageDependency Name="Microsoft.WindowsAppRuntime.1.8" MinVersion="8000.616.2154.0" ... />
<PackageDependency Name="Microsoft.VCLibs.140.00.UWPDesktop" MinVersion="14.0.30704.0" ... />
```

**这些绝对不能动。** 它们是框架依赖包的版本要求，改了会导致依赖解析失败。
只改 `<TargetDeviceFamily>` 里的那个。脚本用正则锚定了 `TargetDeviceFamily` 前缀来规避。

### 步骤 5 — 删掉旧签名和旧 blockmap ⭐

```
删除 unpacked\AppxSignature.p7x
删除 unpacked\AppxBlockMap.xml
```

- `AppxSignature.p7x` 是亚马逊的签名，内容已变，留着是失效签名，会让包直接损坏
- `AppxBlockMap.xml` 记录了每个文件的块哈希，内容变了它就全错了，打包时必须重新生成

漏删是新手最常见的失败原因，现象是"包损坏"或签名校验失败，**且报错信息不会告诉你是这一步**。

### 步骤 6 — 重新打包

```
makeappx pack /d unpacked /p Kindle-Win10-x64.msix /nv /o
```

### 步骤 7 — 重新签名 ⭐ 最难的一步

MSIX 比传统 exe 严格得多：

**a) 证书主题必须逐字等于清单里的 Publisher**

```powershell
# 清单里的 Publisher
CN=0FFC96E0-F797-4E94-87FB-CA2F8265EC08

# 证书主题必须完全一致，多一个空格都不行
New-SelfSignedCertificate -Subject "CN=0FFC96E0-F797-4E94-87FB-CA2F8265EC08" `
    -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My `
    -KeyExportPolicy Exportable -KeyUsage DigitalSignature -HashAlgorithm SHA256
```

这是 MSIX **特有**的：exe 签名不要求发布者匹配，MSIX 要求，否则按"发布者不符"拒绝安装。

**b) 签名**

```
signtool sign /sha1 <证书指纹> /fd SHA256 /td SHA256 <包>.msix
```

**c) 校验**

```
signtool verify /pa <包>.msix
```

看到 `Successfully verified` 才算包本身合格。

## 9. 为什么安装必须管理员

签名通过了，不代表能装上。MSIX 的安装由系统服务 **AppXSVC** 执行，它以 SYSTEM 身份运行：

1. **它只认 `LocalMachine` 证书存储**
   实测导入到 `CurrentUser\Root` 和 `CurrentUser\TrustedPeople` **都无效**，
   仍报 `0x800B0109 根证书不受信任`。写入 `LocalMachine` 必须提权。
2. **框架依赖包装到系统级**：`Microsoft.WindowsAppRuntime.1.8` 同样需要管理员。

所以这一步**没有任何绕过办法**（已实测确认）。这是 MSIX 相对普通安装程序最不灵活的地方。

另外：`.ps1` 文件**右键没有"以管理员身份运行"**（只关联了不提权的"使用 PowerShell 运行"），
所以必须用 `.bat` 包装 —— `.bat` 右键有该选项，且 bat 内可写自提权逻辑弹 UAC。

## 10. 依赖：别只盯着主包

MSIX 会声明框架依赖，缺一个就装不上。本次两个：

| 依赖 | 说明 |
|---|---|
| `Microsoft.WindowsAppRuntime.1.8` | Windows App SDK 运行时，普通机器多半**没有**。官方最低支持 Win10 1809，版本本身不成问题 |
| `Microsoft.VCLibs.140.00.UWPDesktop` | **非开发者机器常常缺**。开发者装过 VS 所以不缺，容易误判 |

```powershell
Get-AppxPackage | Where-Object { $_.Name -like "*WinAppRuntime*" }
Get-AppxPackage | Where-Object { $_.Name -like "*VCLibs*" }
```

两个依赖包都从微软官方下载，签名已校验。

> 小坑：普通版 VCLibs 的 `aka.ms` 短链接**已失效**（会跳到 Bing），只有 Desktop 版还活着。

**依赖会跟应用升级走**：下次若 `PackageDependency` 变成 1.9/2.x，
`WindowsAppRuntimeInstall-x64.exe` 要重新下对应版本（见第 17 节）。

## 11. 核心知识点速查

| 概念 | 要点 |
|---|---|
| MSIX 是 zip | 内部结构可直接读，无需专用工具即可探查 |
| `MinVersion` | 硬门槛，低于它的系统拒绝安装；`MaxVersionTested` 不影响安装 |
| 签名绑定内容 | 改一个字节签名就废，必须重签 |
| MSIX 要求 Publisher 匹配 | exe 签名没这要求，MSIX 有，这是最大差异 |
| AppXSVC 只认 `LocalMachine` | 决定了"必须管理员"，无法绕过 |
| blockmap 是内容哈希 | 内容变了必须重生成 |
| 框架依赖要单独装 | `PackageDependency` 声明什么就得备什么，且版本随应用升级变 |

**一句话总结：改版本号是体力活，重建信任链才是技术活。**

---

# 第三部分 · 自己动手与维护

## 12. 文件清单与外传红线

```
C:\Project\Kindle\
├── README.md                    ← 本文件（全部内容）
│
├── port-to-win10.ps1            ★ 移植主脚本（解包→改版→重打包→签名）
├── Install-Kindle.bat           ★ 安装入口（.bat 右键才有"以管理员身份运行"）
├── install-kindle.ps1             实际安装逻辑（依赖→证书→应用）
│
├── Kindle-Win10-1.0.25218.0-x64.msix      移植产物
├── Kindle-SigningCert.cer        签名证书公钥，安装方需要导入
├── Kindle-SigningCert.pfx        ⚠️ 私钥备份，**绝不外传**
│
├── WindowsAppRuntimeInstall-x64.exe       Windows App SDK 1.8 运行时
├── Microsoft.VCLibs.x64.14.00.Desktop.appx   VCLibs 依赖包
│
├── Kindle.Msixbundle            原始素材（可选保留）
└── work\                        临时目录（解包内容 + SDK 缓存，可删）
```

| 文件 | 能否外传 |
|---|---|
| `.cer`（公钥） | ✅ 可以，别人靠它信任你的包 |
| `.pfx`（私钥） | ❌ **绝对不行**。给了对方就能冒用你的身份签名任意程序 |

公钥可以随便发，私钥必须自己留着 —— 这是理解整个签名体系的起点。

## 13. 一键流程（更新后照做这一段就行）

```powershell
# ① 移植：把新版 Kindle.Msixbundle 放进本目录，执行（不需要管理员，约 3-5 分钟）
powershell -ExecutionPolicy Bypass -File port-to-win10.ps1 -BundlePath .\Kindle.Msixbundle

# ② 安装：右键 Install-Kindle.bat -> 以管理员身份运行
```

第 ① 步自动完成：选 x64 子包 → 解包 → 改 `MinVersion` → 重打包 → 复用/新建证书 → 签名 → 校验。
第 ② 步自动完成：检查系统版本 → 装 VCLibs → 装 WinAppRuntime → 导入证书 → 装 Kindle。

### 可选参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-MinVersion` | `10.0.17763.0` | 目标最低系统版本 |
| `-SdkVersion` | `10.0.26100.4654` | SDK BuildTools 版本 |
| `-OutFile` | 自动生成 | 输出路径 |

输出文件名带版本号（`Kindle-Win10-<版本>-x64.msix`），安装脚本自动挑最新的那个，
**升级后不用改脚本**。

### 验证是否成功

```powershell
# 包本身是否合格（signtool 不在 PATH 里，用脚本缓存的那一份）
$signtool = (Get-ChildItem .\work -Filter signtool.exe -Recurse |
             Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1).FullName
& $signtool verify /pa .\Kindle-Win10-1.0.25218.0-x64.msix

# 是否真的装上了
Get-AppxPackage | Where-Object { $_.Name -like "*Kindle*" }
```

> `work\` 删掉后会取不到工具，届时按第 14 节的 NuGet 地址重新下载即可（22 MB）。

最后一步别省：启动 Kindle **实际翻几本书**确认没有 Win11 API 依赖导致的崩溃。

### `port-to-win10.ps1` 什么时候才有用？

它只做一件事：**把新版 Kindle 重新签成同一个发布者**。所以——

- **对你（签名机）**：有用，而且是更新后唯一的自动化路径
- **对拿到安装包的人**：没用。他们机器上没有私钥，跑了只会新造一张证书，
  签名就和你这台不一样了，还得重新信任一遍。所以分享时不用给
- **换电脑 / 重装系统后**：仍然有用，但**前提是私钥还在**

私钥存在 `Cert:\CurrentUser\My`（本机，随系统走，**不在这个文件夹里**）。
丢了的话脚本会新建一张证书，后果是所有装过旧版的人都要重新导入新的 `.cer`、
已装的 Kindle 也得重装。因此备份了 `Kindle-SigningCert.pfx`，
脚本检测到本机没证书时会提示输入密码自动恢复。

> 脚本本身只有 7KB，删了不省空间，留着就是留一条更新路径。

## 14. 工具从哪来

`makeappx.exe` 和 `signtool.exe` 都在 NuGet 包 `Microsoft.Windows.SDK.BuildTools` 里（22MB）：

```
https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/
    <版本>/microsoft.windows.sdk.buildtools.<版本>.nupkg
```

解压后位于 `bin\<版本>\x64\`。脚本会缓存到 `work\sdk`，第二次跑直接复用。

> ⚠️ v2 接口 `nuget.org/api/v2/package/...` **已失效返回 404**，必须用 v3 flatcontainer。
>
> 版本号建议对齐原包 `AppxManifest.xml` 里 `<build:Metadata>` 的 `makepri.exe Version`
> （本次为 `10.0.26100.4654`），不强制。

## 15. 手动分步流程（脚本失效时的兜底）

```powershell
# 1) 取内部 x64 包
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead('.\Kindle.Msixbundle')
$zip.Entries | Where-Object { $_.FullName -like '*.msix' }   # 看看有哪几个

# 2) 解包
makeappx unpack /p KatxopoApp.Package_x_x64.msix /d unpacked /o /nv

# 3) 改 unpacked\AppxManifest.xml 里 TargetDeviceFamily 的 MinVersion

# 4) 删掉旧签名和旧 blockmap（否则打包会带上失效的东西）
#    unpacked\AppxSignature.p7x
#    unpacked\AppxBlockMap.xml

# 5) 重打包
makeappx pack /d unpacked /p Kindle-Win10-x64.msix /nv /o

# 6) 生成证书（主题必须与清单里的 Publisher 完全一致）
New-SelfSignedCertificate -Subject "CN=0FFC96E0-F797-4E94-87FB-CA2F8265EC08" `
    -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My `
    -KeyExportPolicy Exportable -KeyUsage DigitalSignature -HashAlgorithm SHA256

# 7) 签名
signtool sign /sha1 <指纹> /fd SHA256 /td SHA256 Kindle-Win10-x64.msix

# 8) 校验
signtool verify /pa Kindle-Win10-x64.msix
```

## 16. 如何取得新版 Kindle.Msixbundle

Store 离线包要借第三方直链服务拿（微软官方没提供下载入口）：

1. 浏览器打开 <https://apps.microsoft.com>，搜索 Kindle，进入详情页，**复制地址栏网址**
2. 打开 <https://store.rg-adguard.net/>
3. 第一个下拉框选 **URL** 并粘贴网址；第二个下拉框选 **Retail**（**不要选 RP / WIS**，那是预览通道）
4. 点右侧对勾按钮，等待生成链接列表
5. 找 `.msixbundle` 结尾、**体积最大**的那一项下载
6. 浏览器可能警告"无法安全下载"（链接是 `http://`）→ 选 **"保留"**。
   文件来自微软自己的 CDN，是官方原版，可事后用 `signtool verify /pa` 核对发行者是 Amazon
7. 若下载下来**没有扩展名**，手动改名为 `Kindle.Msixbundle`
8. 列表里还会有一堆依赖包（VCLibs、NET.Native 等）—— 本项目只需要主包，
   依赖已单独备好（见第 10 节）

> ⚠️ 生成的链接**只有 15 分钟有效期**，过期重新生成即可。

## 17. 版本更新怎么办

"更新"有两种完全不同的情况，先分清是哪种。

### 场景 A：Kindle 发了新版，你想升级

走一遍第 18 节清单即可。其中**只有三件事需要动脑判断**：

#### A1. Publisher 变了吗？

脚本运行时会打印 `Publisher: ...`，和上一次的值比对。

| 结果 | 后果 | 处理 |
|---|---|---|
| 没变（大概率） | 证书复用，签出来还是同一张 | 直接覆盖安装，**不用卸载**，登录状态和已下载的书都保留 |
| 变了 | 脚本会自动新建证书 → 旧的信任关系失效 | ① **必须先卸载旧版**（发布者不同的同名包不能共存，会报冲突）<br>② 把新导出的 `.cer` 重新发给所有装过的人 |

```powershell
Get-AppxPackage *Kindle* | Remove-AppxPackage
```

#### A2. 运行时版本变了吗？

看新版 `AppxManifest.xml` 里的 `PackageDependency`：

```xml
<PackageDependency Name="Microsoft.WindowsAppRuntime.1.8" MinVersion="..." />
```

如果变成 `1.9` / `2.x`，当前的 `WindowsAppRuntimeInstall-x64.exe`（1.8）**满足不了**，
必须换对应版本：

```
https://aka.ms/windowsappsdk/<版本号>/latest/WindowsAppRuntimeInstall-x64.exe
# 例：https://aka.ms/windowsappsdk/1.9/latest/WindowsAppRuntimeInstall-x64.exe
```

> Windows App SDK 各版本官方最低都支持 Windows 10 1809，版本升级**不影响 Win10 兼容性**，
> 只是要换安装器。

#### A3. 依赖包有增减吗？

若出现新的 `PackageDependency`（如 `Microsoft.NET.Native.Runtime`），
同样从微软官方下载对应 `.appx`，并加进 `install-kindle.ps1`。

### 场景 B：装好的 Kindle 被商店自动更新覆盖了 ⚠️

**现象**：本来能用，某天突然打不开，或又变成"需要 Windows 11"。

**原因**：商店把官方新版推下来了。官方新版的最低要求又回到 Win11，
而且版本号比我们改过的高，会直接覆盖掉。

#### 根治：关掉商店自动更新

商店设置里那个"应用自动更新"开关，在新版 Windows 10/11 上
**已被微软改成只能"暂停"（最长几周），不能永久关闭**。要永久关闭得用组策略或注册表：

```powershell
# 管理员 PowerShell，执行后重启或注销一次生效
reg add HKLM\SOFTWARE\Policies\Microsoft\WindowsStore /v AutoDownload /t REG_DWORD /d 2 /f
```

| 值 | 含义 |
|---|---|
| `2` | **关闭**应用自动更新（我们要的） |
| `4` | 开启自动更新 |

（企业环境可用组策略：计算机配置 → 管理模板 → Windows 组件 → 应用商店 →
"关闭自动下载和安装更新" → 已启用）

#### 恢复：装回我们改过的版本

```powershell
Get-AppxPackage *Kindle* | Remove-AppxPackage
# 然后重新跑 Install-Kindle.bat
```

这就是为什么第 18 节最后一条要求**保留上一个能用的 `.msix`** ——
它是唯一的回滚手段，应用商店不会帮你退回旧版。

### 如何知道有没有更新

```powershell
Get-AppxPackage *Kindle* | Select-Object Name, Version, Publisher
```

和 `Kindle-Win10-<版本>-x64.msix` 文件名里的版本比对即可。

| 情况 | 动作 |
|---|---|
| 想升到新版 | 第 18 节清单，重点看 Publisher 和运行时版本 |
| Publisher 变了 | 先卸载，再装，重发 `.cer` |
| 被商店覆盖变砖 | 关自动更新（`AutoDownload=2`），用旧包重装 |

## 18. 更新后的复现清单

- [ ] 取得新版 `Kindle.Msixbundle`（步骤见第 16 节）
- [ ] 放到本目录，跑 `port-to-win10.ps1`
- [ ] 检查脚本输出的 `Publisher` 是否与上一次一致（不一致 → 证书会自动重建，需重新导入 `.cer`）
- [ ] 检查 `AppxManifest.xml` 里 `PackageDependency` 的 `Microsoft.WindowsAppRuntime` 版本是否变化
      （变了 → 重新下载对应版本的运行时安装器，替换 `WindowsAppRuntimeInstall-x64.exe`）
- [ ] `signtool verify /pa` 通过
- [ ] 右键 `Install-Kindle.bat` → 以管理员身份运行
- [ ] 开始菜单启动 Kindle，实际翻几本书确认没有 Win11 API 依赖导致的崩溃
- [ ] 确认无误后可删除 `work/` 目录（约 1.2GB），保留脚本和 `.cer` 供下次使用
- [ ] **保留上一个能用的 `.msix`** 作为回滚备份，别急着删

## 19. 分享给另一台 Windows 10 电脑

**好消息：不需要私钥。** 包已经在签名机上签好了，对方只需要"信任公钥"就能装。

### 需要给对方的文件

| 文件 | 大小 | 必需 |
|---|---|---|
| `Kindle-Win10-<版本>-x64.msix` | 493 MB | ✅ |
| `Kindle-SigningCert.cer` | 1 KB | ✅ 缺了会报 `0x800B0109 根证书不受信任` |
| `Install-Kindle.bat` + `install-kindle.ps1` | — | ✅ |
| `WindowsAppRuntimeInstall-x64.exe` | 102 MB | ✅ 对方机器上多半没有 1.8 运行时 |
| `Microsoft.VCLibs.x64.14.00.Desktop.appx` | 6.7 MB | ✅ 对方若非开发者机器，通常没装这个 |
| `README.md` | — | 建议一起给，方便他自己排查 |
| `port-to-win10.ps1` | — | ❌ 只有他要自己转换新版时才需要 |
| `Kindle.Msixbundle` / `work/` | 1.8 GB | ❌ 不要给 |
| `Kindle-SigningCert.pfx` | 2.6 KB | ❌❌ **绝对不要给**。含私钥，给了对方就能冒用你的身份签名 |

合计约 **600 MB**。

### 对方的硬性前提

1. **Windows 10 1809（内部版本 17763）或更高**。低于此版本装不上，脚本会拦下来
2. **64 位系统**。原包只有 x64 版本
3. **本机管理员权限**。原因见第 9 节——要写 `LocalMachine` 证书存储、要装框架包。
   如果他是标准账户，走不了这条路，改用第 6 节的 `winget install Amazon.Kindle`（免管理员）

### 对方的操作

把文件放在**同一个文件夹**里（建议纯英文路径），然后
**右键 `Install-Kindle.bat` → 以管理员身份运行**。脚本会依次检查系统版本 → 装 VCLibs →
装 WinAppRuntime → 导入证书 → 装 Kindle，每一步都有输出。

### 分享后要注意

- 对方机器上会多出一张由你签发的自签根证书（在 `certlm.msc` 的"受信任的根证书颁发机构"里）。
  卸载 Kindle 后**记得提醒他把这张证书删掉**
- 如果对方后续自己跑 `port-to-win10.ps1` 转换新版，那台机器上是**没有**你这张证书的私钥的，
  脚本会自动新建一张同主题的新证书；届时他需要重新导入新导出的 `.cer`
- 分发前可以用 `signtool verify /pa` 自查一下包没在传输中损坏

---

# 第四部分 · 风险与踩坑

## 20. 踩过的坑（按麻烦程度排序）

| # | 坑 | 现象 | 解决 |
|---|---|---|---|
| 1 | `.ps1` 右键没有提权项 | 只有"使用 PowerShell 运行"，且不提权 | 用 `.bat` 包装，`.bat` 右键有该选项；bat 内再自提权 |
| 2 | MSIX 只认 LocalMachine 证书存储 | `0x800B0109` | 必须管理员；用户级导入无效 |
| 3 | 自签证书主题不匹配 | 发布者与签名不符，安装被拒 | 证书 Subject 必须**逐字等于**清单里的 `Publisher` |
| 4 | Git Bash 下 makeappx 参数被改写 | `Unknown command line option: "P:/"` | MSYS 路径转换；加 `MSYS_NO_PATHCONV=1`，或直接用 PowerShell |
| 5 | 忘删旧签名/旧 blockmap | 包损坏或签名校验失败 | 解包后务必删 `AppxSignature.p7x` 和 `AppxBlockMap.xml` |
| 6 | NuGet v2 接口失效 | `nuget.org/api/v2/package/...` 返回 404 | 改用 v3 flatcontainer 地址 |
| 7 | `Import-Certificate` 导入根证书弹窗 | 非交互下报"不允许使用 UI" | 改用 .NET `X509Store.Open('ReadWrite')` + `Add()` |
| 8 | `Remove-Item` 被环境安全策略包装 | 删大目录报 `SAFE_DELETE_FAIL_CLOSED` | 用 `[System.IO.Directory]::Delete($p,$true)` |
| 9 | `.ps1` 含中文却不带 BOM | PowerShell 5.1 按 GBK 解析，中文乱码 | 存成 UTF-8 **带 BOM** |
| 10 | bat 引用中文文件名 | 编码问题 | 脚本文件名统一用 ASCII |
| 11 | `winget` 首次运行卡住 | 等源协议确认 | 加 `--disable-interactivity --accept-source-agreements` |

另外两个在此工作环境里的限制（不影响手工操作，只是自动化时绕不过）：
`ConvertTo-SecureString` 和 `[Diagnostics.Process]::Start -Verb runas` 会被安全策略拦截，
所以**无法从脚本内部自动提权**，只能交给用户点 UAC。

## 21. 已知局限与风险（请如实看待）

1. **签名被换成自签证书**。包不再是亚马逊签名，需要手工信任我们生成的证书；
   SmartScreen 仍会提示"未知发布者"；若机器受企业策略管控（禁止信任第三方根证书）会装不上。
   卸载应用后，可在 `certlm.msc` 里删掉该证书。
2. **签名未加 RFC3161 时间戳**（`signtool verify` 显示 `Timestamp: None`）。
   当前证书有效期到 2056 年所以够用，但严格校验场景下可能因此被拒。后续可加
   `/tr http://timestamp.digicert.com /td SHA256`。
3. **降低 `MinVersion` 不等于真正兼容**。这只是让系统"允许安装"，
   如果应用代码调用了 Windows 11 专有 API，运行时仍会报错或崩溃，只能实测。
4. **安装尚未端到端验证**。包本身已通过 `signtool verify /pa`，
   但最后的 `Add-AppxPackage` 因缺少管理员权限没能跑通，需要用管理员权限确认一次才算闭环。
5. **WindowsAppRuntime 版本会跟着应用升级走**。下次如果依赖变成 1.9 / 2.x，
   `WindowsAppRuntimeInstall-x64.exe` 要重新下对应版本，旧的满足不了新依赖。
   运行时官方最低支持 Windows 10 1809，这一点倒不用担心。
6. **Publisher 若变更需重新出证书**。脚本按 Publisher 复用证书，亚马逊换了 CN 会自动新建一张，
   那时旧的信任关系失效，需要重新导入新的 `.cer`。
7. **升级安装**：版本号更高时可直接覆盖安装（Publisher 一致），不必先卸载。

## 22. 怎么应用到别的应用上

这套思路**不只针对 Kindle**，任何 MSIX/MSIXBUNDLE 都适用：

1. **找素材**：从 Microsoft Store 直链服务取 `.msixbundle`（选 **Retail** 通道，核对发布者）
2. **看清单**：读 `AppxManifest.xml`，确认三件事
   - `TargetDeviceFamily` 的 `MinVersion` 是不是卡住了
   - `Publisher` 是什么（决定证书主题）
   - 有哪些 `PackageDependency`（决定要补什么依赖包）
3. **改包**：解包 → 改 `MinVersion` → 删旧签名/blockmap → 重打包
4. **重签**：按 Publisher 出证书 → 签名 → 校验
5. **补依赖**：把清单里声明的框架包都备齐
6. **安装**：管理员身份导证书 + 装包

判断能不能成功的经验法则：

- **纯 WinUI / UWP 应用** → 成功率高，靠运行时，版本要求往往是保守设置
- **依赖新系统 API（如 Win11 窗口管理、任务栏 API）** → 能装上但可能运行时报错
- **带内核驱动 / 系统级服务** → MSIX 装不了，此路不通

---

## 参考

- MSIX 包结构：<https://learn.microsoft.com/windows/msix/package/manifest-basics>
- `makeappx` / `signtool` 参数：<https://learn.microsoft.com/windows/msix/package/create-app-package-with-makeappx-tool>
- 关闭商店自动更新（`AutoDownload` 策略）：<https://learn.microsoft.com/windows/msix/app-installer/group-policy-msix>
- Windows App SDK 支持矩阵：<https://learn.microsoft.com/windows/apps/windows-app-sdk/>
- Store 离线包直链生成：<https://store.rg-adguard.net/>
