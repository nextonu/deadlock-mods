# Modi lisamine lülitist endast: nupp "+ Lisa mod" või arhiivi lohistamine aknale.
# Laetakse DeadlockModToggle.ps1-st (dot-source). Lisatud modid salvestuvad faili lisatud.json
# ja lähevad "New" alla, väljalülitatuna (addons_off).
#
# Samad sammud, mida Claude käsitsi teeb:
#  1. arhiiv lahti (7-Zip) kuupäevaga kausta D:\Downloads\Muu\deadlock_mods\<kuupäev>\
#  2. VPK failide nimekirjast kangelane (models/heroes_*/<kaust>/)
#  3. jagatud failid (võimete tabel, UI stiilid, helitabelid...) võrreldakse mängu omadega;
#     selgelt vanem koopia visatakse modist välja (vpkdrop.py), muidu jääb alles
#  4. kaamera kontroll (camfix.py): vana kaameraga mod saab nimesse "kaameraparanduseta"
#  5. arhiiv tõstetakse D:\Downloads\Muu\deadlock_mods\ alla

$ToolsDir  = 'D:\GIT\nextcode\.claude\tools'
# Jagatavas versioonis on tööriistad rakenduse kaustas tools\ (Python ja Source2Viewer laaditakse vajadusel alla, vt Initialize-Tools)
$AppTools  = Join-Path $PSScriptRoot 'tools'
if (Test-Path -LiteralPath (Join-Path $AppTools 'vpkread.py')) { $ToolsDir = $AppTools }
$S2V       = Join-Path $ToolsDir 'vrf\Source2Viewer-CLI.exe'
$SevenZip  = @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe', (Join-Path $AppTools '7zip\7z.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
# Python: süsteemi oma (mitte Microsoft Store'i "python.exe" otsetee) või tools\python
function Find-Python {
    $p = Join-Path $AppTools 'python\python.exe'; if (Test-Path -LiteralPath $p) { return $p }
    foreach ($n in 'python', 'py') {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    return $null
}
$Python = Find-Python
$ArchiveDir = 'D:\Downloads\Muu\deadlock_mods'
if ($Portable -or -not (Test-Path -LiteralPath (Split-Path $ArchiveDir -Parent))) { $ArchiveDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\Deadlock mods' }
if ($env:DLMODS_ARCHIVE) { $ArchiveDir = $env:DLMODS_ARCHIVE }
# Arhiivid, mida 7-Zip lahti teeb (ka arhiiv arhiivis, nt zip zipis või .tar.gz)
$ArchiveExts = @('.zip', '.rar', '.7z', '.tar', '.gz', '.tgz', '.xz', '.txz', '.bz2', '.tbz2', '.tbz')

# mudeli kaust -> nimi lülitis, rühma võti (Hero), mängu pildi eesliide
$HeroTable = @{
    unicorn = 'Celeste|celeste|unicorn'; haze = 'Haze|haze|haze'; wraith = 'Wraith|wraith|wraith'
    archer = 'Grey Talon|talon|archer'; grey_talon = 'Grey Talon|talon|archer'; hornet = 'Vindicta|vindicta|hornet'
    nurse = 'Harrow|harrow|nurse'; punkgoat = 'Billy|billy|punkgoat'; bookworm = 'Paige|paige|bookworm'
    lash = 'Lash|lash|lash'; yamato = 'Yamato|yamato|yamato'; fencer = 'Apollo|apollo|fencer'
    gigawatt = 'Seven|seven|gigawatt'; nano = 'Calico|calico|nano'; abrams = 'Abrams|abrams|bull'; atlas = 'Abrams|abrams|bull'
    baba = 'Baba|baba|baba'; familiar = 'Rem|rem|familiar'; werewolf = 'Silver|silver|werewolf'
    mcginnis = 'McGinnis|mcginnis|engineer'; forge = 'McGinnis|mcginnis|engineer'; necro = 'Graves|graves|necro'
    ratking = 'Rat King|ratking|ratking'; doorman = 'Doorman|doorman|doorman'; magician = 'Sinclair|sinclair|magician'
    drifter = 'Drifter|drifter|drifter'; frank = 'Victor|victor|frank'; viper = 'Vyper|vyper|kali'
    artist = 'Violet|violet|artist'; pocket = 'Pocket|pocket|synth'; synth = 'Pocket|pocket|synth'
    deadpack = 'Deadman Danny|danny|deadpack'; chessmaster = 'Solomon|solomon|chessmaster'
    inferno = 'Infernus|infernus|inferno'; ivy = 'Ivy|ivy|tengu'; tengu = 'Ivy|ivy|tengu'
    vampirebat = 'Mina|mina|vampirebat'; digger = 'Mo & Krill|krill|digger'; dynamo = 'Dynamo|dynamo|sumo'
    kelvin = 'Kelvin|kelvin|kelvin'; bebop = 'Bebop|bebop|bebop'; shiv = 'Shiv|shiv|shiv'
    warden = 'Warden|warden|warden'; viscous = 'Viscous|viscous|viscous'; astro = 'Holliday|holliday|astro'
    chrono = 'Paradox|paradox|chrono'; ghost = 'Lady Geist|geist|spectre'; spectre = 'Lady Geist|geist|spectre'
    mirage = 'Mirage|mirage|mirage'; yakuza = 'Wraith|wraith|wraith'
}

# Käivitab välise programmi nii, et aken ei külmu ("Not responding"): ootamise ajal joonistab akent edasi.
# Tagastab programmi väljundi read. Kasutus: Run <exe> <argumendid...>
function Run {
    $exe = $args[0]
    $rest = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)] | ForEach-Object { $_ }) } else { @() }
    $q = ($rest | ForEach-Object {
        $s = [string]$_
        if ($s -eq '' -or $s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' '
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, $q
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    while (-not $p.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25 }
    $p.WaitForExit()
    return @(($o.Result + "`n" + $e.Result) -split "`r?`n" | Where-Object { $_ -ne '' })
}

# VPK failide nimekiri (vpkread.py on kiire ka suurte failide puhul).
function Get-VpkPaths($path) {
    if (-not $Python) { throw 'Python was not found (it should be in the tools\python folder of this app).' }
    $out = New-Object Collections.Generic.List[string]
    foreach ($l in (Run $Python -I (Join-Path $ToolsDir 'vpkread.py') $path)) {
        if ($l -match '^\s+(\S+)\s+\d+\s*$') { $out.Add($Matches[1]) }
    }
    if (-not $out.Count) { throw "Could not read the VPK file: $path" }
    return , $out
}

function Get-HeroInfo($paths) {
    $counts = @{}
    foreach ($p in $paths) {
        if ($p -match '^models/heroes_\w+/(\w+)/') {
            $k = $Matches[1] -replace '_v\d+$', '' -replace '_prisoner$', ''
            if ($HeroTable.ContainsKey($k)) { $counts[$k] = 1 + [int]$counts[$k] }
        }
    }
    if (-not $counts.Count) {
        # Kangelane, keda tabelis veel pole (nt Valve'i uus kangelane): võta nimi mudeli kaustast,
        # kui seal on kangelase põhimudel (<kaust>/<kaust>.vmdl_c). Lisatakse tabelisse, et see edaspidi töötaks.
        foreach ($p in $paths) {
            if ($p -match '^models/heroes_\w+/(\w+)/\1\.vmdl_c$') {
                $k = $Matches[1] -replace '_v\d+$', ''
                $disp = (Get-Culture).TextInfo.ToTitleCase(($k -replace '_', ' '))
                $HeroTable[$k] = "$disp|$k|$k"
                return @{ Folder = $k; Display = $disp; Key = $k; Img = $k }
            }
        }
        return $null
    }
    $best = ($counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
    $v = $HeroTable[$best] -split '\|'
    return @{ Folder = $best; Display = $v[0]; Key = $v[1]; Img = $v[2] }
}

# Jagatud failid: kõigi kangelaste ühised tabelid ja UI. Vana koopia lõhub teisi kangelasi.
$SharedPattern = '^(scripts/[^/]+\.vdata_c|resource/localization/.+|soundevents/[^/]+\.vsndevts_c|panorama/(styles|layout)/.+)$'

function Get-StaleShared($vpk, $paths, $log) {
    $drop = @()
    $shared = @($paths | Where-Object { $_ -match $SharedPattern })
    if (-not $shared.Count) { return , $drop }
    if (-not (Test-Path $S2V)) { [void]$log.Add("Shared files ($($shared.Count)) not checked: Source2Viewer missing."); return , $drop }
    $tmp = Join-Path $env:TEMP ("dlmod_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $i = 0
        foreach ($s in $shared) {
            $i++; $m = Join-Path $tmp "m$i"; $v = Join-Path $tmp "v$i"
            New-Item -ItemType Directory -Force $m, $v | Out-Null
            Set-Busy "Comparing with game file: $s"
            Run $S2V -i $vpk -f $s -o $m -d | Out-Null
            $mf = Get-ChildItem $m -Recurse -File | Select-Object -First 1
            if ($s -like 'resource/*') {
                # tekstifailid (lokaliseerimine) on mängus lahtiste failidena, mitte pak01 sees
                $loose = Join-Path $Citadel ($s -replace '/', '\')
                $vf = if (Test-Path -LiteralPath $loose) { Get-Item -LiteralPath $loose } else { $null }
            } else {
                Run $S2V -i (Join-Path $Citadel 'pak01_dir.vpk') -f $s -o $v -d | Out-Null
                $vf = Get-ChildItem $v -Recurse -File | Select-Object -First 1
            }
            if (-not $vf) { [void]$log.Add("New shared file (not in game): $s - kept"); continue }
            if (-not $mf) { [void]$log.Add("Could not read: $s - kept"); continue }
            # Kiire võrdlus (Compare-Object on suurte tekstifailidega minuteid aeglane)
            $vanL = [IO.File]::ReadAllLines($vf.FullName); $modL = [IO.File]::ReadAllLines($mf.FullName)
            $vanSet = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]$vanL)
            $modSet = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]$modL)
            $onlyVan = 0; foreach ($x in $vanSet) { if (-not $modSet.Contains($x)) { $onlyVan++ } }
            $onlyMod = 0; foreach ($x in $modSet) { if (-not $vanSet.Contains($x)) { $onlyMod++ } }
            [Windows.Forms.Application]::DoEvents()
            if ($onlyVan -gt 10 -and $onlyVan -gt 2 * $onlyMod) {
                $drop += $s; [void]$log.Add("Outdated copy, removed: $s ($onlyVan lines missing)")
            } else {
                [void]$log.Add("Shared file is up to date, kept: $s")
            }
        }
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    return , $drop
}

# Kaamera parandus (camfix.py, sama mis Deadlock Mod Manageril): enne 16. okt 2026 uuendust tehtud
# kangelase mudelite kaamera punktid keeratakse uude asendisse. Tagastab parandatud VPK tee või $null.
# $state.Old = leiti vana kaamera; $state.Fixed = parandati; $state.Failed = vana, aga ei saanud parandada.
function Repair-Camera($vpk, $paths, $state, $log) {
    if (-not (Test-Path $S2V)) { return $null }
    $vanSet = $script:VanillaPaths
    if (-not $vanSet) {
        $vanSet = @{}; foreach ($p in (Get-VpkPaths (Join-Path $Citadel 'pak01_dir.vpk'))) { $vanSet[$p] = 1 }
        $script:VanillaPaths = $vanSet
    }
    $mdls = @($paths | Where-Object { $_ -match '^models/heroes_\w+/.+\.vmdl_c$' -and $vanSet.ContainsKey($_) })
    if (-not $mdls.Count) { return $null }
    $tmp = Join-Path $env:TEMP ("dlcam_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $pairs = @()
    try {
        $i = 0
        foreach ($mdl in $mdls) {
            $i++; $d = "$tmp\$i"
            New-Item -ItemType Directory -Force "$d\m", "$d\v" | Out-Null
            Run $S2V -i $vpk -f $mdl -o "$d\m" | Out-Null
            Run $S2V -i (Join-Path $Citadel 'pak01_dir.vpk') -f $mdl -o "$d\v" | Out-Null
            $mf = Get-ChildItem "$d\m" -Recurse -File | Select-Object -First 1
            $vf = Get-ChildItem "$d\v" -Recurse -File | Select-Object -First 1
            if (-not $mf -or -not $vf) { continue }
            $r = Run $Python -I (Join-Path $ToolsDir 'camfix.py') $mf.FullName $vf.FullName "$d\fixed.vmdl_c"
            if ($r -match 'wrote ') { $state.Old = $true; $pairs += $mdl; $pairs += "$d\fixed.vmdl_c" }
            elseif ($r | Where-Object { $_ -match 'converted|old frame|mixed|blended' }) { $state.Old = $true; $state.Failed = $true }
        }
        if (-not $pairs.Count) { return $null }
        $out = Join-Path $env:TEMP ("dlmod_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + "_kaamera.vpk")
        Run $Python -I (Join-Path $ToolsDir 'vpkreplace.py') $vpk $out @pairs | Out-Null
        if (-not (Test-Path $out)) { $state.Failed = $true; return $null }
        $state.Fixed = $true
        [void]$log.Add("Old camera fixed ($($pairs.Count / 2) model" + $(if ($pairs.Count -gt 2) { 's' } else { '' }) + ')')
        return $out
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# Vabad pak-numbrid (1..99). Eelistab suurimast kasutatud numbrist suuremaid (uus mod ei kirjuta vanu üle);
# kui sinna ei mahu, võtab vahelt vabad numbrid (suuremad enne).
function Get-FreePaks([int]$count = 1) {
    $used = @{}
    foreach ($m in $Mods) { foreach ($f in $m.Files) { if ($f.Pak -match '^pak(\d+)_dir') { $used[[int]$Matches[1]] = 1 } } }
    foreach ($f in Get-ChildItem $Addons -Filter 'pak*_dir.vpk') { if ($f.Name -match '^pak(\d+)_dir') { $used[[int]$Matches[1]] = 1 } }
    $max = 0; foreach ($k in $used.Keys) { if ($k -gt $max) { $max = $k } }
    if ($max + $count -le 99) { return , @(($max + 1)..($max + $count)) }
    $free = @(for ($n = 99; $n -ge 1; $n--) { if (-not $used[$n]) { $n } })
    if ($free.Count -lt $count) { throw 'Out of pak numbers (the game uses pak01-pak99). Delete some mods first.' }
    $out = @($free | Select-Object -First $count); [array]::Reverse($out)
    return , $out
}
function Get-NextPak { return (Get-FreePaks 1)[0] }

# Lisa peab põhimodi failid üle kirjutama (alt tekstuur, alt mudel...). Väiksem pak-number võidab,
# seega lisa saab vabad numbrid põhimodi väikseimast numbrist allpool (suurimad vabad).
function Get-PaksBelow($parentId, [int]$count) {
    $used = @{}
    foreach ($m in $Mods) { foreach ($f in $m.Files) { if ($f.Pak -match '^pak(\d+)_dir') { $used[[int]$Matches[1]] = 1 } } }
    foreach ($f in Get-ChildItem $Addons -Filter 'pak*_dir.vpk') { if ($f.Name -match '^pak(\d+)_dir') { $used[[int]$Matches[1]] = 1 } }
    $min = 100
    foreach ($f in $ById[$parentId].Files) { if ($f.Pak -match '^pak(\d+)_dir') { $min = [Math]::Min($min, [int]$Matches[1]) } }
    $out = @()
    for ($n = $min - 1; $n -ge 1 -and $out.Count -lt $count; $n--) { if (-not $used[$n]) { $out += $n } }
    if ($out.Count -lt $count) { return , (Move-ParentUp $parentId $count) }
    [array]::Reverse($out)
    return , $out
}

# Põhimodist allpool pole vabu numbreid: alt saab põhimodi numbrid, põhimod uued (suuremad) numbrid.
# Kui põhimod on sees, nimetatakse tema fail addons kaustas ümber. Uus number -> pakid.json.
function Move-ParentUp($parentId, [int]$count) {
    $p = $ById[$parentId]
    if ($p.Files.Count -lt $count) { throw "The alt has more files ($count) than its mod ($($p.Files.Count))." }
    if (Get-Process deadlock -ErrorAction SilentlyContinue) { throw 'Close Deadlock first (the mod file has to be renamed).' }
    $oldNums = @($p.Files | ForEach-Object { [int]($_.Pak -replace '\D', '') })
    $newNums = @(Get-FreePaks $p.Files.Count)
    for ($i = 0; $i -lt $p.Files.Count; $i++) {
        $from = Join-Path $Addons $p.Files[$i].Pak
        $to = Join-Path $Addons ('pak{0:D2}_dir.vpk' -f [int]$newNums[$i])
        if (Test-Path -LiteralPath $from) { Move-Item -LiteralPath $from -Destination $to }
        $p.Files[$i].Pak = 'pak{0:D2}_dir.vpk' -f [int]$newNums[$i]
    }
    $o = [ordered]@{}
    $cur = Get-PakOverrides; foreach ($k in $cur.Keys) { $o[$k] = $cur[$k] }
    $o[$parentId] = $newNums
    [IO.File]::WriteAllText($PakFile, (ConvertTo-Json $o), (New-Object Text.UTF8Encoding $false))
    $out = @($oldNums | Sort-Object | Select-Object -First $count)
    return , $out
}

function Show-AddDialog($defaultName, $hero, $log) {
    $d = New-Object Windows.Forms.Form
    $d.Text = 'Add mod'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterParent'; $d.ClientSize = New-Object Drawing.Size(520, 560)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $y = 18
    $mk = {
        param($text)
        $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $true; $l.ForeColor = $DlgMuted
        $l.Location = New-Object Drawing.Point(20, $script:dy); $d.Controls.Add($l); $script:dy += 24
    }
    $script:dy = $y
    & $mk 'Name'
    $name = New-Object Windows.Forms.TextBox
    $name.Text = $defaultName; $name.BackColor = $G::Raised; $name.ForeColor = $G::Bright; $name.BorderStyle = 'FixedSingle'
    $name.Location = New-Object Drawing.Point(20, $script:dy); $name.Width = 480; $d.Controls.Add($name); $script:dy += 40
    & $mk 'Hero (only one skin per hero can be on)'
    $heroBox = New-Object Windows.Forms.ComboBox
    $heroBox.DropDownStyle = 'DropDownList'; $heroBox.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco) { 'Explorer' } else { 'DarkMode_CFD' }), $null) }); $heroBox.BackColor = $G::Raised; $heroBox.ForeColor = $G::Bright; $heroBox.FlatStyle = 'Flat'
    $heroBox.Location = New-Object Drawing.Point(20, $script:dy); $heroBox.Width = 240
    $names = @('— not a hero skin —') + @($HeroTable.Values | ForEach-Object { ($_ -split '\|')[0] } | Sort-Object -Unique)
    [void]$heroBox.Items.AddRange($names)
    $heroBox.SelectedItem = if ($hero) { $hero.Display } else { $names[0] }
    $d.Controls.Add($heroBox); $script:dy += 40
    & $mk 'Category'
    $cat = New-Object Windows.Forms.ComboBox
    $cat.DropDownStyle = 'DropDownList'; $cat.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco) { 'Explorer' } else { 'DarkMode_CFD' }), $null) }); $cat.BackColor = $G::Raised; $cat.ForeColor = $G::Bright; $cat.FlatStyle = 'Flat'
    $cat.Location = New-Object Drawing.Point(20, $script:dy); $cat.Width = 240
    [void]$cat.Items.AddRange(@('Skins', 'Map', 'Visuals', 'Sounds & music', 'Utility (recommended)'))
    $cat.SelectedIndex = if ($hero) { 0 } else { 2 }
    $d.Controls.Add($cat); $script:dy += 40
    & $mk 'Alt for an existing mod (overrides its files when on)'
    $par = New-Object Windows.Forms.ComboBox
    $par.DropDownStyle = 'DropDownList'; $par.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco) { 'Explorer' } else { 'DarkMode_CFD' }), $null) }); $par.BackColor = $G::Raised; $par.ForeColor = $G::Bright; $par.FlatStyle = 'Flat'
    $par.Location = New-Object Drawing.Point(20, $script:dy); $par.Width = 480; $par.MaxDropDownItems = 20
    # sama kangelase modid ettepoole
    $cands = @($Mods | Where-Object { -not $_.Parent } | Sort-Object @{ e = { if ($hero -and $_.Hero -eq $hero.Key) { 0 } else { 1 } } }, @{ e = { $_.Name } })
    $parIds = @($null) + @($cands | ForEach-Object { $_.Id })
    [void]$par.Items.Add('— not an alt, separate mod —')
    foreach ($c in $cands) { [void]$par.Items.Add($c.Name) }
    $par.SelectedIndex = 0
    $d.Controls.Add($par); $script:dy += 40

    # Sama koha peal üks kahest: "Kuhu vahelehele" (eraldi mod) või "Kuidas alti näidata" (alt).
    $destLabel = New-Object Windows.Forms.Label
    $destLabel.Text = $(if ($Portable) { 'Where to show it' } else { 'Which tab (skins)' }); $destLabel.AutoSize = $true; $destLabel.ForeColor = $DlgMuted
    $destLabel.Location = New-Object Drawing.Point(20, $script:dy); $d.Controls.Add($destLabel)
    $styleLabel = New-Object Windows.Forms.Label
    $styleLabel.Text = 'How to show the alt'; $styleLabel.AutoSize = $true; $styleLabel.ForeColor = $DlgMuted
    $styleLabel.Location = New-Object Drawing.Point(20, $script:dy); $styleLabel.Visible = $false; $d.Controls.Add($styleLabel)
    $script:dy += 24
    $dest = New-Object Windows.Forms.ComboBox
    $dest.DropDownStyle = 'DropDownList'; $dest.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco) { 'Explorer' } else { 'DarkMode_CFD' }), $null) }); $dest.BackColor = $G::Raised; $dest.ForeColor = $G::Bright; $dest.FlatStyle = 'Flat'
    $dest.Location = New-Object Drawing.Point(20, $script:dy); $dest.Width = 240
    $destKeys = if ($Portable) { @('New') + @($CustomTabs.Keys | ForEach-Object { "tab:$_" }) } else { @('New', 'Other', 'These') }
    [void]$dest.Items.AddRange(@($destKeys | ForEach-Object { if ($_ -eq 'New') { if ($Portable) { 'All mods only' } else { 'New (choose later)' } } elseif ($_ -like 'tab:*') { 'All mods + tab: ' + $_.Substring(4) } else { $_ } }))
    $dest.SelectedIndex = 0
    $d.Controls.Add($dest)
    $style = New-Object Windows.Forms.ComboBox
    $style.DropDownStyle = 'DropDownList'; $style.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco) { 'Explorer' } else { 'DarkMode_CFD' }), $null) }); $style.BackColor = $G::Raised; $style.ForeColor = $G::Bright; $style.FlatStyle = 'Flat'
    $style.Location = New-Object Drawing.Point(20, $script:dy); $style.Width = 480
    [void]$style.Items.AddRange(@('Small "+ alt" button next to the mod', 'Only a small "n" in the mod button corner (click: on/off)'))
    $style.SelectedIndex = 0; $style.Visible = $false
    $d.Controls.Add($style); $script:dy += 44
    $par.Add_SelectedIndexChanged({
        $isAlt = $par.SelectedIndex -ne 0
        $dest.Visible = -not $isAlt; $destLabel.Visible = -not $isAlt
        $style.Visible = $isAlt; $styleLabel.Visible = $isAlt
    })
    # Kontrolli tulemus (lüliti leidis need ise; siia ei kirjutata): pealkiri + keritav infokast
    $infoHead = New-Object Windows.Forms.Label
    $infoHead.Text = 'What the check found:'; $infoHead.AutoSize = $true; $infoHead.ForeColor = $DlgMuted
    $infoHead.Font = New-Object Drawing.Font($FontUi, [Drawing.FontStyle]::Bold)
    $infoHead.Location = New-Object Drawing.Point(20, $script:dy); $d.Controls.Add($infoHead); $script:dy += 22
    $info = New-Object Windows.Forms.Panel
    $info.AutoScroll = $true; $info.BackColor = $(if ($Deco) { [DlUi.G]::Mix($DlgBg, [Drawing.Color]::Black, 0.08) } else { $G::Raised })
    $info.Size = New-Object Drawing.Size(480, (560 - $script:dy - 64))
    $info.Location = New-Object Drawing.Point(20, $script:dy)
    $infoText = New-Object Windows.Forms.Label
    $infoText.AutoSize = $true; $infoText.MaximumSize = New-Object Drawing.Size(456, 0)
    $infoText.Location = New-Object Drawing.Point(8, 6); $infoText.ForeColor = $DlgText; $infoText.BackColor = 'Transparent'
    $infoText.Text = (($log | ForEach-Object { "•  $_" }) -join "`n")
    $info.Controls.Add($infoText); $d.Controls.Add($info)
    $ok = New-Pill 'Add' $true; $ok.FitWidth(28, 36); $ok.Location = New-Object Drawing.Point((500 - $ok.Width), 510)
    $no = New-Pill 'Cancel' $false; $no.FitWidth(18, 36); $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 510)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.AddRange(@($ok, $no))
    if ($d.ShowDialog($form) -ne 'OK' -or -not $name.Text.Trim()) { return $null }
    $sel = [string]$heroBox.SelectedItem
    $key = $null
    if ($sel -and $sel -notlike '—*') { $key = (@($HeroTable.Values | Where-Object { ($_ -split '\|')[0] -eq $sel })[0] -split '\|')[1] }
    if ($hero -and $sel -eq $hero.Display) { $key = $hero.Key }   # ka tabelis veel puuduv (uus) kangelane
    $parent = $parIds[$par.SelectedIndex]
    $where = @($destKeys)[$dest.SelectedIndex]
    $altStyle = if ($parent) { @('chip', 'badge')[$style.SelectedIndex] } else { $null }
    return @{ Name = $name.Text.Trim(); Cat = [string]$cat.SelectedItem; HeroKey = $key; HeroName = $sel; Parent = $parent; Where = $where; AltStyle = $altStyle }
}

