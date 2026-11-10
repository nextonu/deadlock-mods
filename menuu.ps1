# Paremklõpsu menüü modi nupul / kaardil: Nimeta ümber, Taasta algne nimi, Kustuta.
# Nimi muutub ainult lülitis (nimed.json), modi failid jäävad samaks.
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast kustutamine.ps1-te.

$ModMenu = New-Object Windows.Forms.ContextMenuStrip
$ModMenu.ShowImageMargin = $false
$ModMenu.BackColor = $G::Raised; $ModMenu.ForeColor = $G::Text
$ModMenu.Font = $FontUi
$miFav = $ModMenu.Items.Add('★  Favorite')
[void]$ModMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$miRename = $ModMenu.Items.Add('Rename…')
$miReset = New-Object Windows.Forms.ToolStripMenuItem 'Restore original name'   # menüüs pole (Rename algse nimega teeb sama)
$miParts = $ModMenu.Items.Add('Parts (voice lines, portraits…)…')
[void]$ModMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
# Oma vahelehed: lisa / eemalda (mod jääb alati ka "Kõik modid" alla)
$miToTab = New-Object Windows.Forms.ToolStripMenuItem 'Add to tab'
$miToTab.DropDown.BackColor = $G::Raised; $miToTab.DropDown.ForeColor = $G::Text
[void]$ModMenu.Items.Add($miToTab)
$miFromTab = $ModMenu.Items.Add('Remove from this tab')
[void]$ModMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$miDelete = $ModMenu.Items.Add('Delete…')
$miDelete.ForeColor = $G::Hex('#F48771')
$MenuId = $null

# Milline mod on menüü all: nupp (Tag = id) või ühe modiga kaart (kaardi Tag = tema nupp)
function Get-MenuModId($src) {
    $c = $src
    while ($c) {
        if ($c -is [DlUi.Chip]) { return $c.Tag }
        if ($c -is [DlUi.Card]) { if ($c.Tag -is [DlUi.Chip]) { return $c.Tag.Tag } else { return $null } }
        $c = $c.Parent
    }
    return $null
}

$ModMenu.Add_Opening({
    $script:MenuId = Get-MenuModId $ModMenu.SourceControl
    # paremklõps "n" märgil -> menüü (ja pilt) on selle "n" versiooni jaoks
    $sc = $ModMenu.SourceControl; $ch = $null
    while ($sc) { if ($sc -is [DlUi.Chip]) { $ch = $sc; break }; if ($sc -is [DlUi.Card]) { if ($sc.Tag -is [DlUi.Chip]) { $ch = $sc.Tag }; break }; $sc = $sc.Parent }
    if ($ch -and $ch.AltBadge -and $ch.AccessibleDescription -and $ch.IsOnBadge($ch.PointToClient([Windows.Forms.Cursor]::Position))) { $script:MenuId = $ch.AccessibleDescription }
    if (-not $script:MenuId -or -not $ById[$script:MenuId]) { $_.Cancel = $true; return }
    $m = $ById[$script:MenuId]
    $orig = if ($m.OrigName) { $m.OrigName } else { $m.Name }
    $miReset.Enabled = ($m.Name -ne $orig)
    $miFav.Text = if ($Favorites -contains $script:MenuId) { '★  Remove favorite' } else { '★  Favorite (picked by "Turn all on")' }
    # "Lisa vahelehele" alammenüü: kõik oma vahelehed + uus
    $miToTab.DropDownItems.Clear()
    foreach ($name in @($CustomTabs.Keys)) {
        $it = $miToTab.DropDownItems.Add($name)
        $it.Tag = $name
        if ($CustomTabs[$name] -contains $script:MenuId) { $it.Enabled = $false; $it.Text = "$name  ✓" }
        $it.Add_Click({ Add-ToCustomTab $this.Tag $script:MenuId })
    }
    if ($CustomTabs.Count) { [void]$miToTab.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator)) }
    $nw = $miToTab.DropDownItems.Add('New tab…')
    $nw.Add_Click({ $n = New-CustomTab $false; if ($n) { Add-ToCustomTab $n $script:MenuId } })
    # "Eemalda" ainult siis, kui oled oma vahelehel ja mod on seal
    $cur = $TabBtns[$CurTab]
    $miFromTab.Visible = [bool]($cur.Custom -and ($CustomTabs[$cur.Title] -contains $script:MenuId))
    if ($miFromTab.Visible) { $miFromTab.Text = "Remove from tab '$($cur.Title)'" }
})

function Save-NameOverride($id, $name) {
    $h = Get-NameOverrides
    if ($null -eq $name) { $h.Remove($id) } else { $h[$id] = $name }
    $o = [ordered]@{}; foreach ($k in ($h.Keys | Sort-Object)) { $o[$k] = $h[$k] }
    [IO.File]::WriteAllText($NamesFile, (ConvertTo-Json $o), (New-Object Text.UTF8Encoding $false))
}

