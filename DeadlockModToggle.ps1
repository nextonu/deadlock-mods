# Deadlock modide lüliti. Käivita enne Deadlocki avamist.
# Sees olev mod = addons\pakNN_dir.vpk, väljas olev = addons_off\<nimi>.vpk (number jääb samaks).
# Uue modi lisamiseks lisa rida $Mods nimekirja (ja soovi korral id $SkinTab nimekirja).

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# --- Ainult üks aken korraga ---
# Teine käivitus ei ava uut akent: annab märku juba avatud aknale (see tuleb ette) ja lõpetab.
# Nimi sõltub kaustast (testide liivakast / jagatav koopia ei sega päris rakendust).
$InstKey = 'DeadlockModToggle_' + (([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLower())))) -replace '-', '').Substring(0, 12)
$ShowEvent = New-Object Threading.EventWaitHandle($false, ([Threading.EventResetMode]::AutoReset), "Local\$InstKey.show")
$created = $false
$AppMutex = New-Object Threading.Mutex($true, "Local\$InstKey", [ref]$created)
if (-not $created) {
    # eelmine aken võib just sulguda (stiili vahetus) -> oota hetk
    try { $created = $AppMutex.WaitOne(700) } catch [Threading.AbandonedMutexException] { $created = $true }
    if (-not $created) {
        try { Add-Type -Namespace DlOnce -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);'; [void][DlOnce.W]::AllowSetForegroundWindow(-1) } catch {}
        [void]$ShowEvent.Set(); exit
    }
}

# --- Laadimise aken (oma lõimes, et animatsioon liiguks ka siis, kui rakendus alles laeb) ---
# "Deadlock Mods.exe" (käivitaja) näitab laadimise akent juba ise kohe klõpsu järel -> siin mitte
$FromLauncher = [bool]$env:DLMODS_LAUNCHER; $env:DLMODS_LAUNCHER = $null
$Splash = [hashtable]::Synchronized(@{ Close = $false; Event = $ShowEvent })
$SplashCode = {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form
    $f.FormBorderStyle = 'None'; $f.StartPosition = 'CenterScreen'; $f.Size = New-Object Drawing.Size(340, 150)
    $f.BackColor = [Drawing.ColorTranslator]::FromHtml('#16130F'); $f.Text = 'Deadlock Mods - loading'; $f.ShowInTaskbar = $true
    $f.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($f, $true, $null)
    $st = @{ A = 0.0; Sw = [Diagnostics.Stopwatch]::StartNew() }
    $gold = [Drawing.ColorTranslator]::FromHtml('#E2B456'); $muted = [Drawing.ColorTranslator]::FromHtml('#9C9384')
    $fTitle = New-Object Drawing.Font('Bahnschrift SemiBold', 17); $fSmall = New-Object Drawing.Font('Segoe UI', 9.5)
    $f.Add_Paint({
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        $pen = New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#7A5A2E'), 2); $g.DrawRectangle($pen, 1, 1, $f.Width - 3, $f.Height - 3); $pen.Dispose()
        # pöörlev kuldne kaar
        $r = New-Object Drawing.RectangleF(34, 47, 56, 56)
        $bg = New-Object Drawing.Pen([Drawing.Color]::FromArgb(50, $gold), 5); $g.DrawEllipse($bg, $r); $bg.Dispose()
        $arc = New-Object Drawing.Pen($gold, 5); $arc.StartCap = 'Round'; $arc.EndCap = 'Round'
        $sweep = 70 + 50 * [Math]::Sin($st.A / 40)
        $g.DrawArc($arc, $r, [float]$st.A, [float]$sweep); $arc.Dispose()
        $tb = New-Object Drawing.SolidBrush($gold); $g.DrawString('DEADLOCK MODS', $fTitle, $tb, 110, 44); $tb.Dispose()
        $dots = '.' * (1 + [int]($st.Sw.ElapsedMilliseconds / 400) % 3)
        $mb = New-Object Drawing.SolidBrush($muted); $g.DrawString("Loading your mods$dots", $fSmall, $mb, 113, 80); $mb.Dispose()
    })
    $t = New-Object Windows.Forms.Timer; $t.Interval = 25
    $t.Add_Tick({
        $st.A = ($st.A + 9) % 360; $f.Invalidate()
        if ($Splash.Event.WaitOne(0)) { $f.TopMost = $true; $f.Activate(); $f.TopMost = $false }   # avati uuesti laadimise ajal
        if ($Splash.Close -or $st.Sw.Elapsed.TotalSeconds -gt 90) { $t.Stop(); $f.Close() }
    })
    $f.Add_Shown({ $t.Start() })
    [Windows.Forms.Application]::Run($f)
}
if (-not $FromLauncher) {
    $splashRs = [RunspaceFactory]::CreateRunspace(); $splashRs.ApartmentState = 'STA'; $splashRs.ThreadOptions = 'ReuseThread'; $splashRs.Open()
    $splashRs.SessionStateProxy.SetVariable('Splash', $Splash)
    $SplashPs = [PowerShell]::Create(); $SplashPs.Runspace = $splashRs
    [void]$SplashPs.AddScript($SplashCode.ToString())
    $SplashJob = $SplashPs.BeginInvoke()
}
function Close-Splash {
    $Splash.Close = $true
    if ($FromLauncher) { try { $ev = [Threading.EventWaitHandle]::OpenExisting("Local\$InstKey.ready"); [void]$ev.Set(); $ev.Dispose() } catch {} }
}

# Jagatav versioon (make_share.ps1): fail portable.txt -> ainult "All mods" vaheleht, Sqookyt pole, tööriistad kaustas tools\
$Portable = Test-Path -LiteralPath (Join-Path $PSScriptRoot 'portable.txt')

# Deadlocki kaust: varem valitud (mangukaust.txt), tavaline Steami koht või Steami teekide nimekiri (libraryfolders.vdf)
function Find-Citadel {
    if ($env:DLMODS_CITADEL) { return $env:DLMODS_CITADEL }
    $c = @()
    $saved = Join-Path $PSScriptRoot 'mangukaust.txt'
    if (Test-Path -LiteralPath $saved) { $c += ([IO.File]::ReadAllText($saved)).Trim() }
    $c += 'C:\Program Files (x86)\Steam\steamapps\common\Deadlock\game\citadel'
    try {
        $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        $libs = @($sp) + @([regex]::Matches([IO.File]::ReadAllText((Join-Path $sp 'steamapps\libraryfolders.vdf')), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' })
        foreach ($l in $libs) { $c += Join-Path $l 'steamapps\common\Deadlock\game\citadel' }
    } catch {}
    foreach ($x in $c) { if ($x -and (Test-Path -LiteralPath (Join-Path $x 'gameinfo.gi'))) { return $x } }
    return $null
}
$Citadel = Find-Citadel
if (-not $Citadel) {
    Close-Splash
    $fb = New-Object Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Deadlock was not found. Choose the Deadlock folder (…\steamapps\common\Deadlock).'
    while (-not $Citadel) {
        if ($fb.ShowDialog() -ne 'OK') { exit }
        foreach ($x in @((Join-Path $fb.SelectedPath 'game\citadel'), (Join-Path $fb.SelectedPath 'citadel'), $fb.SelectedPath)) {
            if (Test-Path -LiteralPath (Join-Path $x 'gameinfo.gi')) { $Citadel = $x; break }
        }
        if (-not $Citadel) { [Windows.Forms.MessageBox]::Show('That folder has no game\citadel\gameinfo.gi. Pick the Deadlock folder.', 'Deadlock Mods') | Out-Null }
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'mangukaust.txt'), $Citadel)
}
$Addons  = Join-Path $Citadel 'addons'
$Off     = Join-Path $Citadel 'addons_off'
# Väljas olevate modide kaust võib olla mujal (nt D kettal, et C-l ruumi oleks): fail valjas_kaust.txt. Mäng seda kausta ei loe.
$OffCfg = Join-Path $PSScriptRoot 'valjas_kaust.txt'
if (-not $env:DLTEST -and (Test-Path -LiteralPath $OffCfg)) { $x = ([IO.File]::ReadAllText($OffCfg)).Trim(); if ($x) { $Off = $x } }
foreach ($d in @($Addons, $Off)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null } }
$Sqooky  = ''   # (ainult originaalis)
# Valve'i puhta gameinfo.gi räsi, mille peale Sqooky v3.8 sobib. Kui uuendus muudab faili, on räsi teine -> küsi Claude'ilt.
$VanillaHash = 'ACFAD238326912201030E8EAB5CBD706128B9F37BE94F2D4D79663A0D6067A48'

function F($pak, $off) { @{ Pak = ('pak{0:D2}_dir.vpk' -f [int]$pak); Off = $off } }   # mäng tunneb ainult kahekohalisi (pak01, mitte pak1)

# Modid tulevad failist lisatud.json (+ Add mod).
$Mods = @()
$SkinTab = @()
$NewIds = @()

# Paigutus (kes on Otheris, kes on veel "New" all) elab failis paigutus.json; ülal on ainult algväärtus.
# Uue modi paigaldamisel lisab Claude selle id "New" nimekirja. Valimata uued on ka These all.
$PlacementFile = Join-Path $PSScriptRoot 'paigutus.json'
# Kasutaja enda vahelehed ("+" vahelehtede ribal): nimi -> modide id-d (modid jäävad ka "Kõik modid" alla)
$CustomTabs = [ordered]@{}
$Favorites = @()     # lemmikud: "Turn all on" paneb kangelase reas lemmiku, mitte juhusliku
function Save-Placement {
    $tabs = [ordered]@{}; foreach ($k in $CustomTabs.Keys) { $tabs[$k] = @($CustomTabs[$k]) }
    $o = [ordered]@{ Other = @($SkinTab); New = @($NewIds); Tabs = $tabs; Favorites = @($Favorites) }
    [IO.File]::WriteAllText($PlacementFile, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}
if (Test-Path -LiteralPath $PlacementFile) {
    $p = [IO.File]::ReadAllText($PlacementFile) | ConvertFrom-Json
    $SkinTab = @($p.Other | Where-Object { $_ }); $NewIds = @($p.New | Where-Object { $_ })
    if ($p.Favorites) { $Favorites = @($p.Favorites | Where-Object { $_ }) }
    if ($p.Tabs) { foreach ($t in $p.Tabs.PSObject.Properties) { $CustomTabs[$t.Name] = @($t.Value | Where-Object { $_ }) } }
} else { Save-Placement }

# Lülitist endast lisatud modid ("+ Lisa mod", vt lisamine.ps1) elavad failis lisatud.json.
$AddedFile = Join-Path $PSScriptRoot 'lisatud.json'
function Get-AddedMods {
    if (-not (Test-Path -LiteralPath $AddedFile)) { return @() }
    return @([IO.File]::ReadAllText($AddedFile) | ConvertFrom-Json | ForEach-Object { $_ })
}
# Vanad (eestikeelsed) rubriigid -> praegused ingliskeelsed
$CatRename = @{ 'Skinnid' = 'Skins'; 'Kaart' = 'Map'; 'Muu välimus' = 'Visuals'; 'Helid ja muusika' = 'Sounds & music'; 'Kasulikud (soovitan sisse jätta)' = 'Utility (recommended)' }
foreach ($a in (Get-AddedMods)) {
    $cat = if ($CatRename.ContainsKey([string]$a.Cat)) { $CatRename[[string]$a.Cat] } else { $a.Cat }
    $e = @{ Id = $a.Id; Cat = $cat; Name = $a.Name; Files = @($a.Files | ForEach-Object { F $_.Pak $_.Off }) }
    # (vanemates kirjetes võib tühi väärtus olla {} - see pole kangelane)
    if ($a.Hero -is [string] -and $a.Hero) { $e.Hero = $a.Hero; if ($a.HeroDisplay -is [string] -and $a.HeroDisplay) { $e.HeroDisplay = $a.HeroDisplay } }
    if ($a.Parent -is [string] -and $a.Parent) { $e.Parent = $a.Parent; if ($a.AltStyle -is [string] -and $a.AltStyle) { $e.AltStyle = $a.AltStyle } }
    $Mods += $e
}

# Lülitist kustutatud modid (nupp "✕ Kustuta mod", vt kustutamine.ps1): kustutatud.json [id, ...]
$DeletedFile = Join-Path $PSScriptRoot 'kustutatud.json'
function Get-DeletedIds {
    if (-not (Test-Path -LiteralPath $DeletedFile)) { return @() }
    return @([IO.File]::ReadAllText($DeletedFile) | ConvertFrom-Json | ForEach-Object { $_ })
}
$gone = Get-DeletedIds
if ($gone.Count) { $Mods = @($Mods | Where-Object { $gone -notcontains $_.Id }) }

# Kasutaja antud nimed (paremklõps -> "Nimeta ümber"): nimed.json { id: nimi }. Failid jäävad samaks.
$NamesFile = Join-Path $PSScriptRoot 'nimed.json'
function Get-NameOverrides {
    $h = @{}
    if (Test-Path -LiteralPath $NamesFile) {
        try { $o = [IO.File]::ReadAllText($NamesFile) | ConvertFrom-Json; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = [string]$p.Value } } catch {}
    }
    return $h
}
$nameOv = Get-NameOverrides
foreach ($m in $Mods) { $m.OrigName = $m.Name; if ($nameOv.ContainsKey($m.Id)) { $m.Name = $nameOv[$m.Id] } }

