# Modi info: paremklõps modil -> "Info…" (suurus, failid, kus need on, lisamise aeg, GameBanana link, altid).
# Ja vaheleht "By size": kõik modid suuruse järgi (suurim üleval), suurus kaardi pealkirjas.
# Laetakse DeadlockModToggle.ps1-st pärast uuendused.ps1-te.

# Faili asukoht: mängus (addons) või väljas (addons_off). @{ Path; Where; Size; Date }
function Get-ModFileInfo($f) {
    $a = Join-Path $Addons $f.Pak; $o = Join-Path $Off $f.Off
    foreach ($x in @(@($a, 'in game (addons)'), @($o, 'off (addons_off)'))) {
        if (Test-Path -LiteralPath $x[0]) { $fi = Get-Item -LiteralPath $x[0]; return @{ Path = $fi.FullName; Where = $x[1]; Size = $fi.Length; Date = $fi.LastWriteTime } }
    }
    return @{ Path = $null; Where = 'missing'; Size = 0; Date = $null }
}
function Get-ModOwnSize($m) { $n = [long]0; foreach ($f in @($m.Files)) { $n += (Get-ModFileInfo $f).Size }; return $n }
# mod koos oma altide / lisadega
function Get-ModTotalSize($id) {
    $m = $ById[$id]; if (-not $m) { return [long]0 }
    $n = Get-ModOwnSize $m
    foreach ($c in (Get-Children $id)) { $n += Get-ModOwnSize $c }
    return $n
}
function Format-Bytes([long]$n) {
    if ($n -ge 1GB) { return '{0:0.0} GB' -f ($n / 1GB) }
    if ($n -ge 1MB) { return '{0:0.0} MB' -f ($n / 1MB) }
    if ($n -ge 1KB) { return '{0:0} KB' -f ($n / 1KB) }
    return "$n B"
}