function Show-RenameDialog($current, $caption = 'Rename', $prompt = 'New name (only changes here, files stay the same)') {
    $d = New-Object Windows.Forms.Form
    $d.Text = $caption; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; Enable-DialogMinimize $d
    $d.StartPosition = 'CenterParent'; $d.ClientSize = New-Object Drawing.Size(440, 150)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $lab = New-Object Windows.Forms.Label
    $lab.Text = $prompt; $lab.AutoSize = $true; $lab.ForeColor = $DlgMuted
    $lab.Location = New-Object Drawing.Point(18, 16)
    $tb = New-Object Windows.Forms.TextBox
    $tb.Text = $current; $tb.BackColor = $G::Raised; $tb.ForeColor = $G::Bright; $tb.BorderStyle = 'FixedSingle'
    $tb.Location = New-Object Drawing.Point(18, 42); $tb.Width = 404
    $ok = New-Pill 'Save' $true; $ok.FitWidth(22, 34); $ok.Location = New-Object Drawing.Point((422 - $ok.Width), 98)
    $no = New-Pill 'Cancel' $false; $no.FitWidth(16, 34); $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 98)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $tb.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $d.DialogResult = 'OK'; $d.Close() } elseif ($_.KeyCode -eq 'Escape') { $d.DialogResult = 'Cancel'; $d.Close() } })
    $d.Controls.AddRange(@($lab, $tb, $ok, $no))
    $d.Add_Shown({ $tb.Focus(); $tb.SelectAll() })
    $res = $d.ShowDialog($form)
    $text = $tb.Text.Trim()
    $d.Dispose()
    if ($res -ne 'OK' -or -not $text) { return $null }
    return $text
}

$miRename.Add_Click({
    $id = $script:MenuId; $m = $ById[$id]; if (-not $m) { return }
    $orig = if ($m.OrigName) { $m.OrigName } else { $m.Name }
    $new = Show-RenameDialog (Get-ShortName $m)
    if (-not $new) { return }
    $full = $new -replace ' · ', ' - '
    # kangelane sulgudes jääb alles (selle järgi valitakse kaardi pilt ja pealkiri)
    if ($orig -match '\(([^)]*)\)' -and $full -notmatch '\(') { $full = "$full ($($Matches[1]))" }
    if (-not $m.OrigName) { $m.OrigName = $orig }
    $m.Name = $full
    Save-NameOverride $id $(if ($full -eq $orig) { $null } else { $full })
    Build-Tabs
    $note.Text = "✓  Renamed: $new"; $note.ForeColor = $G::Hex('#89D185')
})

$miReset.Add_Click({
    $id = $script:MenuId; $m = $ById[$id]; if (-not $m -or -not $m.OrigName) { return }
    $m.Name = $m.OrigName
    Save-NameOverride $id $null
    Build-Tabs
})

$miDelete.Add_Click({ if ($script:MenuId) { Remove-ModAsk $script:MenuId } })
$miParts.Add_Click({ if ($script:MenuId) { Show-ModParts $script:MenuId } })

# Lemmik: kangelase reas on lemmikuid üks (uus lemmik asendab sama kangelase eelmise)
$miFav.Add_Click({
    $id = $script:MenuId; $m = $ById[$id]; if (-not $m) { return }
    if ($Favorites -contains $id) { $script:Favorites = @($Favorites | Where-Object { $_ -ne $id }) }
    else {
        $same = if ($m.Hero) { @($Mods | Where-Object { $_.Hero -eq $m.Hero } | ForEach-Object { $_.Id }) } else { @() }
        $script:Favorites = @($Favorites | Where-Object { $same -notcontains $_ }) + $id
    }
    Save-Placement
    Build-Tabs
})

