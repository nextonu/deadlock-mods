# Modi kustutamine lülitist.
# "✕ Delete mod" lülitab kustutamisrežiimi: modi nupule vajutades see MÄRGITAKSE (punane), uuesti vajutades
# märge kaob. All ribal "Delete selected (N)" kustutab kõik märgitud modid korraga (eraldi hoiatust pole,
# kustutamisrežiim ise on hoiatus). Paremklõps -> Delete… kustutab ühe modi ja küsib üle.
# Kustutatakse kõik: failid (addons / addons_off), kaamera paranduse originaal, arhiiv ja lahtipakitud kaust
# (kui teada), kirjed (lisatud.json / kustutatud.json, paigutus.json, pakid.json, oma vahelehed).
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1-te.

$DeleteMode = $false
$DelMarked = @{}     # id -> $true (märgitud kustutamiseks)
$CamfixOriginals = 'D:\Downloads\Muu\deadlock_mods\camfix_originals'
$CamfixOriginals = Join-Path $ArchiveDir 'camfix_originals'   # (jagatavas versioonis kasutaja enda Downloads)

$delBtn = New-Pill '✕  Delete' $false
$delBtn.Font = $FontChip; $delBtn.Dark = $Deco; $delBtn.FitWidth(16, 36)
$header.Controls.Add($delBtn)

# Alumisel ribal: kustuta kõik märgitud (nähtav ainult kustutamisrežiimis)
$delAllBtn = New-Pill '✕  Delete selected (0)' $false
$delAllBtn.Danger = $true; $delAllBtn.Font = $FontChip; $delAllBtn.FitWidth(14, 32); $delAllBtn.Visible = $false
$bottom.Controls.Add($delAllBtn)

# Teine nupp alumisel ribal (ainult Check / Updates režiimis): "kõik"
$selAllBtn = New-Pill 'All' $false
$selAllBtn.Font = $FontChip; $selAllBtn.Dark = $Deco; $selAllBtn.FitWidth(14, 32); $selAllBtn.Visible = $false
$bottom.Controls.Add($selAllBtn)

# Valikurežiim: modide nuppudele vajutades need MÄRGITAKSE (režiimi värviga), alumise riba nupp teeb tegevuse.
#  delete  = kustuta märgitud (punane)          check   = kontrolli märgitud (sinine)
#  updates = otsi märgitud modidele uuendusi    tab     = märgitud modid vahelehele (lilla; olemasolevad ette märgitud)
$SelMode = $null; $SelTab = $null
$SelModes = @{
    delete  = @{ Color = '#B83224'; Sym = '✕'; Word = 'Delete'; Btn = '✕  Delete selected'; Header = '✓  Done'
                 Note = "Delete mode: click mods to mark them, then press 'Delete selected'." }
    check   = @{ Color = '#2F6FB0'; Sym = '✓'; Word = 'Check'; Btn = '✓  Check selected'; All = 'Check all mods'; Header = '✕  Cancel'
                 Note = "Check: click the mods you want checked (a hero card = click each skin), then 'Check selected' - or 'Check all mods'." }
    updates = @{ Color = '#2E7D32'; Sym = '⟳'; Word = 'Update'; Btn = '⟳  Look up selected'; All = 'All linked mods'; Header = '✕  Cancel'
                 Note = "Updates: click the mods to look up on GameBanana, then 'Look up selected' - or 'All linked mods'." }
    tab     = @{ Color = '#7A4FB5'; Sym = '+'; Word = 'Add'; Btn = '+  Save tab'; Header = $null
                 Note = "Click mods to put them in this tab (click again to take one out), then 'Save tab'." }
}
function Get-ModeButton($mode) { switch ($mode) { 'delete' { $delBtn } 'check' { $chkBtn } 'updates' { $updBtn } default { $null } } }
$ModeButtonText = @{}

function Update-DeleteUi {
    $n = $DelMarked.Count
    if ($SelMode) {
        $md = $SelModes[$SelMode]
        $delAllBtn.Text = "$($md.Btn) ($n)"; $delAllBtn.FitWidth(14, 32); $delAllBtn.Invalidate()
        $delAllBtn.Enabled = ($n -gt 0 -or $SelMode -eq 'tab')
        $note.Text = if ($SelMode -eq 'tab') { "+  Tab '$SelTab': $n mod(s). $($md.Note)" } elseif ($n) { "$($md.Sym)  $n marked. Click more, then press '$($md.Btn.Substring(3))'." } else { "$($md.Sym)  $($md.Note)" }
        $note.ForeColor = [DlUi.G]::Mix($G::HeadText, $G::Hex($md.Color), 0.75)
    }
    foreach ($id in $Boxes.Keys) { foreach ($b in $Boxes[$id]) { $m = [bool]$DelMarked[$id]; if ($b.Marked -ne $m) { $b.Marked = $m; $b.Invalidate() } } }
    Place-Right
}

