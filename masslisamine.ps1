# Mass add: mitu modi korraga. Vali mitu faili ("+ Add mod" -> From files, Ctrl/Shift) või lohista mitu faili aknale.
# Failid pakitakse lahti ja kontrollitakse taustal ükshaaval (kangelane, jagatud failid, kaamera).
# Iga rea kohta (all, "Selected"): eraldi mod või ALT / LISA olemasolevale modile, ja kuidas alti näidata
# ("+ …" nupp modi kõrval või "n" modi nupu nurgas; jagatavas versioonis ainult "+").
# Paremal kastid: kuhu eraldi mod läheb (New / Other / These / oma vahelehed / Skip). "Add N mods" lisab kõik korraga.
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1-te ja menuu.ps1-te.

function Show-MassAdd($files) {
    if ($script:AddBusy) { return }
    $script:AddBusy = $true; $addBtn.Enabled = $false
    # Olek ühes hashtable'is: sündmuste skriptiplokid muudavad seda (muutuja omistamine teeks koopia)
    $st = @{ Items = (New-Object Collections.ArrayList); Busy = $false; Closing = $false; Zones = @(); Filling = $false; Seq = 0 }
    $cats = @('Skins', 'Map', 'Visuals', 'Sounds & music', 'Utility (recommended)')
    $dests = @('New') + $(if ($Portable) { @() } else { @('Other', 'These') }) + @($CustomTabs.Keys | ForEach-Object { "tab:$_" }) + @('Skip')
    $destText = @{ New = $(if ($Portable) { 'All mods' } else { 'New (choose later)' }); Other = 'Other'; These = 'These'; Skip = 'Skip (don''t add)' }
    foreach ($t in $CustomTabs.Keys) { $destText["tab:$t"] = "Tab: $t" }
    # olemasolevad modid, millele saab alti/lisa panna (kangelase järgi sorteeritud)
    $parents = @($Mods | Where-Object { -not $_.Parent } | Sort-Object @{ e = { "$(Get-HeroName $_)" } }, @{ e = { $_.Name } })
    # Ema võib olla ka selles nimekirjas olev mod (mod ja tema alt korraga): siis on Parent = tema võti "@N"
    $batchItem = { param($k) @($st.Items | Where-Object { $_.Key -eq $k })[0] }
    $parName = { param($k) if ("$k" -like '@*') { $b = & $batchItem $k; if ($b) { "$($b.Row.Text) (new)" } else { '?' } } else { Get-ShortName $ById[$k] } }
    $parCat = { param($k) if ("$k" -like '@*') { $b = & $batchItem $k; if ($b) { $b.Cat } else { $null } } else { $ById[$k].Cat } }
    $parLabel = {
        param($k, $score)
        $star = if ($score -ge 3) { '★ ' } else { '' }
        if ("$k" -like '@*') { $b = & $batchItem $k; $h = if ($b.Prep -and $b.Prep.Hero) { "$($b.Prep.Hero.Display.ToUpper()) · " } else { '' }; return "$star$h$($b.Row.Text)   (in this list)" }
        $pm = $ById[$k]; $h = Get-HeroName $pm
        "$star$(if ($pm.Hero -and $h) { "$($h.ToUpper()) · " })$(Get-ShortName $pm)$(if ($State[$k]) { '   (on)' })"
    }
    # Kellele see mod sobiks altiks/lisaks: sama kangelane, sarnane nimi, praegu sees olev mod -> eespool
    $suggest = {
        param($it)
        $hk = if ($it.Prep -and $it.Prep.Hero) { $it.Prep.Hero.Key } else { $null }
        $nm = "$($it.Row.Text) $([IO.Path]::GetFileNameWithoutExtension($it.File))"
        $scored = foreach ($pm in $parents) {
            $sc = 0
            if ($hk -and $pm.Hero -eq $hk) { $sc += 3 }
            $sc += 5 * (Get-Sim $nm "$($pm.Name) $(@($pm.Files | ForEach-Object { $_.Off }) -join ' ')")
            if ($State[$pm.Id]) { $sc += 0.5 }
            [pscustomobject]@{ Id = $pm.Id; Score = $sc }
        }
        # samas nimekirjas olevad modid (mitte ise, mitte alt, mitte vahele jäetud)
        $batch = foreach ($o in $st.Items) {
            if ($o -eq $it -or $o.Parent -or $o.Dest -eq 'Skip' -or $o.State -eq 'error') { continue }
            $sc = 1
            $ohk = if ($o.Prep -and $o.Prep.Hero) { $o.Prep.Hero.Key } else { $null }
            if ($hk -and $ohk -eq $hk) { $sc += 3 }
            $sc += 5 * (Get-Sim $nm "$($o.Row.Text) $([IO.Path]::GetFileNameWithoutExtension($o.File))")
            [pscustomobject]@{ Id = $o.Key; Score = $sc }
        }
        return , @(@($batch) + @($scored) | Sort-Object Score -Descending)
    }

    $d = New-Object Windows.Forms.Form
    $d.Text = 'Add several mods'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.StartPosition = 'CenterParent'; Enable-DialogMinimize $d
    $d.ClientSize = New-Object Drawing.Size(980, 700); $d.MinimumSize = New-Object Drawing.Size(820, 560)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $hdr = New-DialogHeader $d 'Add several mods' 'Each file is unpacked and checked. Then press "Add" at the bottom - the rest is optional.'

    $ban = New-Object DlUi.Banner
    $ban.Location = New-Object Drawing.Point(16, 74); $ban.Size = New-Object Drawing.Size(948, 46); $ban.Anchor = 'Top, Left, Right'
    $ban.Font = $FontChip; $ban.Kind = 0; $ban.Text = 'Checking files…'

    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $true; $lv.HideSelection = $false; $lv.LabelEdit = $true
    $lv.Location = New-Object Drawing.Point(16, 130); $lv.Size = New-Object Drawing.Size(700, 404); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    $lv.AllowDrop = $true; $lv.ShowItemToolTips = $true
    foreach ($c in @(@('Name', 200), @('Hero', 90), @('Category', 100), @('Added as', 150), @('Status', 156))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    [DlUi.ListStyle]::Apply($lv, 26)
    $groups = @{}
    foreach ($k in $dests) { $grp = New-Object Windows.Forms.ListViewGroup($k, $destText[$k]); [void]$lv.Groups.Add($grp); $groups[$k] = $grp }
    $grpAlt = New-Object Windows.Forms.ListViewGroup('alt', 'Alts / add-ons'); [void]$lv.Groups.Insert(0, $grpAlt)

    # --- valitud ridade seaded ---
    $ed = New-Object Windows.Forms.Panel
    $ed.Location = New-Object Drawing.Point(16, 542); $ed.Size = New-Object Drawing.Size(700, 92); $ed.Anchor = 'Bottom, Left, Right'
    $ed.BackColor = $G::Panel; $ed.BorderStyle = 'FixedSingle'
    $edLab = New-Object Windows.Forms.Label; $edLab.AutoSize = $true; $edLab.Location = New-Object Drawing.Point(10, 8); $edLab.ForeColor = $G::Text
    $edLab.Font = New-Object Drawing.Font($FontChip, [Drawing.FontStyle]::Bold); $edLab.Text = 'Click a mod in the list to change how it is added.'; $edLab.UseMnemonic = $false
    $mkCombo = {
        param($w)
        $cb = New-Object Windows.Forms.ComboBox
        $cb.DropDownStyle = 'DropDownList'; $cb.FlatStyle = 'Flat'; $cb.BackColor = $G::Raised; $cb.ForeColor = $G::Bright; $cb.Width = $w; $cb.MaxDropDownItems = 20
        $cb.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco -and -not $Night) { 'Explorer' } else { 'DarkMode_CFD' }), $null) })
        $cb
    }
    $l1 = New-Object Windows.Forms.Label; $l1.Text = 'Add as:'; $l1.AutoSize = $true; $l1.ForeColor = $G::Text; $l1.Location = New-Object Drawing.Point(10, 40)
    $asBox = & $mkCombo 380; $asBox.Location = New-Object Drawing.Point(70, 36); $asBox.Enabled = $false
    $st.Order = @($parents | ForEach-Object { $_.Id })
    $fillAs = {
        param($order, $scores)
        $st.Order = $order
        $asBox.BeginUpdate(); $asBox.Items.Clear(); [void]$asBox.Items.Add('Its own mod')
        foreach ($pid2 in $order) {
            $scv = if ($scores) { $scores[$pid2] } else { 0 }
            [void]$asBox.Items.Add("Alt / add-on for:  $(& $parLabel $pid2 $scv)")
        }
        $asBox.EndUpdate()
    }
    & $fillAs $st.Order $null
    $l2 = New-Object Windows.Forms.Label; $l2.Text = 'Show as:'; $l2.AutoSize = $true; $l2.ForeColor = $G::Text; $l2.Location = New-Object Drawing.Point(462, 40)
    $styleBox = & $mkCombo 160; $styleBox.Location = New-Object Drawing.Point(526, 36); $styleBox.Enabled = $false
    [void]$styleBox.Items.AddRange(@('+ button next to it', '"n" in its corner'))
    if ($Portable) { $l2.Visible = $false; $styleBox.Visible = $false }
    $edHint = New-Object Windows.Forms.Label; $edHint.AutoSize = $true; $edHint.ForeColor = $DlgMuted; $edHint.Location = New-Object Drawing.Point(10, 66)
    $edHint.Text = 'Alt / add-on: goes with that mod - also one you are adding now (in this list). Own mod: its own button.'
    $ed.Controls.AddRange(@($edLab, $l1, $asBox, $l2, $styleBox, $edHint))

    # Paremal: sihtkastid
    $zl = New-Object Windows.Forms.Label
    $zl.Text = 'Drag or click - selected mods go to:'; $zl.AutoSize = $true; $zl.ForeColor = $DlgText; $zl.Anchor = 'Top, Right'
    $zl.Location = New-Object Drawing.Point(732, 130)
    $zones = New-Object Windows.Forms.FlowLayoutPanel
    $zones.FlowDirection = 'TopDown'; $zones.WrapContents = $false; $zones.AutoScroll = $true
    $zones.Location = New-Object Drawing.Point(732, 154); $zones.Size = New-Object Drawing.Size(232, 480); $zones.Anchor = 'Top, Bottom, Right'
    $zones.BackColor = $DlgBg

    $cnt = New-Object Windows.Forms.Label
    $cnt.AutoSize = $true; $cnt.ForeColor = $DlgText; $cnt.Anchor = 'Bottom, Left'
    $cnt.Location = New-Object Drawing.Point(16, 660)
    $ok = New-Pill 'Add' $true; $ok.FitWidth(26, 36); $ok.Anchor = 'Bottom, Right'
    $ok.Location = New-Object Drawing.Point((964 - $ok.Width), 652); $ok.Enabled = $false
    $no = New-Pill 'Cancel' $false; $no.FitWidth(18, 36); $no.Anchor = 'Bottom, Right'
    $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 652)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })

    # --- abifunktsioonid (skriptiplokid, et sündmused neid näeksid) ---
    $rowText = {
        param($it)
        if ($it.Parent) { "$(if ($it.Style -eq 'badge') { 'n' } else { '+' }) alt of $(& $parName $it.Parent)" } else { 'Own mod' }
    }
    $refresh = {
        $ready = 0; $wait = 0; $bad = 0; $add = 0
        foreach ($it in $st.Items) {
            switch ($it.State) { 'ready' { $ready++; if ($it.Dest -ne 'Skip') { $add++ } } 'error' { $bad++ } default { $wait++ } }
            $it.Row.SubItems[3].Text = & $rowText $it
            $it.Row.Group = if ($it.Dest -eq 'Skip') { $groups['Skip'] } elseif ($it.Parent) { $grpAlt } else { $groups[$it.Dest] }
        }
        $txt = "$($st.Items.Count) file(s):  $ready ready"
        if ($wait) { $txt += ",  $wait checking…" }
        if ($bad) { $txt += ",  $bad failed" }
        $cnt.Text = $txt
        if ($wait) { $ban.Kind = 0; $ban.Text = "Unpacking and checking… $($st.Items.Count - $wait) / $($st.Items.Count)   (you can already choose how each one is added)" }
        elseif ($bad -and -not $ready) { $ban.Kind = 3; $ban.Text = 'None of the files could be added - see the Status column (hover a row for details).' }
        elseif ($bad) { $ban.Kind = 2; $ban.Text = "$ready ready, $bad failed (see Status). Press 'Add $add mod$(if ($add -ne 1) { 's' })' to add the ready ones." }
        else { $ban.Kind = 1; $ban.Text = "All ready - press 'Add $add mod$(if ($add -ne 1) { 's' })' at the bottom. Click a row to make it an alt / add-on instead." }
        $ok.Text = "Add $add mod" + $(if ($add -ne 1) { 's' } else { '' }); $ok.FitWidth(26, 36)
        $ok.Left = $d.ClientSize.Width - 16 - $ok.Width; $no.Left = $ok.Left - $no.Width - 10
        $ok.Enabled = (-not $wait -and $add -gt 0)
        foreach ($z in $st.Zones) { $z.Invalidate() }
    }
    $setDest = {
        param($it, $dest)
        $it.Dest = $dest   # alt jääb aldiks (näidatakse oma modi kaardil); "Its own mod" tuleb valida all
    }
    $addFiles = {
        param($list)
        foreach ($f in $list) {
            if (-not $f -or @($st.Items | Where-Object { $_.File -eq $f }).Count) { continue }
            $row = New-Object Windows.Forms.ListViewItem([IO.Path]::GetFileNameWithoutExtension($f))
            [void]$row.SubItems.Add('…'); [void]$row.SubItems.Add('…'); [void]$row.SubItems.Add('Own mod'); [void]$row.SubItems.Add('Waiting')
            $st.Seq++
            $it = @{ File = $f; Row = $row; Prep = $null; State = 'wait'; Dest = 'New'; Cat = $null; Parent = $null; Style = 'chip'; Key = "@$($st.Seq)" }
            $row.Tag = $it
            $row.Group = $groups['New']
            [void]$lv.Items.Add($row)
            [void]$st.Items.Add($it)
        }
        & $refresh
    }
    # valitud read -> seadete paneel
    $showSel = {
        $sel = @($lv.SelectedItems | ForEach-Object { $_.Tag })
        $st.Filling = $true
        $asBox.Enabled = [bool]$sel.Count; $styleBox.Enabled = $false
        if (-not $sel.Count) { $edLab.Text = 'Click a mod in the list to change how it is added.'; $asBox.SelectedIndex = -1; $styleBox.SelectedIndex = -1 }
        else {
            $edLab.Text = if ($sel.Count -eq 1) { "Selected: $($sel[0].Row.Text)" } else { "Selected: $($sel.Count) mods" }
            # soovitused esimese valitud modi järgi
            $sug = & $suggest $sel[0]; $sc = @{}; foreach ($x in $sug) { $sc[$x.Id] = $x.Score }
            & $fillAs @($sug | ForEach-Object { $_.Id }) $sc
            $pars = @($sel | ForEach-Object { "$($_.Parent)" } | Select-Object -Unique)
            if ($pars.Count -eq 1) {
                $i = if ($pars[0]) { 1 + [array]::IndexOf(@($st.Order), $pars[0]) } else { 0 }
                $asBox.SelectedIndex = $i
                if ($pars[0]) { $styleBox.Enabled = $true; $styleBox.SelectedIndex = $(if ($sel[0].Style -eq 'badge') { 1 } else { 0 }) } else { $styleBox.SelectedIndex = -1 }
            } else { $asBox.SelectedIndex = -1 }
        }
        $st.Filling = $false
    }
    $lv.Add_SelectedIndexChanged($showSel)
    $asBox.Add_SelectedIndexChanged({
        if ($st.Filling -or $asBox.SelectedIndex -lt 0) { return }
        $parId = if ($asBox.SelectedIndex -eq 0) { $null } else { $st.Order[$asBox.SelectedIndex - 1] }
        foreach ($row in @($lv.SelectedItems)) {
            if ($parId -and $row.Tag.Key -eq $parId) { continue }
            $row.Tag.Parent = $parId; if ($parId) { $c0 = & $parCat $parId; if ($c0) { $row.Tag.Cat = $c0; $row.SubItems[2].Text = $c0 } }
            # sellest saab alt -> tema enda altid lähevad tema ema alla
            if ($parId) { foreach ($o in $st.Items) { if ($o.Parent -eq $row.Tag.Key) { $o.Parent = $parId } } }
        }
        & $refresh; & $showSel
    })
    $styleBox.Add_SelectedIndexChanged({
        if ($st.Filling -or $styleBox.SelectedIndex -lt 0) { return }
        foreach ($row in @($lv.SelectedItems)) { $row.Tag.Style = @('chip', 'badge')[$styleBox.SelectedIndex] }
        & $refresh
    })

    $destText['alt:chip'] = '+  Alt / add-on for…'; $destText['alt:badge'] = 'n  Alt for…'
    $altMenu = New-Object Windows.Forms.ContextMenuStrip
    $altMenu.ShowImageMargin = $false; $altMenu.BackColor = $G::Raised; $altMenu.ForeColor = $G::Text; $altMenu.Font = $FontUi; $altMenu.MaximumSize = New-Object Drawing.Size(520, 600)
    $askParent = {
        param($style, $where)
        $sel = @($lv.SelectedItems | ForEach-Object { $_.Tag }); if (-not $sel.Count) { return }
        $altMenu.Items.Clear()
        $sug = & $suggest $sel[0]
        $hdrItem = $altMenu.Items.Add("$(if ($style -eq 'badge') { '"n" alt' } else { '+ alt / add-on' }) of which mod?  (best matches first)"); $hdrItem.Enabled = $false
        $i = 0
        foreach ($x in $sug) {
            $mi = $altMenu.Items.Add((& $parLabel $x.Id $x.Score))
            $mi.Tag = @{ Parent = $x.Id; Style = $style }
            $mi.Add_Click({
                foreach ($row in @($lv.SelectedItems)) {
                    if ($row.Tag.Key -eq $this.Tag.Parent) { continue }
                    $row.Tag.Parent = $this.Tag.Parent; $row.Tag.Style = $this.Tag.Style
                    $c0 = & $parCat $this.Tag.Parent; if ($c0) { $row.Tag.Cat = $c0; $row.SubItems[2].Text = $c0 }
                    if ($row.Tag.Dest -eq 'Skip') { $row.Tag.Dest = 'New' }
                    foreach ($o in $st.Items) { if ($o.Parent -eq $row.Tag.Key) { $o.Parent = $this.Tag.Parent } }
                }
                & $refresh; & $showSel
            })
            $i++; if ($i -ge 25) { break }
        }
        $altMenu.Show($where)
    }
    $zoneKeys = @($(if ($Portable) { @('alt:chip') } else { @('alt:chip', 'alt:badge') })) + $dests
    # Sihtkast: klõps = vali märgitud modidele see koht; lohistamine = sama (alt-kastid küsivad, kelle altiks)
    foreach ($k in $zoneKeys) {
        $z = New-Object Windows.Forms.Panel
        $z.Size = New-Object Drawing.Size(206, 54); $z.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 8)
        $z.Tag = $k; $z.AllowDrop = $true; $z.Cursor = 'Hand'; $z.AccessibleDescription = ''
        $G::DoubleBuffer($z)
        $z.Add_Paint({
            $gfx = $_.Graphics; $gfx.SmoothingMode = 'AntiAlias'
            $k = $this.Tag
            $n = if ($k -like 'alt:*') { @($st.Items | Where-Object { $_.Parent -and $_.Dest -ne 'Skip' -and $_.Style -eq $k.Substring(4) -and $_.State -ne 'error' }).Count }
                 else { @($st.Items | Where-Object { $_.Dest -eq $k -and ($k -eq 'Skip' -or -not $_.Parent) -and $_.State -ne 'error' }).Count }
            $hot = $this.AccessibleDescription -eq 'hot'
            $col = switch -Wildcard ($k) { 'alt:*' { [DlUi.G]::Hex('#C79A2E') } 'Other' { [DlUi.G]::Hex('#D9772B') } 'These' { [DlUi.G]::Hex('#3F86C9') } 'New' { [DlUi.G]::Hex('#6FA531') } 'Skip' { [DlUi.G]::Hex('#8C7D61') } default { [DlUi.G]::Hex('#8A63BF') } }
            $r = New-Object Drawing.RectangleF(1, 1, ($this.Width - 3), ($this.Height - 3))
            $path = [DlUi.G]::Round($r, 9)
            $fill = if ($hot) { [DlUi.G]::Mix([DlUi.G]::Panel, $col, 0.3) } else { [DlUi.G]::Panel }
            $b = New-Object Drawing.SolidBrush($fill); $gfx.FillPath($b, $path); $b.Dispose()
            $sb = New-Object Drawing.SolidBrush($col); $gfx.FillEllipse($sb, 12, 18, 14, 14); $sb.Dispose()
            $pen = New-Object Drawing.Pen($(if ($hot) { $col } else { [DlUi.G]::Line }), $(if ($hot) { 2 } else { 1 })); $gfx.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
            [Windows.Forms.TextRenderer]::DrawText($gfx, $destText[$k], $FontChip, (New-Object Drawing.Rectangle(34, 8, ($this.Width - 42), 20)), [DlUi.G]::Bright, [Windows.Forms.TextFormatFlags]'Left, EndEllipsis, NoPrefix')
            [Windows.Forms.TextRenderer]::DrawText($gfx, "$n mod" + $(if ($n -ne 1) { 's' } else { '' }), $FontUi, (New-Object Drawing.Rectangle(34, 28, ($this.Width - 42), 18)), [DlUi.G]::Muted, [Windows.Forms.TextFormatFlags]'Left, NoPrefix')
        })
        $z.Add_DragEnter({ if ($_.Data.GetDataPresent('DlMassAdd')) { $_.Effect = 'Move'; $this.AccessibleDescription = 'hot'; $this.Invalidate() } })
        $z.Add_DragLeave({ $this.AccessibleDescription = ''; $this.Invalidate() })
        $z.Add_DragDrop({
            $this.AccessibleDescription = ''; $this.Invalidate()
            if ($this.Tag -like 'alt:*') { & $askParent $this.Tag.Substring(4) ([Windows.Forms.Cursor]::Position); return }
            foreach ($row in @($lv.SelectedItems)) { & $setDest $row.Tag $this.Tag }
            & $refresh; & $showSel
        })
        $z.Add_Click({
            if (-not $lv.SelectedItems.Count) { return }
            if ($this.Tag -like 'alt:*') { & $askParent $this.Tag.Substring(4) ([Windows.Forms.Cursor]::Position); return }
            foreach ($row in @($lv.SelectedItems)) { & $setDest $row.Tag $this.Tag }; & $refresh; & $showSel
        })
        $zones.Controls.Add($z)
        $st.Zones += $z
    }

    # lohistades on kursori juures silt (mis ja mitu), et oleks näha, et midagi on "käes"
    $makeDragCursor = {
        param($text)
        $f = $FontChip; $sz = [Windows.Forms.TextRenderer]::MeasureText($text, $f)
        $w = $sz.Width + 34; $h = 30
        $bmp = New-Object Drawing.Bitmap ($w + 2), ($h + 22)
        $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
        # nool
        $arrow = [Drawing.Point[]]@((New-Object Drawing.Point 1, 1), (New-Object Drawing.Point 1, 17), (New-Object Drawing.Point 5, 13), (New-Object Drawing.Point 8, 20), (New-Object Drawing.Point 10, 19), (New-Object Drawing.Point 7, 12), (New-Object Drawing.Point 12, 12))
        $g.FillPolygon([Drawing.Brushes]::White, $arrow); $g.DrawPolygon([Drawing.Pens]::Black, $arrow)
        $r = New-Object Drawing.RectangleF(2, 21, ($w - 2), ($h - 1)); $path = [DlUi.G]::Round($r, 10)
        $b = New-Object Drawing.SolidBrush([DlUi.G]::Brand); $g.FillPath($b, $path); $b.Dispose()
        $pen = New-Object Drawing.Pen([DlUi.G]::Mix([DlUi.G]::Brand, [Drawing.Color]::Black, 0.4), 1); $g.DrawPath($pen, $path); $pen.Dispose()
        [Windows.Forms.TextRenderer]::DrawText($g, $text, $f, (New-Object Drawing.Rectangle 2, 21, $w, $h), [DlUi.G]::Ink, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, NoPrefix')
        $g.Dispose()
        $c = New-Object Windows.Forms.Cursor($bmp.GetHicon()); $bmp.Dispose()
        return $c
    }
    $lv.Add_ItemDrag({
        if (-not $lv.SelectedItems.Count) { return }
        $n = $lv.SelectedItems.Count
        $st.DragCursor = & $makeDragCursor $(if ($n -eq 1) { "↪  $($lv.SelectedItems[0].Text)" } else { "↪  $n mods" })
        [void]$lv.DoDragDrop((New-Object Windows.Forms.DataObject('DlMassAdd', 'x')), 'Move')
        $st.DragCursor = $null
    })
    $lv.Add_GiveFeedback({ if ($st.DragCursor) { $_.UseDefaultCursors = $false; [Windows.Forms.Cursor]::Current = $st.DragCursor } })
    $lv.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
    $lv.Add_DragDrop({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { & $addFiles @($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) } })
    $lv.Add_AfterLabelEdit({ if ($null -ne $_.Label -and -not $_.Label.Trim()) { $_.CancelEdit = $true } })
    $lv.Add_KeyDown({ if ($_.KeyCode -eq 'F2' -and $lv.SelectedItems.Count -eq 1) { $lv.SelectedItems[0].BeginEdit() } })

    # Paremklõps: koht, kategooria, nimekirjast eemaldamine
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false; $menu.BackColor = $G::Raised; $menu.ForeColor = $G::Text; $menu.Font = $FontUi
    $mGo = New-Object Windows.Forms.ToolStripMenuItem 'Goes to'
    foreach ($k in $dests) { $mi = $mGo.DropDownItems.Add($destText[$k]); $mi.Tag = $k; $mi.Add_Click({ foreach ($row in @($lv.SelectedItems)) { & $setDest $row.Tag $this.Tag }; & $refresh; & $showSel }) }
    $mCat = New-Object Windows.Forms.ToolStripMenuItem 'Category'
    foreach ($c in $cats) { $mi = $mCat.DropDownItems.Add($c); $mi.Tag = $c; $mi.Add_Click({ foreach ($row in @($lv.SelectedItems)) { $row.Tag.Cat = $this.Tag; $row.SubItems[2].Text = $this.Tag } }) }
    foreach ($mm in @($mGo, $mCat)) { $mm.DropDown.BackColor = $G::Raised; $mm.DropDown.ForeColor = $G::Text; [void]$menu.Items.Add($mm) }
    $mRen = $menu.Items.Add('Rename (F2)'); $mRen.Add_Click({ if ($lv.SelectedItems.Count) { $lv.SelectedItems[0].BeginEdit() } })
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $mDel = $menu.Items.Add('Remove from list')
    $mDel.Add_Click({
        foreach ($row in @($lv.SelectedItems)) {
            $it = $row.Tag
            if ($it.State -eq 'checking') { $it.Dest = 'Skip'; $it.Parent = $null; continue }   # käib veel: lihtsalt jäta välja
            Clear-PreparedMod $it.Prep; $st.Items.Remove($it); $lv.Items.Remove($row)
            foreach ($o in $st.Items) { if ($o.Parent -eq $it.Key) { $o.Parent = $null } }   # tema altid jäävad eraldi modideks
        }
        & $refresh; & $showSel
    })
    $menu.Add_Opening({ if (-not $lv.SelectedItems.Count) { $_.Cancel = $true } })
    $lv.ContextMenuStrip = $menu

    # Taustakontroll: üks fail korraga (Run hoiab akna samal ajal elus)
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 60
    $timer.Add_Tick({
        if ($st.Busy -or $st.Closing) { return }
        $it = @($st.Items | Where-Object { $_.State -eq 'wait' })[0]
        if (-not $it) { return }
        $st.Busy = $true
        $it.State = 'checking'; $it.Row.SubItems[4].Text = 'Checking…'; & $refresh
        $row = $it.Row
        try {
            $it.Prep = Initialize-ModFile $it.File { param($t) if (-not $st.Closing) { $row.SubItems[4].Text = $t } }
            $p = $it.Prep
            $row.Text = $p.Nice
            $row.SubItems[1].Text = $(if ($p.Hero) { $p.Hero.Display } else { '—' })
            if (-not $it.Parent) { $it.Cat = if ($p.Hero) { 'Skins' } else { 'Visuals' } }
            $row.SubItems[2].Text = $it.Cat
            $s = if ($p.Old) { 'Ready · old camera (no fix)' } elseif ($p.CamFixed) { 'Ready · camera fixed' } else { '✓ Ready' }
            if (@($p.Log | Where-Object { $_ -like 'Outdated copy, removed*' }).Count) { $s += ' · old shared files removed' }
            $row.SubItems[4].Text = $s
            $row.ToolTipText = (($p.Log | ForEach-Object { "• $_" }) -join "`n")
            $it.State = 'ready'
        } catch {
            $it.State = 'error'; $row.SubItems[4].Text = "Failed: $($_.Exception.Message)"; $row.ForeColor = [DlUi.G]::Fg('#8E2A20')
            $row.ToolTipText = $_.Exception.Message
        }
        $st.Busy = $false
        if (-not $st.Closing) { & $refresh; if (-not @($st.Items | Where-Object { $_.State -in 'wait', 'checking' }).Count) { [DlUi.Notify]::Done($form, [bool]@($st.Items | Where-Object { $_.State -eq 'error' }).Count) } }
    })
    $d.Add_FormClosing({ $st.Closing = $true; $timer.Stop() })
    $d.Add_Shown({ $timer.Start() })
    $d.Controls.AddRange(@($ban, $lv, $ed, $zl, $zones, $cnt, $ok, $no))
    & $addFiles $files

    $res = $d.ShowDialog($form)
    $timer.Dispose()

    $done = @(); $failed = @()
    try {
        if ($res -eq 'OK') {
            $form.Cursor = 'WaitCursor'
            # kõigepealt emad, siis nimekirjas oleva ema altid (ema uue id-ga)
            $made = @{}
            $first = @($st.Items | Where-Object { "$($_.Parent)" -notlike '@*' }); $later = @($st.Items | Where-Object { "$($_.Parent)" -like '@*' })
            foreach ($it in @($first + $later)) {
                if ($it.State -ne 'ready' -or $it.Dest -eq 'Skip') { continue }
                $p = $it.Prep
                Set-Busy "Adding: $($it.Row.Text)"
                $par = $it.Parent
                if ("$par" -like '@*') { $par = $made[$par] }   # ema jäi lisamata -> lisatakse eraldi modina
                $hk = $null; $hn = $null; if ($p.Hero -and -not $par) { $hk = $p.Hero.Key; $hn = $p.Hero.Display }
                $sty = if ($par) { $(if ($Portable) { 'chip' } else { $it.Style }) } else { $null }
                $ans = @{ Name = $it.Row.Text.Trim(); Cat = $it.Cat; HeroKey = $hk; HeroName = $hn; Parent = $par; AltStyle = $sty; Where = $it.Dest }
                if (-not $ans.Cat) { $ans.Cat = if ($p.Hero) { 'Skins' } else { 'Visuals' } }
                try { $r = Install-PreparedMod $p $ans; $done += $r.Name; $it.Prep = $null; $made[$it.Key] = $r.Id }
                catch { $failed += "$($ans.Name): $($_.Exception.Message)" }
            }
        }
    } finally {
        # kõik, mis jäi lisamata (Skip, viga, Cancel): ajutised failid ja lahtipakitud kaustad ära
        foreach ($it in $st.Items) { if ($it.Prep) { Clear-PreparedMod $it.Prep } }
        $d.Dispose()
        $form.Cursor = 'Default'
        $script:AddBusy = $false; $addBtn.Enabled = $true
    }
    if ($done.Count) {
        Build-Tabs
        $tabName = @($st.Items | Where-Object { $_.State -eq 'ready' -and -not $_.Parent -and $_.Dest -ne 'Skip' } | ForEach-Object { $_.Dest })[0]
        if ($tabName -like 'tab:*') { Show-TabByTitle $tabName.Substring(4) }
        elseif ($tabName) { $tt = if ($Portable -and $tabName -eq 'New') { 'All mods' } else { $tabName }; for ($j = 0; $j -lt $TabBtns.Count; $j++) { if ($TabBtns[$j].Title -like "$tt*") { Show-Tab $j $false; break } } }
        $note.Text = "✓  Added $($done.Count) mod" + $(if ($done.Count -ne 1) { 's' } else { '' }) + ' (off)'; $note.ForeColor = $G::Hex('#89D185')
    } else { Update-Boxes }
    if ($failed.Count) {
        [Windows.Forms.MessageBox]::Show($form, "These could not be added:`n`n" + ($failed -join "`n"), 'Add several mods') | Out-Null
    }
}