function Set-Busy($text) {
    $note.Text = "⏳  $text"; $note.ForeColor = $G::Brand
    $form.Cursor = 'WaitCursor'; $form.Refresh(); [Windows.Forms.Application]::DoEvents()
}

# 1. samm: lahtipakkimine ja kontroll (kangelane, vanad jagatud failid, kaamera). Ei muuda veel midagi.
# Tagastab ettevalmistuse (hashtable); vea korral viskab erandi ja koristab poolikud failid.
function Initialize-ModFile($file, $status) {
    if (-not $status) { $status = { param($t) Set-Busy $t } }
    $ext = [IO.Path]::GetExtension($file).ToLower()
    $base = [IO.Path]::GetFileNameWithoutExtension($file) -replace '\.tar$', ''   # x.tar.gz -> x
    $work = Join-Path $ArchiveDir (Get-Date -Format 'yyyy-MM-dd')
    $prep = @{ File = $file; Ext = $ext; Base = $base; Dir = $null; Files = @(); Hero = $null; Old = $false; CamFixed = $false; Log = (New-Object Collections.ArrayList) }
    try {
        if ($ext -eq '.vpk') {
            $vpks = @(Get-Item -LiteralPath $file)
        } elseif ($ArchiveExts -contains $ext) {
            if (-not $SevenZip) { throw '7-Zip is not installed.' }
            & $status "Extracting: $base"
            $prep.Dir = Join-Path $work $base
            Run $SevenZip x -y "-o$($prep.Dir)" $file | Out-Null
            if (-not (Test-Path -LiteralPath $prep.Dir)) { throw 'Could not extract the archive (file missing or damaged).' }
            # arhiiv arhiivis (.tar.gz, zip zipis): paki ka sisemised lahti, kuni tulevad .vpk failid (kuni 3 taset)
            $seen = @{}
            for ($lvl = 0; $lvl -lt 3; $lvl++) {
                if (@(Get-ChildItem $prep.Dir -Recurse -Filter *.vpk).Count) { break }
                $inner = @(Get-ChildItem $prep.Dir -Recurse -File | Where-Object { $ArchiveExts -contains $_.Extension.ToLower() -and -not $seen[$_.FullName] })
                if (-not $inner.Count) { break }
                foreach ($a in $inner) {
                    $seen[$a.FullName] = 1
                    & $status "Extracting: $($a.Name)"
                    Run $SevenZip x -y "-o$(Join-Path $a.DirectoryName ($a.BaseName + '_x'))" $a.FullName | Out-Null
                }
            }
            $vpks = @(Get-ChildItem $prep.Dir -Recurse -Filter *.vpk | Sort-Object Name)
        } else { throw "Unknown file type: $ext (use .zip .rar .7z .tar.gz .vpk ...)" }
        if (-not $vpks.Count) { throw 'The archive has no .vpk file.' }
        foreach ($v in $vpks) {
            & $status "Checking: $($v.Name)"
            $paths = Get-VpkPaths $v.FullName
            $h = Get-HeroInfo $paths
            if ($h -and -not $prep.Hero) { $prep.Hero = $h }
            $drop = Get-StaleShared $v.FullName $paths $prep.Log
            $src = $v.FullName
            if ($drop.Count) {
                $src = Join-Path $env:TEMP ("dlmod_" + [guid]::NewGuid().ToString('N').Substring(0, 6) + "_" + $v.BaseName + "_clean.vpk")
                Run $Python -I (Join-Path $ToolsDir 'vpkdrop.py') $v.FullName $src @drop | Out-Null
                if (-not (Test-Path $src)) { throw "Removing shared files failed: $($v.Name)" }
            }
            & $status "Checking camera: $($v.Name)"
            $cam = @{ Old = $false; Fixed = $false; Failed = $false }
            $fixedVpk = Repair-Camera $src $paths $cam $prep.Log
            if ($fixedVpk) {
                if ($src -ne $v.FullName) { Remove-Item $src -Force -ErrorAction SilentlyContinue }
                $src = $fixedVpk; $prep.CamFixed = $true
            }
            if ($cam.Failed) { $prep.Old = $true }
            $prep.Files += @{ Src = $src; Tmp = ($src -ne $v.FullName) }
        }
        if ($prep.Hero) { [void]$prep.Log.Insert(0, "Hero: $($prep.Hero.Display)") } else { [void]$prep.Log.Insert(0, 'No hero model found (sound/UI/other mod).') }
        if ($prep.Old) { [void]$prep.Log.Add('Old camera that could not be fixed automatically - "no camera fix" is added to the name.') }
        $nice = ($base -replace '[_\-]+', ' ' -replace '\b(pak\d+|dir|v\d+(\s\d+)*|[0-9a-f]{5})\b', '' -replace '\s+', ' ').Trim()
        $prep.Nice = (Get-Culture).TextInfo.ToTitleCase($nice)
        return $prep
    } catch {
        Clear-PreparedMod $prep
        throw
    }
}

