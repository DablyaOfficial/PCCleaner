<#
    PCCleaner - мини-программа для очистки ПК от ненужных программ.
    Сканирует: приложения Windows (Appx/Store, включая предустановленные)
               и классические программы (Win32, из реестра).
    Запуск:    PCCleaner.exe  (или: powershell -ExecutionPolicy Bypass -File PCCleaner.ps1)
    Проверка без GUI и без удаления:  PCCleaner.ps1 -ScanOnly
#>
param([switch]$ScanOnly)

$ErrorActionPreference = 'Continue'

# ---------- Права администратора ----------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$script:IsAdmin = (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $script:IsAdmin -and -not $ScanOnly -and -not $env:PCC_SELFTEST) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList `
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Для удаления программ нужны права администратора. Запуск отменён.',
            'PCCleaner', 'OK', 'Warning')
    }
    exit
}

# Папка программы: рядом со скриптом, а при запуске из exe - рядом с exe
$script:AppDir = $PSScriptRoot
if (-not $script:AppDir) { $script:AppDir = $PCCAppDir }
if (-not $script:AppDir) { $script:AppDir = $env:TEMP }
$script:LogFile = Join-Path $script:AppDir 'PCCleaner.log'

# ---------- Списки классификации ----------
# Appx: известный "мусор" (регулярные выражения по имени пакета)
$BloatAppx = @(
    '^Microsoft\.Bing', '^Microsoft\.GetHelp$', '^Microsoft\.Getstarted$',
    '^Microsoft\.MicrosoftOfficeHub$', '^Microsoft\.MicrosoftSolitaireCollection$',
    '^Microsoft\.People$', '^Microsoft\.PowerAutomateDesktop$', '^Microsoft\.Todos$',
    '^Microsoft\.WindowsFeedbackHub$', '^Microsoft\.WindowsMaps$',
    '^Microsoft\.ZuneMusic$', '^Microsoft\.ZuneVideo$', '^Microsoft\.YourPhone$',
    '^Clipchamp\.', '^MicrosoftTeams$', '^MSTeams$', '^Microsoft\.549981C3F5F10$',
    '^Microsoft\.MixedReality', '^Microsoft\.3DBuilder$', '^Microsoft\.Microsoft3DViewer$',
    '^Microsoft\.SkypeApp$', '^Microsoft\.OutlookForWindows$', '^Microsoft\.Windows\.DevHome$',
    '^MicrosoftCorporationII\.QuickAssist$', '^MicrosoftCorporationII\.MicrosoftFamily$',
    '^Microsoft\.Copilot$', '^Microsoft\.MicrosoftStickyNotes$', '^Microsoft\.Messaging$',
    '^Microsoft\.OneConnect$', '^Microsoft\.Print3D$', '^Microsoft\.Wallet$',
    '^Microsoft\.News$', '^Microsoft\.Office\.OneNote$', '^Microsoft\.MicrosoftJournal$',
    '^Microsoft\.Whiteboard$', '^Microsoft\.WindowsCommunicationsApps$',
    '^MicrosoftWindows\.Client\.WebExperience$', '^Microsoft\.StartExperiencesApp$',
    '^MicrosoftWindows\.CrossDevice$', '^Microsoft\.Advertising',
    '^king\.com\.', 'CandyCrush', '^SpotifyAB\.', '^Facebook\.', 'Instagram', 'TikTok',
    '^Disney\.', 'Netflix', '^AmazonVideo\.', '^Amazon\.com\.', 'Duolingo', 'LinkedIn',
    'McAfee', 'Norton', 'ExpressVPN', 'Booking', 'WildTangent', 'Twitter',
    'BubbleWitch', 'FarmVille', 'RoyalRevolt', 'HiddenCity', 'MarchofEmpires',
    'Dropbox.*Promotion', 'PicsArt', 'Phototastic', 'Flipboard', 'Shazam', 'Viber.*Promo',
    'Asphalt', 'AdobePhotoshopExpress', 'Plex$', 'Hulu', 'Pandora', 'iHeartRadio'
)
# Appx: защищено от удаления (нужно для работы Windows / магазина / других приложений)
$ProtectedAppx = @(
    '^Microsoft\.WindowsStore$', '^Microsoft\.StorePurchaseApp$', '^Microsoft\.DesktopAppInstaller$',
    '^Microsoft\.VCLibs', '^Microsoft\.NET\.', '^Microsoft\.UI\.Xaml', '^Microsoft\.WindowsAppRuntime',
    'WinAppRuntime', '^Microsoft\.WidgetsPlatformRuntime$','^Microsoft\.DirectX', '^Microsoft\.Services\.Store',
    '^Microsoft\.SecHealthUI$', '^Microsoft\.Windows\.', '^Windows\.', '^MicrosoftWindows\.Client\.(CBS|Core|AIX|LKG|FileExp|OOBE|Photon)',
    '^Microsoft\.AAD', '^Microsoft\.AccountsControl', '^Microsoft\.LockApp', '^Microsoft\.Win32WebViewHost',
    '^Microsoft\.MicrosoftEdge', '^Microsoft\.ECApp', '^Microsoft\.CredDialogHost', '^Microsoft\.AsyncTextService',
    '^Microsoft\.BioEnrollment', '^Microsoft\.LanguageExperiencePack', '^MicrosoftWindows\.UndockedDevKit',
    '^Microsoft\.ApplicationCompatibilityEnhancements', '^Microsoft\.StorePurchaseApp', '^NcsiUwpApp', '^c5e2524a', '^E2A4F912', '^F46D4000', '^1527c705'
)
# Appx: удалять можно, но осторожно (кодеки, драйверные панели, игровые сервисы)
$CautionAppx = @(
    'Extension', 'Codec', '^NVIDIACorp', '^Realtek', '^AppUp\.Intel', '^AdvancedMicroDevices',
    '^Dolby', '^DTS', '^Synaptics', '^ELAN', '^Microsoft\.Xbox', '^Microsoft\.GamingApp$',
    '^Microsoft\.GamingServices$', '^Microsoft\.XboxGam', '^Microsoft\.WindowsTerminal$',
    '^Microsoft\.Windows(Calculator|Notepad|Camera|SoundRecorder|Alarms)$', '^Microsoft\.Paint$',
    '^Microsoft\.ScreenSketch$', '^Microsoft\.Windows\.Photos$', '^Microsoft\.SecHealthUI$'
)
# Win32: известный "мусор" (по названию или издателю)
$BloatWin32 = @(
    'McAfee', 'Norton', 'WildTangent', 'WebAdvisor', 'Booking\.com', 'ExpressVPN',
    'Dropbox.*(Promotion|Offer)', 'Mail\.Ru', 'Спутник', 'Амиго', 'Amigo', 'Guard@Mail',
    'Кнопка .?Яндекс', 'Менеджер браузеров', 'Элементы Яндекса', 'Яндекс\.Бар', 'Ask Toolbar',
    'Toolbar', 'Driver ?Booster', 'DriverPack', 'Reimage', 'PC ?Optimizer', 'Registry ?(Cleaner|Booster)',
    'SpeedUp', 'MyPC ?Backup', 'Avast Secure Browser', 'Opera GX.*Promo', 'CyberLink.*(Trial|Demo)',
    'Candy Crush', 'Bonjour', 'Hao123', 'Baidu', '360 Total', 'Conduit', 'Babylon', 'Search Protect',
    'uBar', 'Zaxar', 'MediaGet', 'Оптимизатор', 'Trial', 'Пробная версия'
)
# Win32: удалять можно, но осторожно (драйверы, библиотеки, компоненты)
$CautionWin32 = @(
    'Intel', 'NVIDIA', '\bAMD\b', 'Advanced Micro Devices', 'Realtek', 'Qualcomm', 'MediaTek',
    'Synaptics', 'Driver', 'Драйвер', 'Visual C\+\+', '\.NET', 'WebView2', 'Windows SDK', 'DirectX',
    'Microsoft Edge', 'Update Health', 'Vulkan', 'OpenAL', 'PhysX', 'Chipset', 'Bluetooth',
    'Windows Software Development', 'Windows Driver', 'Redistributable', 'Runtime'
)

