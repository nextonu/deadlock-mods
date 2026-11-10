# Optimize: modide liiga suured tekstuurid (üle 2048 px, nt 4K / 8K) väiksemaks.
#  - Tekstuuri sees on juba valmis väiksemad versioonid (mipid); ära visatakse ainult suurimad. Muu fail jääb
#    baithaaval samaks (mudel, animatsioonid, helid) - mod näeb välja sama, lihtsalt vähem detailne lähedalt.
#  - Vähem videomälu (6 GB kaardil jõnksumine kaob), väiksemad failid, kiirem laadimine.
#  - Ka kasutamata andmed failist välja (nt eemaldatud osade andmed, mis jäid faili alles).
#  - Originaal jääb alles (<arhiivikaust>\optimize_originals). Paremklõps -> "Restore original" paneb tagasi.
# Päise nupp "Optimize" = valikurežiim nagu Check/Updates. Töö: optimeeri.py (Python).
# Laetakse DeadlockModToggle.ps1-st pärast info.ps1-te.

$OptScript = Join-Path $PSScriptRoot 'optimeeri.py'
$OptFile = Join-Path $PSScriptRoot 'optimeeritud.json'
$OptDir = Join-Path $ArchiveDir 'optimize_originals'
$OptMax = 2048

# kirjed: "<modi id>|<Off fail>" -> @{ Orig; Before; After; Tex; Date }
function Get-OptRecords {
    $h = @{}
    if (Test-Path -LiteralPath $OptFile) { try { $j = [IO.File]::ReadAllText($OptFile) | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value } } catch {} }
    return $h
}
function Save-OptRecords($h) {
    $o = [ordered]@{}; foreach ($k in ($h.Keys | Sort-Object)) { $o[$k] = $h[$k] }
    [IO.File]::WriteAllText($OptFile, (ConvertTo-Json $o -Depth 4), (New-Object Text.UTF8Encoding $false))
}
# Kehtiv kirje: fail on praegu täpselt see optimeeritud fail (uuendus / osade taastamine teeb kirje aegunuks)
function Get-OptRecord($recs, $id, $f) {
    $r = $recs["$id|$($f.Off)"]; if (-not $r) { return $null }
    $fi = Get-ModFileInfo $f
    if ($fi.Path -and [long]$fi.Size -eq [long]$r.After -and (Test-Path -LiteralPath $r.Orig)) { return $r }
    return $null
}
function Test-ModOptimized($id) {
    $m = $ById[$id]; if (-not $m) { return $false }; $recs = Get-OptRecords
    foreach ($f in @($m.Files)) { if (Get-OptRecord $recs $id $f) { return $true } }
    return $false
}

# Üks mod (ainult tema enda failid). Tagastab @{ Before; After; Tex; Note }
function Invoke-OptimizeMod($id) {
    $m = $ById[$id]; $res = @{ Before = [long]0; After = [long]0; Tex = 0; Note = ''; Unused = [long]0 }
    if (-not $Python) { throw 'Python was not found (tools\python).' }
    $recs = Get-OptRecords; $did = $false
    foreach ($f in @($m.Files)) {
        $fi = Get-ModFileInfo $f
        if (-not $fi.Path) { $res.Note = 'file missing'; continue }
        $old = Get-OptRecord $recs $id $f
        $tmp = "$($fi.Path).opt_tmp"
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $out = @(Run $Python -I $OptScript $fi.Path $tmp $OptMax)
        $j = $null; foreach ($l in $out) { if ($l.TrimStart().StartsWith('{')) { try { $j = $l | ConvertFrom-Json } catch {} } }
        if (-not $j) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw "optimizer failed: $(($out | Select-Object -Last 2) -join ' ')" }
        $tc = if ($null -ne $j.textures_changed) { [int]$j.textures_changed } else { [int]$j.changed }   # tekstuurid (ilma tühja andme eemaldamiseta)
        if ($j.changed -and [long]$j.unused -gt 1MB) { $res.Unused += [long]$j.unused }
        if ($old) {
            # juba optimeeritud: uuemas versioonis võib olla lisa (nt suured taustapildid) - originaal jääb esimene
            $res.Before += [long]$old.Before; $res.Tex += [int]$old.Tex
            if ($j.changed -and (Test-Path -LiteralPath $tmp)) {
                Move-Item -LiteralPath $tmp -Destination $fi.Path -Force
                $after = (Get-Item -LiteralPath $fi.Path).Length
                $old.After = $after; $old.Tex = [int]$old.Tex + $tc; $recs["$id|$($f.Off)"] = $old
                $res.After += $after; $res.Tex += $tc; $did = $true
            } else { $res.After += $fi.Size; $res.Note = 'already optimized' }
            continue
        }
        $res.Before += $fi.Size
        if (-not $j.changed -or -not (Test-Path -LiteralPath $tmp)) { $res.After += $fi.Size; continue }
        # original kõrvale (kui sama nimega juba on, see ongi original)
        if (-not (Test-Path -LiteralPath $OptDir)) { New-Item -ItemType Directory -Force $OptDir | Out-Null }
        $orig = Join-Path $OptDir "$($id)__$($f.Off)"
        if (-not (Test-Path -LiteralPath $orig)) { Copy-Item -LiteralPath $fi.Path -Destination $orig }
        if ((Get-Item -LiteralPath $orig).Length -ne $fi.Size) { $orig = Join-Path $OptDir "$($id)__$(Get-Date -Format 'yyyyMMddHHmmss')__$($f.Off)"; Copy-Item -LiteralPath $fi.Path -Destination $orig }
        Move-Item -LiteralPath $tmp -Destination $fi.Path -Force
        $after = (Get-Item -LiteralPath $fi.Path).Length
        $recs["$id|$($f.Off)"] = [ordered]@{ Orig = $orig; Before = $fi.Size; After = $after; Tex = $tc; Date = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
        $res.After += $after; $res.Tex += $tc; $did = $true
    }
    if ($did) { Save-OptRecords $recs }
    if (-not $did -and -not $res.Note) { $res.Note = 'nothing to shrink (no textures over 2048 px)' }
    return $res
}

