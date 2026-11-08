# Modi osade eemaldamine: häälread, kangelase portreed, võimete ikoonid, helid jne.
# Paremklõps modil -> "Parts…": aknas on modi osad; topeltklõps osal võtab selle modist välja (või paneb tagasi).
# Eemaldatud osad on vahelehel "Removed parts": seal saab need tagasi panna või jäädavalt kustutada.
# Kuidas: esimesel eemaldamisel salvestatakse modi originaalfail (Downloads\Muu\deadlock_mods\removed_parts\),
# modi fail tehakse originaalist uuesti ilma eemaldatud osadeta (vpkdrop.py). Tagasi panek = sama ilma selle osata.
# "Delete for good" unustab osa (mod jääb ilma selleta); kui modil eemaldatud osi enam pole, kustub ka originaal.
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1-te ja menuu.ps1-te.

$PartsDir = Join-Path $ArchiveDir 'removed_parts'
$PartsFile = Join-Path $PSScriptRoot 'osad.json'

# Osade liigid (esimene sobiv reegel võidab)
$PartKinds = @(
    @{ Key = 'voice';     Label = 'Voice lines';               Rx = '^sounds/vo/' }
    @{ Key = 'portrait';  Label = 'Hero portraits & cards';     Rx = '^panorama/images/heroes/' }
    @{ Key = 'icons';     Label = 'Ability / item icons';       Rx = '^panorama/images/(hud|abilities|upgrades|items)/' }
    @{ Key = 'ui';        Label = 'Other UI (menus, HUD)';      Rx = '^panorama/' }
    @{ Key = 'sounds';    Label = 'Other sounds (abilities, music)'; Rx = '^(sounds|soundevents)/' }
    @{ Key = 'particles'; Label = 'Effects (particles)';        Rx = '^particles/' }
    @{ Key = 'model';     Label = 'Models';                     Rx = '^models/' }
    @{ Key = 'materials'; Label = 'Materials / textures';       Rx = '^materials/' }
    @{ Key = 'text';      Label = 'Text (names, descriptions)'; Rx = '^resource/' }
    @{ Key = 'scripts';   Label = 'Game data (scripts)';        Rx = '^scripts/' }
    @{ Key = 'other';     Label = 'Other files';                Rx = '.' }
)
$PartLabel = @{}; foreach ($k in $PartKinds) { $PartLabel[$k.Key] = $k.Label }

function Get-PartKey($path) {
    $p = $path.ToLower()
    foreach ($k in $PartKinds) { if ($p -match $k.Rx) { return $k.Key } }
    return 'other'
}

# teed -> [ordered] võti -> List[string] (järjekord nagu $PartKinds)
function Get-PartGroups($paths) {
    $tmp = @{}
    foreach ($p in $paths) {
        $k = Get-PartKey $p
        if (-not $tmp.ContainsKey($k)) { $tmp[$k] = New-Object Collections.Generic.List[string] }
        $tmp[$k].Add($p)
    }
    $o = [ordered]@{}; foreach ($k in $PartKinds) { if ($tmp.ContainsKey($k.Key)) { $o[$k.Key] = $tmp[$k.Key] } }
    return $o
}