# ---------- Bulk add: vali nimekirjast mitu modi korraga (üks ümberehitus lõpus) ----------
function Show-BulkAdd($tabName) {
    if (-not $CustomTabs.Contains($tabName)) { return }
    $d = New-Object Windows.Forms.Form
    $d.Text = "Add mods to '$tabName'"; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(520, 600); $d.MinimumSize = New-Object Drawing.Size(420, 420)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $lab = New-Object Windows.Forms.Label
    $lab.Text = 'Tick the mods for this tab (untick to remove). They stay in "All mods".'
    $lab.AutoSize = $true; $lab.ForeColor = $DlgMuted; $lab.Location = New-Object Drawing.Point(16, 12)
    $q = New-Object Windows.Forms.TextBox
    $q.Location = New-Object Drawing.Point(16, 38); $q.Width = 488; $q.Anchor = 'Top, Left, Right'
    $q.BackColor = $G::Panel; $q.ForeColor = $G::Bright; $q.BorderStyle = 'FixedSingle'
    $q.Add_HandleCreated({ [void][DlToggle.Native]::SendMessage($this.Handle, 0x1501, [IntPtr]1, 'Search…') })
    $list = New-Object Windows.Forms.CheckedListBox
    $list.Location = New-Object Drawing.Point(16, 70); $list.Size = New-Object Drawing.Size(488, 470); $list.Anchor = 'Top, Bottom, Left, Right'
    $list.CheckOnClick = $true; $list.IntegralHeight = $false; $list.BorderStyle = 'FixedSingle'
    $list.BackColor = $G::Panel; $list.ForeColor = $G::Text; $list.Font = $FontChip
    # kõik modid (altid väljaarvatud), järjestatud: peatükk, kangelane, nimi
    $all = @($Mods | Where-Object { -not $_.Parent } | Sort-Object @{ e = { $c = [array]::IndexOf($CatOrder, $_.Cat); if ($c -lt 0) { 99 } else { $c } } }, @{ e = { "$(Get-HeroName $_)" } }, @{ e = { $_.Name } })
    $label = @{}; foreach ($m in $all) { $h = Get-HeroName $m; $label[$m.Id] = $(if ($h) { "$($h.ToUpper())  ·  $(Get-ShortName $m)" } else { $m.Name }) }
    $checked = @{}; foreach ($id in $CustomTabs[$tabName]) { $checked[$id] = $true }
    $script:BulkShown = @()
    $fill = {
        $list.BeginUpdate(); $list.Items.Clear(); $script:BulkShown = @()
        $f = $q.Text.Trim().ToLower()
        foreach ($m in $all) {
            if ($f -and -not ($label[$m.Id].ToLower().Contains($f) -or $m.Cat.ToLower().Contains($f))) { continue }
            $i = $list.Items.Add($label[$m.Id]); $script:BulkShown += $m.Id
            if ($checked[$m.Id]) { $list.SetItemChecked($i, $true) }
        }
        $list.EndUpdate()
    }
    & $fill
    $q.Add_TextChanged({ & $fill })
    $list.Add_ItemCheck({ $id = $script:BulkShown[$_.Index]; if ($_.NewValue -eq 'Checked') { $checked[$id] = $true } else { $checked.Remove($id) }; $cnt.Text = "$($checked.Count) selected" })
    $cnt = New-Object Windows.Forms.Label
    $cnt.AutoSize = $true; $cnt.ForeColor = $DlgMuted; $cnt.Text = "$($checked.Count) selected"
    $cnt.Location = New-Object Drawing.Point(16, 558); $cnt.Anchor = 'Bottom, Left'
    $ok = New-Pill 'Save' $true; $ok.FitWidth(24, 34); $ok.Anchor = 'Bottom, Right'
    $ok.Location = New-Object Drawing.Point((504 - $ok.Width), 552)
    $no = New-Pill 'Cancel' $false; $no.FitWidth(16, 34); $no.Anchor = 'Bottom, Right'
    $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 552)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.AddRange(@($lab, $q, $list, $cnt, $ok, $no))
    $d.Add_Shown({ $q.Focus() })
    $res = $d.ShowDialog($form); $d.Dispose()
    if ($res -ne 'OK') { return }
    # varasem järjekord jääb, uued lõppu
    $keep = @($CustomTabs[$tabName] | Where-Object { $checked[$_] })
    $add = @($all | Where-Object { $checked[$_.Id] -and $keep -notcontains $_.Id } | ForEach-Object { $_.Id })
    $CustomTabs[$tabName] = @($keep) + $add
    Save-Placement
    Build-Tabs
    Show-TabByTitle $tabName
    $note.Text = "✓  '$tabName': $($CustomTabs[$tabName].Count) mods"; $note.ForeColor = $G::Hex('#89D185')
}

# Menüü külge: kõik modi nupud ja ühe modiga kaardid (kutsutakse kaardi tegemisel)
function Add-ModMenu($ctl) { $ctl.ContextMenuStrip = $ModMenu }

# ---------- Oma vahelehed ----------
$ReservedTabs = @('Other', 'These', 'All mods', 'New', 'Removed parts')

function Show-TabByTitle($title) {
    for ($j = 0; $j -lt $TabBtns.Count; $j++) { if ($TabBtns[$j].Title -eq $title) { Show-Tab $j $false; return } }
}