function Test-Any([string]$text, [string[]]$patterns) {
    foreach ($p in $patterns) { if ($text -match $p) { return $true } }
    return $false
}

# ---------- Получение "человеческого" имени Appx ----------
Add-Type -Namespace PCC -Name Native -MemberDefinition @'
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
public static extern int SHLoadIndirectString(string pszSource, System.Text.StringBuilder pszOutBuf, int cchOutBuf, IntPtr ppvReserved);
'@

function Get-AppxFriendlyName($pkg) {
    try {
        $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifest)) { return $pkg.Name }
        $dn = ([xml](Get-Content -LiteralPath $manifest -Raw -Encoding UTF8)).Package.Properties.DisplayName
        if (-not $dn) { return $pkg.Name }
        if ($dn -notmatch '^ms-resource:') { return $dn }
        $key = $dn -replace '^ms-resource:', ''
        if ($key.StartsWith('//')) { $candidates = @("ms-resource:$key") }
        else {
            $key = $key.TrimStart('/')
            $candidates = @("ms-resource://$($pkg.Name)/resources/$key", "ms-resource://$($pkg.Name)/$key")
        }
        foreach ($c in $candidates) {
            $sb = New-Object System.Text.StringBuilder 512
            $hr = [PCC.Native]::SHLoadIndirectString("@{$($pkg.PackageFullName)?$c}", $sb, $sb.Capacity, [IntPtr]::Zero)
            if ($hr -eq 0 -and $sb.Length -gt 0) { return $sb.ToString() }
        }
    } catch { }
    return $pkg.Name
}

# ---------- Сканирование ----------
function New-Item2($name, $publisher, $version, $kind, $category, $note, $sizeKB, $id) {
    [pscustomobject]@{
        Name = $name; Publisher = $publisher; Version = $version; Kind = $kind
        Category = $category; Note = $note; SizeKB = $sizeKB; Id = $id
        AppxName = $null; Uninstall = $null; Quiet = $null; MsiGuid = $null
        Protected = ($category -eq 'Защищено'); Checked = $false
    }
}

function Get-AppxItems {
    $pkgs = $null
    if ($script:IsAdmin) {
        try { $pkgs = Get-AppxPackage -AllUsers -ErrorAction Stop } catch { $pkgs = $null }
    }
    if (-not $pkgs) { $pkgs = Get-AppxPackage }
    foreach ($p in $pkgs) {
        $note = ''
        if ($p.IsFramework)                       { $cat = 'Защищено'; $note = 'Библиотека, нужна другим приложениям' }
        elseif ($p.NonRemovable)                  { $cat = 'Защищено'; $note = 'Windows запрещает удаление' }
        elseif ("$($p.SignatureKind)" -eq 'System') { $cat = 'Защищено'; $note = 'Системный компонент Windows' }
        elseif ($p.IsResourcePackage -or $p.IsBundle) { continue }
        elseif (Test-Any $p.Name $ProtectedAppx)  { $cat = 'Защищено'; $note = 'Нужно для работы Windows/Магазина' }
        elseif (Test-Any $p.Name $BloatAppx)      { $cat = 'Мусор'; $note = 'Можно смело удалять' }
        elseif (Test-Any $p.Name $CautionAppx)    { $cat = 'Осторожно'; $note = 'Кодек/драйвер/полезная утилита' }
        elseif ($p.Name -match '^(Microsoft|MicrosoftWindows|MicrosoftCorporationII)\.') {
            $cat = 'Предустановлено'; $note = 'Приложение Microsoft из комплекта Windows'
        }
        else { $cat = 'Программа'; $note = 'Приложение из Магазина' }

        $pub = ($p.Publisher -replace '^CN=', '') -replace ',.*$', ''
        if ($p.Name -match '^(Microsoft|Clipchamp)') { $pub = 'Microsoft Corporation' }
        elseif ($pub -match '^[0-9A-Fa-f]{8}-') { $pub = '' }
        $it = New-Item2 (Get-AppxFriendlyName $p) $pub "$($p.Version)" 'Appx' $cat $note 0 $p.PackageFullName
        $it.AppxName = $p.Name
        if ($it.Name -ne $p.Name) { $it.Note = "$note  [$($p.Name)]" }
        $it
    }
}