# Originaal tagasi. Tagastab mitu faili taastati.
function Restore-ModOriginal($id) {
    $m = $ById[$id]; $recs = Get-OptRecords; $n = 0
    foreach ($f in @($m.Files)) {
        $r = Get-OptRecord $recs $id $f; if (-not $r) { continue }
        $fi = Get-ModFileInfo $f
        Copy-Item -LiteralPath $r.Orig -Destination $fi.Path -Force
        $recs.Remove("$id|$($f.Off)"); $n++
    }
    if ($n) { Save-OptRecords $recs }
    return $n
}

# ---------- Aken: optimeerimine (järjest, taustal edenemine) ----------
function Show-Optimize($ids) {
    if (-not (Test-GameClosed)) { return }
    $ids = @($ids | Where-Object { $ById[$_] })
    if (-not $ids.Count) { return }
    $st = @{ Queue = (New-Object Collections.ArrayList); Busy = $false; Closing = $false; Done = 0; Before = [long]0; After = [long]0; Bad = 0 }
    foreach ($i in $ids) { [void]$st.Queue.Add($i) }
    $d = New-Object Windows.Forms.Form
    $d.Text = 'Optimize mods'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.StartPosition = 'CenterParent'; Enable-DialogMinimize $d
    $d.ClientSize = New-Object Drawing.Size(860, 600); $d.MinimumSize = New-Object Drawing.Size(640, 420)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $hdr = New-DialogHeader $d 'Optimize mods' "Textures bigger than $OptMax px are made $OptMax px. Originals are kept - right-click a mod -> Restore original."
    $lab = New-Object DlUi.Banner
    $lab.Location = New-Object Drawing.Point(16, 74); $lab.Size = New-Object Drawing.Size(828, 46); $lab.Anchor = 'Top, Left, Right'
    $lab.Font = $FontChip; $lab.Kind = 0; $lab.Text = "Optimizing $($ids.Count) mod(s)…"
    $bar = New-Object DlUi.Bar
    $bar.Location = New-Object Drawing.Point(16, 130); $bar.Size = New-Object Drawing.Size(828, 8); $bar.Anchor = 'Top, Left, Right'; $bar.Maximum = $ids.Count
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.ShowItemToolTips = $true
    $lv.Location = New-Object Drawing.Point(16, 150); $lv.Size = New-Object Drawing.Size(828, 386); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('Mod', 300), @('Before', 90), @('After', 90), @('Result', 330))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    [DlUi.ListStyle]::Apply($lv, 26)
    $lv.Add_Resize({ $w = $lv.ClientSize.Width - 300 - 90 - 90 - 4; if ($w -gt 120) { $lv.Columns[3].Width = $w } })
    $close = New-Pill 'Close' $true; $close.FitWidth(18, 36); $close.Anchor = 'Bottom, Right'; $close.Enabled = $false
    $close.Location = New-Object Drawing.Point((844 - $close.Width), 550); $close.Add_Click({ $d.Close() })
    $hint = New-Object Windows.Forms.Label; $hint.AutoSize = $true; $hint.ForeColor = $DlgMuted; $hint.Anchor = 'Bottom, Left'; $hint.Location = New-Object Drawing.Point(16, 560)
    $hint.Text = "Models, animations and sounds stay exactly the same. Originals: $OptDir"
    $rows = @{}
    foreach ($i in $ids) {
        $it = New-Object Windows.Forms.ListViewItem((Get-ShortName $ById[$i]) + $(if (Get-HeroName $ById[$i]) { "  ($(Get-HeroName $ById[$i]))" }))
        [void]$it.SubItems.Add(''); [void]$it.SubItems.Add(''); [void]$it.SubItems.Add('waiting'); $it.ForeColor = $G::Muted
        [void]$lv.Items.Add($it); $rows[$i] = $it
    }
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 50
    $timer.Add_Tick({
        if ($st.Busy -or $st.Closing) { return }
        if (-not $st.Queue.Count) {
            $timer.Stop(); $close.Enabled = $true
            $saved = $st.Before - $st.After
            $lab.Kind = $(if ($st.Bad) { 2 } else { 1 })
            $lab.Text = "Done: $(Format-Bytes $st.Before) -> $(Format-Bytes $st.After)  (saved $(Format-Bytes $saved))" + $(if ($st.Bad) { ", $($st.Bad) failed" } else { '' }) + '. Start Deadlock as usual.'
            $hdr.Sub.Text = "Finished: $($st.Done) mod(s)"
            [DlUi.Notify]::Done($form, [bool]$st.Bad)
            return
        }
        $st.Busy = $true
        $id = $st.Queue[0]; $st.Queue.RemoveAt(0); $row = $rows[$id]
        $row.SubItems[3].Text = 'working…'; $row.ForeColor = $G::Text; $row.EnsureVisible(); $lab.Text = "Optimizing $($st.Done + 1) / $($bar.Maximum):  $($row.Text)"
        $lv.Refresh()
        try {
            $r = Invoke-OptimizeMod $id
            $row.SubItems[1].Text = Format-Bytes $r.Before; $row.SubItems[2].Text = Format-Bytes $r.After
            $st.Before += $r.Before; $st.After += $r.After
            if ($r.Before -gt $r.After) { $row.SubItems[3].Text = "✓  " + $(if ($r.Tex) { "$($r.Tex) texture(s) smaller" } else { '' }) + $(if ($r.Tex -and $r.Unused) { ' + ' } else { '' }) + $(if ($r.Unused) { "$(Format-Bytes $r.Unused) unused data removed" } else { '' }) + ", -$(Format-Bytes ($r.Before - $r.After))" + $(if ($r.Note) { "  ($($r.Note))" }); $row.ForeColor = [DlUi.G]::Fg('#1F5F24') }
            else { $row.SubItems[3].Text = "–  $($r.Note)"; $row.ForeColor = $G::Muted }
        } catch { $row.SubItems[3].Text = "✕  $_"; $row.ToolTipText = "$_"; $row.ForeColor = [DlUi.G]::Fg('#8E2A20'); $st.Bad++ }
        $st.Done++; $bar.Value = [Math]::Min($bar.Maximum, $st.Done)
        $st.Busy = $false
    })
    $d.Add_Shown({ $timer.Start() })
    $d.Add_FormClosing({ if ($st.Busy) { $_.Cancel = $true; return }; $st.Closing = $true; $timer.Stop() })
    $d.Controls.AddRange(@($lab, $bar, $lv, $hint, $close))
    [void]$d.ShowDialog($form)
    $timer.Dispose(); $d.Dispose()
    if ($st.Done) { Build-Tabs; $note.Text = "✓  Optimized: saved $(Format-Bytes ($st.Before - $st.After))"; $note.ForeColor = $G::Hex('#89D185') }
}