# Ümbernummerdatud modid (alt võttis põhimodi pak-numbri, põhimod sai uue): pakid.json { id: [numbrid] }
$PakFile = Join-Path $PSScriptRoot 'pakid.json'
function Get-PakOverrides {
    $h = @{}
    if (Test-Path -LiteralPath $PakFile) {
        $o = [IO.File]::ReadAllText($PakFile) | ConvertFrom-Json
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = @($p.Value) }
    }
    return $h
}
$po = Get-PakOverrides
foreach ($m in $Mods) {
    if ($po.ContainsKey($m.Id)) { for ($i = 0; $i -lt $m.Files.Count -and $i -lt $po[$m.Id].Count; $i++) { $m.Files[$i].Pak = ('pak{0:D2}_dir.vpk' -f [int]$po[$m.Id][$i]) } }
}

$ById = @{}; foreach ($m in $Mods) { $ById[$m.Id] = $m }

function Test-On($mod) { Test-Path -LiteralPath (Join-Path $Addons $mod.Files[0].Pak) }

function Set-Files($files, [bool]$on) {
    foreach ($f in $files) {
        $a = Join-Path $Addons $f.Pak; $o = Join-Path $Off $f.Off
        if ($on -and -not (Test-Path -LiteralPath $a)) {
            if (-not (Test-Path -LiteralPath $o)) { throw "Faili ei leitud: $o" }
            $note.Text = "⏳  Saving: $($f.Off)  ($([Math]::Round((Get-Item -LiteralPath $o).Length / 1MB)) MB)"; $note.ForeColor = $G::Brand; $note.Refresh()   # (teise kettale kopeerimine võtab aega)
            Move-Item -LiteralPath $o -Destination $a
        } elseif (-not $on -and (Test-Path -LiteralPath $a)) {
            if (Test-Path -LiteralPath $o) { throw "File exists in both folders: $($f.Off)" }
            $note.Text = "⏳  Saving: $($f.Off)  ($([Math]::Round((Get-Item -LiteralPath $a).Length / 1MB)) MB)"; $note.ForeColor = $G::Brand; $note.Refresh()
            Move-Item -LiteralPath $a -Destination $o
        }
    }
}

function Get-GameinfoState {
    $gi = Join-Path $Citadel 'gameinfo.gi'
    if (Select-String -LiteralPath $gi -Pattern 'citadel/addons' -Quiet) { return 'ok' }
    if (-not $Portable -and (Test-Path -LiteralPath $Sqooky) -and (Get-FileHash -LiteralPath $gi).Hash -eq $VanillaHash) { return 'fixable' }
    if (Select-String -LiteralPath $gi -Pattern '^\s*(Game|Mod)\s+"?citadel"?\s*$' -Quiet) { return 'fixable' }   # tavaline lisamine (vt Enable-ModsInGameinfo)
    return 'unknown'
}

# Modid mängus sisse: gameinfo.gi SearchPaths plokki rida "Game citadel/addons" esimese "Game citadel" / "Mod citadel" rea ette
# (sama, mida modijuhendid ja Deadlock Mod Manager teevad). Originaal: gameinfo.gi.before_mods
function Enable-ModsInGameinfo {
    $gi = Join-Path $Citadel 'gameinfo.gi'
    if (-not $Portable -and (Test-Path -LiteralPath $Sqooky) -and (Get-FileHash -LiteralPath $gi).Hash -eq $VanillaHash) {
        Copy-Item -LiteralPath $Sqooky -Destination $gi -Force; return
    }
    $lines = [IO.File]::ReadAllLines($gi)
    $out = New-Object Collections.Generic.List[string]; $done = $false
    foreach ($l in $lines) {
        if (-not $done -and $l -match '^(\s*)(Game|Mod)\s+"?citadel"?\s*$') { $out.Add("$($Matches[1])Game`t`t`t`tcitadel/addons"); $done = $true }
        $out.Add($l)
    }
    if (-not $done) { throw 'The game config file looks different than expected; mods could not be enabled automatically.' }
    $bak = "$gi.before_mods"; Copy-Item -LiteralPath $gi -Destination $bak -Force
    [IO.File]::WriteAllLines($gi, $out.ToArray())
}

# --- olek: üks väärtus modi kohta, kõik linnukesed (mõlemal vahelehel) näitavad seda ---
$State = @{}; foreach ($m in $Mods) { $State[$m.Id] = [bool](Test-On $m) }
$Boxes = @{}       # id -> linnukeste nimekiri
$AllBoxes = @()    # @{ Box; Ids } "Kõik" linnukesed
$syncing = $false

# Kasutaja muutis ühte modi: sama kangelase teised välja, välja lülitades Swap sisse.
function Set-Mod($id, [bool]$on) {
    $m = $ById[$id]
    if ($on -and $m.Hero) {
        foreach ($o in $Mods) { if ($o.Hero -eq $m.Hero -and $o.Id -ne $id) { $State[$o.Id] = $false } }
    }
    # Other-vahelehe skinni maha võtmine paneb sama kangelase skinni, mis Otheris pole (Swap, muidu juhuslik).
    # Kui sellist pole, jääb kangelane ilma. Mujalt maha võttes midagi asemele ei tule.
    # Kui see skinn polnud mängus sees (kasutaja võtab oma klõpsu tagasi), minnakse tagasi mängus olevale
    # olekule: teine sama kangelase skinn, mis mängus sees on, või mitte midagi (muidu jäi "1 unsaved change").
    if (-not $on -and $State[$id] -and $m.Hero -and ($SkinTab -contains $id)) {
        $next = $null
        $inGame = @($Mods | Where-Object { $_.Hero -eq $m.Hero -and $_.Id -ne $id -and -not $_.Parent -and (Test-On $_) } | ForEach-Object { $_.Id })
        if ($inGame.Count) { $next = $inGame[0] }
        elseif (Test-On $m) {
            $next = $m.Swap
            if (-not $next) {
                $others = @($Mods | Where-Object { $_.Hero -eq $m.Hero -and $_.Id -ne $id -and ($SkinTab -notcontains $_.Id) } | ForEach-Object { $_.Id })
                if ($others.Count) { $next = $others | Get-Random }
            }
        }
        if ($next) { $State[$id] = $false; Set-Mod $next $true }
    }
    $State[$id] = $on
    # Lisa (Parent) töötab ainult koos oma modiga: lisa sisse -> mod ka sisse.
    if ($on -and $m.Parent -and -not $State[$m.Parent]) { Set-Mod $m.Parent $true }
    Sync-Children
}

# Mod väljas -> tema lisad ka välja (ka siis, kui mod läks välja teise skinni pärast).
function Sync-Children {
    foreach ($c in $Mods) { if ($c.Parent -and $State[$c.Id] -and -not $State[$c.Parent]) { $State[$c.Id] = $false } }
}
function Get-Children($id) { @($Mods | Where-Object { $_.Parent -eq $id }) }

# Nimekiri ridadeks: sama kangelase modid ühele reale (rea koht = esimese modi koht).
function Get-Rows($ids) {
    $rows = New-Object Collections.ArrayList; $byHero = @{}
    foreach ($id in $ids) {
        $h = $ById[$id].Hero
        if ($h -and $byHero[$h]) { [void]$byHero[$h].Add($id); continue }
        $row = New-Object Collections.ArrayList; [void]$row.Add($id)
        if ($h) { $byHero[$h] = $row }
        [void]$rows.Add($row)
    }
    return , $rows
}

function Test-RowOn($row) { foreach ($id in $row) { if ($State[$id]) { return $true } }; return $false }


# --- välimus: tume, Ajukase värvid. Joonistatud osad (kaardid, nupud) on failis ui.cs ---
# ui.cs kompileeritakse ainult siis, kui see on muutunud (valmis DLL vahemälus; enne kompileeriti iga käivitusega, ~1 s)
function Import-UiCs {
    $cs = Join-Path $PSScriptRoot 'ui.cs'
    $hash = (Get-FileHash -LiteralPath $cs -Algorithm SHA1).Hash.Substring(0, 16)
    $dir = Join-Path $env:LOCALAPPDATA 'DeadlockMods\cache'
    $dll = Join-Path $dir "ui_$hash.dll"
    try {
        if (-not (Test-Path -LiteralPath $dll)) {
            New-Item -ItemType Directory -Force $dir | Out-Null
            $tmp = Join-Path $dir "ui_$hash.$PID.tmp.dll"
            Add-Type -Path $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing -OutputAssembly $tmp -OutputType Library
            Move-Item -LiteralPath $tmp $dll -Force
            Get-ChildItem $dir -Filter 'ui_*.dll' | Where-Object { $_.FullName -ne $dll } | Remove-Item -ErrorAction SilentlyContinue   # vanad (lukus olevad jäävad)
        }
        Add-Type -Path $dll; return
    } catch {}
    Add-Type -Path $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing   # varuvariant: nagu enne
}
Import-UiCs