function Get-PartRecords {
    if (-not (Test-Path -LiteralPath $PartsFile)) { return @() }
    try { return @([IO.File]::ReadAllText($PartsFile) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return @() }
}
function Save-PartRecords($recs) {
    [IO.File]::WriteAllText($PartsFile, (ConvertTo-Json @($recs) -Depth 4), (New-Object Text.UTF8Encoding $false))
}

function Get-PartBackup($f) { Join-Path $PartsDir $f.Off }

# Teeb modi faili uuesti: originaal miinus kõik selle faili eemaldatud osad ($keys).
# Kui eemaldatud osi pole, pannakse originaal tagasi ja varukoopia kustub.
function Update-PartFile($f, $keys) {
    $path = Get-ModFilePath $f
    if (-not $path) { throw "Mod file not found: $($f.Off)" }
    if ($path.StartsWith($Addons, [StringComparison]::OrdinalIgnoreCase) -and (Get-Process deadlock -ErrorAction SilentlyContinue)) {
        throw 'This mod is on and Deadlock is running. Close the game first.'
    }
    $orig = Get-PartBackup $f
    if (-not @($keys).Count) {
        if (Test-Path -LiteralPath $orig) { Copy-Item -LiteralPath $orig -Destination $path -Force; Remove-Item -LiteralPath $orig -Force }
        return
    }
    if (-not (Test-Path -LiteralPath $orig)) {
        New-Item -ItemType Directory -Force $PartsDir | Out-Null
        Copy-Item -LiteralPath $path -Destination $orig
    }
    $groups = Get-PartGroups (Get-VpkPaths $orig)
    $drop = New-Object Collections.Generic.List[string]
    foreach ($k in $keys) { if ($groups.Contains($k)) { $drop.AddRange($groups[$k]) } }
    $all = 0; foreach ($k in $groups.Keys) { $all += $groups[$k].Count }
    if ($drop.Count -ge $all) { throw 'That would remove everything from the mod. Delete the mod instead (right-click -> Delete…).' }
    $lst = Join-Path $env:TEMP ("dlparts_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    $tmp = [IO.Path]::ChangeExtension($lst, '.vpk')
    [IO.File]::WriteAllLines($lst, [string[]]$drop.ToArray())
    try {
        if ($drop.Count) {
            Run $Python -I (Join-Path $ToolsDir 'vpkdrop.py') $orig $tmp "@$lst" | Out-Null
            if (-not (Test-Path -LiteralPath $tmp)) { throw 'Rewriting the mod file failed.' }
            Copy-Item -LiteralPath $tmp -Destination $path -Force
        } else { Copy-Item -LiteralPath $orig -Destination $path -Force }
    } finally { Remove-Item -LiteralPath $lst, $tmp -Force -ErrorAction SilentlyContinue }
}

function Get-RemovedKeys($recs, $f) { @($recs | Where-Object { $_.Off -eq $f.Off } | ForEach-Object { $_.Part }) }

function Remove-ModPart($m, $f, $key, $count) {
    $recs = @(Get-PartRecords)
    $keys = @(Get-RemovedKeys $recs $f) + $key | Select-Object -Unique
    Update-PartFile $f $keys
    $recs += [pscustomobject][ordered]@{ Mod = $m.Id; Off = $f.Off; Part = $key; Count = $count; Removed = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
    Save-PartRecords $recs
}

function Restore-ModPart($rec) {
    $m = $ById[$rec.Mod]; if (-not $m) { throw 'The mod no longer exists.' }
    $f = @($m.Files | Where-Object { $_.Off -eq $rec.Off })[0]; if (-not $f) { throw 'The mod file no longer exists.' }
    $recs = @(Get-PartRecords | Where-Object { -not ($_.Off -eq $rec.Off -and $_.Part -eq $rec.Part) })
    Update-PartFile $f @(Get-RemovedKeys $recs $f)
    Save-PartRecords $recs
}

# Jäädavalt: osa jääb modist välja, kirje kaob. Viimase kirjega kustub ka originaal.
function Remove-PartForGood($rec) {
    $recs = @(Get-PartRecords | Where-Object { -not ($_.Off -eq $rec.Off -and $_.Part -eq $rec.Part) })
    if (-not @($recs | Where-Object { $_.Off -eq $rec.Off }).Count) {
        $orig = Join-Path $PartsDir $rec.Off
        if (Test-Path -LiteralPath $orig) { Remove-Item -LiteralPath $orig -Force }
    }
    Save-PartRecords $recs
}

# Modi kustutamisel (kustutamine.ps1): kirjed ja originaalid ära
function Clear-ModParts($m, $log) {
    $recs = @(Get-PartRecords)
    if (-not @($recs | Where-Object { $_.Mod -eq $m.Id }).Count) { return }
    foreach ($f in $m.Files) {
        $orig = Get-PartBackup $f
        if (Test-Path -LiteralPath $orig) { Remove-Item -LiteralPath $orig -Force; if ($log) { [void]$log.Add("Deleted: $orig") } }
    }
    Save-PartRecords @($recs | Where-Object { $_.Mod -ne $m.Id })
}

# ---------- Aken: modi osad ----------
function Show-ModParts($id) {
    $m = $ById[$id]; if (-not $m) { return }
    if ($script:AddBusy) { return }
    $st = @{ Changed = $false; Busy = $false }

    $d = New-Object Windows.Forms.Form
    $d.Text = "Parts: $($m.Name)"; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.MinimizeBox = $false; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(620, 460); $d.MinimumSize = New-Object Drawing.Size(480, 320)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $lab = New-Object Windows.Forms.Label
    $lab.Text = 'Double-click a part to take it out of the mod (double-click again to put it back). Removed parts are listed in the "Removed parts" tab.'
    $lab.AutoSize = $false; $lab.Size = New-Object Drawing.Size(588, 40); $lab.Anchor = 'Top, Left, Right'
    $lab.ForeColor = $DlgMuted; $lab.Location = New-Object Drawing.Point(16, 12)
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
    $lv.Location = New-Object Drawing.Point(16, 56); $lv.Size = New-Object Drawing.Size(588, 340); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('Part', 270), @('Files', 70), @('Status', 220))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $sub = New-Object Windows.Forms.Label
    $sub.AutoSize = $false; $sub.Size = New-Object Drawing.Size(440, 20); $sub.Anchor = 'Bottom, Left, Right'
    $sub.ForeColor = $DlgMuted; $sub.Location = New-Object Drawing.Point(16, 418); $sub.AutoEllipsis = $true
    $close = New-Pill 'Close' $false; $close.FitWidth(18, 36); $close.Anchor = 'Bottom, Right'
    $close.Location = New-Object Drawing.Point((604 - $close.Width), 410)
    $close.Add_Click({ $d.Close() })

    $fill = {
        $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Groups.Clear()
        $recs = @(Get-PartRecords)
        foreach ($f in $m.Files) {
            $grp = $null
            if ($m.Files.Count -gt 1) { $grp = New-Object Windows.Forms.ListViewGroup($f.Off, "File: $($f.Off)"); [void]$lv.Groups.Add($grp) }
            $src = Get-PartBackup $f
            if (-not (Test-Path -LiteralPath $src)) { $src = Get-ModFilePath $f }
            if (-not $src) { $row = New-Object Windows.Forms.ListViewItem('(file missing)'); if ($grp) { $row.Group = $grp }; [void]$lv.Items.Add($row); continue }
            $sub.Text = "Reading $($f.Off)…"; [Windows.Forms.Application]::DoEvents()
            $groups = Get-PartGroups (Get-VpkPaths $src)
            $removed = @(Get-RemovedKeys $recs $f)
            foreach ($k in $groups.Keys) {
                $isOut = $removed -contains $k
                $row = New-Object Windows.Forms.ListViewItem($PartLabel[$k])
                [void]$row.SubItems.Add([string]$groups[$k].Count)
                [void]$row.SubItems.Add($(if ($isOut) { '✕ removed (double-click: put back)' } else { 'in the mod' }))
                if ($isOut) { $row.ForeColor = [DlUi.G]::Hex('#B03A2E') }
                $ex = @($groups[$k] | Select-Object -First 6) -join "`n"; if ($groups[$k].Count -gt 6) { $ex += "`n… $($groups[$k].Count - 6) more" }
                $row.ToolTipText = $ex
                $row.Tag = @{ File = $f; Key = $k; Count = $groups[$k].Count; Out = $isOut }
                if ($grp) { $row.Group = $grp }
                [void]$lv.Items.Add($row)
            }
        }
        $lv.EndUpdate()
        $sub.Text = ''
    }
    $lv.ShowItemToolTips = $true
    $lv.Add_DoubleClick({
        if ($st.Busy -or -not $lv.SelectedItems.Count) { return }
        $t = $lv.SelectedItems[0].Tag; if (-not $t) { return }
        $st.Busy = $true; $d.Cursor = 'WaitCursor'
        try {
            if ($t.Out) {
                $rec = @(Get-PartRecords | Where-Object { $_.Off -eq $t.File.Off -and $_.Part -eq $t.Key })[0]
                $sub.Text = "Putting back: $($PartLabel[$t.Key])…"; [Windows.Forms.Application]::DoEvents()
                Restore-ModPart $rec
            } else {
                $sub.Text = "Removing: $($PartLabel[$t.Key])…"; [Windows.Forms.Application]::DoEvents()
                Remove-ModPart $m $t.File $t.Key $t.Count
            }
            $st.Changed = $true
            & $fill
        } catch {
            [Windows.Forms.MessageBox]::Show($d, $_.Exception.Message, 'Parts') | Out-Null
        } finally { $d.Cursor = 'Default'; $st.Busy = $false }
    })
    $d.Add_Shown({ $d.Cursor = 'WaitCursor'; $d.Refresh(); try { & $fill } catch { $sub.Text = "Could not read the mod: $($_.Exception.Message)" }; $d.Cursor = 'Default' })
    $d.Controls.AddRange(@($lab, $lv, $sub, $close))
    [void]$d.ShowDialog($form); $d.Dispose()
    if ($st.Changed) { Build-Tabs }
}

# ---------- Vaheleht "Removed parts" (Build-Tabs kutsub) ----------
function Add-PartsTab {
    $recs = @(Get-PartRecords | Where-Object { $ById.ContainsKey($_.Mod) })
    if (-not $recs.Count) { return }
    Add-Tab "Removed parts ($($recs.Count))" @() $false $false 'Parts you took out of mods (right-click a mod -> Parts…). Put them back or delete them for good.'
    $tab = $TabBtns[-1]
    $page = $tab.Page
    $top = $page.Controls[0]
    $top.Controls[0].Visible = $false; $top.Controls[1].Visible = $false   # "Turn all on/off" ja loendur pole siin vajalikud
    $script:AllBoxes = @($AllBoxes | Where-Object { $_.Box -ne $top.Controls[0] })
    $W = 2 * ($CardW + 2 * [DlUi.Card]::Inset) - 16
    $insertAt = $page.Controls.Count - 1     # enne lõpu vahet
    foreach ($r in ($recs | Sort-Object Mod, Off, Part)) {
        $m = $ById[$r.Mod]
        $p = New-Object Windows.Forms.Panel
        $p.Size = New-Object Drawing.Size($W, 58); $p.Margin = New-Object Windows.Forms.Padding(9, 0, 6, 8)
        $p.BackColor = 'Transparent'; $G::DoubleBuffer($p)
        $p.AccessibleDescription = $G::CatColor($m.Cat).ToArgb()
        $p.Add_Paint({
            $gfx = $_.Graphics; $gfx.SmoothingMode = 'AntiAlias'
            $r = New-Object Drawing.RectangleF(1, 1, ($this.Width - 3), ($this.Height - 3))
            $path = [DlUi.G]::Round($r, 7)
            $b = New-Object Drawing.SolidBrush([DlUi.G]::Panel); $gfx.FillPath($b, $path); $b.Dispose()
            $sb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb([int]$this.AccessibleDescription)); $gfx.FillRectangle($sb, 1, 10, 5, ($this.Height - 21)); $sb.Dispose()
            $pen = New-Object Drawing.Pen([DlUi.G]::Line, 1); $gfx.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
        })
        $t1 = New-Object Windows.Forms.Label
        $t1.AutoSize = $true; $t1.BackColor = 'Transparent'; $t1.Font = $FontTitle; $t1.ForeColor = $G::Bright; $t1.UseMnemonic = $false
        $t1.Text = $(if ($PartLabel[$r.Part]) { $PartLabel[$r.Part] } else { $r.Part }); $t1.Location = New-Object Drawing.Point(16, 7)
        $t2 = New-Object Windows.Forms.Label
        $t2.AutoSize = $true; $t2.BackColor = 'Transparent'; $t2.Font = $FontUi; $t2.ForeColor = $G::Muted; $t2.UseMnemonic = $false
        $t2.Text = "from  $($m.Name)  ·  $($r.Count) files  ·  $($r.Removed)"; $t2.Location = New-Object Drawing.Point(17, 32)
        $t2.MaximumSize = New-Object Drawing.Size(($W - 260), 0)
        $back = New-Pill 'Put back' $true; $back.Font = $FontChip; $back.FitWidth(14, 30)
        $del = New-Pill 'Delete for good' $false; $del.Danger = $true; $del.Font = $FontChip; $del.FitWidth(14, 30)
        $del.Location = New-Object Drawing.Point(($W - $del.Width - 12), 14)
        $back.Location = New-Object Drawing.Point(($del.Left - $back.Width - 8), 14)
        $back.Tag = @{ Rec = $r; Do = 'back' }; $del.Tag = @{ Rec = $r; Do = 'del' }
        $act = {
            $a = $this.Tag
            try {
                if ($a.Do -eq 'back') { Restore-ModPart $a.Rec; $msg = "✓  Put back: $($PartLabel[$a.Rec.Part]) - $($ById[$a.Rec.Mod].Name)" }
                else {
                    $r2 = [Windows.Forms.MessageBox]::Show($form, "Delete '$($PartLabel[$a.Rec.Part])' of $($ById[$a.Rec.Mod].Name) for good?`n`nThe mod stays without it and it can't be put back (re-add the mod to get it back).", 'Removed parts', 'YesNo', 'Question', 'Button2')
                    if ($r2 -ne 'Yes') { return }
                    Remove-PartForGood $a.Rec; $msg = "✓  Deleted for good: $($PartLabel[$a.Rec.Part])"
                }
            } catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Removed parts') | Out-Null; return }
            $script:PartsMsg = $msg
            # Nupp, millele vajutati, kaob ümberehitusel: ehita pärast klõpsu lõppu
            $script:partsTimer = New-Object Windows.Forms.Timer; $partsTimer.Interval = 1
            $partsTimer.Add_Tick({ $this.Stop(); $this.Dispose(); Build-Tabs; $note.Text = $script:PartsMsg; $note.ForeColor = $G::Hex('#89D185') })
            $partsTimer.Start()
        }
        $back.Add_Click($act); $del.Add_Click($act)
        $p.Controls.AddRange(@($t1, $t2, $back, $del))
        $page.Controls.Add($p); $page.Controls.SetChildIndex($p, $insertAt); $insertAt++
        $page.SetFlowBreak($p, $true)
    }
}