function Get-Win32Items {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $seen = @{}
    foreach ($root in $roots) {
        foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $v = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $v -or -not $v.DisplayName) { continue }
            $name = "$($v.DisplayName)".Trim()
            $dedupe = "$name|$($v.DisplayVersion)"
            if ($seen.ContainsKey($dedupe)) { continue }
            $seen[$dedupe] = $true

            $un = "$($v.UninstallString)".Trim()
            $quiet = "$($v.QuietUninstallString)".Trim()
            $guid = $null
            if ($v.WindowsInstaller -eq 1 -or $un -match 'msiexec') {
                if ($k.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $guid = $k.PSChildName }
                elseif ($un -match '(\{[0-9A-Fa-f\-]{36}\})') { $guid = $Matches[1] }
            }
            $text = "$name $($v.Publisher)"
            $note = ''
            if (-not $un -and -not $quiet -and -not $guid) { $cat = 'Защищено'; $note = 'Нет деинсталлятора' }
            elseif (Test-Any $text $BloatWin32)            { $cat = 'Мусор'; $note = 'Похоже на навязанное/рекламное ПО' }
            elseif ($v.SystemComponent -eq 1)              { $cat = 'Осторожно'; $note = 'Скрытый системный компонент' }
            elseif (Test-Any $text $CautionWin32)          { $cat = 'Осторожно'; $note = 'Драйвер/библиотека/компонент' }
            else                                           { $cat = 'Программа' }

            $size = 0
            if ($v.EstimatedSize) { try { $size = [int64]$v.EstimatedSize } catch { $size = 0 } }
            $it = New-Item2 $name "$($v.Publisher)" "$($v.DisplayVersion)" 'Win32' $cat $note $size $k.PSPath
            $it.Uninstall = $un; $it.Quiet = $quiet; $it.MsiGuid = $guid
            $it
        }
    }
}

function Get-AllItems {
    $order = @{ 'Мусор' = 0; 'Предустановлено' = 1; 'Программа' = 2; 'Осторожно' = 3; 'Защищено' = 4 }
    @(Get-AppxItems) + @(Get-Win32Items) |
        Sort-Object @{ Expression = { $order[$_.Category] } }, Name
}

# ---------- Автозапуск: сканирование ----------
function Get-ExePath([string]$cmd) {
    if (-not $cmd) { return '' }
    $c = [Environment]::ExpandEnvironmentVariables($cmd).Trim()
    if ($c -match '^"([^"]+)"') { return $Matches[1] }
    if ($c -match '^(.+?\.(exe|bat|cmd|com|vbs|js|ps1|scr|msc))(\s|$)') { return $Matches[1] }
    return ($c -split '\s+')[0]
}

function Get-Company([string]$path) {
    try {
        if ($path -and [IO.Path]::IsPathRooted($path) -and (Test-Path -LiteralPath $path)) {
            return "$([Diagnostics.FileVersionInfo]::GetVersionInfo($path).CompanyName)".Trim()
        }
    } catch { }
    return ''
}

function Get-ApprovedState([string]$key, [string]$name) {
    try {
        $rk = Get-Item -LiteralPath $key -ErrorAction Stop
        $b = $rk.GetValue($name)
        if ($b -is [byte[]] -and $b.Length -gt 0 -and ($b[0] -band 1)) { return 'Отключено' }
    } catch { }
    return 'Включено'
}

function New-AutoItem($name, $kind, $source, $status, $command, $note, $hidden) {
    $exe = Get-ExePath $command
    $missing = $false
    try { $missing = [bool]($exe -and [IO.Path]::IsPathRooted($exe) -and -not (Test-Path -LiteralPath $exe)) } catch { $missing = $false }
    if ($missing) { $note = "Файл не найден. $note" }
    [pscustomobject]@{
        Name = $name; Kind = $kind; Source = $source; Status = $status; Command = $command
        Company = (Get-Company $exe); Note = $note; Hidden = $hidden; Missing = $missing
        ApprovedKey = $null; ValueName = $null; TaskPath = $null; TaskName = $null; ServiceName = $null
        Checked = $false
    }
}

function Get-AutorunItems {
    $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    # 1) Реестр: разделы Run
    $runKeys = @(
        @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKLM:\$approved\Run"; Src = 'Реестр (все пользователи)' },
        @{ Key = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKLM:\$approved\Run32"; Src = 'Реестр (все пользователи, 32 бит)' },
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKCU:\$approved\Run"; Src = 'Реестр (текущий пользователь)' }
    )
    foreach ($r in $runKeys) {
        $rk = Get-Item -LiteralPath $r.Key -ErrorAction SilentlyContinue
        if (-not $rk) { continue }
        foreach ($vn in $rk.GetValueNames()) {
            if (-not $vn) { continue }
            $it = New-AutoItem $vn 'Reg' $r.Src (Get-ApprovedState $r.Appr $vn) "$($rk.GetValue($vn))" 'Запуск при входе в систему' $false
            $it.ApprovedKey = $r.Appr; $it.ValueName = $vn
            $it
        }
    }
    # 2) Папки автозагрузки
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup'); Appr = "HKCU:\$approved\StartupFolder"; Src = 'Папка автозагрузки (пользователь)' },
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Appr = "HKLM:\$approved\StartupFolder"; Src = 'Папка автозагрузки (общая)' }
    )
    $shell = $null
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $f.Path -File -Force -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq 'desktop.ini') { continue }
            $target = $file.FullName
            if ($file.Extension -eq '.lnk') {
                try {
                    if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                    $sc = $shell.CreateShortcut($file.FullName)
                    if ($sc.TargetPath) { $target = ('"{0}" {1}' -f $sc.TargetPath, $sc.Arguments).Trim() }
                } catch { }
            }
            $it = New-AutoItem $file.BaseName 'Folder' $f.Src (Get-ApprovedState $f.Appr $file.Name) $target 'Запуск при входе в систему' $false
            $it.ApprovedKey = $f.Appr; $it.ValueName = $file.Name
            $it
        }
    }
    # 3) Планировщик заданий (всё, кроме заданий самой Windows)
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        if ($t.TaskPath -like '\Microsoft\*') { continue }
        $kinds = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName })
        $when = @()
        if ($kinds -contains 'MSFT_TaskLogonTrigger') { $when += 'при входе в систему' }
        if ($kinds -contains 'MSFT_TaskBootTrigger') { $when += 'при загрузке Windows' }
        if (@($kinds | Where-Object { $_ -notin 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' }).Count -gt 0) { $when += 'по расписанию/событию' }
        if ($when.Count -eq 0) { $when = @('только вручную') }
        $a = @($t.Actions)[0]
        $cmd = ''
        if ($a -and $a.Execute) { $cmd = ("$($a.Execute) $($a.Arguments)").Trim() }
        if ("$($t.State)" -eq 'Disabled') { $st = 'Отключено' } else { $st = 'Включено' }
        $hidden = ($when[0] -ne 'только вручную')
        $it = New-AutoItem $t.TaskName 'Task' 'Планировщик заданий' $st $cmd ("Скрытый запуск: " + ($when -join ', ') + '. Не виден в диспетчере задач') $hidden
        $it.TaskPath = $t.TaskPath; $it.TaskName = $t.TaskName
        $it
    }
    # 4) Службы сторонних программ
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $exe = Get-ExePath $s.PathName
        if (-not $exe -or $exe -match '\\svchost\.exe$') { continue }
        $co = Get-Company $exe
        if ($co -match 'Microsoft') { continue }
        # Системные службы без сведений о компании (lsass, OpenSSH и т.п.) не показываем
        if (-not $co -and $exe -like "$env:windir\System32\*" -and $exe -notlike '*\DriverStore\*') { continue }
        switch ("$($s.StartMode)") {
            'Auto'     { $st = 'Включено' }
            'Disabled' { $st = 'Отключено' }
            default    { $st = 'Вручную' }
        }
        $note = 'Фоновая служба. Не видна в диспетчере задач на вкладке автозагрузки'
        if ("$($s.State)" -eq 'Running') { $note = "Сейчас работает. $note" }
        if (Test-Any "$($s.DisplayName) $exe" $CautionWin32) { $note = "Осторожно: похоже на драйвер. $note" }
        $name = "$($s.DisplayName)"; if (-not $name) { $name = $s.Name }
        $it = New-AutoItem $name 'Service' 'Служба' $st "$($s.PathName)" $note ($st -eq 'Включено')
        $it.ServiceName = $s.Name
        $it
    }
}

