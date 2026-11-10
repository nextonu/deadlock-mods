# "Check" nupp: vaatab kõik olemasolevad modid üle ja parandab, mida saab.
#  Kiire osa: fail puudu / fail mõlemas kaustas / kaks modi sama pak-numbriga / tundmatud failid addons kaustas /
#             alt, mille põhimodi pole.
#  Põhjalik osa (iga modi fail eraldi, taustal): vanad jagatud failid (võimete tabel, UI, helitabelid) ja vana kaamera.
# Parandamisel jääb originaal alles (camfix_originals / check_originals).
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1-te ja kustutamine.ps1-te.

$CheckOriginals = Join-Path $ArchiveDir 'check_originals'
$OrphanDir = Join-Path $ArchiveDir 'orphans'

# Minimeerimine pikkadel akendel (Check, Updates, Mass add): modaalne aken üksi minimeerituna jätaks põhiakna lukku,
# seepärast minimeeritakse kogu rakendus; tagasi avades tuleb aken samas seisus tagasi.
# Dialoogi päis: tume riba nagu põhiaknal, suur pealkiri + väike alltekst. Tagastab @{ Panel; Title; Sub }
function New-DialogHeader($dlg, $title, $subtitle) {
    $p = New-Object Windows.Forms.Panel; $p.Dock = 'Top'; $p.Height = 62
    if ($DarkBar) { $p.Add_Paint({ & $DarkBar $_.Graphics $this.ClientRectangle $true }) } else { $p.BackColor = [DlUi.G]::Bg }
    $t = New-Object Windows.Forms.Label; $t.AutoSize = $true; $t.BackColor = 'Transparent'; $t.ForeColor = [DlUi.G]::HeadBright
    $t.Font = New-Object Drawing.Font('Bahnschrift SemiBold', 15); $t.Text = $title; $t.Location = New-Object Drawing.Point(16, 7)
    $s = New-Object Windows.Forms.Label; $s.AutoSize = $true; $s.BackColor = 'Transparent'; $s.ForeColor = [DlUi.G]::HeadMuted
    $s.Text = $subtitle; $s.Location = New-Object Drawing.Point(18, 37); $s.UseMnemonic = $false
    $p.Controls.AddRange(@($t, $s)); $dlg.Controls.Add($p)
    return @{ Panel = $p; Title = $t; Sub = $s }
}

function Enable-DialogMinimize($dlg) {
    $dlg.MinimizeBox = $true
    $dlg.Add_Resize({ if ($this.WindowState -eq 'Minimized') { $this.WindowState = 'Normal'; $form.WindowState = 'Minimized' } })
}
$chkBtn = New-Pill '✓  Check' $false
$chkBtn.Font = $FontChip; $chkBtn.Dark = $Deco; $chkBtn.FitWidth(16, 36)
$header.Controls.Add($chkBtn)
$chkBtn.Add_Click({ if ($SelMode -eq 'check') { Set-SelectMode $null } elseif (Show-Intro 'check') { Set-SelectMode 'check' } })   # valikurežiim (kustutamine.ps1)