function Show-ModInfo($id) {
    $m = $ById[$id]; if (-not $m) { return }
    $rows = New-Object Collections.ArrayList
    $add = { param($k, $v) [void]$rows.Add(@($k, [string]$v)) }
    $sep = { param($t) [void]$rows.Add(@("— $t —", '')) }

    & $add 'Name' $m.Name
    $hero = Get-HeroName $m; if ($hero) { & $add 'Hero' $hero }
    & $add 'Category' $m.Cat
    if ($m.Parent -and $ById[$m.Parent]) { & $add 'Kind' "$(if ($m.AltStyle -eq 'badge') { '"n" version' } else { 'Alt / add-on' }) of $($ById[$m.Parent].Name)" } else { & $add 'Kind' 'Own mod' }
    $inGame = [bool](Test-On $m); $now = [bool]$State[$id]
    & $add 'State' $(if ($inGame -eq $now) { if ($now) { 'On (in the game)' } else { 'Off' } } else { "$(if ($now) { 'On' } else { 'Off' }) - not saved yet (game has it $(if ($inGame) { 'on' } else { 'off' }))" })
    $where = @()
    if ($SkinTab -contains $id) { $where += 'Other' } elseif ($m.Cat -eq 'Skins' -and -not $m.Parent -and -not $Portable) { $where += 'These' }
    foreach ($tn in @($CustomTabs.Keys)) { if ($CustomTabs[$tn] -contains $id) { $where += $tn } }
    if ($Favorites -contains $id) { $where += '★ favorite' }
    if ($where.Count) { & $add 'Tabs' ($where -join ', ') }
    & $add 'Id' $id

    & $sep 'Files'
    $own = [long]0
    foreach ($f in @($m.Files)) {
        $fi = Get-ModFileInfo $f; $own += $fi.Size
        & $add $f.Pak "$(Format-Bytes $fi.Size)  ·  $($fi.Where)  ·  $($f.Off)$(if ($fi.Date) { '  ·  ' + $fi.Date.ToString('yyyy-MM-dd HH:mm') })"
    }
    & $add 'Size' (Format-Bytes $own)
    if (Get-Command Get-OptRecords -ErrorAction SilentlyContinue) {
        $recs = Get-OptRecords; $ob = [long]0; $oa = [long]0
        foreach ($f in @($m.Files)) { $r = Get-OptRecord $recs $id $f; if ($r) { $ob += [long]$r.Before; $oa += [long]$r.After } }
        & $add 'Optimized' $(if ($ob) { "yes: $(Format-Bytes $ob) -> $(Format-Bytes $oa)  (original kept; right-click -> Restore original)" } else { 'no (right-click -> Optimize)' })
    }
    $kids = @(Get-Children $id)
    if ($kids.Count) {
        & $sep 'Alts / add-ons'
        $tot = $own
        foreach ($c in $kids) { $s = Get-ModOwnSize $c; $tot += $s; & $add $(if ($c.AltStyle -eq 'badge') { '"n" version' } else { '+ add-on' }) "$(Get-ShortName $c)  ·  $(Format-Bytes $s)  ·  $(if ($State[$c.Id]) { 'on' } else { 'off' })" }
        & $add 'Size with alts' (Format-Bytes $tot)
    }

    # lisamine (lisatud.json) ja allikas
    $rec = $null; try { $rec = @(Get-AddedMods | Where-Object { $_.Id -eq $id })[0] } catch {}
    $src = $null; try { $src = (Get-Sources)[$id] } catch {}
    if ($rec -or $src) {
        & $sep 'Where it came from'
        if ($rec -and $rec.Added) { & $add 'Added' $rec.Added }
        if ($rec -and $rec.Source) {
            $arch = Join-Path $ArchiveDir $rec.Source
            & $add 'Archive' "$($rec.Source)$(if (Test-Path -LiteralPath $arch) { '  ·  ' + (Format-Bytes (Get-Item -LiteralPath $arch).Length) + '  (kept in ' + $ArchiveDir + ')' } else { '' })"
        }
        if ($src) {
            & $add 'GameBanana' "$($src.Title)"
            & $add 'Page' (Get-GbUrl $src.Model $src.GbId)
            foreach ($sf in @($src.Files)) { if ($sf.Name) { & $add 'Linked file' "$($sf.Name)$(if ($sf.Date) { '  ·  ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$sf.Date).LocalDateTime.ToString('yyyy-MM-dd') })$(if ([long]$sf.File -eq 0) { '  (not on the page any more)' })" } }
        }
    }
    if ($script:GoneMods -and $script:GoneMods.ContainsKey($id)) { $gm = $script:GoneMods[$id]; & $add 'GameBanana' "Page removed by the author (noticed $($gm.Date))  ·  $($gm.Url)" }
    & $add 'Picture' $(if (Test-Path -LiteralPath (Join-Path $ModPicDir "$id.png")) { 'yes' } else { 'no (right-click -> Picture…)' })

    # --- aken ---
    $d = New-Object Windows.Forms.Form
    $d.Text = "Info - $($m.Name)"; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(760, 520); $d.MinimumSize = New-Object Drawing.Size(560, 380)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $hdr = New-DialogHeader $d $m.Name "$(Format-Bytes (Get-ModTotalSize $id))$(if ($hero) { '  ·  ' + $hero })  ·  $($m.Cat)"
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HeaderStyle = 'None'; $lv.ShowItemToolTips = $true
    $lv.Location = New-Object Drawing.Point(16, 84); $lv.Size = New-Object Drawing.Size(728, 372); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    [void]$lv.Columns.Add('', 180); [void]$lv.Columns.Add('', 530)
    [DlUi.ListStyle]::Apply($lv, 24)
    foreach ($r in $rows) {
        $it = New-Object Windows.Forms.ListViewItem($r[0]); [void]$it.SubItems.Add($r[1]); $it.ToolTipText = $r[1]
        if ($r[0] -like '— *') { $it.ForeColor = $G::Muted }
        [void]$lv.Items.Add($it)
    }
    $lv.Add_Resize({ $lv.Columns[1].Width = [Math]::Max(200, $lv.ClientSize.Width - $lv.Columns[0].Width - 4) })
    # Ctrl+C / topeltklõps: rea väärtus lõikelauale
    $lv.Add_DoubleClick({ if ($lv.SelectedItems.Count -and $lv.SelectedItems[0].SubItems[1].Text) { [Windows.Forms.Clipboard]::SetText($lv.SelectedItems[0].SubItems[1].Text); $hdr.Sub.Text = 'Copied: ' + $lv.SelectedItems[0].SubItems[1].Text } })

    $close = New-Pill 'Close' $true; $close.FitWidth(18, 34); $close.Anchor = 'Bottom, Right'
    $close.Location = New-Object Drawing.Point((744 - $close.Width), 470); $close.Add_Click({ $d.Close() })
    $bDir = New-Pill 'Show file in folder' $false; $bDir.FitWidth(14, 34); $bDir.Anchor = 'Bottom, Left'; $bDir.Location = New-Object Drawing.Point(16, 470)
    $first = @(@($m.Files) | ForEach-Object { (Get-ModFileInfo $_).Path } | Where-Object { $_ })[0]
    $bDir.Enabled = [bool]$first; $bDir.Tag = $first
    $bDir.Add_Click({ Start-Process explorer.exe "/select,`"$($this.Tag)`"" })
    $ctl = @($hdr.Panel, $lv, $bDir, $close)
    if ($src) {
        $bPg = New-Pill 'Open GameBanana page' $false; $bPg.FitWidth(14, 34); $bPg.Anchor = 'Bottom, Left'; $bPg.Location = New-Object Drawing.Point(($bDir.Right + 8), 470)
        $bPg.Tag = (Get-GbUrl $src.Model $src.GbId); $bPg.Add_Click({ Start-Process $this.Tag }); $ctl += $bPg
    }
    $d.Controls.AddRange(@($ctl | Where-Object { $_ -ne $hdr.Panel }))
    $d.Add_Shown({ $lv.Columns[1].Width = [Math]::Max(200, $lv.ClientSize.Width - $lv.Columns[0].Width - 4) })
    [void]$d.ShowDialog($form); $d.Dispose()
}

# Paremklõpsu menüüsse (kõige ülemiseks)
$miInfo = New-Object Windows.Forms.ToolStripMenuItem 'Info…  (size, files)'
$ModMenu.Items.Insert(0, $miInfo)
$miInfo.Add_Click({ if ($script:MenuId) { Show-ModInfo $script:MenuId } })