# Loobumisel: ajutised failid ja poolik lahtipakitud kaust ära
function Clear-PreparedMod($prep) {
    if (-not $prep) { return }
    foreach ($f in $prep.Files) { if ($f.Tmp) { Remove-Item -LiteralPath $f.Src -Force -ErrorAction SilentlyContinue } }
    if ($prep.Dir -and (Test-Path -LiteralPath $prep.Dir)) { Remove-Item -LiteralPath $prep.Dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# 2. samm: paigaldus. $ans = @{ Name; Cat; HeroKey; HeroName; Parent; AltStyle; Where }
# Where: 'New' | 'Other' | 'These' | 'tab:<oma vahelehe nimi>'. Ei ehita vahelehti ümber (seda teeb kutsuja).
function Install-PreparedMod($prep, $ans) {
    $files = $prep.Files
    $name = $ans.Name
    if ($ans.Parent) { $ans.Cat = $ById[$ans.Parent].Cat; $ans.HeroKey = $null }
    if ($prep.Old -and $name -notmatch 'no camera fix') { $name += ' - no camera fix' }
    elseif ($prep.CamFixed -and $name -notmatch 'camera') { $name += ' - camera fixed' }
    $slug = ($ans.Name.ToLower() -replace '\([^)]*\)', '' -replace '[^a-z0-9]+', '_').Trim('_')
    if (-not $slug) { $slug = 'mod' }
    $id = $slug; $n = 2; while ($ById.ContainsKey($id)) { $id = "$slug$n"; $n++ }

    $entry = @{ Id = $id; Cat = $ans.Cat; Name = $name; Files = @() }
    $saved = @()
    $paks = if ($ans.Parent) { Get-PaksBelow $ans.Parent $files.Count } else { Get-FreePaks $files.Count }
    $i = 0
    foreach ($f in $files) {
        $i++
        $offName = if ($files.Count -gt 1) { "${id}_$i.vpk" } else { "$id.vpk" }
        $dst = Join-Path $script:Off $offName
        if (Test-Path -LiteralPath $dst) { throw "File already exists: $offName" }
        Copy-Item -LiteralPath $f.Src -Destination $dst
        if ($f.Tmp) { Remove-Item $f.Src -Force -ErrorAction SilentlyContinue }
        $entry.Files += F $paks[$i - 1] $offName
        $saved += [ordered]@{ Pak = [string]$paks[$i - 1]; Off = $offName }
    }
    if ($ans.HeroKey) { $entry.Hero = $ans.HeroKey; $entry.HeroDisplay = $ans.HeroName }
    if ($ans.Parent) { $entry.Parent = $ans.Parent; $entry.AltStyle = $ans.AltStyle }

    # salvesta: lisatud.json + koht (New / Other / These / oma vaheleht)
    $all = @(Get-AddedMods)
    # NB: $(if ...) ilma tulemuseta salvestuks JSON-i kui {} (mitte null), seepärast selged väärtused
    $hk = $null; $hd = $null; if ($ans.HeroKey) { $hk = [string]$ans.HeroKey; $hd = [string]$ans.HeroName }
    $par = $null; $sty = $null; if ($ans.Parent) { $par = [string]$ans.Parent; $sty = [string]$ans.AltStyle }
    $rec = [ordered]@{ Id = $id; Cat = $ans.Cat; Name = $name; Hero = $hk; HeroDisplay = $hd; Parent = $par; AltStyle = $sty; Files = $saved; Added = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Source = [IO.Path]::GetFileName($prep.File) }
    $all += [pscustomobject]$rec
    [IO.File]::WriteAllText($AddedFile, (ConvertTo-Json @($all) -Depth 5), (New-Object Text.UTF8Encoding $false))
    $script:Mods += $entry; $ById[$id] = $entry; $State[$id] = $false
    $where = [string]$ans.Where
    if ($ans.Parent -or $where -eq 'New' -or -not $where) { $script:NewIds = @($NewIds) + $id }
    elseif ($where -eq 'Other') { $script:SkinTab = @($SkinTab) + $id }
    elseif ($where -like 'tab:*') { $tn = $where.Substring(4); if ($CustomTabs.Contains($tn)) { $CustomTabs[$tn] = @($CustomTabs[$tn]) + $id } }
    Save-Placement

    # kangelase pilt, kui seda veel pole
    if ($prep.Hero -and $ans.HeroName -and -not $ans.Parent -and (Test-Path $S2V)) {
        $png = Join-Path $HeroDir ($ans.HeroName.ToLower() + '.png')
        $img = (@($HeroTable.Values | Where-Object { ($_ -split '\|')[0] -eq $ans.HeroName })[0] -split '\|')[2]
        if (-not (Test-Path -LiteralPath $png) -and $img) {
            $tmp = Join-Path $env:TEMP ("dlimg_" + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Force $tmp | Out-Null
            Run $S2V -i (Join-Path $Citadel 'pak01_dir.vpk') -f "panorama/images/heroes/${img}_card_psd.vtex_c" -o $tmp -d | Out-Null
            $p = Get-ChildItem $tmp -Recurse -File | Select-Object -First 1
            if ($p) {
                $im = [Drawing.Image]::FromFile($p.FullName); $w = 120; $h2 = [int]($im.Height * $w / $im.Width)
                $bmp = New-Object Drawing.Bitmap $w, $h2; $gfx = [Drawing.Graphics]::FromImage($bmp)
                $gfx.InterpolationMode = 'HighQualityBicubic'; $gfx.DrawImage($im, 0, 0, $w, $h2); $gfx.Dispose(); $im.Dispose()
                $bmp.Save($png, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            }
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # arhiiv ära Downloadsist
    if ($prep.Ext -ne '.vpk' -and (Split-Path $prep.File -Parent) -ne $ArchiveDir) {
        $target = Join-Path $ArchiveDir ([IO.Path]::GetFileName($prep.File))
        if (-not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $prep.File -Destination $target }
    }
    return @{ Id = $id; Name = $name }
}

# Üks mod (lisamise aknaga)
function Add-ModFromFile($file) {
    if ($script:AddBusy) { return }   # üks lisamine korraga
    $script:AddBusy = $true; $addBtn.Enabled = $false
    $prep = $null; $added = $false
    try {
        $prep = Initialize-ModFile $file
        $form.Cursor = 'Default'; Update-Boxes
        $ans = Show-AddDialog $prep.Nice $prep.Hero $prep.Log
        if (-not $ans) { return }
        $res = Install-PreparedMod $prep $ans
        $added = $true
        Build-Tabs
        if ($ans.Parent) {
            $note.Text = "✓  Added alt: $($res.Name) - for $($ById[$ans.Parent].Name) (off)"
        } else {
            $tabName = if ($ans.Where -in 'Other', 'These') { $ans.Where } elseif ($Portable) { if ($ans.Where -like 'tab:*') { $ans.Where.Substring(4) } else { 'All mods' } } else { 'New' }
            for ($j = 0; $j -lt $TabBtns.Count; $j++) { if ($TabBtns[$j].Title -like "$tabName*") { Show-Tab $j $false } }
            $note.Text = "✓  Added: $($res.Name) (in $tabName, off)"
        }
        $note.ForeColor = $G::Hex('#89D185')
    } catch {
        $form.Cursor = 'Default'
        [Windows.Forms.MessageBox]::Show($form, "Adding the mod failed:`n$($_.Exception.Message)", 'Deadlock Mods') | Out-Null
        Update-Boxes
    } finally {
        if (-not $added) { Clear-PreparedMod $prep }
        $form.Cursor = 'Default'
        $script:AddBusy = $false; $addBtn.Enabled = $true
    }
}

# Mitu faili: mass add aken, mitu faili -> üks lisamine; üks fail -> tavaline lisamise aken
function Add-ModFiles($files) {
    $files = @($files | Where-Object { $_ })
    if ($files.Count -eq 1) { Add-ModFromFile $files[0] }
    elseif ($files.Count -gt 1) { Show-MassAdd $files }
}

function Start-AddMod {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose mod archives or .vpk files (you can pick several)'
    $dlg.Filter = 'Mods (zip, rar, 7z, tar.gz, vpk…)|*.zip;*.rar;*.7z;*.vpk;*.tar;*.gz;*.tgz;*.xz;*.txz;*.bz2;*.tbz2;*.tbz|All files|*.*'
    $dlg.InitialDirectory = $(if (Test-Path 'D:\Downloads') { 'D:\Downloads' } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' })
    $dlg.Multiselect = $true
    if ($dlg.ShowDialog($form) -eq 'OK') { Add-ModFiles $dlg.FileNames }
}

# Nupp päisesse (otsingukasti kõrvale) ja lohistamine aknale
$addBtn = New-Pill '+  Add mod' $true
$addBtn.Font = $FontChip; $addBtn.FitWidth(16, 36)
$addBtn.Add_Click({ if (Get-Command Show-AddMenu -ErrorAction SilentlyContinue) { Show-AddMenu } else { Start-AddMod } })   # menüü: failid / link (uuendused.ps1)
$header.Controls.Add($addBtn)

# failid või brauserist lohistatud link
$dropHandlerEnter = { if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop) -or $_.Data.GetDataPresent([Windows.Forms.DataFormats]::UnicodeText)) { $_.Effect = 'Copy' } }
$dropHandler = {
    $form.Activate()
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { Add-ModFiles $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop); return }
    $t = ([string]$_.Data.GetData([Windows.Forms.DataFormats]::UnicodeText)).Trim()
    if ($t -match '^https?://\S+$' -and (Get-Command Add-ModFromLink -ErrorAction SilentlyContinue)) { Add-ModFromLink $t }
}
function Enable-Drop($ctl) { $ctl.AllowDrop = $true; $ctl.Add_DragEnter($dropHandlerEnter); $ctl.Add_DragDrop($dropHandler) }
Enable-Drop $form; Enable-Drop $content; Enable-Drop $header; Enable-Drop $tabBar