# ---------- Режим проверки без GUI ----------
if ($ScanOnly) {
    $auto = @(Get-AutorunItems)
    "Автозапуск: $($auto.Count)"
    $auto | Group-Object Source | ForEach-Object { '  {0,-36} {1}' -f $_.Name, $_.Count }
    $auto | Format-Table Source, Status, Name, Company -AutoSize | Out-String -Width 200

    $all = Get-AllItems
    "Всего найдено: $($all.Count)  (администратор: $script:IsAdmin)"
    $all | Group-Object Category | ForEach-Object { '  {0,-16} {1}' -f $_.Name, $_.Count }
    $all | Group-Object Kind | ForEach-Object { '  {0,-16} {1}' -f $_.Name, $_.Count }
    ''
    $all | Where-Object { $_.Category -in 'Мусор', 'Предустановлено' } |
        Format-Table Category, Kind, Name, Publisher -AutoSize | Out-String -Width 200
    exit
}

# ---------- Удаление ----------
function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
    $script:txtLog.AppendText($line + "`r`n")
    try { Add-Content -LiteralPath $script:LogFile -Value ((Get-Date -Format 'yyyy-MM-dd ') + $line) -Encoding UTF8 } catch { }
    [System.Windows.Forms.Application]::DoEvents()
}

function Remove-AppxItem($it) {
    # Сначала убираем из образа, чтобы приложение не вернулось у новых пользователей.
    # Делается до удаления пакета: Remove-AppxPackage -AllUsers сам снимает предустановку,
    # и повторная попытка после него даёт ложную ошибку "путь не найден".
    $provFailed = @()
    foreach ($pp in ($script:Provisioned | Where-Object { $_.DisplayName -eq $it.AppxName })) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null }
        catch { $provFailed += $pp.PackageName }
    }
    try {
        Remove-AppxPackage -Package $it.Id -AllUsers -ErrorAction Stop
    } catch {
        try { Remove-AppxPackage -Package $it.Id -ErrorAction Stop }
        catch { Write-Log "  Ошибка: $($_.Exception.Message.Split("`n")[0].Trim())"; return $false }
    }
    if ($provFailed.Count -gt 0) {
        # Сообщаем только если предустановка действительно осталась
        $still = @()
        try { $still = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $provFailed -contains $_.PackageName }) } catch { }
        if ($still.Count -gt 0) { Write-Log '  Осталось в предустановке: приложение может появиться у новых пользователей' }
    }
    $left = Get-AppxPackage -AllUsers -Name $it.AppxName -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageFullName -eq $it.Id -and ($_.PackageUserInformation | Where-Object { "$($_.InstallState)" -eq 'Installed' }) }
    if ($left) { Write-Log '  Пакет всё ещё установлен у кого-то из пользователей'; return $false }
    return $true
}

# Ждёт завершения деинсталлятора и всех процессов, которые он породил, не блокируя окно.
# Возвращает $false, если пользователь нажал "Пропустить ожидание".
function Wait-Uninstaller($proc, [datetime]$started) {
    $script:SkipWait = $false
    $btnSkip.Enabled = $true
    $tracked = @{}; $tracked[[int]$proc.Id] = $true
    $lastPoll = [datetime]::MinValue
    $alive = $true
    while ($alive -and -not $script:SkipWait) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
        if (((Get-Date) - $lastPoll).TotalMilliseconds -lt 1000) { continue }
        $lastPoll = Get-Date
        $procs = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationDate -ge $started })
        do {
            $added = $false
            foreach ($q in $procs) {
                if (-not $tracked.ContainsKey([int]$q.ProcessId) -and $tracked.ContainsKey([int]$q.ParentProcessId)) {
                    $tracked[[int]$q.ProcessId] = $true; $added = $true
                }
            }
        } while ($added)
        $alive = $false
        foreach ($q in $procs) { if ($tracked.ContainsKey([int]$q.ProcessId)) { $alive = $true; break } }
        if (-not $alive -and -not $proc.HasExited) { $alive = $true }
    }
    $btnSkip.Enabled = $false
    return (-not $script:SkipWait)
}

# Возвращает 'ok', 'fail' или 'handed' (удаление передано лаунчеру, например Steam)
function Remove-Win32Item($it) {
    if (-not $it.Quiet -and "$($it.Uninstall)" -match '(steam://uninstall/\d+)') {
        try {
            Start-Process $Matches[1]
            Write-Log '  Это игра из Steam: удаление передано в Steam, подтвердите его в окне Steam'
            return 'handed'
        } catch {
            Write-Log "  Не удалось открыть Steam: $($_.Exception.Message)"
            return 'fail'
        }
    }
    $started = (Get-Date).AddSeconds(-2)
    try {
        if ($it.Quiet) {
            $p = Start-Process cmd.exe -ArgumentList ('/c "' + $it.Quiet + '"') -WindowStyle Hidden -PassThru
        } elseif ($it.MsiGuid) {
            $p = Start-Process msiexec.exe -ArgumentList "/x $($it.MsiGuid) /passive /norestart" -PassThru
        } else {
            Write-Log '  Открыт деинсталлятор программы: следуйте его окну (оно может быть позади этого)'
            $p = Start-Process cmd.exe -ArgumentList ('/c "' + $it.Uninstall + '"') -WindowStyle Hidden -PassThru
        }
    } catch {
        Write-Log "  Ошибка запуска деинсталлятора: $($_.Exception.Message)"
        return 'fail'
    }
    if (-not (Wait-Uninstaller $p $started)) {
        Write-Log '  Ожидание пропущено: деинсталлятор мог остаться открытым'
    }
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $it.Id) {
        Write-Log '  Запись о программе осталась (удаление отменено, не завершено или требует перезагрузки)'
        return 'fail'
    }
    return 'ok'
}

# ---------- Интерфейс ----------
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Items = @()
$script:Populating = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = 'PCCleaner'
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(900, 500)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Верхняя панель
$top = New-Object System.Windows.Forms.FlowLayoutPanel
$top.Dock = 'Top'; $top.Height = 40; $top.Padding = '6,6,6,0'; $top.WrapContents = $false

function New-Button($text, $width) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Width = $width; $b.Height = 27
    return $b
}
$btnScan = New-Button 'Сканировать заново' 140
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = 'Поиск:'; $lblSearch.AutoSize = $true; $lblSearch.Margin = '14,7,2,0'
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Width = 200; $txtSearch.Margin = '2,4,2,0'
$lblCat = New-Object System.Windows.Forms.Label
$lblCat.Text = 'Категория:'; $lblCat.AutoSize = $true; $lblCat.Margin = '14,7,2,0'
$cmbCat = New-Object System.Windows.Forms.ComboBox
$cmbCat.DropDownStyle = 'DropDownList'; $cmbCat.Width = 150; $cmbCat.Margin = '2,4,2,0'
[void]$cmbCat.Items.AddRange(@('Все', 'Мусор', 'Предустановлено', 'Программа', 'Осторожно', 'Защищено'))
$cmbCat.SelectedIndex = 0
$lblKind = New-Object System.Windows.Forms.Label
$lblKind.Text = 'Тип:'; $lblKind.AutoSize = $true; $lblKind.Margin = '14,7,2,0'
$cmbKind = New-Object System.Windows.Forms.ComboBox
$cmbKind.DropDownStyle = 'DropDownList'; $cmbKind.Width = 190; $cmbKind.Margin = '2,4,2,0'
[void]$cmbKind.Items.AddRange(@('Все', 'Приложения Windows (Appx)', 'Обычные программы (Win32)'))
$cmbKind.SelectedIndex = 0
$chkHide = New-Object System.Windows.Forms.CheckBox
$chkHide.Text = 'Скрыть защищённые'; $chkHide.AutoSize = $true; $chkHide.Margin = '14,6,2,0'
$top.Controls.AddRange(@($btnScan, $lblSearch, $txtSearch, $lblCat, $cmbCat, $lblKind, $cmbKind, $chkHide))

# Нижняя панель
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 130

$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Bottom'; $actions.Height = 40; $actions.Padding = '6,6,6,0'; $actions.WrapContents = $false
$btnMarkBloat = New-Button 'Отметить мусор' 120
$btnClear = New-Button 'Снять все отметки' 140
$chkRestore = New-Object System.Windows.Forms.CheckBox
$chkRestore.Text = 'Создать точку восстановления перед удалением'; $chkRestore.Checked = $true
$chkRestore.AutoSize = $true; $chkRestore.Margin = '14,6,2,0'
$lblCount = New-Object System.Windows.Forms.Label
$lblCount.AutoSize = $true; $lblCount.Margin = '14,7,8,0'
$btnRemove = New-Button 'Удалить выбранное...' 150
$btnSkip = New-Button 'Пропустить ожидание' 150
$btnSkip.Enabled = $false
$btnSkip.Add_Click({ $script:SkipWait = $true })
$actions.Controls.AddRange(@($btnRemove, $btnSkip, $btnMarkBloat, $btnClear, $chkRestore, $lblCount))

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true; $script:txtLog.ReadOnly = $true; $script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.Dock = 'Fill'
$bottom.Controls.Add($script:txtLog)

# Список
$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.CheckBoxes = $true
$lv.FullRowSelect = $true; $lv.GridLines = $false; $lv.HideSelection = $false
[void]$lv.Columns.Add('Название', 330)
[void]$lv.Columns.Add('Категория', 120)
[void]$lv.Columns.Add('Тип', 60)
[void]$lv.Columns.Add('Издатель', 190)
[void]$lv.Columns.Add('Версия', 110)
[void]$lv.Columns.Add('Размер', 80)
[void]$lv.Columns.Add('Примечание', 400)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = 'Программы'
$tabAuto = New-Object System.Windows.Forms.TabPage
$tabAuto.Text = 'Автозапуск'
$tabs.TabPages.AddRange(@($tabApps, $tabAuto))

$tabApps.Controls.Add($lv)
$tabApps.Controls.Add($actions)
$tabApps.Controls.Add($top)
$lv.BringToFront()

$form.Controls.Add($tabs)
$form.Controls.Add($bottom)
$tabs.BringToFront()

$GrayText = [System.Drawing.SystemColors]::GrayText

function Format-Size($kb) {
    if (-not $kb -or $kb -le 0) { return '' }
    if ($kb -ge 1048576) { return '{0:N1} ГБ' -f ($kb / 1048576) }
    if ($kb -ge 1024) { return '{0:N0} МБ' -f ($kb / 1024) }
    return "$kb КБ"
}

# ---------- Сортировка по щелчку на заголовке столбца ----------
$script:CatOrder = @{ 'Мусор' = 0; 'Предустановлено' = 1; 'Программа' = 2; 'Осторожно' = 3; 'Защищено' = 4 }

# Версия "1.10.2" -> ключ, который сравнивается как числа, а не как текст
function Get-VersionKey([string]$v) {
    (($v -split '[^0-9A-Za-z]+' | Where-Object { $_ -ne '' } | ForEach-Object {
        if ($_ -match '^\d+$') { $_.PadLeft(12, '0') } else { $_ }
    }) -join '.')
}

$script:AppColNames = @('Название', 'Категория', 'Тип', 'Издатель', 'Версия', 'Размер', 'Примечание')
$script:AppSortKeys = @(
    { $_.Name }, { $script:CatOrder[$_.Category] }, { $_.Kind }, { $_.Publisher },
    { Get-VersionKey $_.Version }, { [int64]$_.SizeKB }, { $_.Note }
)
$script:AutoColNames = @('Название', 'Состояние', 'Источник', 'Компания', 'Команда запуска', 'Примечание')
$script:AutoSortKeys = @({ $_.Name }, { $_.Status }, { $_.Source }, { $_.Company }, { $_.Command }, { $_.Note })
# Col = -1: исходный порядок (как после сканирования)
$script:AppSort = @{ Col = -1; Desc = $false }
$script:AutoSort = @{ Col = -1; Desc = $false }

function Get-Sorted($items, $keys, $state) {
    if ($state.Col -lt 0) { return $items }
    return @($items | Sort-Object -Property @{ Expression = $keys[$state.Col]; Descending = $state.Desc }, @{ Expression = { $_.Name } })
}

function Set-SortArrow($list, $names, $state) {
    for ($i = 0; $i -lt $names.Count; $i++) {
        $text = $names[$i]
        if ($i -eq $state.Col) { if ($state.Desc) { $text += '  ▼' } else { $text += '  ▲' } }
        if ($list.Columns[$i].Text -ne $text) { $list.Columns[$i].Text = $text }
    }
}

function Switch-Sort($state, [int]$col) {
    if ($state.Col -eq $col) { $state.Desc = -not $state.Desc }
    else { $state.Col = $col; $state.Desc = $false }
}

function Update-Count {
    $n = @($script:Items | Where-Object { $_.Checked }).Count
    $lblCount.Text = "Выбрано: $n   |   Всего: $($script:Items.Count)   |   Показано: $($lv.Items.Count)"
}

function Update-List {
    $script:Populating = $true
    $lv.BeginUpdate()
    $lv.Items.Clear()
    $q = $txtSearch.Text.Trim()
    $cat = "$($cmbCat.SelectedItem)"
    $kind = switch ($cmbKind.SelectedIndex) { 1 { 'Appx' } 2 { 'Win32' } default { '' } }
    Set-SortArrow $lv $script:AppColNames $script:AppSort
    foreach ($it in (Get-Sorted $script:Items $script:AppSortKeys $script:AppSort)) {
        if ($cat -ne 'Все' -and $it.Category -ne $cat) { continue }
        if ($kind -and $it.Kind -ne $kind) { continue }
        if ($chkHide.Checked -and $it.Protected) { continue }
        if ($q -and ("$($it.Name) $($it.Publisher) $($it.Note)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
        $row = New-Object System.Windows.Forms.ListViewItem($it.Name)
        [void]$row.SubItems.Add($it.Category)
        [void]$row.SubItems.Add($it.Kind)
        [void]$row.SubItems.Add($it.Publisher)
        [void]$row.SubItems.Add($it.Version)
        [void]$row.SubItems.Add((Format-Size $it.SizeKB))
        [void]$row.SubItems.Add($it.Note)
        if ($it.Protected) { $row.ForeColor = $GrayText }
        $row.Checked = $it.Checked
        $row.Tag = $it
        [void]$lv.Items.Add($row)
    }
    $lv.EndUpdate()
    $script:Populating = $false
    Update-Count
}

function Invoke-Scan {
    $form.Cursor = 'WaitCursor'
    Write-Log 'Сканирование установленных программ и приложений...'
    $script:Items = @(Get-AllItems)
    $summary = ($script:Items | Group-Object Category | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
    Write-Log "Найдено $($script:Items.Count). $summary"
    Update-List
    $form.Cursor = 'Default'
}

$lv.Add_ItemChecked({
    param($s, $e)
    if ($script:Populating) { return }
    $it = $e.Item.Tag
    if ($it.Protected -and $e.Item.Checked) {
        $e.Item.Checked = $false
        Write-Log "«$($it.Name)» защищено от удаления: $($it.Note)"
        return
    }
    $it.Checked = $e.Item.Checked
    Update-Count
})

$lv.Add_ColumnClick({
    param($s, $e)
    Switch-Sort $script:AppSort $e.Column
    Update-List
})
$txtSearch.Add_TextChanged({ Update-List })
$cmbCat.Add_SelectedIndexChanged({ Update-List })
$cmbKind.Add_SelectedIndexChanged({ Update-List })
$chkHide.Add_CheckedChanged({ Update-List })
$btnScan.Add_Click({ Invoke-Scan })
$btnMarkBloat.Add_Click({
    foreach ($it in $script:Items) { if ($it.Category -eq 'Мусор') { $it.Checked = $true } }
    Update-List
})
$btnClear.Add_Click({
    foreach ($it in $script:Items) { $it.Checked = $false }
    Update-List
})

$btnRemove.Add_Click({
    $sel = @($script:Items | Where-Object { $_.Checked -and -not $_.Protected })
    if ($sel.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show('Ничего не выбрано.', 'PCCleaner', 'OK', 'Information')
        return
    }
    $names = ($sel | Select-Object -First 20 | ForEach-Object { "  - $($_.Name)" }) -join "`n"
    if ($sel.Count -gt 20) { $names += "`n  ... и ещё $($sel.Count - 20)" }
    $warn = ''
    $risky = @($sel | Where-Object { $_.Category -eq 'Осторожно' }).Count
    if ($risky -gt 0) { $warn = "`n`nВнимание: $risky из них помечены «Осторожно» (драйверы/библиотеки/компоненты)." }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Будет удалено программ: $($sel.Count)`n`n$names$warn`n`nПродолжить?",
        'Подтверждение удаления', 'YesNo', 'Warning', 'Button2')
    if ($answer -ne 'Yes') { return }

    $form.Cursor = 'WaitCursor'
    $btnRemove.Enabled = $false; $btnScan.Enabled = $false

    if ($chkRestore.Checked) {
        Write-Log 'Создание точки восстановления...'
        try {
            Checkpoint-Computer -Description 'PCCleaner' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable w -WarningAction SilentlyContinue
            if ($w) { Write-Log "  Windows сообщает: $w" } else { Write-Log '  Точка восстановления создана' }
        } catch {
            Write-Log "  Не удалось создать точку восстановления: $($_.Exception.Message)"
            $go = [System.Windows.Forms.MessageBox]::Show(
                'Не удалось создать точку восстановления (возможно, защита системы отключена). Всё равно продолжить удаление?',
                'PCCleaner', 'YesNo', 'Warning', 'Button2')
            if ($go -ne 'Yes') {
                $btnRemove.Enabled = $true; $btnScan.Enabled = $true; $form.Cursor = 'Default'
                return
            }
        }
    }

    $script:Provisioned = @()
    if (@($sel | Where-Object { $_.Kind -eq 'Appx' }).Count -gt 0) {
        try { $script:Provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { }
    }

    $form.Cursor = 'Default'
    $tabAuto.Enabled = $false
    $ok = 0; $fail = 0; $handed = 0; $i = 0
    foreach ($it in $sel) {
        $i++
        Write-Log "[$i/$($sel.Count)] Удаление: $($it.Name) ($($it.Kind))"
        if ($it.Kind -eq 'Appx') {
            if (Remove-AppxItem $it) { $res = 'ok' } else { $res = 'fail' }
        } else { $res = Remove-Win32Item $it }
        switch ($res) {
            'ok'     { $ok++; Write-Log '  Удалено' }
            'handed' { $handed++ }
            default  { $fail++ }
        }
    }
    $summary = "Готово. Удалено: $ok, не удалено: $fail"
    if ($handed -gt 0) { $summary += ", передано в Steam: $handed" }
    Write-Log "$summary. Журнал: $script:LogFile"
    $tabAuto.Enabled = $true
    $btnRemove.Enabled = $true; $btnScan.Enabled = $true
    Invoke-Scan
})