# Check'i algus: selgitus + mida kontrollida (kõik või valitud kangelased/modid, mitu korraga).
# Tagastab 'all', valitud id-de massiivi (koos altidega) või $null (Cancel).
function Show-CheckPicker {
    if ($env:DLTEST -and -not $env:DLTEST_INTRO) { return 'all' }
    $d = New-Object Windows.Forms.Form
    $d.Text = 'Check mods'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(640, 690); $d.MinimumSize = New-Object Drawing.Size(520, 520)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $info = New-Object Windows.Forms.Label
    $info.AutoSize = $false; $info.Location = New-Object Drawing.Point(16, 12); $info.Size = New-Object Drawing.Size(608, 196); $info.Anchor = 'Top, Left, Right'
    $info.ForeColor = $DlgText; $info.UseMnemonic = $false
    $info.Text = $IntroText['check'].Text
    $rAll = New-Object Windows.Forms.RadioButton; $rAll.Text = 'All mods'; $rAll.AutoSize = $true; $rAll.Checked = $true; $rAll.ForeColor = $DlgText
    $rAll.Location = New-Object Drawing.Point(16, 216)
    $rSome = New-Object Windows.Forms.RadioButton; $rSome.Text = 'Only these heroes / mods (tick as many as you want):'; $rSome.AutoSize = $true; $rSome.ForeColor = $DlgText
    $rSome.Location = New-Object Drawing.Point(16, 242)
    $q = New-Object Windows.Forms.TextBox
    $q.Location = New-Object Drawing.Point(16, 270); $q.Width = 608; $q.Anchor = 'Top, Left, Right'
    $q.BackColor = $G::Panel; $q.ForeColor = $G::Bright; $q.BorderStyle = 'FixedSingle'
    $q.Add_HandleCreated({ [void][DlToggle.Native]::SendMessage($this.Handle, 0x1501, [IntPtr]1, 'Search hero or mod…') })
    $list = New-Object Windows.Forms.CheckedListBox
    $list.Location = New-Object Drawing.Point(16, 300); $list.Size = New-Object Drawing.Size(608, 334); $list.Anchor = 'Top, Bottom, Left, Right'
    $list.CheckOnClick = $true; $list.IntegralHeight = $false; $list.BorderStyle = 'FixedSingle'
    $list.BackColor = $G::Panel; $list.ForeColor = $G::Text; $list.Font = $FontChip
    # read: kangelane (märgib kõik tema modid) ja tema modid; lõpus kangelaseta modid
    $rows = New-Object Collections.ArrayList
    $main = @($Mods | Where-Object { -not $_.Parent })
    $byHero = [ordered]@{}
    foreach ($m in ($main | Sort-Object @{ e = { "$(Get-HeroName $_)" } }, @{ e = { $_.Name } })) { $h = Get-HeroName $m; $k = if ($m.Hero -and $h) { $h } else { '' }; if (-not $byHero.Contains($k)) { $byHero[$k] = @() }; $byHero[$k] += $m }
    foreach ($k in @($byHero.Keys | Where-Object { $_ }) + @($byHero.Keys | Where-Object { -not $_ })) {
        $ids = @($byHero[$k] | ForEach-Object { $_.Id })
        if ($k) { [void]$rows.Add(@{ Text = "$($k.ToUpper())   (all $($ids.Count))"; Ids = $ids; Hero = $true }) }
        else { [void]$rows.Add(@{ Text = 'OTHER MODS (no hero)   (all)'; Ids = $ids; Hero = $true }) }
        foreach ($m in $byHero[$k]) { [void]$rows.Add(@{ Text = "      $(Get-ShortName $m)"; Ids = @($m.Id); Hero = $false; Find = "$k $($m.Name)".ToLower() }) }
    }
    $sel = @{}
    $st = @{ Shown = @(); Filling = $false }
    $fill = {
        $st.Filling = $true; $list.BeginUpdate(); $list.Items.Clear(); $st.Shown = @()
        $f = $q.Text.Trim().ToLower()
        foreach ($r in $rows) {
            if ($f -and -not ($r.Text.ToLower().Contains($f) -or ($r.Find -and $r.Find.Contains($f)))) { continue }
            $i = $list.Items.Add($r.Text); $st.Shown += , $r
            $on = @($r.Ids | Where-Object { $sel[$_] }).Count -eq $r.Ids.Count
            if ($on) { $list.SetItemChecked($i, $true) }
        }
        $list.EndUpdate(); $st.Filling = $false
    }
    $count = New-Object Windows.Forms.Label; $count.AutoSize = $true; $count.ForeColor = $DlgText; $count.Anchor = 'Bottom, Left'
    $count.Location = New-Object Drawing.Point(16, 650); $count.Text = 'All mods will be checked.'
    $ok = New-Pill 'Start check' $true; $ok.FitWidth(22, 34); $ok.Anchor = 'Bottom, Right'; $ok.Location = New-Object Drawing.Point((624 - $ok.Width), 642)
    $no = New-Pill 'Cancel' $false; $no.FitWidth(16, 34); $no.Anchor = 'Bottom, Right'; $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 642)
    $upd = {
        $n = @($sel.Keys | Where-Object { $sel[$_] }).Count
        $count.Text = if ($rAll.Checked) { "All $($main.Count) mods will be checked." } else { "$n mod(s) selected." }
        $ok.Enabled = ($rAll.Checked -or $n -gt 0)
    }
    $list.Add_ItemCheck({
        if ($st.Filling) { return }
        $r = $st.Shown[$_.Index]; $v = ($_.NewValue -eq 'Checked')
        foreach ($id in $r.Ids) { $sel[$id] = $v }
        $rSome.Checked = $true
        # kangelase rida muudab ka tema modide linnukesi: täida uuesti pärast seda klõpsu
        $d.BeginInvoke([Action]{ & $fill; & $upd }) | Out-Null
    })
    $q.Add_TextChanged({ & $fill })
    $rAll.Add_CheckedChanged({ & $upd }); $rSome.Add_CheckedChanged({ & $upd })
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.AddRange(@($info, $rAll, $rSome, $q, $list, $count, $ok, $no))
    & $fill; & $upd
    $res = $d.ShowDialog($form); $d.Dispose()
    if ($res -ne 'OK') { return $null }
    if ($rAll.Checked) { return 'all' }
    $ids = @($sel.Keys | Where-Object { $sel[$_] })
    $ids += @($Mods | Where-Object { $_.Parent -and $ids -contains $_.Parent } | ForEach-Object { $_.Id })   # altid ja lisad ka
    return , $ids
}

