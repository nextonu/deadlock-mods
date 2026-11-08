# Mass add: mitu modi korraga. Vali mitu faili ("+ Add mod") või lohista mitu faili aknale.
# Failid kontrollitakse taustal ükshaaval (lahtipakkimine, kangelane, jagatud failid, kaamera).
# Nimekirjast lohistatakse modid paremal olevatesse kastidesse (New / Other / These / oma vahelehed / Skip).
# "Add all" paigaldab kõik korraga ja ehitab vahelehed üks kord ümber.
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1-te ja menuu.ps1-te.

function Show-MassAdd($files) {
    if ($script:AddBusy) { return }
    $script:AddBusy = $true; $addBtn.Enabled = $false
    # Olek ühes hashtable'is: sündmuste skriptiplokid muudavad seda (muutuja omistamine teeks koopia)
    $st = @{ Items = (New-Object Collections.ArrayList); Busy = $false; Closing = $false; Zones = @() }
    $cats = @('Skins', 'Map', 'Visuals', 'Sounds & music', 'Utility (recommended)')
    $dests = @('New') + $(if ($Portable) { @() } else { @('Other', 'These') }) + @($CustomTabs.Keys | ForEach-Object { "tab:$_" }) + @('Skip')
    $destText = @{ New = $(if ($Portable) { 'All mods' } else { 'New (choose later)' }); Other = 'Other'; These = 'These'; Skip = 'Skip (don''t add)' }
    foreach ($t in $CustomTabs.Keys) { $destText["tab:$t"] = "Tab: $t" }

    $d = New-Object Windows.Forms.Form
    $d.Text = 'Mass add mods'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.MinimizeBox = $false; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(980, 620); $d.MinimumSize = New-Object Drawing.Size(760, 460)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })

    $lab = New-Object Windows.Forms.Label
    $lab.Text = 'Select mods (Ctrl/Shift for several) and drag them into a box on the right. F2 renames. Drop more files here to add them.'
    $lab.AutoSize = $false; $lab.Size = New-Object Drawing.Size(940, 22); $lab.Anchor = 'Top, Left, Right'
    $lab.ForeColor = $DlgMuted; $lab.Location = New-Object Drawing.Point(16, 12)

    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $true; $lv.HideSelection = $false; $lv.LabelEdit = $true
    $lv.Location = New-Object Drawing.Point(16, 40); $lv.Size = New-Object Drawing.Size(700, 510); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    $lv.AllowDrop = $true
    foreach ($c in @(@('Name', 250), @('Hero', 100), @('Category', 110), @('Status', 220))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $groups = @{}
    foreach ($k in $dests) { $grp = New-Object Windows.Forms.ListViewGroup($k, $destText[$k]); [void]$lv.Groups.Add($grp); $groups[$k] = $grp }

    # Paremal: sihtkastid
    $zl = New-Object Windows.Forms.Label
    $zl.Text = 'Drag here:'; $zl.AutoSize = $true; $zl.ForeColor = $DlgMuted; $zl.Anchor = 'Top, Right'
    $zl.Location = New-Object Drawing.Point(732, 40)
    $zones = New-Object Windows.Forms.FlowLayoutPanel
    $zones.FlowDirection = 'TopDown'; $zones.WrapContents = $false; $zones.AutoScroll = $true
    $zones.Location = New-Object Drawing.Point(732, 64); $zones.Size = New-Object Drawing.Size(232, 486); $zones.Anchor = 'Top, Bottom, Right'
    $zones.BackColor = $DlgBg

    $cnt = New-Object Windows.Forms.Label
    $cnt.AutoSize = $true; $cnt.ForeColor = $DlgMuted; $cnt.Anchor = 'Bottom, Left'
    $cnt.Location = New-Object Drawing.Point(16, 572)
    $ok = New-Pill 'Add all' $true; $ok.FitWidth(26, 36); $ok.Anchor = 'Bottom, Right'
    $ok.Location = New-Object Drawing.Point((964 - $ok.Width), 566); $ok.Enabled = $false
    $no = New-Pill 'Cancel' $false; $no.FitWidth(18, 36); $no.Anchor = 'Bottom, Right'
    $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 566)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })

    # --- abifunktsioonid (skriptiplokid, et sündmused neid näeksid) ---
    $refresh = {
        $ready = 0; $wait = 0; $bad = 0; $add = 0
        foreach ($it in $st.Items) {
            switch ($it.State) { 'ready' { $ready++; if ($it.Dest -ne 'Skip') { $add++ } } 'error' { $bad++ } default { $wait++ } }
        }
        $txt = "$($st.Items.Count) files:  $ready ready"
        if ($wait) { $txt += ",  $wait checking…" }
        if ($bad) { $txt += ",  $bad failed" }
        $cnt.Text = $txt
        $ok.Text = "Add $add mod" + $(if ($add -ne 1) { 's' } else { '' }); $ok.FitWidth(26, 36)
        $ok.Left = $d.ClientSize.Width - 16 - $ok.Width; $no.Left = $ok.Left - $no.Width - 10
        $ok.Enabled = (-not $wait -and $add -gt 0)
        foreach ($z in $st.Zones) { $z.Invalidate() }
    }
    $setDest = {
        param($it, $dest)
        $it.Dest = $dest; $it.Row.Group = $groups[$dest]
    }
    $addFiles = {
        param($list)
        foreach ($f in $list) {
            if (-not $f -or @($st.Items | Where-Object { $_.File -eq $f }).Count) { continue }
            $row = New-Object Windows.Forms.ListViewItem([IO.Path]::GetFileNameWithoutExtension($f))
            [void]$row.SubItems.Add('…'); [void]$row.SubItems.Add('…'); [void]$row.SubItems.Add('Waiting')
            $it = @{ File = $f; Row = $row; Prep = $null; State = 'wait'; Dest = 'New'; Cat = $null }
            $row.Tag = $it
            $row.Group = $groups['New']
            [void]$lv.Items.Add($row)
            [void]$st.Items.Add($it)
        }
        & $refresh
    }

    # Sihtkast: klõps = vali märgitud modidele see koht; lohistamine = sama
    foreach ($k in $dests) {
        $z = New-Object Windows.Forms.Panel
        $z.Size = New-Object Drawing.Size(206, 54); $z.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 8)
        $z.Tag = $k; $z.AllowDrop = $true; $z.Cursor = 'Hand'; $z.AccessibleDescription = ''
        $G::DoubleBuffer($z)
        $z.Add_Paint({
            $gfx = $_.Graphics; $gfx.SmoothingMode = 'AntiAlias'
            $k = $this.Tag
            $n = @($st.Items | Where-Object { $_.Dest -eq $k -and $_.State -ne 'error' }).Count
            $hot = $this.AccessibleDescription -eq 'hot'
            $col = switch -Wildcard ($k) { 'Other' { [DlUi.G]::Hex('#D9772B') } 'These' { [DlUi.G]::Hex('#3F86C9') } 'New' { [DlUi.G]::Hex('#6FA531') } 'Skip' { [DlUi.G]::Hex('#8C7D61') } default { [DlUi.G]::Hex('#8A63BF') } }
            $r = New-Object Drawing.RectangleF(1, 1, ($this.Width - 3), ($this.Height - 3))
            $path = [DlUi.G]::Round($r, 7)
            $fill = if ($hot) { [DlUi.G]::Mix($col, [DlUi.G]::Panel, 0.35) } else { [DlUi.G]::Panel }
            $b = New-Object Drawing.SolidBrush($fill); $gfx.FillPath($b, $path); $b.Dispose()
            $sb = New-Object Drawing.SolidBrush($col); $gfx.FillRectangle($sb, 1, 8, 5, ($this.Height - 17)); $sb.Dispose()
            $pen = New-Object Drawing.Pen($(if ($hot) { $col } else { [DlUi.G]::Line }), $(if ($hot) { 2 } else { 1 })); $gfx.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
            $tc = if ($hot) { [DlUi.G]::Bright } else { [DlUi.G]::Text }
            [Windows.Forms.TextRenderer]::DrawText($gfx, $destText[$k], $FontChip, (New-Object Drawing.Rectangle(16, 8, ($this.Width - 24), 20)), $tc, [Windows.Forms.TextFormatFlags]'Left, EndEllipsis, NoPrefix')
            [Windows.Forms.TextRenderer]::DrawText($gfx, "$n mod" + $(if ($n -ne 1) { 's' } else { '' }), $FontUi, (New-Object Drawing.Rectangle(16, 28, ($this.Width - 24), 18)), [DlUi.G]::Muted, [Windows.Forms.TextFormatFlags]'Left, NoPrefix')
        })
        $z.Add_DragEnter({ if ($_.Data.GetDataPresent('DlMassAdd')) { $_.Effect = 'Move'; $this.AccessibleDescription = 'hot'; $this.Invalidate() } })
        $z.Add_DragLeave({ $this.AccessibleDescription = ''; $this.Invalidate() })
        $z.Add_DragDrop({
            $this.AccessibleDescription = ''
            foreach ($row in @($lv.SelectedItems)) { & $setDest $row.Tag $this.Tag }
            & $refresh
        })
        $z.Add_Click({ if ($lv.SelectedItems.Count) { foreach ($row in @($lv.SelectedItems)) { & $setDest $row.Tag $this.Tag }; & $refresh } })
        $zones.Controls.Add($z)
        $st.Zones += $z
    }

    $lv.Add_ItemDrag({ if ($lv.SelectedItems.Count) { [void]$lv.DoDragDrop((New-Object Windows.Forms.DataObject('DlMassAdd', 'x')), 'Move') } })
    $lv.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
    $lv.Add_DragDrop({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { & $addFiles @($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) } })
    $lv.Add_AfterLabelEdit({ if ($null -ne $_.Label -and -not $_.Label.Trim()) { $_.CancelEdit = $true } })
    $lv.Add_KeyDown({ if ($_.KeyCode -eq 'F2' -and $lv.SelectedItems.Count -eq 1) { $lv.SelectedItems[0].BeginEdit() } })

    # Paremklõps: koht, kategooria, nimekirjast eemaldamine
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false; $menu.BackColor = $G::Raised; $menu.ForeColor = $G::Text; $menu.Font = $FontUi
    $mGo = New-Object Windows.Forms.ToolStripMenuItem 'Goes to'
    foreach ($k in $dests) { $mi = $mGo.DropDownItems.Add($destText[$k]); $mi.Tag = $k; $mi.Add_Click({ foreach ($row in @($lv.SelectedItems)) { & $setDest $row.Tag $this.Tag }; & $refresh }) }
    $mCat = New-Object Windows.Forms.ToolStripMenuItem 'Category'
    foreach ($c in $cats) { $mi = $mCat.DropDownItems.Add($c); $mi.Tag = $c; $mi.Add_Click({ foreach ($row in @($lv.SelectedItems)) { $row.Tag.Cat = $this.Tag; $row.SubItems[2].Text = $this.Tag } }) }
    foreach ($mm in @($mGo, $mCat)) { $mm.DropDown.BackColor = $G::Raised; $mm.DropDown.ForeColor = $G::Text; [void]$menu.Items.Add($mm) }
    $mRen = $menu.Items.Add('Rename (F2)'); $mRen.Add_Click({ if ($lv.SelectedItems.Count) { $lv.SelectedItems[0].BeginEdit() } })
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $mDel = $menu.Items.Add('Remove from list')
    $mDel.Add_Click({
        foreach ($row in @($lv.SelectedItems)) {
            $it = $row.Tag
            if ($it.State -eq 'checking') { $it.Dest = 'Skip'; $row.Group = $groups['Skip']; continue }   # käib veel: lihtsalt jäta välja
            Clear-PreparedMod $it.Prep; $st.Items.Remove($it); $lv.Items.Remove($row)
        }
        & $refresh
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
        $it.State = 'checking'; $it.Row.SubItems[3].Text = 'Checking…'; & $refresh
        $row = $it.Row
        try {
            $it.Prep = Initialize-ModFile $it.File { param($t) if (-not $st.Closing) { $row.SubItems[3].Text = $t } }
            $p = $it.Prep
            $row.Text = $p.Nice
            $row.SubItems[1].Text = $(if ($p.Hero) { $p.Hero.Display } else { '—' })
            $it.Cat = if ($p.Hero) { 'Skins' } else { 'Visuals' }
            $row.SubItems[2].Text = $it.Cat
            $s = if ($p.Old) { 'Ready · old camera (no fix)' } elseif ($p.CamFixed) { 'Ready · camera fixed' } else { 'Ready' }
            if (@($p.Log | Where-Object { $_ -like 'Outdated copy, removed*' }).Count) { $s += ' · old shared files removed' }
            $row.SubItems[3].Text = $s
            $row.ToolTipText = (($p.Log | ForEach-Object { "• $_" }) -join "`n")
            $it.State = 'ready'
        } catch {
            $it.State = 'error'; $row.SubItems[3].Text = "Failed: $($_.Exception.Message)"; $row.ForeColor = [DlUi.G]::Hex('#C0392B')
            $row.ToolTipText = $_.Exception.Message
        }
        $st.Busy = $false
        if (-not $st.Closing) { & $refresh }
    })
    $lv.ShowItemToolTips = $true
    $d.Add_FormClosing({ $st.Closing = $true; $timer.Stop() })
    $d.Add_Shown({ $timer.Start() })
    $d.Controls.AddRange(@($lab, $lv, $zl, $zones, $cnt, $ok, $no))
    & $addFiles $files

    $res = $d.ShowDialog($form)
    $timer.Dispose()

    $done = @(); $failed = @()
    try {
        if ($res -eq 'OK') {
            $form.Cursor = 'WaitCursor'
            foreach ($it in @($st.Items)) {
                if ($it.State -ne 'ready' -or $it.Dest -eq 'Skip') { continue }
                $p = $it.Prep
                Set-Busy "Adding: $($it.Row.Text)"
                $hk = $null; $hn = $null; if ($p.Hero) { $hk = $p.Hero.Key; $hn = $p.Hero.Display }
                $ans = @{ Name = $it.Row.Text.Trim(); Cat = $it.Cat; HeroKey = $hk; HeroName = $hn; Parent = $null; AltStyle = $null; Where = $it.Dest }
                try { $r = Install-PreparedMod $p $ans; $done += $r.Name; $it.Prep = $null }
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
        $tabName = @($st.Items | Where-Object { $_.State -eq 'ready' -and $_.Dest -ne 'Skip' } | ForEach-Object { $_.Dest })[0]
        if ($tabName -like 'tab:*') { Show-TabByTitle $tabName.Substring(4) }
        else { for ($j = 0; $j -lt $TabBtns.Count; $j++) { if ($TabBtns[$j].Title -like "$tabName*") { Show-Tab $j $false; break } } }
        $note.Text = "✓  Added $($done.Count) mod" + $(if ($done.Count -ne 1) { 's' } else { '' }) + ' (off)'; $note.ForeColor = $G::Hex('#89D185')
    } else { Update-Boxes }
    if ($failed.Count) {
        [Windows.Forms.MessageBox]::Show($form, "These could not be added:`n`n" + ($failed -join "`n"), 'Mass add') | Out-Null
    }
}