# ---------- Вкладка «Автозапуск» ----------
$script:AutoItems = @()

$aTop = New-Object System.Windows.Forms.FlowLayoutPanel
$aTop.Dock = 'Top'; $aTop.Height = 40; $aTop.Padding = '6,6,6,0'; $aTop.WrapContents = $false
$btnAScan = New-Button 'Сканировать заново' 140
$lblASearch = New-Object System.Windows.Forms.Label
$lblASearch.Text = 'Поиск:'; $lblASearch.AutoSize = $true; $lblASearch.Margin = '14,7,2,0'
$txtASearch = New-Object System.Windows.Forms.TextBox
$txtASearch.Width = 200; $txtASearch.Margin = '2,4,2,0'
$lblASrc = New-Object System.Windows.Forms.Label
$lblASrc.Text = 'Источник:'; $lblASrc.AutoSize = $true; $lblASrc.Margin = '14,7,2,0'
$cmbASrc = New-Object System.Windows.Forms.ComboBox
$cmbASrc.DropDownStyle = 'DropDownList'; $cmbASrc.Width = 190; $cmbASrc.Margin = '2,4,2,0'
[void]$cmbASrc.Items.AddRange(@('Все', 'Реестр и папка автозагрузки', 'Планировщик заданий', 'Службы'))
$cmbASrc.SelectedIndex = 0
$chkAOn = New-Object System.Windows.Forms.CheckBox
$chkAOn.Text = 'Только включённые'; $chkAOn.AutoSize = $true; $chkAOn.Margin = '14,6,2,0'
$chkAHidden = New-Object System.Windows.Forms.CheckBox
$chkAHidden.Text = 'Только скрытые (тихий запуск)'; $chkAHidden.AutoSize = $true; $chkAHidden.Margin = '14,6,2,0'
$aTop.Controls.AddRange(@($btnAScan, $lblASearch, $txtASearch, $lblASrc, $cmbASrc, $chkAOn, $chkAHidden))