# Enne "Check" / "Updates" käivitamist: lühike seletus, mida see teeb (linnuke "ära näita enam" -> teated.json)
$IntroFile = Join-Path $PSScriptRoot 'teated.json'
$IntroText = @{
    check = @{ Title = 'Check mods'; Text = @"
Check looks through all your mods and lists problems. It takes a few minutes.

It looks for:
  •  mod files that are missing, or are in both folders at once
  •  two mods using the same file number (only one of them can work)
  •  unknown files in the game's addons folder
  •  old shared files inside mods that can break other heroes' abilities or sounds
  •  old cameras (skins made before the October 2026 game update sit too low/high)

Nothing is changed while it checks. Only the problems you tick are fixed when you press "Fix checked".
Originals are kept in: $ArchiveDir
"@ }
    updates = @{ Title = 'Check for updates'; Text = @"
Updates looks up every mod that has a GameBanana link (internet needed).
Nothing is downloaded or changed yet - you only get a list:

  •  Updates: a newer version is on GameBanana
  •  Maybe updates: probably newer, but the app is not sure (you decide)
  •  Optional extras: other versions or add-ons on the same page
  •  Problems: the page or your file was removed

When you tick mods and press "Update checked", for each one:
  1. the new version is downloaded and checked like a new mod (camera, old shared files)
  2. it replaces the old version in the same place - name, tab and on/off stay the same
  3. the old version and its old archive are deleted
Deadlock must be closed for mods that are on.
"@ }
}
function Show-Intro($key) {
    if ($env:DLTEST -and -not $env:DLTEST_INTRO) { return $true }
    $seen = @{}
    if (Test-Path -LiteralPath $IntroFile) { try { foreach ($p in ([IO.File]::ReadAllText($IntroFile) | ConvertFrom-Json).PSObject.Properties) { $seen[$p.Name] = $p.Value } } catch {} }
    if ($seen[$key]) { return $true }
    $info = $IntroText[$key]
    $d = New-Object Windows.Forms.Form
    $d.Text = $info.Title; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $l = New-Object Windows.Forms.Label
    $l.AutoSize = $true; $l.MaximumSize = New-Object Drawing.Size(600, 0); $l.UseMnemonic = $false
    $l.Location = New-Object Drawing.Point(20, 18); $l.ForeColor = $DlgText; $l.Text = $info.Text
    $d.Controls.Add($l)
    $h = $l.GetPreferredSize((New-Object Drawing.Size(600, 0))).Height
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = "Don't show this again"; $cb.AutoSize = $true; $cb.ForeColor = $DlgText
    $cb.Location = New-Object Drawing.Point(20, (32 + $h))
    $ok = New-Pill 'Start' $true; $ok.FitWidth(26, 34)
    $no = New-Pill 'Cancel' $false; $no.FitWidth(16, 34)
    $d.ClientSize = New-Object Drawing.Size(640, (86 + $h))
    $ok.Location = New-Object Drawing.Point((620 - $ok.Width), (26 + $h)); $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), (26 + $h))
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.AddRange(@($cb, $ok, $no))
    $res = $d.ShowDialog($form)
    if ($res -eq 'OK' -and $cb.Checked) {
        $seen[$key] = $true
        $o = [ordered]@{}; foreach ($k in $seen.Keys) { $o[$k] = $seen[$k] }
        [IO.File]::WriteAllText($IntroFile, (ConvertTo-Json $o), (New-Object Text.UTF8Encoding $false))
    }
    $d.Dispose()
    return ($res -eq 'OK')
}

# Modi faili praegune asukoht (sees -> addons\pakNN_dir.vpk, väljas -> addons_off\nimi.vpk)
function Get-ModFilePath($f) {
    $a = Join-Path $Addons $f.Pak; if (Test-Path -LiteralPath $a) { return $a }
    $o = Join-Path $Off $f.Off; if (Test-Path -LiteralPath $o) { return $o }
    return $null
}

# Kiire kontroll: tagastab leidude nimekirja
function Get-QuickFindings {
    $out = New-Object Collections.ArrayList
    $owner = @{}    # pak-fail -> [mod, ...]
    foreach ($m in $Mods) {
        foreach ($f in $m.Files) {
            $a = Test-Path -LiteralPath (Join-Path $Addons $f.Pak); $o = Test-Path -LiteralPath (Join-Path $Off $f.Off)
            if (-not $a -and -not $o) {
                [void]$out.Add(@{ Level = 'Error'; Mod = $m; Text = "File missing: $($f.Off) (not in addons or addons_off)"; Kind = 'missing'; Fix = $null; FixText = 'Re-add the mod, or delete it (right-click -> Delete)' })
            } elseif ($a -and $o) {
                [void]$out.Add(@{ Level = 'Error'; Mod = $m; Text = "File is in both folders: $($f.Pak) and $($f.Off) - Save fails"; Kind = 'both'; Data = $f; Fix = 'both'; FixText = 'Keep the one in use, move the other copy to Downloads\Muu\deadlock_mods\orphans' })
            }
            $k = $f.Pak.ToLower()
            if (-not $owner.ContainsKey($k)) { $owner[$k] = New-Object Collections.ArrayList }
            if ($owner[$k] -notcontains $m) { [void]$owner[$k].Add($m) }
        }
        if ($m.Parent -and -not $ById[$m.Parent]) {
            [void]$out.Add(@{ Level = 'Warning'; Mod = $m; Text = "Alt for a mod that no longer exists ($($m.Parent))"; Kind = 'parent'; Fix = $null; FixText = 'Delete it (right-click -> Delete)' })
        }
    }
    # sama pak-number mitmel modil: mängus saab sees olla ainult üks
    foreach ($k in $owner.Keys) {
        $ms = @($owner[$k])
        if ($ms.Count -lt 2) { continue }
        $names = ($ms | ForEach-Object { $_.Name }) -join ', '
        # ümber nummerdatakse mod, mis pole alt (altid peavad jääma põhimodist allapoole)
        # (suurem number on alati ohutu: põhimodi altid jäävad ikka temast allapoole)
        $alts = @($ms | Where-Object { $_.Parent }); $nonAlt = @($ms | Where-Object { -not $_.Parent })
        $move = if ($alts.Count) { $nonAlt } else { @($nonAlt | Select-Object -Skip 1) }
        if ($alts.Count -gt 1) {
            [void]$out.Add(@{ Level = 'Error'; Mod = $ms[0]; Text = "Same file name $k used by: $names"; Kind = 'pakdup'; Fix = $null; FixText = 'Delete one of these mods (right-click -> Delete…)' })
        }
        foreach ($m in $move) {
            [void]$out.Add(@{ Level = 'Error'; Mod = $m; Text = "Same file name $k as: $(($ms | Where-Object { $_ -ne $m } | ForEach-Object { $_.Name }) -join ', ') - only one can be on"; Kind = 'pakdup'; Data = $m; Fix = 'pakdup'; FixText = 'Give this mod new pak numbers' })
        }
    }
    # failid addons kaustas, mida ükski mod ei tunne (mäng laeb need ikka)
    $known = @{}; foreach ($m in $Mods) { foreach ($f in $m.Files) { $known[$f.Pak.ToLower()] = 1; $known[$f.Off.ToLower()] = 1 } }
    foreach ($f in @(Get-ChildItem -LiteralPath $Addons -Filter '*.vpk' -File -ErrorAction SilentlyContinue)) {
        if ($known[$f.Name.ToLower()]) { continue }
        [void]$out.Add(@{ Level = 'Warning'; Mod = $null; Text = "Unknown file in addons (the game loads it): $($f.Name)  $([Math]::Round($f.Length / 1MB, 1)) MB"; Kind = 'orphan'; Data = $f.FullName; Fix = 'orphan'; FixText = 'Move it out of the game to Downloads\Muu\deadlock_mods\orphans' })
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $Off -Filter '*.vpk' -File -ErrorAction SilentlyContinue)) {
        if ($known[$f.Name.ToLower()]) { continue }
        [void]$out.Add(@{ Level = 'Info'; Mod = $null; Text = "Unused file in addons_off (no mod uses it): $($f.Name)  $([Math]::Round($f.Length / 1MB, 1)) MB"; Kind = 'orphan'; Data = $f.FullName; Fix = 'orphan'; FixText = 'Move it to Downloads\Muu\deadlock_mods\orphans' })
    }
    # mängus olevate modide jagatud ekraanifailid
    try { foreach ($x in (Get-UiConflicts @($Mods | Where-Object { Test-On $_ } | ForEach-Object { $_.Id }))) { [void]$out.Add($x) } } catch {}
    return , $out
}