# Teema: "deadlock" (poe stiil, vaikimisi) või "ajukas" (eelmine must-kollane). Valik failis seaded.json.
# Eelmise välimuse täielik koopia on kaustas varu_ajukas_stiil.
$SettingsFile = Join-Path $PSScriptRoot 'seaded.json'
$Theme = 'deadlock'
if (Test-Path -LiteralPath $SettingsFile) {
    try { $s = [IO.File]::ReadAllText($SettingsFile) | ConvertFrom-Json; if ($s.Theme) { $Theme = $s.Theme } } catch {}
}
[DlUi.G]::Apply($Theme)
$Deco = [DlUi.G]::Deco
$Night = [DlUi.G]::Night
# Akende (Add mod, Rename, Bulk add) värvid: Deadlocki teemas paberleht tumeda kirjaga
$DlgBg = if ($Deco) { [DlUi.G]::PageBg } else { [DlUi.G]::Bg }; $DlgText = [DlUi.G]::Text; $DlgMuted = [DlUi.G]::Muted
# [DlToggle.Native] (DwmSetWindowAttribute, SetWindowTheme, SendMessage) on failis ui.cs
[Windows.Forms.Application]::EnableVisualStyles()
$G = [DlUi.G]

$FontUi    = New-Object Drawing.Font('Segoe UI', 10)
$FontChip  = New-Object Drawing.Font('Segoe UI', 9.5)
$FontSmallChip = New-Object Drawing.Font('Segoe UI', 8.5)
$FontHint = New-Object Drawing.Font('Segoe UI Semibold', 9.75)   # vahelehe ülarea selgitus (paremini loetav)
$FontTitle = New-Object Drawing.Font('Segoe UI Semibold', 11.5)
$FontBig   = New-Object Drawing.Font('Segoe UI Semibold', 20)
$FontTab   = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$FontMono  = New-Object Drawing.Font('Consolas', 9, [Drawing.FontStyle]::Bold)
if ($Deco) {
    # Deadlocki poe moodi kitsad suurtähed
    $FontTitle = New-Object Drawing.Font('Bahnschrift SemiBold', 12.5)
    $FontTab   = New-Object Drawing.Font('Bahnschrift SemiBold', 11.5)
    $FontMono  = New-Object Drawing.Font('Bahnschrift SemiBold Condensed', 11.5)
    $FontUi    = New-Object Drawing.Font('Segoe UI', 10)
}

function Set-DarkScroll($ctl) { $ctl.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, 'DarkMode_Explorer', $null) }) }

# Kangelaste pildid: heroes\<kangelane>.png (mängu failidest võetud).
$HeroDir = Join-Path $PSScriptRoot 'heroes'
$ImgCache = @{}
function Get-HeroImage($name) {
    if (-not $name) { return $null }
    $k = $name.ToLower()
    if (-not $ImgCache.ContainsKey($k)) {
        $p = Join-Path $HeroDir "$k.png"
        $ImgCache[$k] = if (Test-Path -LiteralPath $p) { [Drawing.Image]::FromFile($p) } else { $null }
    }
    return $ImgCache[$k]
}
# Modi enda pilt (paremklõps -> Picture, vt pildid.ps1): pildid\<id>.png. Laetakse mälust (fail ei jää lukku).
$ModPicDir = Join-Path $PSScriptRoot 'pildid'
$ModPicCache = @{}
function Read-ImageNoLock($path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $img = [Drawing.Image]::FromStream((New-Object IO.MemoryStream(, $bytes)))
    $bmp = New-Object Drawing.Bitmap $img; $img.Dispose(); return $bmp
}
function Get-ModPicture($id) {
    $p = Join-Path $ModPicDir "$id.png"
    if (-not (Test-Path -LiteralPath $p)) { $ModPicCache.Remove($id); return $null }
    $t = (Get-Item -LiteralPath $p).LastWriteTimeUtc.Ticks
    $c = $ModPicCache[$id]
    if (-not $c -or $c.T -ne $t) { $c = @{ T = $t; Img = (Read-ImageNoLock $p) }; $ModPicCache[$id] = $c }
    return $c.Img
}
# Kelle pilti kaart näitab: sees olev mod, ja kui tema alt ("n" / "+") on sees ja sellel on oma pilt, siis alt.
# Ühe modiga kaardil see mod (ja tema sees olev alt). $null = keegi pole sees (mitme modiga kaart).
function Get-CardShownMod($row) {
    $main = @($row | Where-Object { $State[$_] })[0]
    if (-not $main -and @($row).Count -eq 1) { $main = $row[0] }
    if (-not $main) { return $null }
    foreach ($c in $Mods) { if ($c.Parent -eq $main -and $State[$c.Id] -and (Test-Path -LiteralPath (Join-Path $ModPicDir "$($c.Id).png"))) { return $c.Id } }
    return $main
}
# Kaardi pilt: sees oleva modi (või tema sees oleva aldi) pilt; ühe modiga kaardil tema pilt; muidu kangelase pilt; muidu mõne modi pilt
$BuildingTab = $null
function Get-CardPicture($row, $heroImg, $tab = $null) {
    $id = Get-CardShownMod $row
    if ($id) { $p = Get-ModPicture $id; if ($p) { return $p } }
    foreach ($id in $row) { if ($State[$id]) { $p = Get-ModPicture $id; if ($p) { return $p } } }
    if (@($row).Count -eq 1) { $p = Get-ModPicture $row[0]; if ($p) { return $p } }
    if ($heroImg) { return $heroImg }
    foreach ($id in $row) { $p = Get-ModPicture $id; if ($p) { return $p } }
    return $null
}
# Kangelase nimi kaardile ja pildile: nimes sulgudes, või (lülitist lisatud modidel) Hero võtme järgi.
function Get-HeroName($mod) {
    if ($mod.Name -match '\(([^)]*)\)') { return $Matches[1] }
    if ($mod.HeroDisplay) { return $mod.HeroDisplay }
    if ($mod.Hero -and $HeroTable) {
        foreach ($v in $HeroTable.Values) { $p = $v -split '\|'; if ($p[1] -eq $mod.Hero) { return $p[0] } }
    }
    return $null
}
function Get-ShortName($mod) { (($mod.Name -replace '\s*\([^)]*\)', '') -replace ' - ', ' · ').Trim() }

$Cards = @()      # @{ Card; Title; Row; Text; Header }
$AltChips = @()   # @{ Chip; Alt } - "n" nurgamärgiga altid

function Update-Boxes {
    Sync-Children
    $script:syncing = $true
    foreach ($id in $Boxes.Keys) { foreach ($b in $Boxes[$id]) { $b.Checked = $State[$id] } }
    foreach ($ac in $AltChips) { $on = [bool]$State[$ac.Alt]; if ($ac.Chip.AltOn -ne $on) { $ac.Chip.AltOn = $on; $ac.Chip.Invalidate() } }
    foreach ($c in $Cards) {
        $on = Test-RowOn $c.Row
        if ($c.Card.On -ne $on) { $c.Card.On = $on; $c.Card.Invalidate() }
        if ($c.Card.Picture) { $pic = Get-CardPicture $c.Row $c.HeroImg $c.Tab; if ($pic -and -not [object]::ReferenceEquals($pic, $c.Card.Picture)) { $c.Card.Picture = $pic; $c.Card.Invalidate() } }
        $c.Title.ForeColor = if ($on) { $G::Bright } else { $G::Text }
    }
    foreach ($a in $AllBoxes) {
        $n = 0; foreach ($row in $a.Rows) { if (Test-RowOn $row) { $n++ } }
        $a.Full = ($n -eq $a.Rows.Count)
        $a.Box.Text = if ($a.Full) { 'Turn all off' } else { 'Turn all on' }
        $a.Count.Text = "$n / $($a.Rows.Count) on"
    }
    # Salvestamata muudatused
    # Üks muudatus kangelase kohta: skinni vahetus (üks maha, teine peale) loeb ühena.
    $changed = @{}; foreach ($m in $Mods) { if ([bool]$State[$m.Id] -ne [bool](Test-On $m)) { $grp = if ($m.Parent -and $ById[$m.Parent]) { $ById[$m.Parent] } else { $m }; $changed[$(if ($grp.Hero) { "h:$($grp.Hero)" } else { $grp.Id })] = 1 } }
    $diff = $changed.Count
    if ($diff) { $note.Text = "●  $diff unsaved change" + $(if ($diff -gt 1) { 's' } else { '' }); $note.ForeColor = $G::Brand }
    else { $note.Text = 'Changes reach the game after you press Save and start Deadlock. Don''t want to keep them? Just close the app.'; $note.ForeColor = $G::HeadMuted }
    $script:syncing = $false
}

function New-Pill($text, [bool]$primary) {
    $b = New-Object DlUi.Pill
    $b.Primary = $primary
    $b.Font = if ($primary) { New-Object Drawing.Font('Segoe UI Semibold', 10.5) } else { $FontUi }
    $b.Text = $text
    return $b
}

# --- aken ---
$form = New-Object Windows.Forms.Form
$form.Text = 'Deadlock Mods'
$icon = if ($Deco) { Join-Path $PSScriptRoot 'toggle.ico' } else { Join-Path $PSScriptRoot 'varu_ajukas_stiil\toggle.ico' }
if (Test-Path -LiteralPath $icon) { $form.Icon = New-Object Drawing.Icon($icon) }
$form.Font = $FontUi
$form.BackColor = $G::Bg
$form.ForeColor = $G::HeadText
$form.StartPosition = 'CenterScreen'
$wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.ClientSize = New-Object Drawing.Size(846,[Math]::Min(880, $wa.Height - 60))
$form.MinimumSize = New-Object Drawing.Size(500, 520)
$form.Add_HandleCreated({ [DlUi.MoveWatcher]::Attach($this) })   # sujuv lohistamine (vt ui.cs MoveWatcher)
$form.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })

# Päis
$header = New-Object Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 112
$eyebrow = New-Object Windows.Forms.Label
$eyebrow.Text = 'DEADLOCK'; $eyebrow.Font = $FontMono; $eyebrow.ForeColor = $G::Brand; $eyebrow.AutoSize = $true
$eyebrow.Location = New-Object Drawing.Point(24, 16)
$title = New-Object Windows.Forms.Label
$title.Text = 'Mods'; $title.Font = $FontBig; $title.ForeColor = $G::Bright; $title.AutoSize = $true
$title.Location = New-Object Drawing.Point(20, 32)
$status = New-Object Windows.Forms.Label
$status.AutoSize = $true; $status.MaximumSize = New-Object Drawing.Size(520, 0)
$status.Location = New-Object Drawing.Point(25, 80)
$fixBtn = New-Pill $(if ($Portable) { 'Enable mods' } else { 'Re-enable mods' }) $false
$fixBtn.Dark = $Deco; $fixBtn.FitWidth(12, 26); $fixBtn.Visible = $false
$header.Controls.AddRange(@($eyebrow, $title, $status, $fixBtn))
if ($Deco) {
    # Deadlocki teema: joonistatud logo (embleem + DEADLOCK / MODID) ja soe kuldne üleminek päises
    $eyebrow.Visible = $false; $title.Visible = $false
    $logo = New-Object DlUi.Logo
    $logo.Location = New-Object Drawing.Point(18, 10)
    $header.Controls.Add($logo)
    $logo.SendToBack()   # nupud alati logo peal, kui aken on kitsas
    $status.Location = New-Object Drawing.Point(25, 84)
    $header.Height = 116
    # Päis ja alumine riba nagu poe tumedad paneelid: tume kulunud paber + pronksist äär
    $DarkBar = {
        param($gfx, $r, [bool]$trimBottom)   # NB: mitte $g - see on sama mis $G (teema)
        [DlUi.G]::PaintPaper($gfx, $r, [DlUi.G]::Hex($(if ($Night) { '#16130F' } else { '#2A231C' })), $true)
        $sh = New-Object Drawing.Drawing2D.LinearGradientBrush($r, [Drawing.Color]::FromArgb(0, 0, 0, 0), [Drawing.Color]::FromArgb(70, 0, 0, 0), $(if ($trimBottom) { 270 } else { 90 }))
        $gfx.FillRectangle($sh, $r); $sh.Dispose()
        $y = if ($trimBottom) { $r.Bottom - 3 } else { $r.Top }
        $b1 = New-Object Drawing.SolidBrush([DlUi.G]::Hex('#7A5A2E')); $gfx.FillRectangle($b1, $r.Left, $y, $r.Width, 3); $b1.Dispose()
        $p2 = New-Object Drawing.Pen([DlUi.G]::Hex('#C79A55'), 1); $gfx.DrawLine($p2, $r.Left, $(if ($trimBottom) { $y } else { $y + 2 }), $r.Right, $(if ($trimBottom) { $y } else { $y + 2 })); $p2.Dispose()
    }
    $header.Add_Paint({ & $DarkBar $_.Graphics $this.ClientRectangle $true })
    foreach ($c in @($status)) { $c.BackColor = 'Transparent' }
}

# Otsing (päise paremas servas)
$searchFrame = New-Object DlUi.Frame
$searchFrame.Size = New-Object Drawing.Size(260, 36)
$search = New-Object Windows.Forms.TextBox
$search.BorderStyle = 'None'; $search.BackColor = $G::SearchFill; $search.ForeColor = $G::SearchText
$search.Font = New-Object Drawing.Font('Segoe UI', 10.5)
$search.Location = New-Object Drawing.Point(34, 8); $search.Width = 212
$searchIcon = New-Object Windows.Forms.Label
$searchIcon.Text = [string][char]0xE721; $searchIcon.Font = New-Object Drawing.Font('Segoe MDL2 Assets', 10)
$searchIcon.ForeColor = $G::HeadMuted; $searchIcon.BackColor = $G::SearchFill; $searchIcon.AutoSize = $true
$searchIcon.Location = New-Object Drawing.Point(11, 10)
$searchFrame.Controls.AddRange(@($search, $searchIcon))
$searchFrame.Add_Click({ $search.Focus() })
$search.Add_GotFocus({ $searchFrame.Focused2 = $true; $searchFrame.Invalidate() })
$search.Add_LostFocus({ $searchFrame.Focused2 = $false; $searchFrame.Invalidate() })
$search.Add_HandleCreated({ [void][DlToggle.Native]::SendMessage($this.Handle, 0x1501, [IntPtr]1, 'Search…') })
$header.Controls.Add($searchFrame)

# Vahelehtede riba (kollane joon libiseb valitud vahelehe alla)
$tabBar = New-Object Windows.Forms.Panel
$tabBar.Dock = 'Top'; $tabBar.Height = 46
if ($Deco) {
    # poe ülemine kategooriariba: tumedam kulunud paber
    $tabBar.BackColor = $G::TabBg
    $tabBar.Add_Paint({ [DlUi.G]::PaintPaper($_.Graphics, $this.ClientRectangle, [DlUi.G]::TabBg, $false) })
}
$tabLine = New-Object Windows.Forms.Panel
$tabLine.Dock = 'Bottom'; $tabLine.Height = 1; $tabLine.BackColor = $(if ($Deco) { $G::TabEdge } else { $G::Line })
$tabBar.Controls.Add($tabLine)
$under = New-Object Windows.Forms.Panel
$under.Height = 3; $under.BackColor = $G::TabLine
$tabBar.Controls.Add($under); $under.BringToFront()
$UnderTarget = @{ X = 0.0; W = 0.0; CurX = 0.0; CurW = 0.0 }
$anim = New-Object Windows.Forms.Timer
$anim.Interval = 15
$anim.Add_Tick({
    $u = $UnderTarget
    $u.CurX += ($u.X - $u.CurX) * 0.3; $u.CurW += ($u.W - $u.CurW) * 0.3
    if ([Math]::Abs($u.X - $u.CurX) -lt 0.5 -and [Math]::Abs($u.W - $u.CurW) -lt 0.5) { $u.CurX = $u.X; $u.CurW = $u.W; $anim.Stop() }
    $under.SetBounds([int]$u.CurX, 42, [int]$u.CurW, 3)
})

$content = New-Object Windows.Forms.Panel
$Scroll = New-Object DlUi.ScrollBarLite; $Scroll.Dock = 'Right'   # ilus kerimisriba (Windowsi oma on peidus)
$content.Dock = 'Fill'; $content.BackColor = $G::PageBg
$content.Controls.Add($Scroll)

$TabBtns = @()
$CurTab = 0
function Show-Tab($i, [bool]$instant) {
    if (-not $TabBtns[$i].Built) { $form.Cursor = 'WaitCursor'; try { Prebuild-Tab $i } finally { $form.Cursor = 'Default' } }
    Show-TabNow $i $instant
}
# Vahelehe kaardid valmis (esimesel avamisel või taustal, vt $PrebuildTimer)
function Prebuild-Tab($i) {
    if ($TabBtns[$i].Built) { return }
    $nAll = $AllBoxes.Count; $nAlt = $AltChips.Count; $script:FillChips = New-Object Collections.ArrayList
    Fill-TabPage $TabBtns[$i]
    $newChips = $script:FillChips; $script:FillChips = $null
    if (-not $script:InBuildTabs) {
        # ainult selle vahelehe nupud/kaardid/loendur (kogu Update-Boxes võttis ~0,5 s)
        $script:syncing = $true
        foreach ($b in $newChips) { $b.Checked = [bool]$State[$b.Tag] }
        foreach ($ac in @($AltChips | Select-Object -Skip $nAlt)) { $ac.Chip.AltOn = [bool]$State[$ac.Alt] }
        $script:syncing = $false
        foreach ($c in $Cards) {
            if ($c.Tab -ne $TabBtns[$i].Title) { continue }
            $on = Test-RowOn $c.Row; $c.Card.On = $on; $c.Title.ForeColor = if ($on) { $G::Bright } else { $G::Text }
        }
        foreach ($a in @($AllBoxes | Select-Object -Skip $nAll)) {
            $n = 0; foreach ($row in $a.Rows) { if (Test-RowOn $row) { $n++ } }
            $a.Full = ($n -eq $a.Rows.Count); $a.Box.Text = if ($a.Full) { 'Turn all off' } else { 'Turn all on' }; $a.Count.Text = "$n / $($a.Rows.Count) on"
        }
        if ($search.Text.Trim()) { Apply-Search }
        if ($script:DeleteMode -and (Get-Command Update-DeleteUi -ErrorAction SilentlyContinue)) { Update-DeleteUi }
        Initialize-Page $TabBtns[$i] $newChips
    }
}
function Show-TabNow($i, [bool]$instant) {
    foreach ($tb in $TabBtns) { $tb.Page.SyncNow() }   # pooleli kerimine lõpetatakse enne vahetust
    $script:CurTab = $i
    for ($j = 0; $j -lt $TabBtns.Count; $j++) {
        $t = $TabBtns[$j]; $sel = ($j -eq $i)
        # Aknas on ainult valitud vahelehe sisu. Teised võetakse aknast välja (WinForms hoiab nende aknad alles
        # "parkimisaknas", vahetus on ikka kiire): peidetud alamaknad tegid akna lohistamise aeglaseks.
        $clip = $t.Page.Parent
        if ($sel) { if ($clip.Parent -ne $content) { $content.Controls.Add($clip) }; $clip.Visible = $true; $clip.BringToFront() }
        elseif ($clip.Parent -eq $content) { $content.Controls.Remove($clip) }
        if ($sel -and $Scroll) { $Scroll.Target = $t.Page; $Scroll.Invalidate() }
        $selL = [object]::ReferenceEquals($t.Label, $TabBtns[$i].Label)   # rühma lehtedel on üks ühine silt
        $t.Label.ForeColor = if ($selL) { $G::TabSel } elseif ($t.Label.AccessibleDescription -eq 'new') { $G::TabNew } else { $G::TabIdle }
    }
    if ($TabBtns[$i].Group) { $GroupLast[$TabBtns[$i].Group] = $TabBtns[$i].Title }
    $l = $TabBtns[$i].Label
    $UnderTarget.X = [double]$l.Left; $UnderTarget.W = [double]$l.Width
    if ($instant) { $UnderTarget.CurX = $UnderTarget.X; $UnderTarget.CurW = $UnderTarget.W; $under.SetBounds($l.Left, 42, $l.Width, 3) }
    else { $anim.Start() }
}

function New-Chip($parent, $text, $id, [bool]$onOff, [bool]$small = $false) {
    $cb = New-Object DlUi.Chip
    $cb.Font = if ($small) { $FontSmallChip } else { $FontChip }
    $cb.Small = $small
    $cb.Text = $(if ($Favorites -contains $id -and -not $onOff) { "★ $text" } else { $text })
    if ($text -and $script:GoneMods -and $script:GoneMods.ContainsKey($id)) { $cb.Text += '  · page removed' }   # autor võttis GameBanana lehe maha (uuendused.ps1)
    if ($DelMarked -and $DelMarked[$id]) { $cb.Marked = $true }
    if ($small -and -not $Portable -and ($NewIds -contains $id)) { $cb.Badge = 'n' }
    $cb.OnOff = $onOff
    # väike joon: pilti pole veel (lisal/aldil loeb ka põhimodi pilt - kaardil on siis see)
    $pm = $ById[$id]
    $cb.NoPic = -not (Test-Path -LiteralPath (Join-Path $ModPicDir "$id.png")) -and -not ($pm -and $pm.Parent -and (Test-Path -LiteralPath (Join-Path $ModPicDir "$($pm.Parent).png")))
    $cb.Margin = New-Object Windows.Forms.Padding(0, 0, 6, 6)
    $cb.FitWidth(270)
    $cb.Tag = $id
    $cb.Add_CheckedChanged({
        if ($script:syncing) { return }
        # Kustutamisrežiimis ei lülita nupp modi, vaid küsib kustutamist.
        if ($script:DeleteMode) {
            $script:syncing = $true; $this.Checked = -not $this.Checked; $script:syncing = $false
            Switch-DeleteMark $this.Tag; return    # märgi / võta märge maha (kustutab alles "Delete selected")
        }
        # Uue lisa "n" kaob esimesel vajutusel.
        if ($this.Badge) {
            $script:NewIds = @($NewIds | Where-Object { $_ -ne $this.Tag }); Save-Placement
            foreach ($b in $Boxes[$this.Tag]) { $b.Badge = ''; $b.Invalidate() }
        }
        Set-Mod $this.Tag $this.Checked; Update-Boxes
    })
    if ($ModMenu) { $cb.ContextMenuStrip = $ModMenu }   # paremklõps: nimeta ümber / kustuta
    $parent.Controls.Add($cb)
    if (-not $Boxes[$id]) { $Boxes[$id] = @() }
    $Boxes[$id] += $cb
    if ($script:FillChips) { [void]$script:FillChips.Add($cb) }   # Show-Tab: selle vahelehe uued nupud
    return $cb
}

