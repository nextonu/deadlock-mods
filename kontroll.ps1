# "Check" nupp: vaatab kõik olemasolevad modid üle ja parandab, mida saab.
#  Kiire osa: fail puudu / fail mõlemas kaustas / kaks modi sama pak-numbriga / tundmatud failid addons kaustas /
#             alt, mille põhimodi pole.
#  Põhjalik osa (iga modi fail eraldi, taustal): vanad jagatud failid (võimete tabel, UI, helitabelid) ja vana kaamera.
# Parandamisel jääb originaal alles (camfix_originals / check_originals).
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1-te ja kustutamine.ps1-te.

$CheckOriginals = Join-Path $ArchiveDir 'check_originals'
$OrphanDir = Join-Path $ArchiveDir 'orphans'

$chkBtn = New-Pill '✓  Check' $false
$chkBtn.Font = $FontChip; $chkBtn.Dark = $Deco; $chkBtn.FitWidth(16, 36)
$header.Controls.Add($chkBtn)
$chkBtn.Add_Click({ Show-ModCheck })

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
    return , $out
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
            $free = @(Get-FreePaks $m.Files.Count)
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
        'stale' {
            $f = $x.Data.File; $path = Get-ModFilePath $f
            if (-not $path) { throw 'File not found.' }
            $lst = Join-Path $env:TEMP ("dlchk_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
            $tmp = [IO.Path]::ChangeExtension($lst, '.vpk')
            [IO.File]::WriteAllLines($lst, [string[]]$x.Data.Drop)
            try {
                Run $Python -I (Join-Path $ToolsDir 'vpkdrop.py') $path $tmp "@$lst" | Out-Null
                if (-not (Test-Path -LiteralPath $tmp)) { throw 'Removing the files failed.' }
                Backup-Original $path $CheckOriginals
                Copy-Item -LiteralPath $tmp -Destination $path -Force
            } finally { Remove-Item -LiteralPath $lst, $tmp -Force -ErrorAction SilentlyContinue }
        }
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

function Show-ModCheck {
    if ($script:AddBusy) { return }
    $script:AddBusy = $true; $chkBtn.Enabled = $false
    $st = @{ Queue = (New-Object Collections.ArrayList); Busy = $false; Closing = $false; Total = 0; Done = 0; Found = (New-Object Collections.ArrayList); Changed = $false }

    $d = New-Object Windows.Forms.Form
    $d.Text = 'Check mods'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.MinimizeBox = $false; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(940, 580); $d.MinimumSize = New-Object Drawing.Size(700, 400)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $lab = New-Object Windows.Forms.Label
    $lab.AutoSize = $false; $lab.Size = New-Object Drawing.Size(908, 22); $lab.Anchor = 'Top, Left, Right'
    $lab.ForeColor = $DlgText; $lab.Font = $FontChip; $lab.Location = New-Object Drawing.Point(16, 12)
    $lab.Text = 'Checking files…'
    $bar = New-Object Windows.Forms.ProgressBar
    $bar.Location = New-Object Drawing.Point(16, 38); $bar.Size = New-Object Drawing.Size(908, 8); $bar.Anchor = 'Top, Left, Right'
    $sub = New-Object Windows.Forms.Label
    $sub.AutoSize = $false; $sub.Size = New-Object Drawing.Size(908, 20); $sub.Anchor = 'Top, Left, Right'
    $sub.ForeColor = $DlgMuted; $sub.Location = New-Object Drawing.Point(16, 50); $sub.AutoEllipsis = $true
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true; $lv.ShowItemToolTips = $true
    $lv.Location = New-Object Drawing.Point(16, 76); $lv.Size = New-Object Drawing.Size(908, 440); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('', 70), @('Mod', 230), @('Problem', 400), @('Fix', 190))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $deep = New-Object Windows.Forms.CheckBox
    $deep.Text = 'Also check cameras and shared files (slower)'; $deep.Checked = $true; $deep.AutoSize = $true
    $deep.ForeColor = $DlgText; $deep.Location = New-Object Drawing.Point(16, 538); $deep.Anchor = 'Bottom, Left'
    $fix = New-Pill 'Fix checked' $true; $fix.FitWidth(22, 36); $fix.Anchor = 'Bottom, Right'; $fix.Enabled = $false
    $close = New-Pill 'Close' $false; $close.FitWidth(18, 36); $close.Anchor = 'Bottom, Right'
    $close.Location = New-Object Drawing.Point((924 - $close.Width), 530)
    $fix.Location = New-Object Drawing.Point(($close.Left - $fix.Width - 10), 530)
    $close.Add_Click({ $d.Close() })

    $addRow = {
        param($x)
        $lvl = $x.Level
        $row = New-Object Windows.Forms.ListViewItem($(switch ($lvl) { 'Error' { '✕ Error' } 'Warning' { '! Warn' } default { 'i Info' } }))
        [void]$row.SubItems.Add($(if ($x.Mod) { $x.Mod.Name } else { '—' }))
        [void]$row.SubItems.Add($x.Text)
        [void]$row.SubItems.Add($(if ($x.Fix) { $x.FixText } else { "(manual) $($x.FixText)" }))
        $row.ToolTipText = "$($x.Text)`n`nFix: $($x.FixText)"
        $row.ForeColor = switch ($lvl) { 'Error' { [DlUi.G]::Hex('#B03A2E') } 'Warning' { [DlUi.G]::Hex('#9A6A12') } default { [DlUi.G]::Muted } }
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
        $lab.Text = if (-not $st.Found.Count) { "✓  All $($Mods.Count) mods look fine." } else { "Done: $errs error(s), $warn warning(s). Tick what to fix and press 'Fix checked'." }
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
        if (-not $st.Closing) { $bar.Value = [Math]::Min($bar.Maximum, $st.Done); $lab.Text = "Checking mods… $($st.Done) / $($st.Total)" }
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
                $row.Checked = $false; $x.Done = $true; $row.Text = '✓ Fixed'; $row.ForeColor = [DlUi.G]::Hex('#3E7A26'); $ok++
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
        foreach ($x in (Get-QuickFindings)) { & $addRow $x }
        # põhjalik: iga modi iga fail eraldi
        foreach ($m in $Mods) { foreach ($f in $m.Files) { [void]$st.Queue.Add(@{ Mod = $m; File = $f }) } }
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