# Ekraanifailid (panorama layout / styles / scripts), mida mitu sees olevat modi muudavad. Iga faili puhul
# kasutab mäng väikseima pak-numbriga modi oma. Kui modi enda layout või skript jääb kehtima, aga tema
# stiilifail tuleb teiselt modilt, läheb ekraan segi (nt kangelase valikus kattuvad sildid).
# $on = sees olevate modide id-d. Tagastab leiud (Kind 'uisplit', Data = @{ Mod; Other }).
function Get-UiConflicts($on) {
    $out = New-Object Collections.ArrayList
    if (-not $Python) { return , $out }
    $paths = New-Object Collections.Generic.List[string]; $src = New-Object Collections.ArrayList
    foreach ($id in $on) {
        $m = $ById[$id]; if (-not $m) { continue }
        foreach ($f in $m.Files) { $p = Get-ModFilePath $f; if ($p) { $paths.Add($p); [void]$src.Add(@{ Mod = $m; Pak = [int]($f.Pak -replace '\D', ''); File = $f }) } }
    }
    if (-not $paths.Count) { return , $out }
    $byEntry = @{}
    foreach ($l in (Run $Python -I (Join-Path $ToolsDir 'vpkui.py') @($paths))) {
        if ($l -notmatch '^(\d+)\t(panorama/.+)$') { continue }
        $k = $Matches[2].ToLower()
        if (-not $byEntry.ContainsKey($k)) { $byEntry[$k] = New-Object Collections.ArrayList }
        [void]$byEntry[$k].Add($src[[int]$Matches[1]])
    }
    $family = { param($a, $b) $a.Id -eq $b.Id -or $a.Parent -eq $b.Id -or $b.Parent -eq $a.Id -or ($a.Parent -and $a.Parent -eq $b.Parent) }
    $hasCode = @{}   # modid, millel on oma layout / skript
    foreach ($k in $byEntry.Keys) { if ($k -match '^panorama/(layout|scripts)/') { foreach ($s in $byEntry[$k]) { $hasCode[$s.Mod.Id] = $true } } }
    $wins = @{}; $lost = @{}   # mod id -> entries
    foreach ($k in $byEntry.Keys) {
        $win = @($byEntry[$k] | Sort-Object { $_.Pak })[0]
        foreach ($s in $byEntry[$k]) {
            $id = $s.Mod.Id
            if ($s.Mod.Id -eq $win.Mod.Id) { if (-not $wins[$id]) { $wins[$id] = @{} }; $wins[$id][$k] = 1 }
            elseif (-not (& $family $s.Mod $win.Mod)) { if (-not $lost[$id]) { $lost[$id] = @{} }; $lost[$id][$k] = $win.Mod }
        }
    }
    foreach ($id in $lost.Keys) {
        $code = @($wins[$id].Keys | Where-Object { $_ -match '^panorama/(layout|scripts)/' })
        $styles = @($lost[$id].Keys | Where-Object { $_ -match '^panorama/styles/' } | Sort-Object)
        if (-not $code.Count -or -not $styles.Count) { continue }   # kogu ekraaniosa võidab teine mod -> lihtsalt tema oma kehtib
        $m = $ById[$id]
        $others = @($styles | ForEach-Object { $lost[$id][$_] } | Sort-Object { $_.Id } -Unique)
        $names = ($styles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) -replace '\.vcss$', '' }) -join ', '
        # Parandus: need stiilifailid välja kõigist modidest, mis on selle modi ees (väiksem pak). Ainult siis, kui
        # need modid muudavad ekraanil ainult stiili (oma layout'i/skripti pole) - siis kaob neil vaid väike muutus (nt sildi värv).
        $fixes = @{}; $fixable = $true
        foreach ($k in $styles) {
            $mine = @($byEntry[$k] | Where-Object { $_.Mod.Id -eq $id } | Sort-Object { $_.Pak })[0]
            foreach ($s in $byEntry[$k]) {
                if ($s.Pak -ge $mine.Pak -or (& $family $s.Mod $m)) { continue }
                if ($hasCode[$s.Mod.Id]) { $fixable = $false; break }
                $fk = $s.File.Off
                if (-not $fixes[$fk]) { $fixes[$fk] = @{ File = $s.File; Mod = $s.Mod; Drop = New-Object Collections.ArrayList } }
                if ($fixes[$fk].Drop -notcontains $k) { [void]$fixes[$fk].Drop.Add($k) }
            }
        }
        $dropMods = @($fixes.Values | ForEach-Object { $_.Mod } | Sort-Object { $_.Id } -Unique)
        $x = @{ Level = 'Error'; Mod = $m; Kind = 'uisplit'; Data = @{ Mod = $m; Other = $others; Fixes = @($fixes.Values); DropMods = $dropMods }; Fix = $null
            Text = "Screen can look broken (e.g. overlapping text): this mod's layout is used, but its style file ($names) comes from $(($others | ForEach-Object { $_.Name }) -join ', ') (lower pak number wins)"
            FixText = "Turn off this mod or $(($others | ForEach-Object { $_.Name }) -join ' / ')" }
        if ($fixable -and $fixes.Count) {
            $x.Fix = 'uisplit'
            $x.FixText = "Remove $names from $(($dropMods | ForEach-Object { $_.Name }) -join ', ') (they only change its look there, e.g. a colour; originals are kept)"
        }
        [void]$out.Add($x)
    }
    return , $out
}