$aActions = New-Object System.Windows.Forms.FlowLayoutPanel
$aActions.Dock = 'Bottom'; $aActions.Height = 40; $aActions.Padding = '6,6,6,0'; $aActions.WrapContents = $false
$btnADisable = New-Button 'Отключить выбранное' 150
$btnAEnable = New-Button 'Включить выбранное' 150
$btnAClear = New-Button 'Снять все отметки' 140
$lblACount = New-Object System.Windows.Forms.Label
$lblACount.AutoSize = $true; $lblACount.Margin = '14,7,8,0'
$aActions.Controls.AddRange(@($btnADisable, $btnAEnable, $btnAClear, $lblACount))

$lvA = New-Object System.Windows.Forms.ListView
$lvA.Dock = 'Fill'; $lvA.View = 'Details'; $lvA.CheckBoxes = $true
$lvA.FullRowSelect = $true; $lvA.GridLines = $false; $lvA.HideSelection = $false; $lvA.ShowItemToolTips = $true
[void]$lvA.Columns.Add('Название', 260)
[void]$lvA.Columns.Add('Состояние', 85)
[void]$lvA.Columns.Add('Источник', 200)
[void]$lvA.Columns.Add('Компания', 170)
[void]$lvA.Columns.Add('Команда запуска', 330)
[void]$lvA.Columns.Add('Примечание', 420)