$CardW = 380      # kaardi nähtav laius
# Peatükid (rubriigid) selles järjekorras; tundmatu rubriik läheb lõppu
$CatOrder = @('Skins', 'Map', 'Visuals', 'Sounds & music', 'Utility (recommended)')
function New-Card($flow, $row, $headerRef, [bool]$placing) {
    $m = $ById[$row[0]]
    $hero = Get-HeroName $m
    $heroImg = Get-HeroImage $hero
    $img = Get-CardPicture $row $heroImg $script:BuildingTab
    $multi = $row.Count -gt 1
    $I = [DlUi.Card]::Inset

    $card = New-Object DlUi.Card
    $card.Margin = New-Object Windows.Forms.Padding(0)
    $card.Picture = $img
    $x = 16
    if ($img) {
        $card.PicRect = New-Object Drawing.Rectangle(($I + 9), ($I + 9), 72, 98)
        $x = 96
    }
    $t = New-Object Windows.Forms.Label
    $t.AutoSize = $true; $t.Font = $FontTitle; $t.UseMnemonic = $false; $t.BackColor = 'Transparent'
    $t.MaximumSize = New-Object Drawing.Size(($CardW - $x - 12), 0)
    $t.Location = New-Object Drawing.Point(($I + $x - 3), ($I + 11))
    # kangelase kaart (pilt või mitu modi): pealkiri = kangelane; kangelaseta modi pildiga kaardil = modi nimi
    $useHero = $multi -or ($img -and $m.Hero)
    $t.Text = if ($useHero) { $(if ($hero) { $hero } else { $m.Hero }) } else { $m.Name }
    if ($Deco -and $useHero) { $t.Text = $t.Text.ToUpper() }
    $card.Controls.Add($t)

    $chips = New-Object DlUi.CardFlow
    $chips.WrapContents = $true
    $chips.Margin = New-Object Windows.Forms.Padding(0)
    $chipW = $CardW - $x - 10
    $card.Controls.Add($chips)
    $names = @($t.Text)
    $made = @()
    foreach ($id in $row) {
        $mm = $ById[$id]; $names += $mm.Name
        if ($useHero -or $multi) { $made += New-Chip $chips (Get-ShortName $mm) $id $false }
        else { $made += New-Chip $chips '' $id $true }
        # Selle modi altid: väike "+ alt" nupp kõrval, või ainult "n" modi nupu nurgas (AltStyle = 'badge')
        $mainChip = $made[-1]
        foreach ($c in (Get-Children $id)) {
            $names += $c.Name
            if ($c.AltStyle -eq 'badge' -and -not $Portable -and -not $mainChip.AltBadge) {   # jagatavas ainult "+ …" nupud
                $mainChip.AltBadge = 'n'; $mainChip.AltOn = [bool]$State[$c.Id]
                $mainChip.AccessibleDescription = $c.Id    # millist alti "n" lülitab
                $mainChip.Add_AltClicked({
                    $alt = $this.AccessibleDescription
                    if ($script:DeleteMode) { Switch-DeleteMark $alt; return }
                    Set-Mod $alt (-not $State[$alt]); Update-Boxes
                })
                $script:AltChips += @{ Chip = $mainChip; Alt = $c.Id }
            } else {
                $sc = New-Chip $chips ('+ ' + (Get-ShortName $c)) $c.Id $false $true
                $sc.Margin = New-Object Windows.Forms.Padding(0, 3, 6, 6)
            }
        }
    }
    if ($Deco) {
        # poe kategooria värv kaardile ja nuppudele
        $acc = $G::CatColor($m.Cat)
        $card.Accent = $acc
        foreach ($c in $chips.Controls) { if ($c -is [DlUi.Chip]) { $c.Accent = $acc } }
    }
    $ps = $chips.GetPreferredSize((New-Object Drawing.Size($chipW, 0)))
    $titleH = $t.GetPreferredSize((New-Object Drawing.Size(($CardW - $x - 12), 0))).Height
    $chipY = $I + 14 + $titleH + 6
    $chips.SetBounds(($I + $x), $chipY, $chipW, $ps.Height)
    $bottomY = $chipY + $ps.Height
    if ($placing) {
        # Uue modi koht: Other või These (mitte-skinnidel lihtsalt "Selge").
        $pl = New-Object Windows.Forms.FlowLayoutPanel
        $pl.WrapContents = $false; $pl.BackColor = 'Transparent'; $pl.AutoSize = $true
        $lab = New-Object Windows.Forms.Label
        $lab.AutoSize = $true; $lab.BackColor = 'Transparent'; $lab.ForeColor = $G::Muted
        $lab.Margin = New-Object Windows.Forms.Padding(0, 7, 8, 0)
        $pl.Controls.Add($lab)
        $dests = if ($m.Cat -eq 'Skins') { $lab.Text = 'Put in:'; @('Other', 'These') } else { $lab.Visible = $false; @('Done') }
        foreach ($d in $dests) {
            $b = New-Pill $(if ($d -eq 'Done') { '✓ Done' } else { "→ $d" }) ($d -eq 'Other')
            $b.Font = $FontChip; $b.FitWidth(14, 30)
            $b.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 0)
            $b.Tag = @{ Id = $row[0]; Dest = $d }
            $b.Add_Click({ Set-Placement $this.Tag.Id $this.Tag.Dest })
            $pl.Controls.Add($b)
        }
        $card.Controls.Add($pl)
        $pl.Location = New-Object Drawing.Point(($I + $x), ($bottomY + 4))
        $bottomY += 4 + $pl.GetPreferredSize([Drawing.Size]::Empty).Height
    }
    $bodyH = [Math]::Max($(if ($img) { 116 } else { 0 }), $bottomY - $I + 8)
    $card.Size = New-Object Drawing.Size(($CardW + 2 * $I), ($bodyH + 2 * $I))

    # Ühe modiga kaart: kogu kaardile vajutamine lülitab modi.
    if (-not $multi) {
        $chip = $made[0]
        $toggle = { $c = $this; while ($c -and -not ($c -is [DlUi.Card])) { $c = $c.Parent }; $c.Tag.Checked = -not $c.Tag.Checked }
        $card.Tag = $chip
        $card.Cursor = 'Hand'; $t.Cursor = 'Hand'; $chips.Cursor = 'Hand'
        $card.Add_Click($toggle); $t.Add_Click($toggle); $chips.Add_Click($toggle)
        if ($ModMenu) { $card.ContextMenuStrip = $ModMenu; $t.ContextMenuStrip = $ModMenu }
    }
    $flow.Controls.Add($card)
    $script:Cards += @{ Card = $card; Title = $t; Row = $row; Text = ($names -join ' ').ToLower(); Header = $headerRef; HeroImg = $heroImg; Tab = $script:BuildingTab }
    # paremklõps kaardi pildil: pildi muutmine (pildid.ps1)
    $card.Add_MouseUp({
        if ($_.Button -ne 'Right' -or $this.PicRect.IsEmpty -or -not $this.PicRect.Contains($_.Location)) { return }
        $me = $this; $c = @($Cards | Where-Object { $_.Card -eq $me })[0]; if (-not $c) { return }
        $script:PicClickAt = [DateTime]::Now
        $id = Get-CardShownMod $c.Row; if (-not $id) { $id = $c.Row[0] }
        $script:PicReq = @{ Id = $id; Row = @($c.Row) }   # (BeginInvoke käivitub hiljem: muutujad skripti tasemel)
        if (Get-Command Show-PictureFor -ErrorAction SilentlyContinue) { $form.BeginInvoke([Action]{ Show-PictureFor $script:PicReq.Id $script:PicReq.Row }) | Out-Null }
    })
}

# $flat: järjekord jääb nagu antud (nt suuruse järgi), iga mod oma kaardil, peatükkideta
# Vahelehe sisu (kaardid) ehitatakse alles siis, kui vaheleht esimest korda avatakse (Fill-TabPage, Show-Tab kutsub):
# kõigi vahelehtede ehitamine kohe võttis käivitamisel ~4 s. $eager = ehita kohe (kui kutsuja vajab lehte kohe).
# $after = { param($t) ... } käivitub pärast ehitamist (nt kaartide pealkirjade täiendamine).
# $group: mitu vahelehte ühe vahelehena ribal (nt "Lists" = No link / No picture / By size); lehe ülaosas nupud
# nende vahel vahetamiseks, "Turn all" nuppu pole. Ribal on üks silt (jagatud), see avab viimati vaadatud lehe.
$GroupLast = @{}
function Add-Tab($title, $ids, [bool]$withHeaders, [bool]$placing = $false, $hintText = $null, [bool]$flat = $false, [bool]$eager = $false, $after = $null, $group = $null) {
    $flow = New-Object DlUi.SmoothFlow
    $flow.Dock = 'Fill'; $flow.AutoScroll = $true; $flow.WrapContents = $true
    $flow.Padding = New-Object Windows.Forms.Padding(14, 8, 14, 16)
    $flow.Visible = $false; $flow.BackColor = $G::PageBg
    $G::DoubleBuffer($flow)
    Set-DarkScroll $flow
    if (Get-Command Enable-Drop -ErrorAction SilentlyContinue) { Enable-Drop $flow }
    # Windowsi kerimisriba peitmiseks on flow 17 px laiem kui teda ümbritsev clip; nähtav on DlUi.ScrollBarLite
    $clip = New-Object Windows.Forms.Panel; $clip.Dock = 'Fill'; $clip.Visible = $false; $clip.BackColor = $G::PageBg
    $flow.Dock = 'None'; $flow.Visible = $true
    $clip.Controls.Add($flow)
    $clip.Add_Resize({ $f = @($this.Controls | Where-Object { $_ -is [DlUi.SmoothFlow] })[0]; $f.SetBounds(0, 0, $this.ClientSize.Width + [Windows.Forms.SystemInformation]::VerticalScrollBarWidth, $this.ClientSize.Height) })
    $content.Controls.Add($clip); $clip.BringToFront()
    # kerimise ajal näidatakse lehe hetktõmmist (sujuv), päris kaardid tõstetakse kohale pärast kerimist
    $snapV = New-Object DlUi.SnapView; $snapV.Dock = 'Fill'; $clip.Controls.Add($snapV); $snapV.BringToFront(); $flow.AttachView($snapV)

    # Vaheleht ribal
    $i = $TabBtns.Count
    $shared = if ($group) { @($TabBtns | Where-Object { $_.Group -eq $group })[0] } else { $null }
    if ($shared) {
        $script:TabBtns += @{ Label = $shared.Label; Page = $flow; Title = $title; Built = $false; After = $after; Group = $group
                              Spec = @{ Ids = @($ids); WithHeaders = $withHeaders; Placing = $placing; Hint = $hintText; Flat = $flat } }
        if ($eager) { Fill-TabPage $TabBtns[-1] }
        return
    }
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $(if ($group) { $group } else { $title }); if ($Deco) { $lbl.Text = $lbl.Text.ToUpper() }; $lbl.AutoSize = $true; $lbl.Cursor = 'Hand'; $lbl.Font = $FontTab; $lbl.BackColor = 'Transparent'
    $x = 24; foreach ($tb in $TabBtns) { $x = [Math]::Max($x, $tb.Label.Right + 28) }
    if ($script:PlusLbl) { $x = [Math]::Max($x, $script:PlusLbl.Right + 22) }   # "+" järel tuleb New
    $lbl.Location = New-Object Drawing.Point($x, $(if ($Deco) { 9 } else { 13 }))
    if ($Deco) { $lbl.Padding = New-Object Windows.Forms.Padding(0, 4, 0, 0) }   # ruum Õ kriipsule
    $lbl.Tag = $i
    $lbl.Add_Click({
        $k = $this.Tag
        # rühma silt: viimati vaadatud leht
        $grp = $TabBtns[$k].Group   # (mitte $g: PowerShell ei erista suurtähti, $g varjaks teema $G)
        if ($grp -and $GroupLast[$grp]) { for ($j = 0; $j -lt $TabBtns.Count; $j++) { if ($TabBtns[$j].Group -eq $grp -and $TabBtns[$j].Title -eq $GroupLast[$grp]) { $k = $j } } }
        Show-Tab $k $false
    })
    $lbl.Add_MouseEnter({ if (-not [object]::ReferenceEquals($TabBtns[$script:CurTab].Label, $this)) { $this.ForeColor = $G::TabHover } })
    $lbl.Add_MouseLeave({ if (-not [object]::ReferenceEquals($TabBtns[$script:CurTab].Label, $this)) { $this.ForeColor = $(if ($this.AccessibleDescription -eq 'new') { $G::TabNew } else { $G::TabIdle }) } })
    $tabBar.Controls.Add($lbl)
    $t = @{ Label = $lbl; Page = $flow; Title = $title; Built = $false; After = $after; Group = $group
            Spec = @{ Ids = @($ids); WithHeaders = $withHeaders; Placing = $placing; Hint = $hintText; Flat = $flat } }
    $script:TabBtns += $t
    if ($eager) { Fill-TabPage $t }
}