# Save'i ajal: kas see salvestus teeb ekraanifailide segaduse (ainult need, kus mõni mod lülitatakse just sisse).
# Tagastab $true, kui võib salvestada.
function Confirm-UiConflicts {
    $on = @($Mods | Where-Object { $State[$_.Id] } | ForEach-Object { $_.Id })
    $new = @{}; foreach ($m in $Mods) { if ($State[$m.Id] -and -not (Test-On $m)) { $new[$m.Id] = 1 } }
    if (-not $new.Count) { return $true }
    try { $found = Get-UiConflicts $on } catch { return $true }
    $bad = @($found | Where-Object { $new[$_.Data.Mod.Id] -or @($_.Data.Other | Where-Object { $new[$_.Id] }).Count })
    if (-not $bad.Count) { return $true }
    $lines = ($bad | ForEach-Object { "•  $($_.Data.Mod.Name)  +  $(($_.Data.Other | ForEach-Object { $_.Name }) -join ', ')" }) -join "`n"
    $msg = "These mods change the same screen files, and together the game screen will look broken (for example overlapping text on hero tags):`n`n$lines"
    if (@($bad | Where-Object { $_.Fix -ne 'uisplit' }).Count) {
        $r = [Windows.Forms.MessageBox]::Show($form, "$msg`n`nTurn one of them off.`n`nSave anyway?", 'Deadlock Mods', 'YesNo', 'Warning', 'Button2')
        return ($r -eq 'Yes')
    }
    # kõik parandatavad: stiilifail välja nendest, kes seda ainult natuke muudavad (nt sildi värv)
    $fixLines = ($bad | ForEach-Object { "•  $($_.FixText)" }) -join "`n"
    $r = [Windows.Forms.MessageBox]::Show($form, "$msg`n`nThis can be fixed so all of them work:`n$fixLines`n`nYes = fix it and save`nNo = save without fixing`nCancel = go back", 'Deadlock Mods', 'YesNoCancel', 'Warning', 'Button1')
    if ($r -eq 'Cancel') { return $false }
    if ($r -eq 'Yes') {
        try { foreach ($x in $bad) { Invoke-CheckFix $x } }
        catch { [Windows.Forms.MessageBox]::Show($form, "Fixing failed:`n`n$($_.Exception.Message)", 'Deadlock Mods', 'OK', 'Error') | Out-Null; return $false }
    }
    return $true
}

# Põhjalik kontroll ühele modi failile (vanad jagatud failid + kaamera)
function Get-DeepFindings($m, $f) {
    $out = New-Object Collections.ArrayList
    $path = Get-ModFilePath $f
    if (-not $path) { return , $out }
    $log = New-Object Collections.ArrayList
    $paths = Get-VpkPaths $path
    $drop = Get-StaleShared $path $paths $log      # (tagastab massiivi; @() ümber teeks tühjast ühe elemendi)
    $drop = @($drop | Where-Object { $_ })
    if ($drop.Count) {
        $lst = ($drop | ForEach-Object { $_ -replace '^.*/', '' }) -join ', '
        if ($m.Hero -or $m.Parent) {
            # skinn: jagatud tabelid pole modi sisu, vana koopia lõhub teisi kangelasi -> välja
            [void]$out.Add(@{ Level = 'Error'; Mod = $m; Text = "Outdated shared file(s) that can break other heroes: $lst"; Kind = 'stale'; Data = @{ File = $f; Drop = $drop }; Fix = 'stale'; FixText = 'Remove the outdated files from the mod (game uses its own)' })
        } else {
            # UI / heli / muu mod: need failid ON mod ise; eemaldamine võib modi välja lülitada
            [void]$out.Add(@{ Level = 'Warning'; Mod = $m; NoAuto = $true; Text = "Files older than the game's (mod may be outdated, parts of the UI can look wrong): $lst"; Kind = 'stale'; Data = @{ File = $f; Drop = $drop }; Fix = 'stale'; FixText = 'Best: get an updated version. Fix = remove them (the mod may stop working)' })
        }
    }
    $cam = @{ Old = $false; Fixed = $false; Failed = $false }
    $fixed = Repair-Camera $path $paths $cam $log
    if ($fixed) {
        [void]$out.Add(@{ Level = 'Error'; Mod = $m; Text = 'Old camera (from before the Oct 2026 update): camera too low/high'; Kind = 'camera'; Data = @{ File = $f; Fixed = $fixed }; Fix = 'camera'; FixText = 'Fix the camera (original is kept in camfix_originals)' })
    } elseif ($cam.Failed) {
        [void]$out.Add(@{ Level = 'Warning'; Mod = $m; Text = 'Old camera that cannot be fixed automatically'; Kind = 'camold'; Fix = $null; FixText = 'Look for an updated version of the mod' })
    }
    return , $out
}