$tabAuto.Controls.Add($lvA)
$tabAuto.Controls.Add($aActions)
$tabAuto.Controls.Add($aTop)
$lvA.BringToFront()

function Update-AutoCount {
    $n = @($script:AutoItems | Where-Object { $_.Checked }).Count
    $on = @($script:AutoItems | Where-Object { $_.Status -eq 'Включено' }).Count
    $lblACount.Text = "Выбрано: $n   |   Всего: $($script:AutoItems.Count)   |   Включено: $on   |   Показано: $($lvA.Items.Count)"
}

function Update-AutoList {
    $script:Populating = $true
    $lvA.BeginUpdate()
    $lvA.Items.Clear()
    $q = $txtASearch.Text.Trim()
    Set-SortArrow $lvA $script:AutoColNames $script:AutoSort
    foreach ($it in (Get-Sorted $script:AutoItems $script:AutoSortKeys $script:AutoSort)) {
        switch ($cmbASrc.SelectedIndex) {
            1 { if ($it.Kind -notin 'Reg', 'Folder') { continue } }
            2 { if ($it.Kind -ne 'Task') { continue } }
            3 { if ($it.Kind -ne 'Service') { continue } }
        }
        if ($chkAOn.Checked -and $it.Status -ne 'Включено') { continue }
        if ($chkAHidden.Checked -and -not $it.Hidden) { continue }
        if ($q -and ("$($it.Name) $($it.Company) $($it.Command)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
        $row = New-Object System.Windows.Forms.ListViewItem($it.Name)
        [void]$row.SubItems.Add($it.Status)
        [void]$row.SubItems.Add($it.Source)
        [void]$row.SubItems.Add($it.Company)
        [void]$row.SubItems.Add($it.Command)
        [void]$row.SubItems.Add($it.Note)
        if ($it.Status -ne 'Включено') { $row.ForeColor = $GrayText }
        $row.ToolTipText = $it.Command
        $row.Checked = $it.Checked
        $row.Tag = $it
        [void]$lvA.Items.Add($row)
    }
    $lvA.EndUpdate()
    $script:Populating = $false
    Update-AutoCount
}

function Invoke-AutoScan {
    $form.Cursor = 'WaitCursor'
    Write-Log 'Сканирование автозапуска (реестр, папки, планировщик, службы)...'
    $script:AutoItems = @(Get-AutorunItems | Sort-Object @{ Expression = { $_.Status -ne 'Включено' } }, Source, Name)
    $summary = ($script:AutoItems | Group-Object Kind | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
    Write-Log "Автозапуск: найдено $($script:AutoItems.Count). $summary"
    Update-AutoList
    $form.Cursor = 'Default'
}

function Set-AutoItemState($it, [bool]$enable) {
    try {
        switch ($it.Kind) {
            'Task' {
                if ($enable) { Enable-ScheduledTask -TaskPath $it.TaskPath -TaskName $it.TaskName -ErrorAction Stop | Out-Null }
                else { Disable-ScheduledTask -TaskPath $it.TaskPath -TaskName $it.TaskName -ErrorAction Stop | Out-Null }
            }
            'Service' {
                if ($enable) { Set-Service -Name $it.ServiceName -StartupType Automatic -ErrorAction Stop }
                else { Set-Service -Name $it.ServiceName -StartupType Manual -ErrorAction Stop }
            }
            default {
                # Тот же механизм, что у диспетчера задач: запись не удаляется, а помечается отключённой
                if (-not (Test-Path -LiteralPath $it.ApprovedKey)) { New-Item -Path $it.ApprovedKey -Force | Out-Null }
                if ($enable) { $bytes = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
                else { $bytes = [byte[]](3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()) }
                $rk = (Get-Item -LiteralPath $it.ApprovedKey).OpenSubKey('', $true)
                $rk.SetValue($it.ValueName, [byte[]]$bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
                $rk.Close()
            }
        }
        return $true
    } catch {
        Write-Log "  Ошибка: $($_.Exception.Message.Split("`n")[0].Trim())"
        return $false
    }
}

function Invoke-AutoToggle([bool]$enable) {
    $sel = @($script:AutoItems | Where-Object { $_.Checked })
    if ($sel.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show('Ничего не выбрано.', 'PCCleaner', 'OK', 'Information')
        return
    }
    if ($enable) { $verb = 'включён' } else { $verb = 'отключён' }
    $names = ($sel | Select-Object -First 20 | ForEach-Object { "  - $($_.Name)  [$($_.Source)]" }) -join "`n"
    if ($sel.Count -gt 20) { $names += "`n  ... и ещё $($sel.Count - 20)" }
    $warn = ''
    if (-not $enable -and @($sel | Where-Object { $_.Kind -eq 'Service' }).Count -gt 0) {
        $warn = "`n`nСлужбы будут переведены в режим «Вручную»: уже запущенные проработают до перезагрузки."
    }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Автозапуск будет $verb для записей: $($sel.Count)`n`n$names$warn`n`nПродолжить?",
        'Подтверждение', 'YesNo', 'Question', 'Button2')
    if ($answer -ne 'Yes') { return }
    $form.Cursor = 'WaitCursor'
    $ok = 0; $fail = 0
    foreach ($it in $sel) {
        Write-Log "Автозапуск $verb`: $($it.Name) [$($it.Source)]"
        if (Set-AutoItemState $it $enable) { $ok++ } else { $fail++ }
    }
    Write-Log "Готово. Успешно: $ok, с ошибкой: $fail"
    $form.Cursor = 'Default'
    Invoke-AutoScan
}

$lvA.Add_ItemChecked({
    param($s, $e)
    if ($script:Populating) { return }
    $e.Item.Tag.Checked = $e.Item.Checked
    Update-AutoCount
})
$lvA.Add_ColumnClick({
    param($s, $e)
    Switch-Sort $script:AutoSort $e.Column
    Update-AutoList
})
$txtASearch.Add_TextChanged({ Update-AutoList })
$cmbASrc.Add_SelectedIndexChanged({ Update-AutoList })
$chkAOn.Add_CheckedChanged({ Update-AutoList })
$chkAHidden.Add_CheckedChanged({ Update-AutoList })
$btnAScan.Add_Click({ Invoke-AutoScan })
$btnAClear.Add_Click({
    foreach ($it in $script:AutoItems) { $it.Checked = $false }
    Update-AutoList
})
$btnADisable.Add_Click({ Invoke-AutoToggle $false })
$btnAEnable.Add_Click({ Invoke-AutoToggle $true })

$form.Add_Shown({
    Invoke-AutoScan
    Invoke-Scan
    if ($env:PCC_SELFTEST) {
        # Самопроверка сборки: записать число строк в обоих списках и закрыться
        Set-Content -LiteralPath (Join-Path $script:AppDir 'selftest.txt') -Value "apps=$($lv.Items.Count) autorun=$($lvA.Items.Count) admin=$script:IsAdmin"
        $out = Join-Path $script:AppDir 'selftest.txt'
        # Сортировка: размер по убыванию, затем версия по возрастанию
        Switch-Sort $script:AppSort 5; Switch-Sort $script:AppSort 5; Update-List
        Add-Content -LiteralPath $out -Value ('size desc: ' + ((0..3 | ForEach-Object { $lv.Items[$_].Text + ' = ' + $lv.Items[$_].SubItems[5].Text }) -join ' | '))
        Switch-Sort $script:AppSort 4; Update-List
        $vers = @($lv.Items | ForEach-Object { $_.SubItems[4].Text } | Where-Object { $_ })
        Add-Content -LiteralPath $out -Value ('version asc: ' + (($vers | Select-Object -First 4) -join ' | ') + ' ... ' + (($vers | Select-Object -Last 3) -join ' | '))
        Switch-Sort $script:AppSort 5; Switch-Sort $script:AppSort 5; Update-List
        # Ожидание деинсталлятора: дерево cmd -> cmd -> ping должно ждаться целиком (~4 с)
        $t0 = Get-Date
        $tp = Start-Process cmd.exe -ArgumentList '/c start "" /b cmd /c ping -n 5 127.0.0.1 >nul' -WindowStyle Hidden -PassThru
        $done = Wait-Uninstaller $tp $t0.AddSeconds(-2)
        Add-Content -LiteralPath $out -Value ("wait: completed=$done seconds=" + [int]((Get-Date) - $t0).TotalSeconds)
        foreach ($n in 0, 1) {
            $tabs.SelectedIndex = $n
            [System.Windows.Forms.Application]::DoEvents()
            $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
            $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
            $bmp.Save((Join-Path $script:AppDir "selftest$n.png"))
            $bmp.Dispose()
        }
        $form.Close()
    }
})
[void]$form.ShowDialog()