function Fill-TabPage($t) {
    if ($t.Built) { return }
    $t.Built = $true
    $title = $t.Title; $flow = $t.Page; $sp = $t.Spec
    $ids = $sp.Ids; $withHeaders = $sp.WithHeaders; $placing = $sp.Placing; $hintText = $sp.Hint; $flat = $sp.Flat
    $script:BuildingTab = $title
    $flow.SuspendLayout()
    # Peatükkide järjekord: skinnid, kaart, muu välimus, helid, kasulikud (sama peatüki sees jääb algne järjekord)
    $ids = @($ids | Where-Object { $null -ne $_ })   # tühi vaheleht (nt sõbra versioon ilma modideta) andis @($null)
    $pos = @{}; $k = 0; foreach ($id in $ids) { $pos[$id] = $k++ }
    if (-not $flat) { $ids = @($ids | Sort-Object @{ e = { $c = [array]::IndexOf($CatOrder, $ById[$_].Cat); if ($c -lt 0) { 99 } else { $c } } }, @{ e = { $pos[$_] } }) }
    # Peatükkide pealkirjad: "Kõik modid" all alati, mujal siis, kui vahelehel on mitu peatükki
    $cats = @($ids | ForEach-Object { $ById[$_].Cat } | Select-Object -Unique)
    $showHeaders = (-not $flat) -and ($withHeaders -or $cats.Count -gt 1)

    # New all: iga mod oma kaardil (paigutus käib modi kaupa)
    if ($placing -or $flat) { $rows = New-Object Collections.ArrayList; foreach ($id in $ids) { $r = New-Object Collections.ArrayList; [void]$r.Add($id); [void]$rows.Add($r) } }
    else { $rows = Get-Rows $ids }
    $FullW = 2 * ($CardW + 2 * [DlUi.Card]::Inset)

    # "Kõik" rida
    $top = New-Object Windows.Forms.FlowLayoutPanel
    $top.AutoSize = $true; $top.WrapContents = $false; if ($Deco) { $top.BackColor = 'Transparent' }
    $top.Margin = New-Object Windows.Forms.Padding(7, 4, 6, 6)
    $all = New-Pill 'Turn all off' $false
    $all.FitWidth(16, 34)
    $all.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0)
    $cnt = New-Object Windows.Forms.Label
    $cnt.AutoSize = $true; $cnt.ForeColor = $G::Text; $cnt.Font = $FontHint; $cnt.Margin = New-Object Windows.Forms.Padding(0, 8, 0, 0)
    $hint = New-Object Windows.Forms.Label
    $hint.AutoSize = $true; $hint.ForeColor = $G::Text; $hint.Font = $FontHint; $hint.Margin = New-Object Windows.Forms.Padding(14, 8, 0, 0)
    $hint.Text = if ($hintText) { $hintText } elseif ($Portable) { 'One skin per hero can be on at a time. Right-click a mod for more.' } else { 'One skin per hero. Turning one off in Other puts its These skin on.' }
    if ($t.Group) {
        # rühma leht: nupud rühma lehtede vahel (see leht esile tõstetud), "Turn all" nuppu ega loendurit pole
        $hint.Margin = New-Object Windows.Forms.Padding(10, 8, 0, 0)
        foreach ($gt in @($TabBtns | Where-Object { $_.Group -eq $t.Group })) {
            $txt = $gt.Title; if ($gt.Title -ne 'By size') { $txt += "  ·  $(@($gt.Spec.Ids).Count)" }
            $sb = New-Pill $txt ($gt.Title -eq $title); $sb.Font = $FontChip; $sb.FitWidth(14, 34)
            $sb.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 0); $sb.Tag = $gt.Title
            if ($gt.Title -ne $title) { $sb.Add_Click({ Show-TabByTitle $this.Tag }) }
            $top.Controls.Add($sb)
        }
        $top.Controls.Add($hint)
        $flow.Controls.Add($top); $flow.SetFlowBreak($top, $true)
        $all.Dispose(); $cnt.Dispose()
    } else {
    $top.Controls.AddRange(@($all, $cnt, $hint))
    $flow.Controls.Add($top)
    $flow.SetFlowBreak($top, $true)
    }
    $entry = @{ Box = $all; Rows = $rows; Count = $cnt; Full = $false }
    $all.Tag = $entry
    # Kõik sees -> kõik maha; muidu -> kõik peale (kangelase real, kus midagi sees pole, valitakse üks juhuslikult).
    $all.Add_Click({
        $e = $this.Tag; $rows = $e.Rows
        if ($e.Full) {
            foreach ($row in $rows) { foreach ($id in $row) { Set-Mod $id $false } }
            foreach ($row in $rows) { foreach ($id in $row) { $State[$id] = $false } }  # Swap ei too sama nimekirja modi tagasi
        } else {
            foreach ($row in $rows) { if (-not (Test-RowOn $row)) { $fav = @($row | Where-Object { $Favorites -contains $_ }); Set-Mod $(if ($fav.Count) { $fav[0] } else { $row | Get-Random }) $true } }
        }
        Update-Boxes
    })
    if (-not $t.Group) { $script:AllBoxes += $entry }

    $cat = $null; $last = $top; $h = $null
    foreach ($row in $rows) {
        $m = $ById[$row[0]]
        if ($showHeaders -and $m.Cat -ne $cat) {
            $cat = $m.Cat
            $flow.SetFlowBreak($last, $true)
            # Peatüki pealkiri: "SKINNID ──────────" (joon eraldab peatükid)
            $h = New-Object Windows.Forms.Label
            $h.Text = $cat.ToUpper(); $h.Font = $FontMono; $h.ForeColor = $G::CatColor($cat)
            $h.AutoSize = $false; $h.Size = New-Object Drawing.Size(($FullW - 16), 30)
            $h.TextAlign = 'BottomLeft'
            $h.Margin = New-Object Windows.Forms.Padding(9, 14, 6, 2)
            if ($Deco) {
                # Poe kategooria bänner (nagu WEAPON / SPIRIT / VITALITY): värviline riba, suur hele kiri
                $h.Size = New-Object Drawing.Size(($FullW - 16), 42); $h.Margin = New-Object Windows.Forms.Padding(9, 16, 6, 6)
                $h.Font = New-Object Drawing.Font('Bahnschrift SemiBold Condensed', 20); $h.BackColor = 'Transparent'
            }
            $h.Add_Paint({
                $gfx = $_.Graphics
                if ([DlUi.G]::Deco) {
                    $gfx.SmoothingMode = 'AntiAlias'
                    $r = New-Object Drawing.RectangleF(0, 0, ($this.Width - 1), ($this.Height - 1))
                    $c = $this.ForeColor
                    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($r, [DlUi.G]::Mix($c, [Drawing.Color]::White, 0.10), [DlUi.G]::Mix($c, [Drawing.Color]::Black, 0.22), 0)
                    # (taust paistab läbi: paberleht)
                    $path = [DlUi.G]::Round($r, 6); $gfx.FillPath($br, $path); $br.Dispose(); [DlUi.G]::PaintGrain($gfx, $path); [DlUi.G]::PaintGrain($gfx, $path)
                    $pen = New-Object Drawing.Pen([DlUi.G]::Mix($c, [Drawing.Color]::Black, 0.35), 1); $gfx.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
                    $tr = New-Object Drawing.Rectangle(14, 0, ($this.Width - 20), $this.Height)
                    [Windows.Forms.TextRenderer]::DrawText($gfx, $this.Text, $this.Font, $tr, [DlUi.G]::Hex('#FFF6E6'), [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, NoPrefix')
                    return
                }
                $tw = [Windows.Forms.TextRenderer]::MeasureText($this.Text, $this.Font).Width
                $y = $this.Height - [int]($this.Font.Height / 2) - 2
                $pen = New-Object Drawing.Pen([DlUi.G]::Mix([DlUi.G]::Line2, $this.ForeColor, 0.45), 1)
                $gfx.DrawLine($pen, ($tw + 8), $y, ($this.Width - 4), $y); $pen.Dispose()
            })
            $flow.Controls.Add($h)
            $flow.SetFlowBreak($h, $true)
        }
        New-Card $flow $row $h $placing
        $last = $flow.Controls[$flow.Controls.Count - 1]
    }
    $flow.SetFlowBreak($last, $true)
    $pad = New-Object Windows.Forms.Panel; $pad.Size = New-Object Drawing.Size(10, 14); $pad.BackColor = 'Transparent'; $flow.Controls.Add($pad)
    if ($t.After) { & $t.After $t }
    Set-GoneTitles @($Cards | Where-Object { $_.Tab -eq $title })
    $flow.ResumeLayout()
}

# lehe maha võtnud modid, mille nupul pole teksti (üks mod kaardil): märge pealkirja
function Set-GoneTitles($cards) {
    if (-not ($script:GoneMods -and $script:GoneMods.Count)) { return }
    foreach ($c in $cards) { foreach ($rid in $c.Row) { if ($script:GoneMods.ContainsKey($rid) -and $Boxes[$rid] -and -not @($Boxes[$rid] | Where-Object { $_.Text })[0] -and $c.Title.Text -notlike '*page removed*') { $c.Title.Text += '  · page removed' } } }
}

# Alumine riba (enne kaarte, sest Update-Boxes kirjutab $note'i)
$bottom = New-Object Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 64
$bLine = New-Object Windows.Forms.Panel
$bLine.Dock = 'Top'; $bLine.Height = 1; $bLine.BackColor = $G::Line
$bottom.Controls.Add($bLine)
if ($Deco) { $bLine.Visible = $false; $bottom.Add_Paint({ & $DarkBar $_.Graphics $this.ClientRectangle $false }) }
$save = New-Pill 'Save' $true
$save.FitWidth(30, 40)
$bottom.Controls.Add($save)
# Stiili vahetus: Deadlocki poe stiil <-> sama tumedana ("dark"); lüliti avaneb uuesti valitud stiiliga.
# (Vana must-kollane "ajukas" on alles: kui see on seaded.json-is, viib nupp poe stiili.)
$themeBtn = New-Pill $(if ($Night) { 'Light mode' } elseif ($Deco) { 'Dark mode' } else { 'Deadlock style' }) $false
$themeBtn.Font = $FontChip; $themeBtn.Dark = $Deco; $themeBtn.FitWidth(12, 26)
$header.Controls.Add($themeBtn)   # päise paremas ülanurgas
$themeBtn.Add_Click({
    $pending = 0; foreach ($m in $Mods) { if ([bool]$State[$m.Id] -ne [bool](Test-On $m)) { $pending++ } }
    if ($pending) {
        $r = [Windows.Forms.MessageBox]::Show($form, 'Unsaved changes will be lost when switching style. Continue?', 'Deadlock Mods', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
    }
    $new = if ($Deco -and -not $Night) { 'dark' } else { 'deadlock' }
    [IO.File]::WriteAllText($SettingsFile, (@{ Theme = $new } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
    try { $AppMutex.ReleaseMutex(); $AppMutex.Dispose() } catch {}   # uus aken tohib kohe avaneda
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`""
    $form.Close()
})
$note = New-Object Windows.Forms.Label
$note.AutoSize = $true; $note.ForeColor = $G::HeadMuted; $note.Location = New-Object Drawing.Point(24, 24); $note.BackColor = 'Transparent'
$note.Add_TextChanged({ if (Get-Command Place-Right -ErrorAction SilentlyContinue) { Place-Right } })
$bottom.Controls.Add($note)

# Kõik ette valmis: kaartide ja nuppude pildid joonistatakse kohe ning kõigi vahelehtede aknakomponendid
# luuakse kohe (mitte alles siis, kui need kerimisel või vahelehte vahetades esimest korda nähtavale tulevad).
function Initialize-AllPages { foreach ($t in $TabBtns) { if ($t.Built) { Initialize-Page $t } }; foreach ($id in @($Boxes.Keys)) { foreach ($b in $Boxes[$id]) { $b.Prewarm() } } }
function Initialize-Page($t, $chips = @()) {
    $mk = { param($c) [void]$c.Handle; foreach ($ch in $c.Controls) { & $mk $ch } }
    & $mk $t.Page.Parent
    foreach ($c in $Cards) { if ($c.Tab -eq $t.Title) { $c.Card.Prewarm() } }
    # kerimise hetktõmmised tehakse taustal valmis (SmoothFlow.PrewarmTick)
    foreach ($b in $chips) { $b.Prewarm() }
}

function Build-Tabs {
    $keep = if ($TabBtns.Count) { $TabBtns[$CurTab].Title } else { $null }
    foreach ($t in $TabBtns) {
        $cp = $t.Page.Parent; $content.Controls.Remove($cp); $cp.Dispose()
        $tabBar.Controls.Remove($t.Label); $t.Label.Dispose()
    }
    if ($script:PlusLbl) { $tabBar.Controls.Remove($script:PlusLbl); $script:PlusLbl.Dispose(); $script:PlusLbl = $null }
    $script:TabBtns = @(); $script:Cards = @(); $script:AllBoxes = @(); $script:AltChips = @(); $Boxes.Clear()
    $script:InBuildTabs = $true
    $script:SkinTab = @($SkinTab | Where-Object { $ById.ContainsKey($_) })
    $script:NewIds = @($NewIds | Where-Object { $ById.ContainsKey($_) })

    # Lisad (Parent) ei ole eraldi kaardid, need on oma modi kaardil väikeste nuppudena.
    $main = @($Mods | Where-Object { -not $_.Parent })
    if (-not $Portable) {   # jagatavas versioonis ainult "All mods" (+ oma vahelehed)
        Add-Tab 'Other' @($SkinTab | Where-Object { -not $ById[$_].Parent }) $false
        # These = skinnid, mis pole Otheris (Otherist maha võttes tulevad asemele siit). Valimata uued on ka siin.
        Add-Tab 'These' @($main | Where-Object { $_.Cat -eq 'Skins' -and ($SkinTab -notcontains $_.Id) } | ForEach-Object { $_.Id }) $false
    }
    Add-Tab 'All mods' ($main | ForEach-Object { $_.Id }) $true $false $(if ($Portable -and -not $main.Count) { 'No mods yet: press "+ Add mod" or drop a mod file (.zip .rar .7z .vpk) on this window.' } else { $null })
    # Kasutaja vahelehed
    foreach ($name in @($CustomTabs.Keys)) {
        $CustomTabs[$name] = @($CustomTabs[$name] | Where-Object { $ById.ContainsKey($_) })
        Add-Tab $name @($CustomTabs[$name] | Where-Object { -not $ById[$_].Parent }) $false $false 'Your own tab: right-click a mod -> Add to tab.' $false $true
        $TabBtns[-1].Custom = $true
        $TabBtns[-1].Label.AccessibleName = $name          # vahelehe paremklõpsu menüü jaoks
        $TabBtns[-1].Label.ContextMenuStrip = $TabMenu
        $bulk = New-Pill '+  Add mods' $true; $bulk.Font = $FontChip; $bulk.FitWidth(14, 34)
        $bulk.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 0); $bulk.Tag = $name
        $bulk.Add_Click({ Set-SelectMode 'tab' $this.Tag })   # klõpsa modidel, siis "Save tab"
        $topRow = $TabBtns[-1].Page.Controls[0]; $topRow.Controls.Add($bulk); $topRow.Controls.SetChildIndex($bulk, 0)
    }
    # Ilma lingita modid (lingi lisamine: paremklõps -> Source & updates…)
    if (-not $Portable -and (Get-Command Get-Sources -ErrorAction SilentlyContinue)) {
        $srcAll = Get-Sources
        $noLink = @($main | Where-Object { -not $srcAll.ContainsKey($_.Id) } | ForEach-Object { $_.Id })
        if ($noLink.Count) { Add-Tab 'No link' $noLink $false $false 'Right-click a mod -> Source and updates…' $false $false $null 'Lists' }
    }
    # Ilma pildita modid (peidetud pildiga modid jäävad välja)
    if (-not $Portable) {
        $noPic = @($main | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ModPicDir "$($_.Id).png")) } | ForEach-Object { $_.Id })
        if ($noPic.Count) { Add-Tab 'No picture' $noPic $false $false 'Right-click a mod -> Picture…' $false $false $null 'Lists' }
    }
    # Suuruse järgi (suurim üleval; mod koos oma altidega). Info: paremklõps -> Info… (info.ps1)
    if (-not $Portable -and (Get-Command Get-ModTotalSize -ErrorAction SilentlyContinue)) {
        $sizes = @{}; $total = [long]0
        foreach ($x in $main) { $sizes[$x.Id] = Get-ModTotalSize $x.Id; $total += $sizes[$x.Id] }
        $bySize = @($main | Sort-Object @{ e = { $sizes[$_.Id] }; Descending = $true } | ForEach-Object { $_.Id })
        Add-Tab 'By size' $bySize $false $false "Biggest first, all together $(Format-Bytes $total). Right-click -> Info…" $true $false {
            param($t) foreach ($c in @($Cards | Where-Object { $_.Tab -eq 'By size' })) { $c.Title.Text = "$($c.Title.Text)  ·  $(Format-Bytes $t.Sizes[$c.Row[0]])" } } 'Lists'
        $TabBtns[-1].Sizes = $sizes
    }
    Add-PlusTab
    $newCards = @($NewIds | Where-Object { -not $ById[$_].Parent })
    if ($newCards.Count -and -not $Portable) {
        Add-Tab "New ($($newCards.Count))" $newCards $false $true 'Choose where each new skin goes. Until you choose, it is also under These.'
    }
    if (Get-Command Add-PartsTab -ErrorAction SilentlyContinue) { Add-PartsTab }   # modidest eemaldatud osad (osad.ps1)
    $i = 0
    for ($j = 0; $j -lt $TabBtns.Count; $j++) { if ($TabBtns[$j].Title -eq $keep -or ($keep -like 'New (*' -and $TabBtns[$j].Title -like 'New (*') -or ($keep -like 'Removed parts*' -and $TabBtns[$j].Title -like 'Removed parts*')) { $i = $j } }
    Show-Tab $i $true          # ehitab selle vahelehe kaardid (teised alles avamisel)
    $script:InBuildTabs = $false
    Update-Boxes
    Apply-Search
    Initialize-AllPages
}

# Uue modi koht valitud: New alt ära, Other valikul Otherisse. Salvestub kohe paigutus.json'i.
function Set-Placement($id, $dest) {
    $script:NewIds = @($NewIds | Where-Object { $_ -ne $id })
    if ($dest -eq 'Other' -and $SkinTab -notcontains $id) { $script:SkinTab = @($SkinTab) + $id }
    Save-Placement
    # Nupp, millele vajutati, kaob ümberehitusel; ehita pärast klõpsu lõppu.
    $script:rebuildTimer = New-Object Windows.Forms.Timer
    $rebuildTimer.Interval = 1
    $rebuildTimer.Add_Tick({ $this.Stop(); $this.Dispose(); Build-Tabs })
    $rebuildTimer.Start()
}

# Otsing: peida kaardid, mis ei sobi; peida ka tühjaks jäänud rubriikide pealkirjad.
$search.Add_TextChanged({ Apply-Search })
function Apply-Search {
    $q = $search.Text.Trim().ToLower()
    foreach ($t in $TabBtns) { $t.Page.SuspendLayout() }
    $shown = @{}
    foreach ($c in $Cards) {
        $vis = (-not $q) -or $c.Text.Contains($q)
        $c.Card.Visible = $vis
        if ($vis -and $c.Header) { $shown[$c.Header.GetHashCode()] = $true }
    }
    foreach ($c in $Cards) { if ($c.Header) { $c.Header.Visible = [bool]$shown[$c.Header.GetHashCode()] } }
    foreach ($t in $TabBtns) { $t.Page.ResumeLayout(); $t.Page.AutoScrollPosition = New-Object Drawing.Point(0, 0) }
}

$form.Controls.Add($content)
$form.Controls.Add($tabBar)
$form.Controls.Add($header)
$form.Controls.Add($bottom)
$content.BringToFront()

function Place-Right {
    $save.Location = New-Object Drawing.Point(($bottom.ClientSize.Width - $save.Width - 24), 12)
    if ($themeBtn) { $themeBtn.Location = New-Object Drawing.Point(($header.ClientSize.Width - $themeBtn.Width - 24), 8) }   # päise paremas ülanurgas
    # ⚡ Optimize: ülemises reas stiilinupu kõrval (alumises reas ei mahu kitsas aknas, läks logo peale)
    if ($optBtn) { $optBtn.Height = $(if ($themeBtn) { $themeBtn.Height } else { 28 }); $optBtn.Location = New-Object Drawing.Point($(if ($themeBtn) { $themeBtn.Left - $optBtn.Width - 8 } else { $header.ClientSize.Width - $optBtn.Width - 24 }), 8); $optBtn.BringToFront() }
    # alumine teade ei tohi nuppude alla minna: murrab vajadusel kahele reale
    if ($delAllBtn -and $delAllBtn.Visible) { $delAllBtn.Location = New-Object Drawing.Point(($save.Left - $delAllBtn.Width - 12), 16) }
    if ($selAllBtn -and $selAllBtn.Visible) { $selAllBtn.Location = New-Object Drawing.Point(($delAllBtn.Left - $selAllBtn.Width - 8), 16) }
    $right = if ($selAllBtn -and $selAllBtn.Visible) { $selAllBtn.Left } elseif ($delAllBtn -and $delAllBtn.Visible) { $delAllBtn.Left } else { $save.Left }
    $note.MaximumSize = New-Object Drawing.Size([Math]::Max(150, $right - 44), 0)
    $note.Top = [Math]::Max(4, [int](($bottom.ClientSize.Height - $note.Height) / 2))
    # Päise nupud paremalt vasakule: otsing, Add, Delete, Check, Updates. Nupud ei tohi minna logo alla:
    # kui ruumi pole, jääb otsingukast kitsamaks (kuni 160 px).
    $hb = @($addBtn, $delBtn, $chkBtn, $updBtn) | Where-Object { $_ }
    $need = 4; foreach ($b in $hb) { $need += $b.Width + 8 }
    $minL = if ($logo) { $logo.Right + 14 } else { $title.Right + 14 }
    $sw = [Math]::Max(160, [Math]::Min(260, $header.ClientSize.Width - 24 - $need - $minL))
    if ($searchFrame.Width -ne $sw) { $searchFrame.Width = $sw; $search.Width = $sw - 48 }
    $searchFrame.Location = New-Object Drawing.Point(($header.ClientSize.Width - $searchFrame.Width - 24), 46)
    $x = $searchFrame.Left - 4
    foreach ($b in $hb) { $x -= $b.Width + 8; $b.Location = New-Object Drawing.Point($x, 46); $b.BringToFront() }
    $fixBtn.Location = New-Object Drawing.Point(($status.Right + 10), ($status.Top + [int](($status.Height - $fixBtn.Height) / 2)))   # olekurea järel (päise nuppude taga oli peidus)
}
$form.Add_Shown({ Place-Right; Show-Tab $script:CurTab $true; $save.Focus() })
$form.Add_Resize({ Place-Right })
# Esc tühjendab otsingu; Ctrl+F läheb otsingusse.
$form.KeyPreview = $true
$form.Add_KeyDown({
    if ($_.KeyCode -eq 'Escape' -and $search.Text) { $search.Text = ''; $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'F') { $search.Focus(); $_.Handled = $true }
})

. (Join-Path $PSScriptRoot 'lisamine.ps1')
. (Join-Path $PSScriptRoot 'kustutamine.ps1')
. (Join-Path $PSScriptRoot 'menuu.ps1')
. (Join-Path $PSScriptRoot 'masslisamine.ps1')
. (Join-Path $PSScriptRoot 'kontroll.ps1')
. (Join-Path $PSScriptRoot 'osad.ps1')
. (Join-Path $PSScriptRoot 'uuendused.ps1')
. (Join-Path $PSScriptRoot 'pildid.ps1')
. (Join-Path $PSScriptRoot 'info.ps1')
. (Join-Path $PSScriptRoot 'optimize.ps1')
# laikide meeldetuletus: ainult sinu versioonis (jagatavas seda faili pole)
# sinu enda lisad (Other: "n" nupp, kangelaste pildid): ainult sinu versioonis
Build-Tabs

function Update-Status {
    $fixBtn.Visible = $false
    $status.ForeColor = $G::Hex('#89D185')
    switch (Get-GameinfoState) {
        'ok'      { $status.Text = '●  Mods are enabled in the game.' }
        'fixable' { $status.Text = $(if ($Portable) { '●  Mods are not enabled in the game yet (or a game update turned them off).' } else { '●  A game update turned ALL mods off.' }); $status.ForeColor = $G::Hex('#F48771'); $fixBtn.Visible = $true }
        default   { $status.Text = $(if ($Portable) { '●  Mods are off in the game and its config file (gameinfo.gi) looks unusual - add "Game citadel/addons" to it by hand.' } else { '●  A game update turned ALL mods off and changed the config file. Ask Claude to apply a new Sqooky config.' });$status.ForeColor = $G::Hex('#F48771') }
    }
    Place-Right   # nupp "Enable mods" olekurea järel
}

function Test-GameClosed {
    if (Get-Process deadlock -ErrorAction SilentlyContinue) {
        [Windows.Forms.MessageBox]::Show('Deadlock is running. Close the game first.', 'Deadlock Mods') | Out-Null
        return $false
    }
    return $true
}

$fixBtn.Add_Click({
    if (-not (Test-GameClosed)) { return }
    try {
        Enable-ModsInGameinfo
    } catch { [Windows.Forms.MessageBox]::Show("Failed: $_", 'Deadlock Mods') | Out-Null }
    Update-Status
})

# Salvestamata muudatuste arv (üks kangelase kohta, nagu alumisel ribal)
function Get-PendingCount {
    $changed = @{}
    foreach ($m in $Mods) { if ([bool]$State[$m.Id] -ne [bool](Test-On $m)) { $grp = if ($m.Parent -and $ById[$m.Parent]) { $ById[$m.Parent] } else { $m }; $changed[$(if ($grp.Hero) { "h:$($grp.Hero)" } else { $grp.Id })] = 1 } }
    return $changed.Count
}
# Sulgemisel salvestamata muudatused: Yes = salvesta ja sulge, No = sulge ilma, Cancel = jää
$form.Add_FormClosing({
    if ($script:ClosingChecked -or $env:DLTEST) { return }
    $n = Get-PendingCount
    if (-not $n) { return }
    $r = [Windows.Forms.MessageBox]::Show($form, "You have $n unsaved change$(if ($n -gt 1) { 's' }).`n`nSave them before closing?`n`nYes = save and close    No = close without saving    Cancel = keep the app open", 'Deadlock Mods', 'YesNoCancel', 'Question', 'Button1')
    if ($r -eq 'Cancel') { $_.Cancel = $true; return }
    # Yes: salvesta kohe siin; õnnestus -> aken sulgub (sulgemist ei katkestata), ebaõnnestus -> jääb lahti
    if ($r -eq 'Yes') { if (-not (Save-Changes)) { $_.Cancel = $true; return } }
    $script:ClosingChecked = $true
})

# Salvestab modid mängu. Tagastab $true, kui õnnestus.
function Save-Changes {
    if (-not (Test-GameClosed)) { return $false }
    if (-not (Confirm-UiConflicts)) { return $false }   # kontroll.ps1: kaks modi jagavad ekraanifaile -> ekraan läheb segi
    try {
        # Enne välja, siis sisse, et sama kangelase kaks skinni korraga sees poleks.
        foreach ($m in $Mods) { if (-not $State[$m.Id]) { Set-Files $m.Files $false } }
        foreach ($m in $Mods) { if ($State[$m.Id]) { Set-Files $m.Files $true } }
        return $true
    } catch {
        [Windows.Forms.MessageBox]::Show($form, "Saving failed:`n`n$($_.Exception.Message)`n`nIf a file is locked, close Deadlock and try again.", 'Deadlock Mods', 'OK', 'Error') | Out-Null
        return $false
    }
}
# Õnnestus: aken lihtsalt sulgub (teadet ei näidata)
$save.Add_Click({ if (Save-Changes) { $script:ClosingChecked = $true; $form.Close() } })

Update-Status
if ($env:DLTOGGLE_SHOT) {
    # Testimiseks: tee pildid aknast ja sulge (ei salvesta midagi).
    # Vorm: "vaheleht[:kerimine[:hiir-kaardil-nr]]=fail.png;..."
    $form.Add_Shown({
        foreach ($pair in ($env:DLTOGGLE_SHOT -split ';')) {
            $spec, $out = $pair -split '=', 2
            $tab, $y, $hov = $spec -split ':'
            Show-Tab ([int]$tab) $true
            if ($y) { $TabBtns[[int]$tab].Page.AutoScrollPosition = New-Object Drawing.Point(0, [int]$y) }
            foreach ($c in $Cards) { $c.Card.Lift = 0 }
            if ($hov) { $pc = @($Cards | ? { $_.Card.Parent -eq $TabBtns[[int]$tab].Page })[[int]$hov].Card; $pc.Lift = 1; $pc.GetType().GetMethod('ApplyLift', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($pc, $null) }
            $form.Refresh(); [Windows.Forms.Application]::DoEvents()
            $bmp = New-Object Drawing.Bitmap $form.Width, $form.Height
            $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle 0, 0, $form.Width, $form.Height))
            $bmp.Save($out); $bmp.Dispose()
        }
        $form.Close()
    })
}
# Laadimise aken kinni, kui põhiaken on ekraanil; teine käivitus -> see aken (või avatud dialoog) ette
$form.Add_Shown({ Close-Splash; $this.Activate() })
$OnceTimer = New-Object Windows.Forms.Timer; $OnceTimer.Interval = 300
$OnceTimer.Add_Tick({
    if (-not $ShowEvent.WaitOne(0)) { return }
    if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal' }
    $top = $form; foreach ($w in [Windows.Forms.Application]::OpenForms) { if ($w.Visible -and $w.Modal) { $top = $w } }
    $top.TopMost = $true; $top.Activate(); $top.TopMost = $false
})
$OnceTimer.Start()
# Teised vahelehed ehitatakse taustal valmis, kui kasutaja parasjagu midagi ei tee (üks vaheleht korraga, ~1 s),
# siis on vahetus kohe kiire. Kui hiir/klaviatuur liigub, ootab.
$PrebuildTimer = New-Object Windows.Forms.Timer; $PrebuildTimer.Interval = 700
$PrebuildTimer.Add_Tick({
    $next = $null; for ($j = 0; $j -lt $TabBtns.Count; $j++) { if (-not $TabBtns[$j].Built) { $next = $j; break } }
    if ($null -eq $next) { return }
    if ([DlToggle.Native]::IdleMs() -lt 1500 -or [Windows.Forms.Form]::ActiveForm -and [Windows.Forms.Form]::ActiveForm -ne $form) { return }
    $this.Stop()
    try { Prebuild-Tab $next } finally { $this.Start() }
})
$form.Add_Shown({ $PrebuildTimer.Start() })
[void]$form.ShowDialog()
Close-Splash