# ---------- Päise nupp + valikurežiim ----------
$optBtn = New-Pill '⚡' $false   # päises pole ruumi pikale nupule: ainult märk + vihje
$optBtn.Font = $FontChip; $optBtn.Dark = $Deco; $optBtn.FitWidth(14, 36)
(New-Object Windows.Forms.ToolTip).SetToolTip($optBtn, 'Optimize: make big (4K/8K) textures 2K - less video memory, less stutter')
$header.Controls.Add($optBtn)
$SelModes['optimize'] = @{ Color = '#8C5A10'; Sym = '⚡'; Word = 'Optimize'; Btn = '⚡  Optimize selected'; All = 'Optimize all mods'; Header = '✕  Cancel'
    Note = "Optimize: makes 4K/8K textures 2K (less video memory = less stutter). Click mods, then 'Optimize selected' - or 'Optimize all mods'." }
$ExtraModeButtons['optimize'] = $optBtn
$ExtraModeActions['optimize'] = { param($ids) Show-Optimize $ids }
$ExtraModeAll['optimize'] = { Show-Optimize @($Mods | ForEach-Object { $_.Id }) }
$optBtn.Add_Click({ if ($SelMode -eq 'optimize') { Set-SelectMode $null } else { Set-SelectMode 'optimize' } })

# ---------- Paremklõpsu menüü ----------
$miOpt = New-Object Windows.Forms.ToolStripMenuItem 'Optimize (smaller textures)'
$miOptBack = New-Object Windows.Forms.ToolStripMenuItem 'Restore original (not optimized)'
$ModMenu.Items.Insert(1, $miOpt); $ModMenu.Items.Insert(2, $miOptBack)
$ModMenu.Add_Opening({
    if (-not $script:MenuId) { return }
    $o = Test-ModOptimized $script:MenuId
    $miOpt.Visible = -not $o; $miOptBack.Visible = $o
})
$miOpt.Add_Click({ if ($script:MenuId) { Show-Optimize @($script:MenuId) } })
$miOptBack.Add_Click({
    if (-not $script:MenuId -or -not (Test-GameClosed)) { return }
    try { $n = Restore-ModOriginal $script:MenuId; $note.Text = "✓  Original restored ($n file(s))"; $note.ForeColor = $G::Hex('#89D185') }
    catch { [Windows.Forms.MessageBox]::Show($form, "Could not restore: $_", 'Deadlock Mods') | Out-Null }
})