# Küsib nime ja teeb uue tühja vahelehe. Tagastab nime või $null.
function New-CustomTab([bool]$openBulk = $true) {
    $n = Show-RenameDialog '' 'New tab' 'Tab name (add mods with right-click: Add to tab)'
    if (-not $n) { return $null }
    if ($ReservedTabs -contains $n -or $CustomTabs.Contains($n)) {
        [Windows.Forms.MessageBox]::Show($form, "A tab named '$n' already exists.", 'Deadlock Mods') | Out-Null
        return $null
    }
    $CustomTabs[$n] = @()
    Save-Placement
    Build-Tabs
    Show-TabByTitle $n
    if ($openBulk) { Set-SelectMode 'tab' $n }   # kohe modide valik (klõpsa modidel, siis "Save tab")
    return $n
}

function Add-ToCustomTab($name, $id) {
    if (-not $CustomTabs.Contains($name) -or -not $id) { return }
    if ($CustomTabs[$name] -notcontains $id) { $CustomTabs[$name] = @($CustomTabs[$name]) + $id }
    Save-Placement
    Build-Tabs
    $note.Text = "✓  $($ById[$id].Name) -> tab '$name'"; $note.ForeColor = $G::Hex('#89D185')
}

$miFromTab.Add_Click({
    $name = $TabBtns[$CurTab].Title; $id = $script:MenuId
    if (-not $CustomTabs.Contains($name)) { return }
    $CustomTabs[$name] = @($CustomTabs[$name] | Where-Object { $_ -ne $id })
    Save-Placement
    Build-Tabs
})

# Vahelehe nime paremklõps (ainult oma vahelehtedel): nimeta ümber / kustuta vaheleht
$TabMenu = New-Object Windows.Forms.ContextMenuStrip
$TabMenu.ShowImageMargin = $false; $TabMenu.BackColor = $G::Raised; $TabMenu.ForeColor = $G::Text; $TabMenu.Font = $FontUi
$miTabBulk = $TabMenu.Items.Add('Add mods…')
$miTabRename = $TabMenu.Items.Add('Rename tab…')
$miTabDelete = $TabMenu.Items.Add('Delete tab (mods are kept)')
$miTabDelete.ForeColor = $G::Hex('#F48771')
$TabMenu.Add_Opening({ $script:TabMenuTitle = $TabMenu.SourceControl.AccessibleName })

$miTabBulk.Add_Click({ Set-SelectMode 'tab' $script:TabMenuTitle })
$miTabRename.Add_Click({
    $old = $script:TabMenuTitle
    $n = Show-RenameDialog $old 'Rename tab' 'New tab name'
    if (-not $n -or $n -eq $old) { return }
    if ($ReservedTabs -contains $n -or $CustomTabs.Contains($n)) {
        [Windows.Forms.MessageBox]::Show($form, "A tab named '$n' already exists.", 'Deadlock Mods') | Out-Null; return
    }
    # sama koht järjekorras
    $new = [ordered]@{}; foreach ($k in $CustomTabs.Keys) { if ($k -eq $old) { $new[$n] = $CustomTabs[$k] } else { $new[$k] = $CustomTabs[$k] } }
    $CustomTabs.Clear(); foreach ($k in $new.Keys) { $CustomTabs[$k] = $new[$k] }
    Save-Placement
    Build-Tabs
    Show-TabByTitle $n
})

$miTabDelete.Add_Click({
    $t = $script:TabMenuTitle
    $r = [Windows.Forms.MessageBox]::Show($form, "Delete tab '$t'?`n`nThe mods themselves stay (under 'All mods').", 'Deadlock Mods', 'YesNo', 'Question', 'Button2')
    if ($r -ne 'Yes') { return }
    $CustomTabs.Remove($t)
    Save-Placement
    Build-Tabs
})

# "+" vahelehtede ribal: uus vaheleht
function Add-PlusTab {
    if ($script:PlusLbl) { $tabBar.Controls.Remove($script:PlusLbl); $script:PlusLbl.Dispose(); $script:PlusLbl = $null }
    $p = New-Object Windows.Forms.Label
    $p.Text = '+'; $p.AutoSize = $true; $p.Cursor = 'Hand'; $p.ForeColor = $G::TabIdle; $p.BackColor = 'Transparent'
    $p.Font = New-Object Drawing.Font($FontTab.FontFamily, ($FontTab.Size + 4), [Drawing.FontStyle]::Bold)
    $x = 24; foreach ($tb in $TabBtns) { $x = [Math]::Max($x, $tb.Label.Right + 22) }
    $p.Location = New-Object Drawing.Point($x, 7)
    $p.Add_Click({ [void](New-CustomTab) })
    $p.Add_MouseEnter({ $this.ForeColor = $G::Brand })
    $p.Add_MouseLeave({ $this.ForeColor = $G::TabIdle })
    $tabBar.Controls.Add($p)
    $script:PlusLbl = $p
    $tt = New-Object Windows.Forms.ToolTip; $tt.SetToolTip($p, 'New tab')
}