function Get-Sha($path) {
    $s = [IO.File]::OpenRead($path)
    try { return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s)) } finally { $s.Dispose() }
}

function Backup-Original($path, $dir) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $b = Join-Path $dir ([IO.Path]::GetFileName($path))
    if (Test-Path -LiteralPath $b) { $b = Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($path) + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.vpk') }
    Copy-Item -LiteralPath $path -Destination $b
}

# Modi failist ($f = modi Files kirje) need sisefailid välja; original läheb check_originals kausta.
function Remove-VpkEntries($f, $drop) {
    $path = Get-ModFilePath $f
    if (-not $path) { throw 'File not found.' }
    $lst = Join-Path $env:TEMP ("dlchk_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    $tmp = [IO.Path]::ChangeExtension($lst, '.vpk')
    [IO.File]::WriteAllLines($lst, [string[]]@($drop))
    try {
        Run $Python -I (Join-Path $ToolsDir 'vpkdrop.py') $path $tmp "@$lst" | Out-Null
        if (-not (Test-Path -LiteralPath $tmp)) { throw 'Removing the files failed.' }
        Backup-Original $path $CheckOriginals
        Copy-Item -LiteralPath $tmp -Destination $path -Force
    } finally { Remove-Item -LiteralPath $lst, $tmp -Force -ErrorAction SilentlyContinue }
}

# Üks parandus. Viskab erandi, kui ei õnnestu.
function Invoke-CheckFix($x) {
    switch ($x.Fix) {
        'both' {
            # Kasutusel on addons kaustas olev; teine koopia välja (mitte kustutada: võib olla teine versioon)
            $f = $x.Data
            $o = Join-Path $Off $f.Off
            New-Item -ItemType Directory -Force $OrphanDir | Out-Null
            $a = Join-Path $Addons $f.Pak
            if ((Get-Item -LiteralPath $a).Length -eq (Get-Item -LiteralPath $o).Length -and (Get-Sha $a) -eq (Get-Sha $o)) {
                Remove-Item -LiteralPath $o -Force     # täpselt sama fail: koopia lihtsalt ära
            } else {
                Move-Item -LiteralPath $o -Destination (Join-Path $OrphanDir ("off_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + "_" + $f.Off))
            }
        }
        'orphan' {
            New-Item -ItemType Directory -Force $OrphanDir | Out-Null
            $t = Join-Path $OrphanDir ([IO.Path]::GetFileName($x.Data))
            if (Test-Path -LiteralPath $t) { $t = Join-Path $OrphanDir ((Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [IO.Path]::GetFileName($x.Data)) }
            Move-Item -LiteralPath $x.Data -Destination $t
        }
        'pakdup' {
            $m = $x.Data
            $free = Get-FreePaks $m.Files.Count   # (funktsioon tagastab juba massiivi; @() tegi massiivi massiivis)
            $nums = @()
            for ($i = 0; $i -lt $m.Files.Count; $i++) {
                $n = $free[$i]
                $f = $m.Files[$i]
                # sees olev fail (addons) kuulub sellele modile ainult siis, kui tema väljas olev koopia puudub
                $a = Join-Path $Addons $f.Pak
                if ((Test-Path -LiteralPath $a) -and -not (Test-Path -LiteralPath (Join-Path $Off $f.Off))) {
                    $others = @($Mods | Where-Object { $_ -ne $m } | ForEach-Object { $_.Files } | Where-Object { $_.Pak -eq $f.Pak })
                    $otherOff = @($others | Where-Object { Test-Path -LiteralPath (Join-Path $Off $_.Off) })
                    if ($otherOff.Count -eq $others.Count) { Move-Item -LiteralPath $a -Destination (Join-Path $Addons ('pak{0:D2}_dir.vpk' -f [int]$n)) }
                }
                $f.Pak = 'pak{0:D2}_dir.vpk' -f [int]$n; $nums += $n
            }
            $o = [ordered]@{}; $cur = Get-PakOverrides; foreach ($k in $cur.Keys) { $o[$k] = $cur[$k] }
            $o[$m.Id] = $nums
            [IO.File]::WriteAllText($PakFile, (ConvertTo-Json $o), (New-Object Text.UTF8Encoding $false))
        }
        'stale' { Remove-VpkEntries $x.Data.File $x.Data.Drop }
        'uisplit' { foreach ($fx in $x.Data.Fixes) { Remove-VpkEntries $fx.File @($fx.Drop) } }
        'camera' {
            $f = $x.Data.File; $path = Get-ModFilePath $f
            if (-not $path) { throw 'File not found.' }
            Backup-Original $path $CamfixOriginals
            Copy-Item -LiteralPath $x.Data.Fixed -Destination $path -Force
            Remove-Item -LiteralPath $x.Data.Fixed -Force -ErrorAction SilentlyContinue
            $x.Data.Fixed = $null
        }
    }
}

function Show-ModCheck($pick = 'all') {
    if ($script:AddBusy) { return }
    $script:AddBusy = $true; $chkBtn.Enabled = $false
    $st = @{ Queue = (New-Object Collections.ArrayList); Busy = $false; Closing = $false; Total = 0; Done = 0; Found = (New-Object Collections.ArrayList); Changed = $false }

    $d = New-Object Windows.Forms.Form
    $d.Text = 'Check mods'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.StartPosition = 'CenterParent'; Enable-DialogMinimize $d
    $d.ClientSize = New-Object Drawing.Size(940, 660); $d.MinimumSize = New-Object Drawing.Size(700, 460)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $sel = if ($pick -is [array]) { @($pick) } else { $null }    # $null = kõik modid
    $nMods = if ($sel) { @($Mods | Where-Object { -not $_.Parent -and $sel -contains $_.Id }).Count } else { @($Mods | Where-Object { -not $_.Parent }).Count }
    $hdr = New-DialogHeader $d 'Check mods' $(if ($sel) { "Checking $nMods selected mod(s)" } else { "Checking all $nMods mods" })
    # $lab = suur teatekast (töötab -> valmis), $bar = edenemine, $sub = mida parajasti vaatab
    $lab = New-Object DlUi.Banner
    $lab.Location = New-Object Drawing.Point(16, 74); $lab.Size = New-Object Drawing.Size(908, 46); $lab.Anchor = 'Top, Left, Right'
    $lab.Font = $FontChip; $lab.Text = 'Checking files…'; $lab.Kind = 0
    $bar = New-Object DlUi.Bar
    $bar.Location = New-Object Drawing.Point(16, 130); $bar.Size = New-Object Drawing.Size(908, 8); $bar.Anchor = 'Top, Left, Right'
    $sub = New-Object Windows.Forms.Label
    $sub.AutoSize = $false; $sub.Size = New-Object Drawing.Size(908, 20); $sub.Anchor = 'Top, Left, Right'; $sub.UseMnemonic = $false
    $sub.ForeColor = $DlgMuted; $sub.Location = New-Object Drawing.Point(16, 144); $sub.AutoEllipsis = $true
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true; $lv.ShowItemToolTips = $true
    $lv.Location = New-Object Drawing.Point(16, 170); $lv.Size = New-Object Drawing.Size(908, 426); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('', 84), @('Mod', 220), @('Problem', 390), @('How it is fixed', 200))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    [DlUi.ListStyle]::Apply($lv, 28)
    $fitCols = { $w = $lv.ClientSize.Width - $lv.Columns[0].Width - $lv.Columns[1].Width - $lv.Columns[2].Width - 4; if ($w -gt 150) { $lv.Columns[3].Width = $w } }
    $lv.Add_Resize($fitCols); $d.Add_Shown($fitCols)
    $deep = New-Object Windows.Forms.CheckBox
    $deep.Text = 'Also check cameras and shared files (slower)'; $deep.Checked = $true; $deep.AutoSize = $true
    $deep.ForeColor = $DlgText; $deep.Location = New-Object Drawing.Point(16, 618); $deep.Anchor = 'Bottom, Left'
    $fix = New-Pill 'Fix checked' $true; $fix.FitWidth(22, 36); $fix.Anchor = 'Bottom, Right'; $fix.Enabled = $false
    $close = New-Pill 'Close' $false; $close.FitWidth(18, 36); $close.Anchor = 'Bottom, Right'
    $close.Location = New-Object Drawing.Point((924 - $close.Width), 610)
    $fix.Location = New-Object Drawing.Point(($close.Left - $fix.Width - 10), 610)
    $close.Add_Click({ $d.Close() })

    $addRow = {
        param($x)
        $lvl = $x.Level
        $row = New-Object Windows.Forms.ListViewItem($(switch ($lvl) { 'Error' { '✕ Problem' } 'Warning' { '! Warning' } default { 'i Note' } }))
        [void]$row.SubItems.Add($(if ($x.Mod) { $x.Mod.Name } else { '—' }))
        [void]$row.SubItems.Add($x.Text)
        [void]$row.SubItems.Add($(if ($x.Fix) { $x.FixText } else { "(manual) $($x.FixText)" }))
        $row.ToolTipText = "$($x.Text)`n`nFix: $($x.FixText)"
        $row.ForeColor = switch ($lvl) { 'Error' { [DlUi.G]::Fg('#8E2A20') } 'Warning' { [DlUi.G]::Fg('#6E4A08') } default { [DlUi.G]::Text } }
        $row.Tag = $x
        if ($x.Fix -and $lvl -eq 'Error' -and -not $x.NoAuto) { $row.Checked = $true }   # hoiatused valib kasutaja ise
        [void]$lv.Items.Add($row)
        [void]$st.Found.Add($x)
    }
    $updateFix = {
        $n = @($lv.Items | Where-Object { $_.Checked -and $_.Tag.Fix -and -not $_.Tag.Done }).Count
        $fix.Text = "Fix checked ($n)"; $fix.FitWidth(22, 36); $fix.Left = $close.Left - $fix.Width - 10
        $fix.Enabled = ($n -gt 0 -and -not $st.Busy -and $st.Done -ge $st.Total)
    }
    $finish = {
        $bar.Value = $bar.Maximum
        $errs = @($st.Found | Where-Object { $_.Level -eq 'Error' }).Count
        $warn = @($st.Found | Where-Object { $_.Level -eq 'Warning' }).Count
        $info = @($st.Found | Where-Object { $_.Level -ne 'Error' -and $_.Level -ne 'Warning' }).Count
        if (-not $st.Found.Count) { $lab.Kind = 1; $lab.Text = "Done - all $nMods mods look fine. Nothing to fix." }
        elseif ($errs) { $lab.Kind = 3; $lab.Text = "Done - found $errs problem(s)" + $(if ($warn) { " and $warn warning(s)" } else { '' }) + ". The ticked ones are fixed when you press 'Fix checked'." }
        elseif ($warn) { $lab.Kind = 2; $lab.Text = "Done - $warn warning(s), no real problems. Read them and tick the ones you want to fix." }
        else { $lab.Kind = 1; $lab.Text = "Done - no problems. $info note(s) about unused files (harmless)." }
        $hdr.Sub.Text = "Finished: $nMods mod(s) checked"
        [DlUi.Notify]::Done($form, [bool]($errs -or $warn))
        $sub.Text = if ($deep.Checked) { 'Checked: files, pak numbers, unknown files, alts, shared files, cameras.' } else { 'Checked: files, pak numbers, unknown files, alts (cameras/shared files skipped).' }
        & $updateFix
    }
    $lv.Add_ItemChecked({ & $updateFix })
    $lv.Add_ItemCheck({ if ($lv.Items[$_.Index].Tag.Done -or -not $lv.Items[$_.Index].Tag.Fix) { $_.NewValue = $_.CurrentValue } })

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 40
    $timer.Add_Tick({
        if ($st.Busy -or $st.Closing) { return }
        if (-not $deep.Checked) { $st.Queue.Clear(); $st.Done = $st.Total }
        if (-not $st.Queue.Count) { $timer.Stop(); & $finish; return }
        $st.Busy = $true
        $job = $st.Queue[0]; $st.Queue.RemoveAt(0)
        $sub.Text = "$($job.Mod.Name)  ·  $($job.File.Off)"
        try { foreach ($x in (Get-DeepFindings $job.Mod $job.File)) { if (-not $st.Closing) { & $addRow $x } } }
        catch { if (-not $st.Closing) { & $addRow @{ Level = 'Warning'; Mod = $job.Mod; Text = "Could not read $($job.File.Off): $($_.Exception.Message)"; Fix = $null; FixText = 'Re-add the mod' } } }
        $st.Done++
        if (-not $st.Closing) { $bar.Value = [Math]::Min($bar.Maximum, $st.Done); $lab.Text = "Checking mods… $($st.Done) / $($st.Total)   (you can minimize this window - it tells you when it is done)" }
        $st.Busy = $false
    })

    $fix.Add_Click({
        $todo = @($lv.Items | Where-Object { $_.Checked -and $_.Tag.Fix -and -not $_.Tag.Done })
        if (-not $todo.Count) { return }
        if (Get-Process deadlock -ErrorAction SilentlyContinue) {
            [Windows.Forms.MessageBox]::Show($d, 'Deadlock is running. Close the game first (mod files are changed).', 'Check mods') | Out-Null; return
        }
        $st.Busy = $true; $fix.Enabled = $false; $close.Enabled = $false; $d.Cursor = 'WaitCursor'
        $ok = 0; $bad = 0
        foreach ($row in $todo) {
            $x = $row.Tag
            $sub.Text = "Fixing: $($row.SubItems[1].Text) - $($x.Text)"; [Windows.Forms.Application]::DoEvents()
            try {
                Invoke-CheckFix $x
                $row.Checked = $false; $x.Done = $true; $row.Text = '✓ Fixed'; $row.ForeColor = [DlUi.G]::Fg('#3E7A26'); $ok++
                $st.Changed = $true
            } catch {
                $row.Text = '✕ Failed'; $row.SubItems[3].Text = $_.Exception.Message; $row.ToolTipText = $_.Exception.Message; $bad++
            }
        }
        $d.Cursor = 'Default'; $close.Enabled = $true; $st.Busy = $false
        $lab.Text = "Fixed $ok" + $(if ($bad) { ", $bad failed (see the Fix column)" } else { '' }) + '.'
        $sub.Text = "Originals are kept in $ArchiveDir (camfix_originals / check_originals / orphans)."
        & $updateFix
    })

    $d.Add_Shown({
        $d.Refresh()
        foreach ($x in (Get-QuickFindings)) { if (-not $sel -or ($x.Mod -and $sel -contains $x.Mod.Id)) { & $addRow $x } }   # valikuga: ainult nende modide leiud
        # põhjalik: iga modi iga fail eraldi
        foreach ($m in $Mods) { if ($sel -and $sel -notcontains $m.Id) { continue }; foreach ($f in $m.Files) { [void]$st.Queue.Add(@{ Mod = $m; File = $f }) } }
        $st.Total = $st.Queue.Count; $bar.Maximum = [Math]::Max(1, $st.Total)
        $lab.Text = "Checking mods… 0 / $($st.Total)"
        $timer.Start()
    })
    $d.Add_FormClosing({ $st.Closing = $true; $timer.Stop() })
    $d.Controls.AddRange(@($lab, $bar, $sub, $lv, $deep, $fix, $close))
    try {
        [void]$d.ShowDialog($form)
    } finally {
        $timer.Dispose()
        # parandamata kaamera paranduste ajutised failid ära
        foreach ($x in $st.Found) { if ($x.Fix -eq 'camera' -and $x.Data.Fixed) { Remove-Item -LiteralPath $x.Data.Fixed -Force -ErrorAction SilentlyContinue } }
        $d.Dispose()
        $form.Cursor = 'Default'
        $script:AddBusy = $false; $chkBtn.Enabled = $true
    }
    if ($st.Changed) {
        Build-Tabs
        $note.Text = '✓  Check: fixes applied'; $note.ForeColor = $G::Hex('#89D185')
    } else { Update-Boxes }
}