function Switch-DeleteMark($id) {
    if (-not $ById[$id]) { return }
    if ($DelMarked.ContainsKey($id)) { $DelMarked.Remove($id) } else { $DelMarked[$id] = $true }
    Update-DeleteUi
}

# $mode = 'delete' | 'check' | 'updates' | 'tab' | $null (välja). $tab = vahelehe nimi (tab režiimis).
function Set-SelectMode($mode, $tab = $null) {
    $prev = $SelMode
    if ($prev) { $b = Get-ModeButton $prev; if ($b) { $b.Text = $ModeButtonText[$prev]; $b.Danger = $false; $b.FitWidth(16, 36); $b.Invalidate() } }
    $script:SelMode = $mode; $script:SelTab = $tab
    $script:DeleteMode = [bool]$mode
    [DlUi.Chip]::DeleteMode = [bool]$mode
    $DelMarked.Clear()
    if ($mode) {
        $md = $SelModes[$mode]
        [DlUi.Chip]::MarkColor = $G::Hex($md.Color); [DlUi.Chip]::MarkSymbol = $md.Sym; [DlUi.Chip]::MarkWord = $md.Word
        $b = Get-ModeButton $mode
        if ($b -and $md.Header) { $ModeButtonText[$mode] = $b.Text; $b.Text = $md.Header; $b.Danger = ($mode -eq 'delete'); $b.FitWidth(16, 36); $b.Invalidate() }
        $delAllBtn.Danger = ($mode -eq 'delete')
        $delAllBtn.Primary = ($mode -ne 'delete')
        $selAllBtn.Visible = [bool]$md.All
        if ($md.All) { $selAllBtn.Text = $md.All; $selAllBtn.FitWidth(14, 32) }
        if ($mode -eq 'tab') {
            foreach ($id in @($CustomTabs[$tab])) { $DelMarked[$id] = $true }   # olemasolevad ette märgitud
            Show-TabByTitle 'All mods'                                          # kõik modid nähtaval
        }
    } else { $selAllBtn.Visible = $false }
    $delAllBtn.Visible = [bool]$mode
    Update-DeleteUi
    if (-not $mode) { Update-Boxes }
}
function Set-DeleteMode([bool]$on) { Set-SelectMode $(if ($on) { 'delete' } else { $null }) }

# märgitud id-d koos nende altide/lisadega
function Get-MarkedWithChildren { $ids = @($DelMarked.Keys); $ids += @($Mods | Where-Object { $_.Parent -and $ids -contains $_.Parent } | ForEach-Object { $_.Id }); return , @($ids | Select-Object -Unique) }

$delBtn.Add_Click({ if ($SelMode -eq 'delete') { Set-SelectMode $null } else { Set-SelectMode 'delete' } })
$delAllBtn.Add_Click({
    switch ($SelMode) {
        'delete'  { if ($DelMarked.Count) { Remove-Mods @($DelMarked.Keys) $false } }
        'check'   { $ids = Get-MarkedWithChildren; Set-SelectMode $null; if ($ids.Count) { Show-ModCheck $ids } }
        'updates' { $ids = Get-MarkedWithChildren; Set-SelectMode $null; if ($ids.Count) { Show-ModUpdates $ids } }
        'tab'     {
            $name = $SelTab; $marked = @($DelMarked.Keys)
            # varasem järjekord jääb, uued lõppu
            $keep = @($CustomTabs[$name] | Where-Object { $marked -contains $_ })
            $CustomTabs[$name] = @($keep) + @($marked | Where-Object { $keep -notcontains $_ })
            Save-Placement; Set-SelectMode $null; Build-Tabs; Show-TabByTitle $name
            $note.Text = "✓  '$name': $($CustomTabs[$name].Count) mods"; $note.ForeColor = $G::Hex('#89D185')
        }
    }
})
$selAllBtn.Add_Click({
    switch ($SelMode) {
        'check'   { Set-SelectMode $null; Show-ModCheck 'all' }
        'updates' { Set-SelectMode $null; Show-ModUpdates $null }
    }
})

