# Modi enda pilt kaardil: paremklõps modil -> "Picture…", või paremklõps otse kaardi pildil.
#  - Lingitud modil (GameBanana) avaneb aken lehe piltidega; lingita modil kõigepealt väike aken (fail / kleebi / lingi).
#  - Raamis: lohista pilti, ratas = suum. "Auto" valib pildi (allkiri, nimi) ja koha (kus on kõige rohkem detaili).
#  - Ka aldil ("n" / "+ …") võib olla oma pilt: kui alt on sees, näitab kaart aldi pilti, muidu modi oma.
#  - Salvestub pildid\<id>.png kaardi kujus (432x588). Lingiga lisatud modid saavad pildi ise (Save-ModPictureFromGb).
# Laetakse DeadlockModToggle.ps1-st pärast uuendused.ps1-te.

$PicAspect = 72.0 / 98.0          # kaardi pildi kuju (Card.PicRect)
$PicW = 432; $PicH = 588          # 2x, et suumitud kaardil ka terav oleks
$PicFilter = 'Pictures (*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp)|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp|All files|*.*'

function Set-ModPicture($id, [Drawing.Image]$img) {
    if (-not (Test-Path -LiteralPath $ModPicDir)) { New-Item -ItemType Directory -Force $ModPicDir | Out-Null }
    $k = [Math]::Min(1.0, 600.0 / [Math]::Max($img.Width, $img.Height))
    $w = [Math]::Max(1, [int]($img.Width * $k)); $h = [Math]::Max(1, [int]($img.Height * $k))
    $bmp = New-Object Drawing.Bitmap $w, $h
    $g = [Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose()
    $tmp = Join-Path $ModPicDir "$id.tmp.png"
    $bmp.Save($tmp, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Move-Item -LiteralPath $tmp -Destination (Join-Path $ModPicDir "$id.png") -Force
    $ModPicCache.Remove($id)
}

# Originaalpilt ja kärpe koht kaardi pildi kõrval: pildiaknas saab pilti hiljem uuesti liigutada / suumida
# (kaardi pilt ise on juba kärbitud - selles pole ruumi liigutada)
function Save-PictureOrig($id, [Drawing.Image]$img, [double]$cx, [double]$cy, [double]$zoom) {
    if (-not (Test-Path -LiteralPath $ModPicDir)) { New-Item -ItemType Directory -Force $ModPicDir | Out-Null }
    $small = Get-SmallCopy $img 1600
    try { $small.Save((Join-Path $ModPicDir "$id.orig.png"), [Drawing.Imaging.ImageFormat]::Png) } finally { $small.Dispose() }
    $j = ConvertTo-Json @{ Cx = $cx; Cy = $cy; Zoom = $zoom }
    [IO.File]::WriteAllText((Join-Path $ModPicDir "$id.crop.json"), $j, (New-Object Text.UTF8Encoding $false))
}
function Get-PictureOrig($id) {
    $o = Join-Path $ModPicDir "$id.orig.png"; $c = Join-Path $ModPicDir "$id.crop.json"
    if (-not (Test-Path -LiteralPath $o)) { return $null }
    try {
        $img = Read-ImageNoLock $o; $cr = @{ Cx = 0.5; Cy = 0.5; Zoom = 1.0 }
        if (Test-Path -LiteralPath $c) { $j = [IO.File]::ReadAllText($c) | ConvertFrom-Json; $cr = @{ Cx = [double]$j.Cx; Cy = [double]$j.Cy; Zoom = [double]$j.Zoom } }
        return @{ Img = $img; Cx = $cr.Cx; Cy = $cr.Cy; Zoom = [Math]::Max(1.0, $cr.Zoom) }
    } catch { return $null }
}
function Remove-PictureFiles($id) {
    foreach ($n in "$id.png", "$id.orig.png", "$id.crop.json") { $f = Join-Path $ModPicDir $n; if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $ModPicCache.Remove($id)
}

# Kärbe: pilt $img, keskpunkt ($cx,$cy 0..1), suum (1 = suurim kaardi kujuline ala) -> $w x $h bitmap
function Get-CroppedPicture([Drawing.Image]$img, [double]$cx, [double]$cy, [double]$zoom, [int]$w = $PicW, [int]$h = $PicH) {
    # NB: $iw/$ih, mitte $W/$H - PowerShell ei erista suurtähti ja $W kirjutaks üle väljundi laiuse $w
    $iw = $img.Width; $ih = $img.Height
    if ($iw / $ih -gt $PicAspect) { $ch = $ih; $cw = $ih * $PicAspect } else { $cw = $iw; $ch = $iw / $PicAspect }
    $cw /= $zoom; $ch /= $zoom
    $x = [Math]::Max(0, [Math]::Min($iw - $cw, $cx * $iw - $cw / 2)); $y = [Math]::Max(0, [Math]::Min($ih - $ch, $cy * $ih - $ch / 2))
    $bmp = New-Object Drawing.Bitmap $w, $h
    $g = [Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($img, (New-Object Drawing.RectangleF 0, 0, $w, $h), (New-Object Drawing.RectangleF ([single]$x), ([single]$y), ([single]$cw), ([single]$ch)), [Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    return $bmp
}
# Väiksem koopia eelvaateks (lohistamine jääb sujuvaks ka suure pildiga)
function Get-SmallCopy([Drawing.Image]$img, [int]$max = 900) {
    $k = [Math]::Min(1.0, $max / [Math]::Max($img.Width, $img.Height))
    $bmp = New-Object Drawing.Bitmap ([Math]::Max(1, [int]($img.Width * $k))), ([Math]::Max(1, [int]($img.Height * $k)))
    $g = [Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.DrawImage($img, 0, 0, $bmp.Width, $bmp.Height); $g.Dispose()
    return $bmp
}

function Get-WebImage($url) {
    $tmp = Join-Path $env:TEMP ('dlpic_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try { $dl = [DlDownload]::Start($url, $tmp); Wait-Task $dl.Task; return (Read-ImageNoLock $tmp) }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# Lõikelaualt parim võimalik pilt: brauseri "Copy image" paneb sinna ka PNG-voo ja/või HTML-i pildi aadressiga
# (originaal, täiskvaliteet). Tavaline bitmap (CF_BITMAP) on viimane valik.
function Get-ClipboardPicture {
    $data = [Windows.Forms.Clipboard]::GetDataObject()
    if (-not $data) { return $null }
    if ($data.GetDataPresent('PNG')) {
        try { $ms = $data.GetData('PNG'); if ($ms -is [IO.Stream]) { $buf = New-Object IO.MemoryStream; $ms.CopyTo($buf); $img = [Drawing.Image]::FromStream($buf); return (New-Object Drawing.Bitmap $img) } } catch {}
    }
    if ($data.GetDataPresent('HTML Format')) {
        $html = [string]$data.GetData('HTML Format')
        if ($html -match '<img[^>]+src="(https?://[^"]+)"') { try { return (Get-WebImage ($Matches[1] -replace '&amp;', '&')) } catch {} }
    }
    if ([Windows.Forms.Clipboard]::ContainsFileDropList()) { try { return (Read-ImageNoLock (@([Windows.Forms.Clipboard]::GetFileDropList())[0])) } catch {} }
    if ([Windows.Forms.Clipboard]::ContainsImage()) { $i = [Windows.Forms.Clipboard]::GetImage(); return (New-Object Drawing.Bitmap $i) }
    return $null
}

# Millist GameBanana pilti kasutada: allkirjas modi/kangelase nimi (+), ikoonid/UI/võrdlus (-), püstisem pilt (+), esimesed (+)
function Get-BestGbImage($id, $inf) {
    $m = $ById[$id]
    $mine = Get-NameTokens "$($m.Name) $(Get-HeroName $m)"   # (ilma @(): muidu massiiv massiivis ja -contains ei leia midagi)
    $best = $null; $bs = -99; $i = 0
    foreach ($im in @($inf.Images)) {
        $cap = ([string]$im.Caption).ToLower(); $s = 0
        foreach ($t in (Get-NameTokens $cap)) { if ($mine -contains $t) { $s += 2 } }
        if ($cap -match 'icon|\bui\b|\bhud\b|abilit|comparison|before|after|vs\b|minimap|portrait|card|menu') { $s -= 3 }
        if ($cap -match 'in.?game|model|full|front|render|skin') { $s += 1 }
        if ($im.W -and $im.H) { $s += [Math]::Min(1.5, ($im.H / $im.W) * 1.2) }
        $s -= 0.3 * $i; $i++
        if ($s -gt $bs) { $bs = $s; $best = $im }
    }
    return $best
}

# Automaatne pilt GameBananast (lingiga lisamisel): parim pilt + automaatne kärbe
function Save-ModPictureFromGb($id, $inf) {
    $im = Get-BestGbImage $id $inf
    if (-not $im) { throw 'The GameBanana page has no pictures.' }
    $img = Get-WebImage $im.Url
    try {
        $c = [DlUi.AutoCrop]::Find($img, $PicAspect, 1.0)
        $bmp = Get-CroppedPicture $img $c.X $c.Y 1.0
        try { Set-ModPicture $id $bmp } finally { $bmp.Dispose() }
        Save-PictureOrig $id $img $c.X $c.Y 1.0
    } finally { $img.Dispose() }
}

# Modi (või aldi) GameBanana allikas: oma link, muidu põhimodi link
function Get-PictureSource($id) {
    $a = Get-Sources; $m = $ById[$id]
    if ($a.ContainsKey($id)) { return $a[$id] }
    if ($m -and $m.Parent -and $a.ContainsKey($m.Parent)) { return $a[$m.Parent] }
    return $null
}

# Kelle pilti saab sellel kaardil muuta: rea modid ja nende altid/lisad
function Get-PictureTargets($row) {
    $out = @()
    foreach ($rid in @($row)) {
        if (-not $rid) { continue }; $m = $ById[$rid]; if (-not $m) { continue }
        $out += , @{ Id = $rid; Text = (Get-ShortName $m) }
        foreach ($c in (Get-Children $rid)) { $out += , @{ Id = $c.Id; Text = "      $(if ($c.AltStyle -eq 'badge') { '"n" version' } else { '+ add-on' }): $(Get-ShortName $c)" } }
    }
    return , $out
}

# Väike esimene aken lingita modile: fail / kleebi / lingi GameBananaga. Tagastab pildi, 'link' või $null.
function Show-PictureSmall($id) {
    $m = $ById[$id]
    $d = New-Object Windows.Forms.Form
    $d.Text = "Picture: $($m.Name)"; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(460, 220)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $hdr = New-DialogHeader $d 'Mod picture' "Where should the picture for $(Get-ShortName $m) come from?"
    $st = @{ Res = $null }
    $b1 = New-Pill 'Choose a picture file…' $true; $b1.FitWidth(18, 36); $b1.Location = New-Object Drawing.Point(20, 80)
    $b2 = New-Pill 'Paste copied picture' $false; $b2.FitWidth(18, 36); $b2.Location = New-Object Drawing.Point(($b1.Right + 10), 80)
    $b3 = New-Pill 'Link to GameBanana (pick from its pictures)…' $false; $b3.FitWidth(18, 36); $b3.Location = New-Object Drawing.Point(20, 126)
    $msg = New-Object Windows.Forms.Label; $msg.AutoSize = $true; $msg.ForeColor = $DlgText; $msg.Location = New-Object Drawing.Point(20, 176)
    $msg.Text = 'Tip: in the browser right-click a picture -> Copy image, then Paste.'
    $b1.Add_Click({
        $fs = [DlUi.FreePicker]::Open('Choose a picture', $PicFilter, '', $false)
        if ($fs -and $fs.Count) { try { $st.Res = Read-ImageNoLock $fs[0]; $d.Close() } catch { $msg.Text = 'That file is not a picture Windows can open.' } }
    })
    $b2.Add_Click({ $d.Cursor = 'WaitCursor'; try { $st.Res = Get-ClipboardPicture } catch {} finally { $d.Cursor = 'Default' }; if ($st.Res) { $d.Close() } else { $msg.Text = 'Nothing to paste: copy a picture first (right-click it -> Copy image).' } })
    $b3.Add_Click({ $st.Res = 'link'; $d.Close() })
    $d.Controls.AddRange(@($b1, $b2, $b3, $msg))
    [void]$d.ShowDialog($form); $d.Dispose()
    return $st.Res
}

# Sisenemine: paremklõps modil / kaardi pildil. $row = kaardi modid (pildi saab valida ka altidele).
function Show-PictureFor($id, $row = $null) {
    if (-not $ById[$id]) { return }
    if (-not $row) { $m = $ById[$id]; $row = @($(if ($m.Parent -and $ById[$m.Parent]) { $m.Parent } else { $id })) }
    $img = $null
    if (-not (Get-PictureSource $id) -and -not (Get-ModPicture $id)) {
        $r = Show-PictureSmall $id
        if (-not $r) { return }
        if ($r -eq 'link') {
            $main = if ($ById[$id].Parent) { $ById[$id].Parent } else { $id }
            Show-ModSource $main
            if (-not (Get-PictureSource $id)) { return }
        } else { $img = $r }
    }
    Show-PictureEditor $id $row $img
}

# Peidetud pildiga modid (PlainPicTabs, vaikimisi tühi):
# pildiaken ei näita praegust pilti ega GameBanana lehe pilte
function Test-PicHidden($id) { Test-OtherPicHidden $id }   # (DeadlockModToggle.ps1)

# ---------- Aken: pildi valik ja koht ----------
function Show-PictureEditor($id, $row, $startImg = $null) {
    if (-not $row) { $m0 = $ById[$id]; $row = @($(if ($m0.Parent -and $ById[$m0.Parent]) { $m0.Parent } else { $id })) }
    $targets = Get-PictureTargets $row
    if (-not @($targets | Where-Object { $_.Id -eq $id }).Count) { $targets = @(@{ Id = $id; Text = (Get-ShortName $ById[$id]) }) + $targets }
    $st = @{ Id = $id; Img = $null; View = $null; Cx = 0.5; Cy = 0.4; Zoom = 1.0; Drag = $null; Gb = $null; GbKey = '-'; Thumbs = @(); Changed = $false; Saved = @() }
    $d = New-Object Windows.Forms.Form
    $d.Text = 'Mod picture'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(920, 600); $d.MinimumSize = New-Object Drawing.Size(780, 560)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $hdr = New-DialogHeader $d 'Mod picture' 'Pick a picture, then drag it in the frame (mouse wheel = zoom). An alt''s picture shows while that alt is on.'

    $forLab = New-Object Windows.Forms.Label; $forLab.AutoSize = $true; $forLab.ForeColor = $DlgText; $forLab.Location = New-Object Drawing.Point(16, 78); $forLab.Text = 'Picture for:'
    $forBox = New-Object Windows.Forms.ComboBox
    $forBox.DropDownStyle = 'DropDownList'; $forBox.FlatStyle = 'Flat'; $forBox.BackColor = $G::Raised; $forBox.ForeColor = $G::Bright; $forBox.Width = 420
    $forBox.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco -and -not $Night) { 'Explorer' } else { 'DarkMode_CFD' }), $null) })
    $forBox.Location = New-Object Drawing.Point(100, 74)
    foreach ($t in $targets) { [void]$forBox.Items.Add($t.Text + $(if ((Get-ModPicture $t.Id) -and -not (Test-PicHidden $t.Id)) { '   ✓' } else { '' })) }

    $lab = New-Object Windows.Forms.Label; $lab.AutoSize = $true; $lab.ForeColor = $DlgText; $lab.Location = New-Object Drawing.Point(16, 110)
    $thumbs = New-Object Windows.Forms.FlowLayoutPanel
    $thumbs.Location = New-Object Drawing.Point(16, 132); $thumbs.Size = New-Object Drawing.Size(560, 392); $thumbs.Anchor = 'Top, Bottom, Left, Right'
    $thumbs.AutoScroll = $true; $thumbs.BackColor = $G::Panel; $thumbs.BorderStyle = 'FixedSingle'
    $bFile = New-Pill 'Choose file…' $false; $bFile.FitWidth(14, 32); $bFile.Location = New-Object Drawing.Point(16, 540); $bFile.Anchor = 'Bottom, Left'
    $bPaste = New-Pill 'Paste copied picture' $false; $bPaste.FitWidth(14, 32); $bPaste.Location = New-Object Drawing.Point(($bFile.Right + 8), 540); $bPaste.Anchor = 'Bottom, Left'
    $bAuto = New-Pill '✦  Auto' $false; $bAuto.FitWidth(14, 32); $bAuto.Location = New-Object Drawing.Point(($bPaste.Right + 8), 540); $bAuto.Anchor = 'Bottom, Left'
    $bDel = New-Pill 'Remove picture' $false; $bDel.FitWidth(14, 32); $bDel.Location = New-Object Drawing.Point(($bAuto.Right + 8), 540); $bDel.Anchor = 'Bottom, Left'

    $pv = New-Object Windows.Forms.PictureBox
    $pv.Size = New-Object Drawing.Size(270, 367); $pv.Location = New-Object Drawing.Point(626, 110); $pv.Anchor = 'Top, Right'
    $pv.BackColor = $G::Raised; $pv.Cursor = 'SizeAll'
    $pvLab = New-Object Windows.Forms.Label; $pvLab.AutoSize = $true; $pvLab.ForeColor = $DlgText; $pvLab.Anchor = 'Top, Right'
    $pvLab.Location = New-Object Drawing.Point(626, 484); $pvLab.Text = 'Drag = move,  mouse wheel = zoom'
    $pv.Add_Paint({
        $gx = $_.Graphics
        if (-not $st.View) { [Windows.Forms.TextRenderer]::DrawText($gx, $(if ($st.Hidden) { 'Hidden' } else { 'No picture yet' }), $FontUi, $pv.ClientRectangle, $G::Text, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter'); return }
        $bmp = Get-CroppedPicture $st.View $st.Cx $st.Cy $st.Zoom $pv.Width $pv.Height
        $gx.DrawImageUnscaled($bmp, 0, 0); $bmp.Dispose()
    })
    $clamp = {
        $W = $st.View.Width; $H = $st.View.Height
        if ($W / $H -gt $PicAspect) { $ch = $H; $cw = $H * $PicAspect } else { $cw = $W; $ch = $W / $PicAspect }
        $hw = $cw / $st.Zoom / 2 / $W; $hh = $ch / $st.Zoom / 2 / $H
        $st.Cx = [Math]::Max($hw, [Math]::Min(1 - $hw, $st.Cx)); $st.Cy = [Math]::Max($hh, [Math]::Min(1 - $hh, $st.Cy))
    }
    $pv.Add_MouseDown({ if ($st.View) { $st.Drag = @{ X = $_.X; Y = $_.Y; Cx = $st.Cx; Cy = $st.Cy } } })
    $pv.Add_MouseUp({ $st.Drag = $null })
    $pv.Add_MouseMove({
        if (-not $st.Drag) { return }
        $W = $st.View.Width; $H = $st.View.Height
        if ($W / $H -gt $PicAspect) { $ch = $H; $cw = $H * $PicAspect } else { $cw = $W; $ch = $W / $PicAspect }
        $cw /= $st.Zoom; $ch /= $st.Zoom
        $st.Cx = $st.Drag.Cx - ($_.X - $st.Drag.X) / $pv.Width * $cw / $W
        $st.Cy = $st.Drag.Cy - ($_.Y - $st.Drag.Y) / $pv.Height * $ch / $H
        & $clamp; $st.Changed = $true; $pv.Invalidate()
    })
    $pv.Add_MouseWheel({ if ($st.View) { $st.Zoom = [Math]::Max(1.0, [Math]::Min(6.0, $st.Zoom * $(if ($_.Delta -gt 0) { 1.15 } else { 1 / 1.15 }))); & $clamp; $st.Changed = $true; $pv.Invalidate() } })
    $pv.Add_MouseEnter({ $pv.Focus() })
    $setImg = {
        param($img, [bool]$auto)
        if ($st.Img) { $st.Img.Dispose() }; if ($st.View) { $st.View.Dispose() }
        $st.Img = $img; $st.View = Get-SmallCopy $img; $st.Zoom = 1.0
        if ($auto) { $c = [DlUi.AutoCrop]::Find($img, $PicAspect, 1.0); $st.Cx = $c.X; $st.Cy = $c.Y } else { $st.Cx = 0.5; $st.Cy = 0.5 }
        & $clamp; $st.Changed = $true; $pv.Invalidate()
    }
    $pickGb = {
        param($im)
        $d.Cursor = 'WaitCursor'
        try { & $setImg (Get-WebImage $im.Url) $true; foreach ($t in $st.Thumbs) { $t.BackColor = $(if ($t.Tag -eq $im) { $G::Brand } else { $G::Panel }) } }
        catch { $lab.Text = "Could not load that picture: $_" } finally { $d.Cursor = 'Default' }
    }
    $saveCur = {
        # muudatus salvestatakse enne teise sihi valimist ja OK-ga
        if ($st.Changed -and $st.Img) {
            $bmp = Get-CroppedPicture $st.Img $st.Cx $st.Cy $st.Zoom; try { Set-ModPicture $st.Id $bmp } finally { $bmp.Dispose() }
            Save-PictureOrig $st.Id $st.Img $st.Cx $st.Cy $st.Zoom
            $st.Saved += $st.Id
        }
        $st.Changed = $false
    }
    $loadGallery = {
        $src = Get-PictureSource $st.Id
        $key = if ($src) { "$($src.Model)/$($src.GbId)" } else { $null }
        if ($key -eq $st.GbKey) { return }
        $st.GbKey = $key; $st.Gb = $null
        foreach ($t in $st.Thumbs) { foreach ($c in $t.Controls) { if ($c.Image) { $c.Image.Dispose() } } }
        $thumbs.Controls.Clear(); $st.Thumbs = @()
        if (-not $src) { $lab.Text = 'No GameBanana link for this mod: use "Choose file…" or "Paste copied picture".'; return }
        $lab.Text = 'Loading pictures from GameBanana…'; $d.Refresh()
        try {
            $st.Gb = Get-GbInfo $src.Model $src.GbId 60
            $n = 0
            foreach ($im in @($st.Gb.Images)) {
                $box = New-Object Windows.Forms.Panel; $box.Size = New-Object Drawing.Size(168, 132); $box.Padding = New-Object Windows.Forms.Padding(3); $box.Margin = New-Object Windows.Forms.Padding(4)
                $box.BackColor = $G::Panel; $box.Tag = $im; $box.Cursor = 'Hand'
                $pb = New-Object Windows.Forms.PictureBox; $pb.Dock = 'Fill'; $pb.SizeMode = 'Zoom'; $pb.Tag = $im; $pb.Cursor = 'Hand'
                try { $pb.Image = Get-WebImage $im.Thumb } catch {}
                $tt = New-Object Windows.Forms.ToolTip; if ($im.Caption) { $tt.SetToolTip($pb, $im.Caption) }
                $pb.Add_Click({ & $pickGb $this.Tag })
                $box.Controls.Add($pb); $thumbs.Controls.Add($box); $st.Thumbs += $box; $n++
                [Windows.Forms.Application]::DoEvents()
            }
            $lab.Text = if ($n) { "Pictures on the GameBanana page ($n) - click one:" } else { 'The GameBanana page has no pictures. Use a file or paste a picture.' }
        } catch { $lab.Text = "Could not load the GameBanana page: $_" }
    }
    $loadTarget = {
        $cur = Get-ModPicture $st.Id
        if ($st.Img) { $st.Img.Dispose(); $st.Img = $null }; if ($st.View) { $st.View.Dispose(); $st.View = $null }
        $st.Hidden = Test-PicHidden $st.Id; $bAuto.Enabled = -not $st.Hidden
        if ($st.Hidden) {
            # peidus: ei praegust pilti ega GameBanana galeriid (fail / kleebi / eemalda töötavad)
            foreach ($t in $st.Thumbs) { foreach ($c in $t.Controls) { if ($c.Image) { $c.Image.Dispose() } } }
            $thumbs.Controls.Clear(); $st.Thumbs = @(); $st.Gb = $null; $st.GbKey = '-'
            $lab.Text = 'Pictures are hidden here. Use "Choose file…" or "Paste copied picture".'
            $st.Changed = $false; $bDel.Enabled = [bool]$cur; $pv.Invalidate(); return
        }
        $orig = if ($cur) { Get-PictureOrig $st.Id } else { $null }
        if ($orig) { $st.Img = $orig.Img; $st.View = Get-SmallCopy $st.Img; $st.Cx = $orig.Cx; $st.Cy = $orig.Cy; $st.Zoom = $orig.Zoom; & $clamp }
        elseif ($cur) { $st.Img = New-Object Drawing.Bitmap $cur; $st.View = Get-SmallCopy $st.Img; $st.Cx = 0.5; $st.Cy = 0.5; $st.Zoom = 1.0 }
        $st.Changed = $false; $bDel.Enabled = [bool]$cur; $pv.Invalidate()
        & $loadGallery
        if ($cur -and -not $orig -and $st.Gb) {
            # vanem pilt (ilma originaalita): laadi GameBanana pilt, millest see tehti, et saaks liigutada
            $best = Get-BestGbImage $st.Id $st.Gb
            if ($best) { & $pickGb $best; $st.Changed = $false }
        }
    }
    $forBox.Add_SelectedIndexChanged({
        $nid = $targets[$forBox.SelectedIndex].Id
        if ($nid -eq $st.Id -and $st.Loaded) { return }
        if ($st.Loaded) { & $saveCur }
        $st.Id = $nid; $st.Loaded = $true; & $loadTarget
    })
    $bAuto.Add_Click({
        if ($st.Hidden) { return }
        if ($st.Gb) { $best = Get-BestGbImage $st.Id $st.Gb; if ($best) { & $pickGb $best; return } }
        if ($st.Img) { $c = [DlUi.AutoCrop]::Find($st.Img, $PicAspect, 1.0); $st.Zoom = 1.0; $st.Cx = $c.X; $st.Cy = $c.Y; & $clamp; $st.Changed = $true; $pv.Invalidate() }
    })
    $bFile.Add_Click({
        $fs = [DlUi.FreePicker]::Open('Choose a picture', $PicFilter, '', $false)
        if ($fs -and $fs.Count) { try { & $setImg (Read-ImageNoLock $fs[0]) $true } catch { $lab.Text = 'That file is not a picture Windows can open.' } }
    })
    $bPaste.Add_Click({
        $d.Cursor = 'WaitCursor'
        try { $img = Get-ClipboardPicture; if ($img) { & $setImg $img $true } else { $lab.Text = 'Nothing to paste: copy a picture first (right-click it in the browser -> Copy image).' } }
        catch { $lab.Text = "Could not paste: $_" } finally { $d.Cursor = 'Default' }
    })
    $bDel.Add_Click({
        Remove-PictureFiles $st.Id
        $st.Saved += $st.Id; & $loadTarget
    })
    $ok = New-Pill 'Save picture' $true; $ok.FitWidth(22, 34); $ok.Anchor = 'Bottom, Right'
    $no = New-Pill 'Cancel' $false; $no.FitWidth(16, 34); $no.Anchor = 'Bottom, Right'
    $ok.Location = New-Object Drawing.Point((904 - $ok.Width), 550); $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 550)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.AddRange(@($forLab, $forBox, $lab, $thumbs, $bFile, $bPaste, $bAuto, $bDel, $pv, $pvLab, $ok, $no))

    $d.Add_Shown({
        $forBox.SelectedIndex = [Math]::Max(0, [array]::IndexOf(@($targets | ForEach-Object { $_.Id }), $id))
        if (-not $st.Loaded) { $st.Loaded = $true; & $loadTarget }
        if ($startImg) { & $setImg $startImg $true }
    })
    $res = $d.ShowDialog($form)
    if ($res -eq 'OK') { & $saveCur }
    if ($st.Img) { $st.Img.Dispose() }; if ($st.View) { $st.View.Dispose() }
    foreach ($t in $st.Thumbs) { foreach ($c in $t.Controls) { if ($c.Image) { $c.Image.Dispose() } } }
    $d.Dispose()
    if ($st.Saved.Count) { Build-Tabs; $note.Text = "✓  Picture saved"; $note.ForeColor = $G::Hex('#89D185') }
}

# ---------- Paremklõpsu menüü ----------
$miPic = New-Object Windows.Forms.ToolStripMenuItem 'Picture…'
$ModMenu.Items.Insert($ModMenu.Items.IndexOf($miParts), $miPic)
$ModMenu.Add_Opening({
    # paremklõps kaardi pildil avab pildiakna (DeadlockModToggle.ps1, kaardi MouseUp) - menüüd siis ei näidata
    if ($script:PicClickAt -and ([DateTime]::Now - $script:PicClickAt).TotalMilliseconds -lt 800) { $script:PicClickAt = $null; $_.Cancel = $true; return }
    if (-not $script:MenuId) { return }
    $miPic.Text = if (Get-ModPicture $script:MenuId) { 'Picture…  (change)' } else { 'Picture…' }
})
$miPic.Add_Click({ if ($script:MenuId) { Show-PictureFor $script:MenuId } })