function Remove-ModCompletely($m, $log) {
    # failid
    foreach ($f in $m.Files) {
        foreach ($p in @((Join-Path $Addons $f.Pak), (Join-Path $Off $f.Off), (Join-Path $CamfixOriginals $f.Off))) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; [void]$log.Add("Deleted: $p") }
        }
    }
    # eemaldatud osade originaalid ja kirjed (osad.ps1)
    if (Get-Command Clear-ModParts -ErrorAction SilentlyContinue) { Clear-ModParts $m $log }
    # modi pilt (pildid.ps1)
    $pic = Join-Path $PSScriptRoot "pildid\$($m.Id).png"; if (Test-Path -LiteralPath $pic) { Remove-Item -LiteralPath $pic -Force }
    # allika link (uuendused.ps1)
    if (Get-Command Clear-ModSource -ErrorAction SilentlyContinue) { Clear-ModSource $m.Id }
    # arhiiv ja lahtipakitud kaust (teada ainult lülitist lisatud modidel)
    $rec = @(Get-AddedMods | Where-Object { $_.Id -eq $m.Id })[0]
    if ($rec -and $rec.Source) {
        $arc = Join-Path $ArchiveDir $rec.Source
        if (Test-Path -LiteralPath $arc) { Remove-Item -LiteralPath $arc -Force; [void]$log.Add("Deleted: $arc") }
        $base = [IO.Path]::GetFileNameWithoutExtension($rec.Source)
        foreach ($d in @(Get-ChildItem -LiteralPath $ArchiveDir -Directory -ErrorAction SilentlyContinue)) {
            $x = Join-Path $d.FullName $base
            if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Recurse -Force; [void]$log.Add("Deleted: $x") }
        }
    }
    # kirjed
    if ($rec) {
        $all = @(Get-AddedMods | Where-Object { $_.Id -ne $m.Id })
        [IO.File]::WriteAllText($AddedFile, (ConvertTo-Json @($all) -Depth 5), (New-Object Text.UTF8Encoding $false))
    } else {
        # lüliti enda nimekirjas olev mod: jäta meelde, et see on kustutatud
        $del = @(Get-DeletedIds) + $m.Id | Select-Object -Unique
        [IO.File]::WriteAllText($DeletedFile, (ConvertTo-Json @($del)), (New-Object Text.UTF8Encoding $false))
    }
    $po = Get-PakOverrides
    if ($po.ContainsKey($m.Id)) {
        $po.Remove($m.Id)
        [IO.File]::WriteAllText($PakFile, (ConvertTo-Json $po), (New-Object Text.UTF8Encoding $false))
    }
    $script:SkinTab = @($SkinTab | Where-Object { $_ -ne $m.Id })
    foreach ($tn in @($CustomTabs.Keys)) { $CustomTabs[$tn] = @($CustomTabs[$tn] | Where-Object { $_ -ne $m.Id }) }
    $script:NewIds = @($NewIds | Where-Object { $_ -ne $m.Id })
    Save-Placement
    $script:Mods = @($Mods | Where-Object { $_.Id -ne $m.Id })
    $ById.Remove($m.Id); $State.Remove($m.Id)
}

# Kustutab antud modid (koos nende altidega). $ask = küsi enne üle (ühe modi kustutamine paremklõpsuga).
function Remove-Mods($ids, [bool]$ask) {
    $targets = New-Object Collections.ArrayList; $seen = @{}
    foreach ($id in $ids) {
        $m = $ById[$id]; if (-not $m) { continue }
        foreach ($k in (@(Get-Children $id) + $m)) { if (-not $seen[$k.Id]) { $seen[$k.Id] = $true; [void]$targets.Add($k) } }
    }
    if (-not $targets.Count) { return }
    if ($ask) {
        $msg = "Delete permanently:`n`n" + (($targets | ForEach-Object { "    $($_.Name)" }) -join "`n")
        $msg += "`n`nThe mod files are deleted from the game folder and (if known) the archive from Downloads. This cannot be undone."
        $r = [Windows.Forms.MessageBox]::Show($form, $msg, 'Delete mod', 'YesNo', 'Warning', 'Button2')
        if ($r -ne 'Yes') { return }
    }
    $inGame = @($targets | Where-Object { $mm = $_; @($mm.Files | Where-Object { Test-Path -LiteralPath (Join-Path $Addons $_.Pak) }).Count })
    if ($inGame.Count -and (Get-Process deadlock -ErrorAction SilentlyContinue)) {
        [Windows.Forms.MessageBox]::Show($form, 'Some of these mods are in use and Deadlock is running. Close the game first.', 'Delete mod') | Out-Null
        return
    }
    $log = New-Object Collections.ArrayList
    $done = 0
    try {
        foreach ($t in $targets) { Remove-ModCompletely $t $log; $done++ }
    } catch {
        [Windows.Forms.MessageBox]::Show($form, "Deleting stopped halfway ($done of $($targets.Count) done):`n$($_.Exception.Message)", 'Delete mod') | Out-Null
    }
    $DelMarked.Clear()
    Build-Tabs
    if ($script:DeleteMode) { Update-DeleteUi }
    $note.Text = if ($targets.Count -eq 1) { "✓  Deleted: $($targets[0].Name)" } else { "✓  Deleted $done mods" }
    $note.ForeColor = $G::Hex('#C0392B')
}

# Ühe modi kustutamine (paremklõps -> Delete…): küsib üle
function Remove-ModAsk($id) { Remove-Mods @($id) $true }
