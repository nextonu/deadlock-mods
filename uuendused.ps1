# Uuendused: modi allikas (GameBanana link) ja uuenduste kontroll.
#  - Paremklõps modil -> "Source & updates…": pane link, vali, milline lehe fail on iga sinu fail
#    (Main / Alt version / Add-on). Lisatud modidel leitakse fail ise (arhiivi nime järgi).
#  - Päises "⟳ Updates": vaatab kõik lingitud modid üle. GameBanana lehel on igal failil oma id;
#    autor uuendab = uus fail, vana läheb "arhiveeritud" alla. Uuendus = sinu fail on arhiveeritud/kadunud
#    (asendus leitakse nime/kirjelduse järgi samast rollist) või failil on uus sisu (md5).
#  - Uuendamine: uus fail alla (md5 kontroll) -> sama kontroll nagu lisamisel (kaamera, vanad jagatud
#    failid) -> vana modi fail asendatakse samas kohas (pak-number, nimi, vaheleht, sees/väljas jäävad),
#    vana arhiiv kustutatakse. Eemaldatud osad (osad.ps1) võetakse uuest versioonist uuesti välja.
#  - Alt versioon vs lisa: lehel olev uus ALT läheb eraldi modiks sama kangelase alla (korraga üks sees),
#    uus LISA (add-on) läheb modi külge (sees koos modiga). Altid ja lisad uuenevad igaüks oma järglasega.
# Laetakse DeadlockModToggle.ps1-st (dot-source) pärast lisamine.ps1, kontroll.ps1 ja osad.ps1.

$SourcesFile = Join-Path $PSScriptRoot 'allikad.json'
$GbGameId = 20948
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$GbCache = @{}          # "Mod/123" -> @{ Info; At }
$RoleNames = [ordered]@{ main = 'Main'; alt = 'Alt version'; addon = 'Add-on' }

function Get-UnixNow { [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Format-GbDate($ts) { if (-not $ts) { return '?' }; [DateTimeOffset]::FromUnixTimeSeconds([long]$ts).LocalDateTime.ToString('yyyy-MM-dd') }
function Format-Size($b) { if ($b -ge 1MB) { '{0:N1} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ([Math]::Max(1, $b / 1KB)) } }

# ---------- allikad.json ----------
# { modId: { Model, GbId, Title, Seen, Ignore:[failiId], Files:[{ File, Name, Md5, Date, Size, Role, Idx:[modi failide indeksid] }] } }
function Get-Sources {
    $h = @{}
    if (-not (Test-Path -LiteralPath $SourcesFile)) { return $h }
    try { $o = [IO.File]::ReadAllText($SourcesFile) | ConvertFrom-Json } catch { return $h }
    foreach ($p in $o.PSObject.Properties) {
        $v = $p.Value
        $files = @(foreach ($f in @($v.Files)) {
            if (-not $f) { continue }
            @{ File = [long]$f.File; Name = [string]$f.Name; Md5 = [string]$f.Md5; Date = [long]$f.Date; Size = [long]$f.Size
               Role = $(if ($f.Role) { [string]$f.Role } else { 'main' }); Idx = @(@($f.Idx) | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ }) }
        })
        $h[$p.Name] = @{ Model = $(if ($v.Model) { [string]$v.Model } else { 'Mod' }); GbId = [long]$v.GbId; Title = [string]$v.Title
                         Seen = [long]$v.Seen; Ignore = @(@($v.Ignore) | Where-Object { $_ } | ForEach-Object { [long]$_ }); Files = $files }
    }
    return $h
}
function Save-Sources($h) {
    $o = [ordered]@{}
    foreach ($k in ($h.Keys | Sort-Object)) {
        $v = $h[$k]
        $o[$k] = [ordered]@{ Model = $v.Model; GbId = $v.GbId; Title = $v.Title; Seen = $v.Seen; Ignore = @($v.Ignore)
            Files = @(foreach ($f in $v.Files) { [ordered]@{ File = $f.File; Name = $f.Name; Md5 = $f.Md5; Date = $f.Date; Size = $f.Size; Role = $f.Role; Idx = @($f.Idx) } }) }
    }
    [IO.File]::WriteAllText($SourcesFile, (ConvertTo-Json $o -Depth 6), (New-Object Text.UTF8Encoding $false))
}
# Modi kustutamisel (kustutamine.ps1)
function Clear-ModSource($id) { $all = Get-Sources; if ($all.ContainsKey($id)) { $all.Remove($id); Save-Sources $all } }

# ---------- GameBanana ----------
function Get-GbRef($text) {
    $t = ([string]$text).Trim()
    if ($t -match 'gamebanana\.com/(mods|sounds)/(?:download/)?(\d+)') { return @{ Model = $(if ($Matches[1] -eq 'sounds') { 'Sound' } else { 'Mod' }); GbId = [long]$Matches[2] } }
    if ($t -match '^\d{3,8}$') { return @{ Model = 'Mod'; GbId = [long]$t } }
    return $null
}
function Get-GbUrl($model, $id) { "https://gamebanana.com/$(if ($model -eq 'Sound') { 'sounds' } else { 'mods' })/$id" }

# Võrgupäringud käivad täielikult taustalõimes (Task.Run): .NET Frameworkis jätkas WebClient/HttpClient
# päringut aknalõimes ja DoEvents-tsükkel jäi selle taha kinni. Aken ainult küsib, kas Task on valmis.
if (-not ('DlNet' -as [type])) {
    Add-Type -ReferencedAssemblies System.Net.Http -TypeDefinition @"
using System; using System.IO; using System.Net; using System.Net.Http; using System.Threading.Tasks;
public static class DlNet {
    static HttpClient client;
    static HttpClient C {
        get {
            if (client == null) {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                var h = new HttpClientHandler(); h.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
                client = new HttpClient(h); client.Timeout = TimeSpan.FromMinutes(30);
                client.DefaultRequestHeaders.UserAgent.ParseAdd("DeadlockModToggle/1.0");
            }
            return client;
        }
    }
    public static Task<string> GetString(string url) { return Task.Run(() => C.GetStringAsync(url)); }
    internal static Task<HttpResponseMessage> GetHeaders(string url) { return C.GetAsync(url, HttpCompletionOption.ResponseHeadersRead); }
}
public class DlDownload {
    public long Done; public Task Task; public string Name;
    public static DlDownload Start(string url, string path) {
        var d = new DlDownload();
        d.Task = Task.Run(async () => {
            using (var r = await DlNet.GetHeaders(url).ConfigureAwait(false)) {
                if (!r.IsSuccessStatusCode) throw new Exception("server answered " + (int)r.StatusCode);
                var cd = r.Content.Headers.ContentDisposition;
                if (cd != null) d.Name = (cd.FileNameStar ?? cd.FileName ?? "").Trim('"');
                if (string.IsNullOrEmpty(d.Name) && r.RequestMessage != null) d.Name = Uri.UnescapeDataString(System.IO.Path.GetFileName(r.RequestMessage.RequestUri.AbsolutePath));
                using (var s = await r.Content.ReadAsStreamAsync().ConfigureAwait(false))
                using (var f = new FileStream(path, FileMode.Create, FileAccess.Write)) {
                    var buf = new byte[1 << 20]; int n;
                    while ((n = await s.ReadAsync(buf, 0, buf.Length).ConfigureAwait(false)) > 0) { f.Write(buf, 0, n); d.Done += n; }
                }
            }
        });
        return d;
    }
}
"@
}
function Start-GbString($url) { [DlNet]::GetString($url) }# Ootab Task'i lõppu nii, et aken ei külmu. $__tick kutsutakse vahepeal (nt allalaadimise edenemine).
function Wait-Task($__task, $__tick) {
    $__sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $__task.IsCompleted) {
        [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30
        if ($__tick -and $__sw.ElapsedMilliseconds -gt 300) { & $__tick; $__sw.Restart() }
    }
    if ($__task.IsFaulted) {
        $e = $__task.Exception; while ($e.InnerException) { $e = $e.InnerException }
        throw $e.Message
    }
    if ($__task.IsCanceled) { throw 'Cancelled.' }
}

function Start-GbPage($model, $id) {
    return @{ Task = (Start-GbString "https://gamebanana.com/apiv11/$model/$id/ProfilePage"); Model = $model; GbId = [long]$id }
}
function ConvertTo-GbInfo($model, $id, $json) {
    $j = $json | ConvertFrom-Json
    $mk = {
        param($f, [bool]$arch)
        @{ Id = [long]$f._idRow; Name = [string]$f._sFile; Size = [long]$f._nFilesize; Date = [long]$f._tsDateAdded; Md5 = [string]$f._sMd5Checksum
           Desc = ([string]$f._sDescription).Trim(); Url = $(if ($f._sDownloadUrl) { [string]$f._sDownloadUrl } else { "https://gamebanana.com/dl/$($f._idRow)" }); Archived = $arch }
    }
    $cur = @(foreach ($f in @($j._aFiles)) { if ($f -and $f._idRow) { & $mk $f $false } })
    $arc = @(foreach ($f in @($j._aArchivedFiles)) { if ($f -and $f._idRow) { & $mk $f $true } })
    $upd = [long]$j._tsDateUpdated; if (-not $upd) { $upd = [long]$j._tsDateModified }; if (-not $upd) { $upd = [long]$j._tsDateAdded }
    # eelvaate pildid: suur (530 px või originaal), pisipilt (220/100), allkiri, mõõdud
    $imgs = @(foreach ($im in @($j._aPreviewMedia._aImages)) { if ($im -and $im._sFile) {
        @{ Url = "$($im._sBaseUrl)/$(if ($im._sFile530) { $im._sFile530 } else { $im._sFile })"
           Thumb = "$($im._sBaseUrl)/$(if ($im._sFile220) { $im._sFile220 } elseif ($im._sFile100) { $im._sFile100 } else { $im._sFile })"
           Caption = [string]$im._sCaption; W = [int]$im._wFile530; H = [int]$im._hFile530 } } })
    return @{ Model = $model; GbId = [long]$id; Name = [string]$j._sName; Url = (Get-GbUrl $model $id); Updated = $upd; Images = $imgs
              Gone = [bool]($j._bIsTrashed -or $j._bIsWithheld -or $j._bIsPrivate); Cur = $cur; Arch = $arc }
}
function Complete-GbPage($r) {
    try {
        if ($r.Task.IsFaulted) {
            $e = $r.Task.Exception; while ($e.InnerException) { $e = $e.InnerException }
            if ($e.Message -match '404') { return @{ Model = $r.Model; GbId = $r.GbId; Name = ''; Url = (Get-GbUrl $r.Model $r.GbId); Gone = $true; Cur = @(); Arch = @(); Updated = 0 } }
            throw $e.Message
        }
        $info = ConvertTo-GbInfo $r.Model $r.GbId $r.Task.Result
        $GbCache["$($r.Model)/$($r.GbId)"] = @{ Info = $info; At = [DateTime]::Now }
        return $info
    } finally { }
}
function Get-GbInfo($model, $id, [int]$maxAgeMin = 10) {
    $c = $GbCache["$model/$id"]
    if ($c -and ([DateTime]::Now - $c.At).TotalMinutes -lt $maxAgeMin) { return $c.Info }
    $r = Start-GbPage $model $id
    while (-not $r.Task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
    return Complete-GbPage $r
}

function Search-Gb($query) {
    $out = @()
    foreach ($model in 'Mod', 'Sound') {
        $u = "https://gamebanana.com/apiv11/Util/Search/Results?_sModelName=$model&_sOrder=best_match&_idGameRow=$GbGameId&_sSearchString=$([uri]::EscapeDataString($query))&_nPage=1"
        $t = Start-GbString $u
        try { Wait-Task $t } catch { continue }
        $j = $t.Result | ConvertFrom-Json
        foreach ($r in @($j._aRecords)) { if ($r -and $r._idRow) { $out += @{ Model = $model; GbId = [long]$r._idRow; Name = [string]$r._sName; By = [string]$r._aSubmitter._sName; SubCat = [string]$r._aSubCategory._sName; Likes = [int]$r._nLikeCount } } }
    }
    return , $out
}

function Get-FileMd5($path) {
    $s = [IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash($s)) -replace '-', '').ToLower() } finally { $s.Dispose() }
}

# Laeb lehe faili arhiivikausta (sama nimega olemasolev ja korras fail kasutatakse uuesti).
function Save-GbFile($c, $status) {
    New-Item -ItemType Directory -Force $ArchiveDir | Out-Null
    $dst = Join-Path $ArchiveDir ($c.Name -replace '[\\/:*?"<>|]', '_')
    if ((Test-Path -LiteralPath $dst) -and $c.Md5 -and (Get-FileMd5 $dst) -eq $c.Md5.ToLower()) { return $dst }
    $part = "$dst.part"
    try {
        & $status "Downloading $($c.Name)…"
        $dl = [DlDownload]::Start($c.Url, $part)
        Wait-Task $dl.Task { & $status ("Downloading $($c.Name): " + (Format-Size $dl.Done) + $(if ($c.Size) { ' / ' + (Format-Size $c.Size) } else { '' })) }
    } catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        throw "Download failed: $_"
    }
    if ($c.Md5 -and (Get-FileMd5 $part) -ne $c.Md5.ToLower()) { Remove-Item -LiteralPath $part -Force; throw 'The download is damaged (checksum does not match). Try again.' }
    Move-Item -LiteralPath $part -Destination $dst -Force
    return $dst
}

# ---------- Failide võrdlus ----------
function Get-NameTokens($s) {
    $s = ([string]$s).ToLower() -replace '\.(zip|rar|7z|vpk)$', ''
    $s = $s -replace '[_\-\s][0-9a-f]{5}$', ''               # GameBanana räsi lõpus (_a5ff4)
    $s = $s -replace 'v\d+([._\-]\d+)*', ' ' -replace 'pak\d+', ' '
    return , @($s -split '[^a-z0-9]+' | Where-Object { $_ -and $_ -notmatch '^\d+$' -and $_ -notin 'dir', 'the', 'a', 'of', 'and', 'for', 'mod', 'over', 'as' } | Select-Object -Unique)
}
function Get-Sim($a, $b) {
    $x = Get-NameTokens $a; $y = Get-NameTokens $b
    if (-not $x.Count -and -not $y.Count) { return 0.5 }
    $i = @($x | Where-Object { $y -contains $_ }).Count
    $u = @(($x + $y) | Select-Object -Unique).Count
    return $i / [Math]::Max(1, $u)
}
function Get-DescSim($a, $b) {
    $x = @(([string]$a).ToLower() -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique)
    $y = @(([string]$b).ToLower() -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique)
    if (-not $x.Count -and -not $y.Count) { return 0.5 }
    if (-not $x.Count -or -not $y.Count) { return 0 }
    $i = @($x | Where-Object { $y -contains $_ }).Count
    return $i / [Math]::Max(1, @(($x + $y) | Select-Object -Unique).Count)
}
# Versioon nimes (v1_6, v1-3-1, v124) -> int[] või $null
function Get-NameVer($s) {
    if (([string]$s).ToLower() -match 'v(\d+(?:[._\-]\d+)*)') { return , @($Matches[1] -split '[._\-]' | ForEach-Object { [int]$_ }) }
    return $null
}
function Compare-Ver($a, $b) {
    for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
        $x = if ($i -lt $a.Count) { $a[$i] } else { 0 }; $y = if ($i -lt $b.Count) { $b[$i] } else { 0 }
        if ($x -ne $y) { return [Math]::Sign($x - $y) }
    }
    return 0
}
# Kas lehel olev $new on sama faili uuem versioon (vana fail on lehel veel alles)?
function Test-NewerSame($old, $new) {
    $va = Get-NameVer $old; $vb = Get-NameVer $new
    if ($va -and $vb) { return ((Compare-Ver $vb $va) -gt 0 -and (Get-Sim $old $new) -ge 0.4) }
    return ((Get-Sim $old $new) -ge 0.8)
}

# Lehe faili roll: main / alt / addon (nimi ennekõike, siis suurus ja kirjeldus)
$AltRx = '\balt\b|alternat|variant|without|\bno[ _\-]|\bnon[ _\-]|colou?r|recolou?r|classic|\bsfw\b|\blite\b|model[ _\-]?only|only[ _\-]?model'
$AddonRx = 'add[ _\-]?on|extra|optional|bonus|voice|\bvo\b|\bvls\b|lines|sound|sfx|music|icon|portrait|\bhud\b|bike|weapon|\bgun\b|\bprop|effect|particle|\bvfx\b|\bpet\b|accessor'
function Get-RoleGuess($f, $cur) {
    $cur = @($cur | Where-Object { $_ })
    if ($cur.Count -le 1 -and -not $f.Archived) { return 'main' }
    $n = ($f.Name.ToLower() -replace '[_\-\.]', ' ')
    if ($n -match $AltRx) { return 'alt' }
    if ($n -match $AddonRx) { return 'addon' }
    $max = 0; foreach ($c in $cur) { if ($c.Size -gt $max) { $max = $c.Size } }
    if ($f.Size -ge $max) { return 'main' }
    $d = $f.Desc.ToLower()
    if ($d -match '\balt\b|alternat|variant|without|version without|version with') { return 'alt' }
    if ($d -match $AddonRx) { return 'addon' }
    if ($max -and $f.Size -lt 0.3 * $max) { return 'addon' }
    return 'alt'
}
# Kui hästi sobib lehe fail $c sinu vana faili ($L) järglaseks
function Get-SuccScore($L, $c, $cur, $oldDesc) {
    $s = 0.6 * (Get-Sim $L.Name $c.Name) + 0.3 * (Get-DescSim $oldDesc $c.Desc)
    $r = Get-RoleGuess $c $cur
    if ($r -eq $L.Role -or ($L.Role -eq 'main' -and $r -eq 'main')) { $s += 0.1 }
    elseif (($L.Role -eq 'addon') -ne ($r -eq 'addon')) { $s -= 0.15 }
    return $s
}

# ---------- Uuenduste leidmine ----------
# Üks lingitud mod + tema lehe info -> leiud (update / new / nosucc / gone / ok)
function Find-SourceUpdates($id, $src, $info) {
    $out = New-Object Collections.ArrayList
    if ($info.Gone) { [void]$out.Add(@{ Kind = 'gone'; Id = $id; Src = $src; Info = $info }); return , $out }
    $taken = @{}; $need = @(); $ok = @()
    foreach ($L in $src.Files) {
        $c = @($info.Cur | Where-Object { $_.Id -eq $L.File })[0]
        if (-not $c) { $need += , $L; continue }
        $taken[$c.Id] = 1
        if ($L.Md5 -and $c.Md5 -and $L.Md5.ToLower() -ne $c.Md5.ToLower()) {
            [void]$out.Add(@{ Kind = 'update'; Id = $id; Src = $src; Info = $info; Link = $L; New = $c; Sure = $true; Why = 'The file was replaced on the page.' })
        } else { $ok += , $L }
    }
    foreach ($L in $need) {
        $old = @($info.Arch | Where-Object { $_.Id -eq $L.File })[0]
        $oldDesc = if ($old) { $old.Desc } else { '' }
        $cands = @($info.Cur | Where-Object { -not $taken[$_.Id] -and $src.Ignore -notcontains $_.Id })
        $best = $null; $bs = -9; $second = -9
        foreach ($c in $cands) {
            $s = Get-SuccScore $L $c $info.Cur $oldDesc
            if ($s -gt $bs) { $second = $bs; $bs = $s; $best = $c } elseif ($s -gt $second) { $second = $s }
        }
        $single = ($cands.Count -eq 1 -and $need.Count -eq 1)
        if ($best -and ($single -or $bs -ge 0.35)) {
            $taken[$best.Id] = 1
            $why = if ($old) { 'Your version is archived on the page (old).' } elseif ($L.File) { 'Your file was removed from the page.' } else { 'Your version is not on the page (probably older).' }
            [void]$out.Add(@{ Kind = 'update'; Id = $id; Src = $src; Info = $info; Link = $L; New = $best; Sure = ([bool]$L.File -and ($single -or ($bs - $second) -ge 0.1)); Why = $why })
        } else {
            # nimed muutusid täiesti (nt vyper_camerafix_all -> spin_update): kui lehel on täpselt üks sama rolliga fail, see
            $same = @($cands | Where-Object { (Get-RoleGuess $_ $info.Cur) -eq $(if ($L.Role -eq 'alt') { 'alt' } elseif ($L.Role -eq 'addon') { 'addon' } else { 'main' }) })
            if ($same.Count -eq 1) {
                $taken[$same[0].Id] = 1
                [void]$out.Add(@{ Kind = 'update'; Id = $id; Src = $src; Info = $info; Link = $L; New = $same[0]; Sure = $false; Why = 'Your version is old; the file name changed, so this is a guess - check the page.' })
            } else {
                [void]$out.Add(@{ Kind = 'nosucc'; Id = $id; Src = $src; Info = $info; Link = $L })
            }
        }
    }
    foreach ($L in $ok) {
        foreach ($c in $info.Cur) {
            if ($taken[$c.Id] -or $src.Ignore -contains $c.Id -or $c.Date -le $L.Date) { continue }
            if (Test-NewerSame $L.Name $c.Name) {
                $taken[$c.Id] = 1
                [void]$out.Add(@{ Kind = 'update'; Id = $id; Src = $src; Info = $info; Link = $L; New = $c; Sure = $true; Why = 'A newer version of your file is on the page.' })
                break
            }
        }
    }
    foreach ($c in $info.Cur) {
        if ($taken[$c.Id] -or $src.Ignore -contains $c.Id -or $c.Date -le $src.Seen) { continue }
        $r = Get-RoleGuess $c $info.Cur; if ($r -eq 'main') { $r = 'alt' }
        [void]$out.Add(@{ Kind = 'new'; Id = $id; Src = $src; Info = $info; New = $c; Role = $r })
    }
    if (-not @($out | Where-Object { $_.Kind -ne 'new' }).Count) { [void]$out.Add(@{ Kind = 'ok'; Id = $id; Src = $src; Info = $info }) }
    return , $out
}

# ---------- Uuendamine ----------
function Update-AddedSource($id, $name) {
    $all = @(Get-AddedMods)
    $hit = $false
    foreach ($a in $all) { if ($a.Id -eq $id) { $a.Source = $name; $hit = $true } }
    if ($hit) { [IO.File]::WriteAllText($AddedFile, (ConvertTo-Json @($all) -Depth 5), (New-Object Text.UTF8Encoding $false)) }
}

function Invoke-SourceUpdate($x, $status) {
    $m = $ById[$x.Id]; if (-not $m) { throw 'The mod no longer exists.' }
    $L = $x.Link; $c = $x.New
    $targets = @($L.Idx | Where-Object { $_ -lt $m.Files.Count } | ForEach-Object { $m.Files[$_] })
    if (-not $targets.Count) { throw 'No mod files are linked to this page file. Open Source & updates… and pick it.' }
    if (@($targets | Where-Object { Test-Path -LiteralPath (Join-Path $Addons $_.Pak) }).Count -and (Get-Process deadlock -ErrorAction SilentlyContinue)) {
        throw 'This mod is on and Deadlock is running. Close the game first.'
    }
    $file = Save-GbFile $c $status
    $prep = Initialize-ModFile $file $status
    try {
        $new = @($prep.Files)
        if ($new.Count -ne $targets.Count) {
            throw "The new version has $($new.Count) .vpk file(s), yours has $($targets.Count). Add it with '+ Add mod' instead (the archive is in $ArchiveDir)."
        }
        $recs = @(Get-PartRecords)
        for ($i = 0; $i -lt $targets.Count; $i++) {
            $f = $targets[$i]
            $path = Get-ModFilePath $f
            if (-not $path) { $path = Join-Path $Off $f.Off }
            & $status "Replacing: $($f.Off)"
            Copy-Item -LiteralPath $new[$i].Src -Destination "$path.new" -Force
            Move-Item -LiteralPath "$path.new" -Destination $path -Force      # vana fail kaob
            # eemaldatud osad: varukoopia = uus versioon, osad võetakse uuesti välja
            $keys = @(Get-RemovedKeys $recs $f)
            if ($keys.Count) {
                Remove-Item -LiteralPath (Get-PartBackup $f) -Force -ErrorAction SilentlyContinue
                try { Update-PartFile $f $keys; [void]$prep.Log.Add("Removed parts taken out again: $($keys -join ', ')") }
                catch { [void]$prep.Log.Add("Could not remove the parts again: $($_.Exception.Message)") }
            }
        }
        if ($prep.Hero -and $m.Hero -and $prep.Hero.Key -ne $m.Hero) { [void]$prep.Log.Add("Note: the new version looks like a $($prep.Hero.Display) skin.") }
        if ($L.Name -and $L.Name -ne $c.Name) {
            $old = Join-Path $ArchiveDir $L.Name
            if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force; [void]$prep.Log.Add("Deleted old archive: $($L.Name)") }
        }
        $all = Get-Sources
        $s = $all[$x.Id]
        if ($s) {
            $key = @($L.Idx) -join ','
            foreach ($lf in $s.Files) { if ($lf.File -eq $L.File -and (@($lf.Idx) -join ',') -eq $key) { $lf.File = $c.Id; $lf.Name = $c.Name; $lf.Md5 = $c.Md5; $lf.Date = $c.Date; $lf.Size = $c.Size } }
            Save-Sources $all
        }
        Update-AddedSource $x.Id $c.Name
        return $prep.Log
    } finally { Clear-PreparedMod $prep }
}

function Get-BaseName($m) { (($m.Name -replace '\s*\([^)]*\)', '') -replace '\s*-\s*(camera fixed|no camera fix|large).*$', '').Trim() }
# Uue faili nimi: sõnad, mida põhimodi failinimes pole (nt "without music"), muidu kirjeldus
function Get-VariantLabel($c, $mainName) {
    $base = @(); foreach ($n in @($mainName)) { $base += Get-NameTokens $n }
    $extra = @((Get-NameTokens $c.Name) | Where-Object { $base -notcontains $_ })
    $t = if ($extra.Count) { $extra -join ' ' } elseif ($c.Desc) { ($c.Desc -split '[.\r\n]')[0] } else { [IO.Path]::GetFileNameWithoutExtension($c.Name) }
    if ($t.Length -gt 40) { $t = $t.Substring(0, 40).Trim() }
    return (Get-Culture).TextInfo.ToTitleCase($t.ToLower())
}

# Lehel olev uus fail juurde: alt -> eraldi mod sama kangelase alla; lisa -> modi külge (Parent)
function Invoke-SourceAdd($x, $status) {
    $base = $ById[$x.Id]; if (-not $base) { throw 'The mod no longer exists.' }
    $main = if ($base.Parent -and $ById[$base.Parent]) { $ById[$base.Parent] } else { $base }
    $c = $x.New
    $file = Save-GbFile $c $status
    $prep = Initialize-ModFile $file $status
    $done = $false
    try {
        $label = Get-VariantLabel $c @($x.Src.Files | ForEach-Object { $_.Name })
        $hero = Get-HeroName $main
        if ($x.Role -eq 'addon') {
            $ans = @{ Name = "$(Get-BaseName $main) - $label"; Cat = $main.Cat; HeroKey = $null; HeroName = $null; Parent = $main.Id; AltStyle = 'chip'; Where = 'New' }
        } else {
            $nm = "$(Get-BaseName $main) - $label"; if ($hero) { $nm += " ($hero)" }
            $ans = @{ Name = $nm; Cat = $main.Cat; HeroKey = $main.Hero; HeroName = $(if ($main.Hero) { $hero } else { $null }); Parent = $null; Where = 'New' }
        }
        $res = Install-PreparedMod $prep $ans
        $done = $true
        $all = Get-Sources
        $all[$res.Id] = @{ Model = $x.Src.Model; GbId = $x.Src.GbId; Title = $x.Src.Title; Seen = (Get-UnixNow); Ignore = @()
                           Files = @(@{ File = $c.Id; Name = $c.Name; Md5 = $c.Md5; Date = $c.Date; Size = $c.Size; Role = $x.Role; Idx = @(0..($prep.Files.Count - 1)) }) }
        # põhimod ei pea seda faili enam "uueks" pidama
        if ($all[$x.Id]) { $all[$x.Id].Ignore = @($all[$x.Id].Ignore) + $c.Id }
        Save-Sources $all
        return $res
    } finally { if (-not $done) { Clear-PreparedMod $prep } }
}

# ---------- Lingi leidmine ----------
function Get-ArchiveNames {
    $h = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $ArchiveDir -File -ErrorAction SilentlyContinue)) { $h[$f.Name.ToLower()] = 1 }
    foreach ($a in @(Get-AddedMods)) { if ($a.Source) { $h[([string]$a.Source).ToLower()] = 1 } }
    return $h
}
# Lehe failid, mis on sinu arhiivikaustas olemas (= tõenäoliselt sealt võetud)
function Get-PageMatches($info, $names) { @(@($info.Cur) + @($info.Arch) | Where-Object { $_ -and $names.ContainsKey($_.Name.ToLower()) }) }

# Iga modi faili jaoks lehe fail: varasem link, lisamise arhiivi nimi, arhiivikaust (pere liikmed eelistavad
# eri faile: põhimod + hääled/lisa), ainus fail, nime sarnasus. $guess = $false: ilma tõendita jääb fail
# teadmata (Unknown) - siis ei eeldata, et sul on uusim versioon.
function Get-AutoLinks($m, $info, $names, $prev, $used, [bool]$guess = $true) {
    if (-not $used) { $used = @{} }
    $rec = @(Get-AddedMods | Where-Object { $_.Id -eq $m.Id })[0]
    $all = @(@($info.Cur) + @($info.Arch) | Where-Object { $_ })
    $hits = @(Get-PageMatches $info $names)
    $out = @()
    for ($i = 0; $i -lt $m.Files.Count; $i++) {
        $f = $m.Files[$i]; $pick = $null; $pl = $null; $sure = $false
        if ($prev -and $prev.GbId -eq $info.GbId) {
            $pl = @($prev.Files | Where-Object { $_.Idx -contains $i })[0]
            if ($pl) { $sure = $true; $pick = @($all | Where-Object { $_.Id -eq $pl.File })[0]; if (-not $pick -and $pl.File) { $pick = @{ Id = $pl.File; Name = $pl.Name; Md5 = $pl.Md5; Date = $pl.Date; Size = $pl.Size; Desc = ''; Archived = $true } } }
        }
        if (-not $pick -and $rec -and $rec.Source) { $pick = @($all | Where-Object { $_.Name -ieq [string]$rec.Source })[0]; if ($pick) { $sure = $true } }
        if (-not $pick -and $hits.Count) {
            $pool = @($hits | Where-Object { -not $used[$_.Id] }); if (-not $pool.Count) { $pool = $hits }
            $pick = @($pool | Sort-Object @{ e = { Get-Sim "$($f.Off) $($m.Name)" $_.Name }; Descending = $true }, @{ e = { $_.Date }; Descending = $true })[0]
            $sure = $true
        }
        if (-not $pick -and $guess -and @($info.Cur).Count -eq 1) { $pick = $info.Cur[0] }
        if (-not $pick -and $guess -and @($info.Cur).Count) {
            $pick = @($info.Cur | Sort-Object @{ e = { Get-Sim "$($f.Off) $($m.Name)" "$($_.Name) $($_.Desc)" }; Descending = $true }, @{ e = { $_.Size }; Descending = $true })[0]
        }
        if ($pick) { $used[$pick.Id] = 1 }
        $role = if ($pl) { $pl.Role } elseif ($pick) { Get-RoleGuess $pick $info.Cur } elseif ($m.Parent) { 'addon' } else { 'main' }
        if (-not $pl) { if ($m.Parent) { if ($role -eq 'main') { $role = 'addon' } } elseif ($role -eq 'addon' -and $i -eq 0) { $role = 'main' } }
        $out += , @{ Index = $i; File = $pick; Role = $role; Sure = $sure; Unknown = (-not $pick) }
    }
    return , $out
}
# Kirjutab lingid: $rows = @{ Mod; Index; File; Role }; sama lehe failid rühmitatakse (üks arhiiv -> mitu vpk-d)
function Set-ModLinks($info, $rows) {
    $all = Get-Sources
    foreach ($grp in @($rows | Group-Object { $_.Mod.Id })) {
        $mid = $grp.Name
        $prev = $all[$mid]
        $files = @()
        foreach ($r in $grp.Group) {
            if (-not $r.File) {
                # teadmata versioon: link lehele on, fail mitte -> uuenduste kontroll pakub lehe uusimat
                if ($r.Unknown) { $files += , @{ File = 0; Name = ''; Md5 = ''; Date = 0; Size = 0; Role = $r.Role; Idx = @($r.Index) } }
                continue
            }
            $e = @($files | Where-Object { $_.File -eq $r.File.Id })[0]
            if ($e) { $e.Idx = @($e.Idx) + $r.Index; continue }
            $files += , @{ File = $r.File.Id; Name = $r.File.Name; Md5 = $r.File.Md5; Date = $r.File.Date; Size = $r.File.Size; Role = $r.Role; Idx = @($r.Index) }
        }
        if ($files.Count) {
            $same = ($prev -and $prev.GbId -eq $info.GbId)
            $all[$mid] = @{ Model = $info.Model; GbId = $info.GbId; Title = $info.Name; Files = $files
                            Seen = $(if ($same -and $prev.Seen) { $prev.Seen } else { Get-UnixNow }); Ignore = $(if ($same) { @($prev.Ignore) } else { @() }) }
        } elseif ($prev -and $prev.GbId -eq $info.GbId) { $all.Remove($mid) }
    }
    Save-Sources $all
}

# Otsib GameBananast modi nime järgi.
#  1. otsing ainult modi enda nimega (ilma kangelaseta: "Kitsune"), siis koos kangelasega - kangelase nimi uputaks
#     muidu tulemused ("Kitsune Grey Talon" -> 110 suvalist Grey Talon modi)
#  2. iga tulemus saab punkte: modi nime sõnad pealkirjas (+3 tk), kangelane pealkirjas või kategoorias (+2)
#  3. kindel (Sure), kui lehel on sinu allalaadimiste kaustas olev fail; muidu "Likely", kui parim on selgelt parim
# Tagastab @{ Info; Sure; Likely; Cands (punktide järjekorras) }
function Find-ModPage($m, $names) {
    $q = Get-BaseName $m
    $hero = Get-HeroName $m
    $heroT = Get-NameTokens "$hero $($m.Hero)"   # (ilma @(): funktsioon tagastab juba massiivi)
    $distinct = @((Get-NameTokens $q) | Where-Object { $heroT -notcontains $_ })
    $mine = @((Get-NameTokens "$q $(@($m.Files | ForEach-Object { $_.Off }) -join ' ')") | Where-Object { $heroT -notcontains $_ })
    $seen = @{}; $cands = @()
    $queries = @(($distinct -join ' '), "$q $hero".Trim(), $q) | Where-Object { $_ } | Select-Object -Unique
    foreach ($query in $queries) {
        foreach ($r in (Search-Gb $query)) { if (-not $seen["$($r.Model)/$($r.GbId)"]) { $seen["$($r.Model)/$($r.GbId)"] = 1; $cands += , $r } }
    }
    # kokku kirjutatud nimi ("Helloneighbor" vs lehel "Hello Neighbor"): GameBanana otsib terveid sõnu, seega
    # jaga pikk sõna kaheks (keskelt alustades) ja otsi uuesti, kuni mõne tulemuse pealkiri ilma tühikuteta sisaldab seda
    $glued = { param($r) ([string]$r.Name).ToLower() -replace '[^a-z0-9]', '' }
    foreach ($t in @($distinct | Where-Object { $_.Length -ge 8 })) {
        $t1 = $t
        if (@($cands | Where-Object { (& $glued $_).Contains($t1) }).Count) { continue }
        $mid = $t.Length / 2
        $cuts = @(3..($t.Length - 3) | Sort-Object { [Math]::Abs($_ - $mid) } | Select-Object -First 8)
        foreach ($k in $cuts) {
            $query = (@($distinct | Where-Object { $_ -ne $t1 }) + "$($t.Substring(0, $k)) $($t.Substring($k))") -join ' '
            $new = Search-Gb $query   # (ilma @(): Search-Gb tagastab massiivi ühe objektina)
            foreach ($r in $new) { if (-not $seen["$($r.Model)/$($r.GbId)"]) { $seen["$($r.Model)/$($r.GbId)"] = 1; $cands += , $r } }
            if (@($new | Where-Object { (& $glued $_).Contains($t1) }).Count) { break }
            Start-Sleep -Milliseconds 80
        }
    }
    $tokMatch = { param($a, $b) $a -eq $b -or ($a.Length -ge 4 -and $b.Contains($a)) -or ($b.Length -ge 4 -and $a.Contains($b)) }
    foreach ($r in $cands) {
        $title = Get-NameTokens $r.Name   # (ilma @(): muidu massiiv massiivis ja osaline sõna ei sobinud kunagi)
        $hitD = @($distinct | Where-Object { $d1 = $_; @($title | Where-Object { & $tokMatch $d1 $_ }).Count }).Count
        $heroHit = [bool](@($heroT | Where-Object { $h1 = $_; @($title | Where-Object { & $tokMatch $h1 $_ }).Count }).Count) -or ($r.SubCat -and $hero -and $r.SubCat -like "*$hero*")
        $r.Score = 3 * $hitD + $(if ($heroHit) { 2 } else { 0 }) + $(if ($r.Model -eq 'Mod') { 0.2 } else { 0 })
        $r.AllWords = ($distinct.Count -gt 0 -and $hitD -eq $distinct.Count)
        $r.HeroHit = $heroHit
    }
    $cands = @($cands | Sort-Object @{ e = { $_.Score }; Descending = $true }, @{ e = { $_.Likes }; Descending = $true })
    # kindel: allalaaditud fail on lehel
    foreach ($r in @($cands | Where-Object { $_.Score -ge 3 } | Select-Object -First 6)) {
        try { $info = Get-GbInfo $r.Model $r.GbId 60 } catch { continue }
        if (@(Get-PageMatches $info $names).Count) { return @{ Info = $info; Sure = $true; Likely = $false; Cands = $cands } }
        Start-Sleep -Milliseconds 120
    }
    # tõenäoline: kõik nime sõnad + õige kangelane (või kangelaseta mod) ja selgelt parem kui järgmine
    $best = $cands[0]
    if ($best -and $best.AllWords -and ($best.HeroHit -or -not $hero) -and ($cands.Count -eq 1 -or $cands[1].Score -lt $best.Score)) {
        try { return @{ Info = (Get-GbInfo $best.Model $best.GbId 60); Sure = $false; Likely = $true; Cands = $cands } } catch {}
    }
    return @{ Info = $null; Sure = $false; Likely = $false; Cands = $cands }
}
# ---------- Aken: modi allikas ----------
# Modid, mille GameBanana lehe autor on maha võtnud (kadunud.json): id -> @{ Url; Date }.
# Märgitakse Updatesis ja "Source & updates" aknas (ka siis, kui kleebid ise lingi); leht tagasi -> märge kaob.
$GoneFile = Join-Path $PSScriptRoot 'kadunud.json'
function Get-GoneMods {
    $h = @{}
    if (Test-Path -LiteralPath $GoneFile) { try { $j = [IO.File]::ReadAllText($GoneFile) | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value } } catch {} }
    return $h
}
function Save-GoneMods($h) {
    $o = [ordered]@{}; foreach ($k in ($h.Keys | Sort-Object)) { $o[$k] = $h[$k] }
    [IO.File]::WriteAllText($GoneFile, (ConvertTo-Json $o -Depth 3), (New-Object Text.UTF8Encoding $false))
    $script:GoneMods = $h
}
function Set-PageGone($id, $url, [bool]$gone) {
    $h = Get-GoneMods
    if ($gone) { if ($h.ContainsKey($id)) { return }; $h[$id] = [ordered]@{ Url = $url; Date = (Get-Date -Format 'yyyy-MM-dd') } }
    else { if (-not $h.ContainsKey($id)) { return }; $h.Remove($id) }
    Save-GoneMods $h; $script:GoneChanged = $true
}
$GoneMods = Get-GoneMods

function Show-ModSource($id) {
    $m0 = $ById[$id]; if (-not $m0) { return }
    $main = if ($m0.Parent -and $ById[$m0.Parent]) { $ById[$m0.Parent] } else { $m0 }
    $fam = @($main) + @(Get-Children $main.Id)
    $all = Get-Sources
    $st = @{ Info = $null; Rows = @(); Opts = @(); Names = (Get-ArchiveNames); Check = $false }

    $d = New-Object Windows.Forms.Form
    $d.Text = "Source & updates: $(Get-BaseName $main)"; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(860, 560); $d.MinimumSize = New-Object Drawing.Size(700, 420)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $lab = New-Object Windows.Forms.Label
    $lab.Text = 'GameBanana page of this mod (paste the link from the browser):'; $lab.AutoSize = $true; $lab.ForeColor = $DlgMuted
    $lab.Location = New-Object Drawing.Point(16, 14)
    $url = New-Object Windows.Forms.TextBox
    $url.BackColor = $G::Raised; $url.ForeColor = $G::Bright; $url.BorderStyle = 'FixedSingle'
    $url.Location = New-Object Drawing.Point(16, 40); $url.Width = 500; $url.Anchor = 'Top, Left, Right'
    $url.Add_HandleCreated({ [void][DlToggle.Native]::SendMessage($this.Handle, 0x1501, [IntPtr]1, 'https://gamebanana.com/mods/…') })
    $fetch = New-Pill 'Load' $true; $fetch.FitWidth(18, 30); $fetch.Anchor = 'Top, Right'
    $find = New-Pill 'Find it' $false; $find.FitWidth(14, 30); $find.Anchor = 'Top, Right'
    $open = New-Pill 'Open page' $false; $open.FitWidth(14, 30); $open.Anchor = 'Top, Right'
    $open.Location = New-Object Drawing.Point((844 - $open.Width), 37)
    $find.Location = New-Object Drawing.Point(($open.Left - $find.Width - 8), 37)
    $fetch.Location = New-Object Drawing.Point(($find.Left - $fetch.Width - 8), 37)
    $url.Width = $fetch.Left - 26
    $info = New-Object Windows.Forms.Label
    $info.AutoSize = $false; $info.Size = New-Object Drawing.Size(828, 40); $info.Anchor = 'Top, Left, Right'
    $info.Location = New-Object Drawing.Point(16, 74); $info.ForeColor = $DlgText; $info.Font = $FontChip
    $info.Text = 'Paste the link and press Load. "Find it" searches GameBanana by the mod name.'
    $head = New-Object Windows.Forms.Label
    $head.Text = 'Your files: which file on the page is each one, and what it is'; $head.AutoSize = $true; $head.ForeColor = $DlgMuted
    $head.Location = New-Object Drawing.Point(16, 118)
    $panel = New-Object Windows.Forms.Panel
    $panel.AutoScroll = $true; $panel.BackColor = $G::Panel; $panel.BorderStyle = 'FixedSingle'
    $panel.Location = New-Object Drawing.Point(16, 140); $panel.Size = New-Object Drawing.Size(828, 190); $panel.Anchor = 'Top, Left, Right'
    $head2 = New-Object Windows.Forms.Label
    $head2.Text = 'All files on the page'; $head2.AutoSize = $true; $head2.ForeColor = $DlgMuted
    $head2.Location = New-Object Drawing.Point(16, 340)
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.ShowItemToolTips = $true; $lv.HeaderStyle = 'Nonclickable'
    $lv.Location = New-Object Drawing.Point(16, 362); $lv.Size = New-Object Drawing.Size(828, 136); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('File', 260), @('Date', 90), @('Size', 80), @('Looks like', 90), @('Description', 280))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $unlink = New-Pill 'Remove link' $false; $unlink.FitWidth(14, 34); $unlink.Anchor = 'Bottom, Left'; $unlink.Location = New-Object Drawing.Point(16, 514)
    $save = New-Pill 'Save' $true; $save.FitWidth(22, 34); $save.Anchor = 'Bottom, Right'; $save.Enabled = $false
    $saveChk = New-Pill 'Save & check for updates' $false; $saveChk.FitWidth(14, 34); $saveChk.Anchor = 'Bottom, Right'; $saveChk.Enabled = $false
    $cancel = New-Pill 'Cancel' $false; $cancel.FitWidth(16, 34); $cancel.Anchor = 'Bottom, Right'
    $save.Location = New-Object Drawing.Point((844 - $save.Width), 514)
    $saveChk.Location = New-Object Drawing.Point(($save.Left - $saveChk.Width - 8), 514)
    $cancel.Location = New-Object Drawing.Point(($saveChk.Left - $cancel.Width - 8), 514)
    $unlink.Visible = [bool](@($fam | Where-Object { $all.ContainsKey($_.Id) }).Count)
    $cancel.Add_Click({ $d.Close() })

    $mkCombo = {
        param($w)
        $cb = New-Object Windows.Forms.ComboBox
        $cb.DropDownStyle = 'DropDownList'; $cb.FlatStyle = 'Flat'; $cb.BackColor = $G::Raised; $cb.ForeColor = $G::Bright; $cb.Width = $w
        $cb.Add_HandleCreated({ [void][DlToggle.Native]::SetWindowTheme($this.Handle, $(if ($Deco -and -not $Night) { 'Explorer' } else { 'DarkMode_CFD' }), $null) })
        $cb
    }
    $fill = {
        param($inf)
        $st.Info = $inf
        $panel.Controls.Clear(); $lv.Items.Clear(); $st.Rows = @()
        if ($inf.Gone) { Set-PageGone $id $inf.Url $true; $info.Text = "This page was removed or hidden by the author ($($inf.Url)). The mod is now marked 'page removed'."; $save.Enabled = $false; $saveChk.Enabled = $false; return }
        Set-PageGone $id $inf.Url $false
        $cur = @($inf.Cur); $arc = @($inf.Arch)
        $info.Text = "$($inf.Name)   ·   updated $(Format-GbDate $inf.Updated)   ·   $($cur.Count) file(s)" + $(if ($arc.Count) { " + $($arc.Count) old (archived)" } else { '' })
        $url.Text = $inf.Url
        $st.Opts = @($null) + $cur + @($arc | Sort-Object { - $_.Date })
        $labels = @('— not from this page —') + @($cur | ForEach-Object { "$($_.Name)   ·   $(Format-GbDate $_.Date)   ·   $(Format-Size $_.Size)" }) + @($arc | Sort-Object { - $_.Date } | ForEach-Object { "$($_.Name)   ·   $(Format-GbDate $_.Date)   ·   OLD version" })
        foreach ($f in $cur + $arc) {
            $it = New-Object Windows.Forms.ListViewItem($f.Name)
            [void]$it.SubItems.Add((Format-GbDate $f.Date)); [void]$it.SubItems.Add((Format-Size $f.Size))
            [void]$it.SubItems.Add($(if ($f.Archived) { 'old version' } else { $RoleNames[(Get-RoleGuess $f $cur)] }))
            [void]$it.SubItems.Add($f.Desc); $it.ToolTipText = $f.Desc
            if ($f.Archived) { $it.ForeColor = [DlUi.G]::Muted }
            [void]$lv.Items.Add($it)
        }
        $y = 8; $used = @{}
        foreach ($mm in $fam) {
            $auto = Get-AutoLinks $mm $inf $st.Names $all[$mm.Id] $used
            foreach ($a in $auto) {
                $f = $mm.Files[$a.Index]
                $where = if (Test-Path -LiteralPath (Join-Path $Addons $f.Pak)) { 'on' } else { 'off' }
                $l = New-Object Windows.Forms.Label
                $l.AutoSize = $false; $l.Size = New-Object Drawing.Size(270, 38); $l.UseMnemonic = $false; $l.ForeColor = $G::Text; $l.BackColor = 'Transparent'
                $l.Text = "$(if ($mm.Parent) { '+ ' } else { '' })$(Get-ShortName $mm)`n$($f.Off)  ($where)"
                $l.Location = New-Object Drawing.Point(8, $y)
                $cb = & $mkCombo 360; $cb.Location = New-Object Drawing.Point(286, ($y + 4)); [void]$cb.Items.AddRange($labels)
                $sel = 0; if ($a.File) { for ($k = 1; $k -lt $st.Opts.Count; $k++) { if ($st.Opts[$k].Id -eq $a.File.Id) { $sel = $k } } }
                $cb.SelectedIndex = $sel
                $rb = & $mkCombo 140; $rb.Location = New-Object Drawing.Point(656, ($y + 4)); [void]$rb.Items.AddRange(@($RoleNames.Values))
                $rb.SelectedIndex = [Math]::Max(0, @($RoleNames.Keys).IndexOf([string]$a.Role))
                $panel.Controls.AddRange(@($l, $cb, $rb))
                $st.Rows += , @{ Mod = $mm; Index = $a.Index; Combo = $cb; RoleBox = $rb }
                $y += 42
            }
        }
        $save.Enabled = $true; $saveChk.Enabled = $true
    }
    $load = {
        $ref = Get-GbRef $url.Text
        if (-not $ref) { $info.Text = 'That is not a GameBanana mod link (it should look like https://gamebanana.com/mods/123456).'; return }
        $info.Text = 'Loading…'; $d.Cursor = 'WaitCursor'; $d.Refresh()
        try { & $fill (Get-GbInfo $ref.Model $ref.GbId 0) } catch { $info.Text = "Could not load the page: $_" } finally { $d.Cursor = 'Default' }
    }
    $fetch.Add_Click($load)
    $url.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $load } })
    $open.Add_Click({ $ref = Get-GbRef $url.Text; if ($ref) { Start-Process (Get-GbUrl $ref.Model $ref.GbId) } else { Start-Process "https://gamebanana.com/search?_sModelName=Mod&_idGameRow=$GbGameId&_sSearchString=$([uri]::EscapeDataString((Get-BaseName $main)))" } })
    $find.Add_Click({
        $info.Text = 'Searching GameBanana…'; $d.Cursor = 'WaitCursor'; $d.Refresh()
        try {
            $r = Find-ModPage $main $st.Names
            if ($r.Sure) { & $fill $r.Info; $info.Text = "Found (your downloaded file is on this page): " + $info.Text; return }
            if ($r.Likely) { & $fill $r.Info; $info.Text = "Best match (name + hero) - check the files below look right: " + $info.Text; return }
            if (-not $r.Cands.Count) { $info.Text = 'Nothing found. Open GameBanana, find the mod and paste its link.'; return }
            $info.Text = 'Not sure which one it is - pick from the list (best matches first):'
            $menu = New-Object Windows.Forms.ContextMenuStrip; $menu.ShowImageMargin = $false; $menu.BackColor = $G::Raised; $menu.ForeColor = $G::Text
            foreach ($c in @($r.Cands | Select-Object -First 12)) {
                $it = $menu.Items.Add("$($c.Name)   ·   by $($c.By)"); $it.Tag = $c
                $it.Add_Click({ $url.Text = Get-GbUrl $this.Tag.Model $this.Tag.GbId; & $load })
            }
            $menu.Show($find, (New-Object Drawing.Point(0, $find.Height)))
        } catch { $info.Text = "Search failed: $_" } finally { $d.Cursor = 'Default' }
    })
    $doSave = {
        if (-not $st.Info) { return }
        $rows = @(foreach ($r in $st.Rows) { @{ Mod = $r.Mod; Index = $r.Index; File = $st.Opts[$r.Combo.SelectedIndex]; Role = @($RoleNames.Keys)[$r.RoleBox.SelectedIndex] } })
        Set-ModLinks $st.Info $rows
        $d.DialogResult = 'OK'; $d.Close()
    }
    $save.Add_Click($doSave)
    $saveChk.Add_Click({ $st.Check = $true; & $doSave })
    $unlink.Add_Click({
        $a = Get-Sources; foreach ($mm in $fam) { $a.Remove($mm.Id) }; Save-Sources $a
        $d.DialogResult = 'OK'; $d.Close()
    })
    $d.Controls.AddRange(@($lab, $url, $fetch, $find, $open, $info, $head, $panel, $head2, $lv, $unlink, $cancel, $saveChk, $save))
    $d.Add_Shown({
        $s0 = @($fam | ForEach-Object { $all[$_.Id] } | Where-Object { $_ })[0]
        if ($s0) { $url.Text = Get-GbUrl $s0.Model $s0.GbId; & $load }
        else { $url.Focus() }
    })
    $res = $d.ShowDialog($form); $d.Dispose()
    if ($res -eq 'OK') {
        $note.Text = "✓  Source saved: $(Get-BaseName $main)"; $note.ForeColor = $G::Hex('#89D185')
        if ($st.Check) { Show-ModUpdates @($fam | ForEach-Object { $_.Id }) }
    }
}

# ---------- Aken: uuendused ----------
function Show-ModUpdates($onlyIds) {
    if ($script:AddBusy) { return }
    $script:AddBusy = $true; $updBtn.Enabled = $false
    $all = Get-Sources
    $ids = @($all.Keys | Where-Object { $ById[$_] -and (-not $onlyIds -or $onlyIds -contains $_) })
    $st = @{ Queue = (New-Object Collections.ArrayList); Busy = $false; Closing = $false; Total = 0; Done = 0; Changed = $false; Updates = 0 }
    # üks päring lehe kohta (mitu modi võivad olla samalt lehelt: alt, lisa)
    $pages = [ordered]@{}
    foreach ($i in $ids) { $k = "$($all[$i].Model)/$($all[$i].GbId)"; if (-not $pages.Contains($k)) { $pages[$k] = @() }; $pages[$k] += $i }
    foreach ($k in $pages.Keys) { [void]$st.Queue.Add(@{ Key = $k; Ids = $pages[$k] }) }
    $st.Total = $st.Queue.Count

    $d = New-Object Windows.Forms.Form
    $d.Text = 'Mod updates'; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; $d.StartPosition = 'CenterParent'; Enable-DialogMinimize $d
    $d.ClientSize = New-Object Drawing.Size(980, 660); $d.MinimumSize = New-Object Drawing.Size(720, 480)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $hdr = New-DialogHeader $d 'Mod updates' "Looking up $($ids.Count) linked mod(s) on GameBanana"
    $lab = New-Object DlUi.Banner
    $lab.Location = New-Object Drawing.Point(16, 74); $lab.Size = New-Object Drawing.Size(948, 46); $lab.Anchor = 'Top, Left, Right'
    $lab.Font = $FontChip; $lab.Kind = 0; $lab.Text = 'Checking GameBanana…'
    $bar = New-Object DlUi.Bar
    $bar.Location = New-Object Drawing.Point(16, 130); $bar.Size = New-Object Drawing.Size(948, 8); $bar.Anchor = 'Top, Left, Right'; $bar.Maximum = [Math]::Max(1, $st.Total)
    $sub = New-Object Windows.Forms.Label
    $sub.AutoSize = $false; $sub.Size = New-Object Drawing.Size(948, 20); $sub.Anchor = 'Top, Left, Right'; $sub.AutoEllipsis = $true; $sub.UseMnemonic = $false
    $sub.ForeColor = $DlgMuted; $sub.Location = New-Object Drawing.Point(16, 144)
    $noLink = @($Mods | Where-Object { -not $all.ContainsKey($_.Id) -and -not ($_.Parent -and $all.ContainsKey($_.Parent)) }).Count
    $sub.Text = if ($onlyIds) { '' } else { "$($ids.Count) mod(s) have a source link. $noLink without: right-click a mod -> Source & updates…" }
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true; $lv.ShowItemToolTips = $true
    $lv.Location = New-Object Drawing.Point(16, 170); $lv.Size = New-Object Drawing.Size(948, 356); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('Status', 118), @('Mod', 220), @('Newest file on GameBanana', 290), @('What it means', 300))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    # rühmad: mida teha tuleb, on üleval
    $grp = [ordered]@{}
    foreach ($gdef in @(
        @('update', 'Updates - a newer version is on GameBanana (ticked = will be updated)'),
        @('maybe', 'Maybe updates - the app is not sure, tick them yourself if you want'),
        @('new', 'Optional extras on the page - tick to add them'),
        @('problem', 'Problems'),
        @('done', 'Done'),
        @('ok', 'Up to date - nothing to do'))) {
        $gg = New-Object Windows.Forms.ListViewGroup($gdef[0], $gdef[1]); [void]$lv.Groups.Add($gg); $grp[$gdef[0]] = $gg
    }
    # valitud rea kogu tekst (veergudes lõigatakse ära)
    $det = New-Object Windows.Forms.Label
    $det.AutoSize = $false; $det.Location = New-Object Drawing.Point(16, 532); $det.Size = New-Object Drawing.Size(948, 66); $det.Anchor = 'Bottom, Left, Right'
    $det.BackColor = $G::Panel; $det.ForeColor = $G::Text; $det.Font = $FontChip; $det.BorderStyle = 'FixedSingle'; $det.UseMnemonic = $false
    $det.Padding = New-Object Windows.Forms.Padding(8, 5, 8, 5); $det.Text = 'Click a row to see all of its text here.'
    [DlUi.ListStyle]::Apply($lv, 26)
    # veerud jagavad kogu laiuse (staatus fikseeritud, ülejäänu protsentides) - midagi ei jää akna taha
    $fitCols = { $w = $lv.ClientSize.Width - 112 - 4; if ($w -gt 300) { $lv.Columns[0].Width = 112; $lv.Columns[1].Width = [int]($w * 0.22); $lv.Columns[2].Width = [int]($w * 0.33); $lv.Columns[3].Width = $w - $lv.Columns[1].Width - $lv.Columns[2].Width } }
    $lv.Add_Resize($fitCols)
    $lv.Add_SelectedIndexChanged({
        if (-not $lv.SelectedItems.Count) { return }
        $it = $lv.SelectedItems[0]
        $det.Text = "$($it.Text)   ·   $($it.SubItems[1].Text)`nOn the page: $($it.SubItems[2].Text)`n$($it.SubItems[3].Text)"
    })
    $go = New-Pill 'Update checked' $true; $go.FitWidth(22, 36); $go.Anchor = 'Bottom, Right'; $go.Enabled = $false
    $close = New-Pill 'Close' $false; $close.FitWidth(18, 36); $close.Anchor = 'Bottom, Right'
    $close.Location = New-Object Drawing.Point((964 - $close.Width), 610)
    $go.Location = New-Object Drawing.Point(($close.Left - $go.Width - 10), 610)
    $close.Add_Click({ $d.Close() })
    $hint = New-Object Windows.Forms.Label
    $hint.AutoSize = $true; $hint.ForeColor = $DlgMuted; $hint.Anchor = 'Bottom, Left'; $hint.Location = New-Object Drawing.Point(16, 620)
    $hint.Text = 'Updating replaces the old version in the same place (stays on/off). Right-click a row: open the page or hide a file.'

    $addRow = {
        param($x)
        $m = $ById[$x.Id]
        $mn = if ($m) { $m.Name } else { $x.Id }
        $row = New-Object Windows.Forms.ListViewItem('')
        [void]$row.SubItems.Add($mn); [void]$row.SubItems.Add(''); [void]$row.SubItems.Add('')
        switch ($x.Kind) {
            'update' {
                $new = "$($x.New.Name)  ($(Format-GbDate $x.New.Date), $(Format-Size $x.New.Size))"
                $row.SubItems[2].Text = $new
                if ($x.Sure) {
                    $row.Text = '⟳ Update'; $row.Group = $grp['update']; $row.Checked = $true
                    $row.SubItems[3].Text = "Newer. Yours is from $(Format-GbDate $x.Link.Date)."
                } elseif (-not $x.Link.File) {
                    $row.Text = '? Update'; $row.Group = $grp['maybe']
                    $row.SubItems[3].Text = "Probably newer - your file is gone from the page. Safe to update."
                } else {
                    $row.Text = '? Update'; $row.Group = $grp['maybe']
                    $row.SubItems[3].Text = "Probably newer - file name changed. Open the page to check."
                }
                $row.ToolTipText = "$($x.New.Desc)"
                $row.ForeColor = [DlUi.G]::Fg('#1F5F24')
                $st.Updates++
            }
            'new' {
                $row.Text = if ($x.Role -eq 'addon') { '+ Add-on' } else { '+ Other version' }
                $row.Group = $grp['new']
                $row.SubItems[2].Text = "$($x.New.Name)  ($(Format-GbDate $x.New.Date), $(Format-Size $x.New.Size))" + $(if ($x.New.Desc) { " - $($x.New.Desc)" } else { '' })
                $row.SubItems[3].Text = if ($x.Role -eq 'addon') { 'Extra for this mod. Tick to add.' } else { 'Another version (one on at a time). Tick to add.' }
                $row.ToolTipText = $x.New.Desc
                $row.ForeColor = [DlUi.G]::Fg('#6E4A08')
            }
            'nosucc' {
                $row.Text = '! Missing'; $row.Group = $grp['problem']
                $row.SubItems[2].Text = "(your file $($x.Link.Name) was removed)"
                $row.SubItems[3].Text = 'Your file was removed. Right-click -> Source & updates to pick.'
                $row.ForeColor = [DlUi.G]::Fg('#8E2A20')
            }
            'gone' {
                Set-PageGone $x.Id $x.Info.Url $true
                $row.Text = '✕ Page gone'; $row.Group = $grp['problem']; $row.SubItems[2].Text = $x.Info.Url
                $row.SubItems[3].Text = 'Page removed. Your mod still works, no updates.'
                $row.ForeColor = [DlUi.G]::Fg('#8E2A20')
            }
            'error' {
                $row.Text = '! Error'; $row.Group = $grp['problem']; $row.SubItems[2].Text = $x.Url
                $row.SubItems[3].Text = "Could not check: $($x.Err)"; $row.ForeColor = [DlUi.G]::Fg('#8E2A20')
            }
            default {
                Set-PageGone $x.Id $null $false
                $row.Text = '✓ Up to date'; $row.Group = $grp['ok']; $row.SubItems[2].Text = "$($x.Info.Name)"
                $row.SubItems[3].Text = "Newest already (page changed $(Format-GbDate $x.Info.Updated))."; $row.ForeColor = [DlUi.G]::Text
            }
        }
        $row.Tag = $x
        [void]$lv.Items.Add($row)
    }
    $updateGo = {
        $n = @($lv.Items | Where-Object { $_.Checked -and $_.Tag.Kind -in 'update', 'new' -and -not $_.Tag.Done }).Count
        $go.Text = "Update checked ($n)"; $go.FitWidth(22, 36); $go.Left = $close.Left - $go.Width - 10
        $go.Enabled = ($n -gt 0 -and -not $st.Busy -and $st.Done -ge $st.Total)
    }
    $lv.Add_ItemChecked({ & $updateGo })
    $lv.Add_ItemCheck({ $t = $lv.Items[$_.Index].Tag; if ($t.Done -or $t.Kind -notin 'update', 'new') { $_.NewValue = $_.CurrentValue } })

    $menu = New-Object Windows.Forms.ContextMenuStrip; $menu.ShowImageMargin = $false; $menu.BackColor = $G::Raised; $menu.ForeColor = $G::Text
    $miOpen = $menu.Items.Add('Open the page'); $miIgn = $menu.Items.Add("Ignore this file (don't show again)"); $miSrc = $menu.Items.Add('Source & updates…')
    $lv.ContextMenuStrip = $menu
    $menu.Add_Opening({
        if (-not $lv.SelectedItems.Count) { $_.Cancel = $true; return }
        $t = $lv.SelectedItems[0].Tag
        $miIgn.Visible = ($t.Kind -in 'new', 'update' -and -not $t.Done)
    })
    $miOpen.Add_Click({ $t = $lv.SelectedItems[0].Tag; $u = if ($t.Info) { $t.Info.Url } elseif ($t.Url) { $t.Url } else { $null }; if ($u) { Start-Process $u } })
    $miIgn.Add_Click({
        $row = $lv.SelectedItems[0]; $t = $row.Tag
        $a = Get-Sources; if ($a[$t.Id]) { $a[$t.Id].Ignore = @($a[$t.Id].Ignore) + $t.New.Id; Save-Sources $a }
        $lv.Items.Remove($row); & $updateGo
    })
    $miSrc.Add_Click({ $t = $lv.SelectedItems[0].Tag; $st.Src = $t.Id; $d.Close() })

    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 60
    $timer.Add_Tick({
        if ($st.Busy -or $st.Closing) { return }
        if (-not $st.Queue.Count) {
            $timer.Stop(); $bar.Value = $bar.Maximum
            $probs = @($lv.Items | Where-Object { $_.Tag.Kind -in 'nosucc', 'gone', 'error' }).Count
            if ($st.Updates) { $lab.Kind = 2; $lab.Text = "Done - $($st.Updates) mod(s) can be updated. The ticked ones are updated when you press 'Update checked'." }
            elseif ($probs) { $lab.Kind = 2; $lab.Text = "Done - no updates, but $probs mod(s) have a problem (see Problems)." }
            elseif ($st.Total) { $lab.Kind = 1; $lab.Text = 'Done - all your linked mods are up to date. Nothing to do.' }
            else { $lab.Kind = 2; $lab.Text = 'No mod has a source link yet. Right-click a mod -> Source & updates…' }
            $hdr.Sub.Text = "Finished: $($ids.Count) linked mod(s) checked"
            [DlUi.Notify]::Done($form, [bool]($st.Updates -or $probs))
            & $updateGo; return
        }
        $st.Busy = $true
        $job = $st.Queue[0]; $st.Queue.RemoveAt(0)
        $src0 = $all[$job.Ids[0]]
        $sub.Text = "$($src0.Title)  ·  $(Get-GbUrl $src0.Model $src0.GbId)"
        try {
            $inf = Get-GbInfo $src0.Model $src0.GbId 10
            foreach ($i in $job.Ids) { foreach ($x in (Find-SourceUpdates $i $all[$i] $inf)) { if (-not $st.Closing) { & $addRow $x } } }
        } catch {
            foreach ($i in $job.Ids) { if (-not $st.Closing) { & $addRow @{ Kind = 'error'; Id = $i; Url = (Get-GbUrl $src0.Model $src0.GbId); Err = "$_" } } }
        }
        $st.Done++
        if (-not $st.Closing) { $bar.Value = [Math]::Min($bar.Maximum, $st.Done); $lab.Text = "Checking GameBanana… $($st.Done) / $($st.Total)" }
        $st.Busy = $false
    })

    $go.Add_Click({
        $todo = @($lv.Items | Where-Object { $_.Checked -and $_.Tag.Kind -in 'update', 'new' -and -not $_.Tag.Done })
        if (-not $todo.Count) { return }
        $st.Busy = $true; $go.Enabled = $false; $close.Enabled = $false; $d.Cursor = 'WaitCursor'
        $ok = 0; $bad = 0
        $status = { param($t) $sub.Text = $t; $sub.Refresh(); [Windows.Forms.Application]::DoEvents() }
        foreach ($row in $todo) {
            $x = $row.Tag
            try {
                if ($x.Kind -eq 'update') {
                    $log = Invoke-SourceUpdate $x $status
                    $row.Text = '✓ Updated'; $row.SubItems[3].Text = (@($log) -join ' · '); $row.ToolTipText = (@($log) -join "`n")
                } else {
                    $res = Invoke-SourceAdd $x $status
                    $row.Text = '✓ Added'; $row.SubItems[3].Text = "Added as '$($res.Name)' (in New, off)"
                }
                $row.Checked = $false; $x.Done = $true; $row.ForeColor = [DlUi.G]::Fg('#1F5F24'); $row.Group = $grp['done']; $ok++; $st.Changed = $true
            } catch {
                $row.Text = '✕ Failed'; $row.SubItems[3].Text = "$_"; $row.ToolTipText = "$_"; $bad++
            }
        }
        $d.Cursor = 'Default'; $close.Enabled = $true; $st.Busy = $false
        $lab.Kind = $(if ($bad) { 3 } else { 1 })
        $lab.Text = "Updated $ok mod(s)" + $(if ($bad) { ", $bad failed - click the row to see why" } else { '. Old versions were deleted.' })
        [DlUi.Notify]::Done($form, [bool]$bad)
        $sub.Text = "New archives are in $ArchiveDir. Updated mods keep their place and on/off state."
        & $updateGo
    })

    $d.Add_Shown({ & $fitCols; $d.Refresh(); $timer.Start() })
    $d.Add_FormClosing({ $st.Closing = $true; $timer.Stop() })
    $d.Controls.AddRange(@($lab, $bar, $sub, $lv, $det, $hint, $go, $close))
    $wa = [Windows.Forms.Screen]::FromControl($form).WorkingArea
    $d.ClientSize = New-Object Drawing.Size([Math]::Min(1240, $wa.Width - 60), [Math]::Min(700, $wa.Height - 60))
    try { [void]$d.ShowDialog($form) }
    finally {
        $timer.Dispose()
        $left = @($lv.Items | Where-Object { $_.Tag.Kind -eq 'update' -and -not $_.Tag.Done }).Count
        $d.Dispose()
        $form.Cursor = 'Default'
        if ($script:GoneChanged) { $script:GoneChanged = $false; Build-Tabs }
        $script:AddBusy = $false; $updBtn.Enabled = $true
    }
    if (-not $onlyIds) { Set-UpdateCount $left }
    if ($st.Changed) {
        Build-Tabs
        $note.Text = '✓  Updates installed'; $note.ForeColor = $G::Hex('#89D185')
    } else { Update-Boxes }
    if ($st.Src) { Show-ModSource $st.Src }
}

# ---------- Päise nupp + taustakontroll käivitamisel ----------
$updBtn = New-Pill '⟳  Updates' $false
$updBtn.Font = $FontChip; $updBtn.Dark = $Deco; $updBtn.FitWidth(16, 36)
$header.Controls.Add($updBtn)
$updBtn.Add_Click({ if ($SelMode -eq 'updates') { Set-SelectMode $null } elseif (Show-Intro 'updates') { Set-SelectMode 'updates' } })   # valikurežiim (kustutamine.ps1)
$UpdTip = New-Object Windows.Forms.ToolTip
$UpdTip.SetToolTip($updBtn, 'Check GameBanana for new versions of your mods (mods need a source link: right-click -> Source & updates…)')

function Set-UpdateCount([int]$n) {
    $script:UpdCount = $n
    $updBtn.Text = if ($n) { "⟳  Updates ($n)" } else { '⟳  Updates' }
    $updBtn.Primary = ($n -gt 0)
    $updBtn.FitWidth(16, 36); $updBtn.Invalidate()
    Place-Right
}

# Käivitamisel taustal (aken ei oota): üks leht korraga, tulemus nupule
function Start-BackgroundUpdateCheck {
    $all = Get-Sources
    if (-not $all.Count) { return }
    $pages = [ordered]@{}
    foreach ($i in $all.Keys) { if (-not $ById[$i]) { continue }; $k = "$($all[$i].Model)/$($all[$i].GbId)"; if (-not $pages.Contains($k)) { $pages[$k] = @() }; $pages[$k] += $i }
    $bg = @{ Queue = [Collections.ArrayList]@($pages.Keys); Pages = $pages; All = $all; Cur = $null; Count = 0 }
    $script:BgUpd = $bg
    $t = New-Object Windows.Forms.Timer; $t.Interval = 150
    $t.Add_Tick({
        $bg = $script:BgUpd
        if ($bg.Cur) {
            if (-not $bg.Cur.Task.IsCompleted) { return }
            try {
                $inf = Complete-GbPage $bg.Cur
                foreach ($i in $bg.Pages[$bg.Key]) { foreach ($x in (Find-SourceUpdates $i $bg.All[$i] $inf)) { if ($x.Kind -eq 'update') { $bg.Count++ } } }
            } catch {}
            $bg.Cur = $null
        }
        if (-not $bg.Queue.Count) { $this.Stop(); $this.Dispose(); if (-not $script:AddBusy) { Set-UpdateCount $bg.Count }; return }
        $bg.Key = $bg.Queue[0]; $bg.Queue.RemoveAt(0)
        $s = $bg.All[$bg.Pages[$bg.Key][0]]
        try { $bg.Cur = Start-GbPage $s.Model $s.GbId } catch { $bg.Cur = $null }
    })
    $t.Start()
}
if (-not $env:DLTEST_NOUPD) { $form.Add_Shown({ Start-BackgroundUpdateCheck }) }

# ---------- Paremklõpsu menüü ----------
$miSource = New-Object Windows.Forms.ToolStripMenuItem 'Source & updates…'
$ModMenu.Items.Insert($ModMenu.Items.IndexOf($miParts) + 1, $miSource)
$miSource.Add_Click({ if ($script:MenuId) { $had = (Get-Sources).ContainsKey($script:MenuId); $script:GoneChanged = $false; Show-ModSource $script:MenuId; if ($script:GoneChanged -or $had -ne (Get-Sources).ContainsKey($script:MenuId)) { $script:GoneChanged = $false; Build-Tabs } } })
$ModMenu.Add_Opening({
    if (-not $script:MenuId) { return }
    $a = Get-Sources; $m = $ById[$script:MenuId]
    $k = if ($m -and $m.Parent -and -not $a.ContainsKey($m.Id)) { $m.Parent } else { $script:MenuId }
    $miSource.Text = if ($a.ContainsKey($k)) { 'Source & updates…  (linked)' } else { 'Source & updates…  (add link)' }
})

# ---------- Lisamine lingist ----------
# "+ Add mod" -> "From a link…", lingi lohistamine aknale või Ctrl+V aknas.
# GameBanana mod/heli, Deadlock Mod Manageri id/link (nende kataloog = GameBanana: api.deadlockmods.app annab
# GameBanana aadressi) või otselink failile. GameBanana modid saavad kohe allika lingi (uuendused).
function Resolve-ModLink($text) {
    $t = ([string]$text).Trim()
    if ($t -match 'gamebanana\.com/') { $r = Get-GbRef $t; if ($r) { return @{ Kind = 'gb'; Model = $r.Model; GbId = $r.GbId } } }
    $id = $null
    if ($t -match 'deadlockmods\.(?:app|com)/\D*(\d{4,8})') { $id = $Matches[1] } elseif ($t -match '^\d{4,8}$') { $id = $t }
    if ($id) {
        try {
            $tk = Start-GbString "https://api.deadlockmods.app/api/v2/mods/$id"; Wait-Task $tk
            $r = Get-GbRef ($tk.Result | ConvertFrom-Json).remoteUrl
            if ($r) { return @{ Kind = 'gb'; Model = $r.Model; GbId = $r.GbId } }
        } catch {}
        return @{ Kind = 'gb'; Model = 'Mod'; GbId = [long]$id }
    }
    if ($t -match '^https?://\S+$') { return @{ Kind = 'direct'; Url = $t } }
    return $null
}

# Lehe failide valik (mitu = mass add). Tagastab valitud failid või $null.
function Show-PickFiles($inf) {
    $cur = @($inf.Cur)
    $d = New-Object Windows.Forms.Form
    $d.Text = "Download: $($inf.Name)"; $d.BackColor = $DlgBg; $d.ForeColor = $DlgText; $d.Font = $FontUi
    $d.FormBorderStyle = 'Sizable'; Enable-DialogMinimize $d; $d.StartPosition = 'CenterParent'
    $d.ClientSize = New-Object Drawing.Size(760, 360); $d.MinimumSize = New-Object Drawing.Size(520, 260)
    $d.Add_HandleCreated({ $v = 1; [void][DlToggle.Native]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4) })
    $lab = New-Object Windows.Forms.Label
    $lab.Text = 'Tick the file(s) to add. Main = the mod, Alt version = a variant (pick one), Add-on = extra on top.'
    $lab.AutoSize = $true; $lab.ForeColor = $DlgMuted; $lab.Location = New-Object Drawing.Point(16, 12)
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true; $lv.ShowItemToolTips = $true
    $lv.Location = New-Object Drawing.Point(16, 38); $lv.Size = New-Object Drawing.Size(728, 262); $lv.Anchor = 'Top, Bottom, Left, Right'
    $lv.BackColor = $G::Panel; $lv.ForeColor = $G::Text; $lv.BorderStyle = 'FixedSingle'; $lv.Font = $FontChip
    foreach ($c in @(@('File', 250), @('Date', 90), @('Size', 80), @('Looks like', 90), @('Description', 200))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $best = @($cur | Sort-Object @{ e = { if ((Get-RoleGuess $_ $cur) -eq 'main') { 0 } else { 1 } } }, @{ e = { - $_.Date } })[0]
    foreach ($f in $cur) {
        $it = New-Object Windows.Forms.ListViewItem($f.Name)
        [void]$it.SubItems.Add((Format-GbDate $f.Date)); [void]$it.SubItems.Add((Format-Size $f.Size))
        [void]$it.SubItems.Add($RoleNames[(Get-RoleGuess $f $cur)]); [void]$it.SubItems.Add($f.Desc)
        $it.ToolTipText = $f.Desc; $it.Tag = $f; $it.Checked = ($f -eq $best)
        [void]$lv.Items.Add($it)
    }
    $ok = New-Pill 'Download & add' $true; $ok.FitWidth(20, 34); $ok.Anchor = 'Bottom, Right'; $ok.Location = New-Object Drawing.Point((744 - $ok.Width), 312)
    $no = New-Pill 'Cancel' $false; $no.FitWidth(16, 34); $no.Anchor = 'Bottom, Right'; $no.Location = New-Object Drawing.Point(($ok.Left - $no.Width - 10), 312)
    $ok.Add_Click({ $d.DialogResult = 'OK'; $d.Close() }); $no.Add_Click({ $d.DialogResult = 'Cancel'; $d.Close() })
    $d.Controls.AddRange(@($lab, $lv, $ok, $no))
    $res = $d.ShowDialog($form)
    $sel = @($lv.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    $d.Dispose()
    if ($res -ne 'OK' -or -not $sel.Count) { return $null }
    return , $sel
}

# Otselink: fail alla, tüüp päisest / URL-ist / faili algusest
function Save-UrlFile($url) {
    New-Item -ItemType Directory -Force $ArchiveDir | Out-Null
    $tmp = Join-Path $ArchiveDir ('download_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.part')
    try {
        $dl = [DlDownload]::Start($url, $tmp)
        Wait-Task $dl.Task { Set-Busy "Downloading: $(Format-Size $dl.Done)" }
    } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw "Download failed: $_" }
    $name = ([string]$dl.Name -replace '[\\/:*?"<>|]', '_').Trim()
    $ext = [IO.Path]::GetExtension($name).ToLower()
    if ($ext -ne '.vpk' -and $ArchiveExts -notcontains $ext) {
        $b = New-Object byte[] 6; $fs = [IO.File]::OpenRead($tmp); [void]$fs.Read($b, 0, 6); $fs.Dispose()
        $ext = if ($b[0] -eq 0x50 -and $b[1] -eq 0x4B) { '.zip' } elseif ($b[0] -eq 0x52 -and $b[1] -eq 0x61 -and $b[2] -eq 0x72) { '.rar' }
               elseif ($b[0] -eq 0x37 -and $b[1] -eq 0x7A) { '.7z' } elseif ($b[0] -eq 0x1F -and $b[1] -eq 0x8B) { '.gz' } elseif ($b[0] -eq 0xFD -and $b[1] -eq 0x37 -and $b[2] -eq 0x7A) { '.xz' } elseif ($b[0] -eq 0x42 -and $b[1] -eq 0x5A -and $b[2] -eq 0x68) { '.bz2' } elseif ($b[0] -eq 0x34 -and $b[1] -eq 0x12 -and $b[2] -eq 0xAA -and $b[3] -eq 0x55) { '.vpk' } else { $null }
        if (-not $ext) { Remove-Item -LiteralPath $tmp -Force; throw 'The link did not give a mod file (.zip .rar .7z .tar.gz .vpk ...) - probably a web page. Use the direct download link.' }
        $base = [IO.Path]::GetFileNameWithoutExtension($name); if (-not $base) { $base = 'download_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
        $name = $base + $ext
    }
    $dst = Join-Path $ArchiveDir $name; $n = 2
    while (Test-Path -LiteralPath $dst) { $dst = Join-Path $ArchiveDir ([IO.Path]::GetFileNameWithoutExtension($name) + "_$n" + [IO.Path]::GetExtension($name)); $n++ }
    Move-Item -LiteralPath $tmp -Destination $dst
    return $dst
}

function Add-ModFromLink($text) {
    if ($script:AddBusy) { return }
    if (-not $text) {
        $clip = ''; try { $clip = [Windows.Forms.Clipboard]::GetText().Trim() } catch {}
        $text = Show-RenameDialog $(if ($clip -match '^https?://\S+$') { $clip } else { '' }) 'Add mod from a link' 'GameBanana or Deadlock Mod Manager link, or a direct link to a mod file (.zip .rar .7z .vpk .tar.gz ...)'
        if (-not $text) { return }
    }
    $files = @(); $links = @(); $fresh = @(); $inf = $null
    try {
        Set-Busy 'Reading the link…'
        $ref = Resolve-ModLink $text
        if (-not $ref) { throw "That is not a link: $text" }
        if ($ref.Kind -eq 'gb') {
            $inf = Get-GbInfo $ref.Model $ref.GbId 0
            if ($inf.Gone -or -not @($inf.Cur).Count) { throw "The page was removed or has no files: $($inf.Url)" }
            $form.Cursor = 'Default'; Update-Boxes
            $pick = Show-PickFiles $inf
            if (-not $pick) { return }
            foreach ($c in $pick) {
                $was = Test-Path -LiteralPath (Join-Path $ArchiveDir $c.Name)
                $f = Save-GbFile $c { param($x) Set-Busy $x }
                $files += $f; $links += , @{ File = $f; C = $c }; if (-not $was) { $fresh += $f }
            }
        } else {
            $f = Save-UrlFile $ref.Url; $files += $f; $fresh += $f
        }
        $before = @(Get-AddedMods | ForEach-Object { $_.Id })
        $form.Cursor = 'Default'; Update-Boxes
        Add-ModFiles $files
        $after = @(Get-AddedMods | Where-Object { $before -notcontains $_.Id })
        # allika link kohe külge (uuenduste kontroll)
        if ($inf) {
            foreach ($a in $after) {
                $l = @($links | Where-Object { [IO.Path]::GetFileName($_.File) -ieq [string]$a.Source })[0]
                $m = $ById[$a.Id]
                if (-not $l -or -not $m) { continue }
                $role = Get-RoleGuess $l.C $inf.Cur; if ($m.Parent -and $role -eq 'main') { $role = 'addon' }
                Set-ModLinks $inf @(for ($i = 0; $i -lt $m.Files.Count; $i++) { @{ Mod = $m; Index = $i; File = $l.C; Role = $role } })
                # pilt GameBananast (pildid.ps1), kui modil veel pole
                if (-not $m.Parent -and (Get-Command Save-ModPictureFromGb -ErrorAction SilentlyContinue) -and -not (Get-ModPicture $m.Id)) { try { Save-ModPictureFromGb $m.Id $inf; Build-Tabs } catch {} }
            }
        }
        # lisamata jäänud allalaadimised ära
        foreach ($f in $fresh) {
            if (-not @($after | Where-Object { [string]$_.Source -ieq [IO.Path]::GetFileName($f) }).Count) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        $form.Cursor = 'Default'
        [Windows.Forms.MessageBox]::Show($form, "Adding from the link failed:`n$_", 'Deadlock Mods') | Out-Null
        Update-Boxes
    } finally { $form.Cursor = 'Default' }
}

# "+ Add mod" menüü: failid või link
$AddMenu = New-Object Windows.Forms.ContextMenuStrip
$AddMenu.ShowImageMargin = $false; $AddMenu.BackColor = $G::Raised; $AddMenu.ForeColor = $G::Text; $AddMenu.Font = $FontUi
$miAddFiles = $AddMenu.Items.Add('From files on this PC…   (pick one or many: Ctrl+click / Shift+click)')
$miAddLink = $AddMenu.Items.Add('From a link…   (GameBanana, Deadlock Mod Manager, direct link)')
$miAddFiles.Add_Click({ Start-AddMod })
$miAddLink.Add_Click({ Add-ModFromLink $null })
function Show-AddMenu { $AddMenu.Show($addBtn, (New-Object Drawing.Point(0, $addBtn.Height))) }
# Ctrl+V aknas (mitte otsingukastis): lõikelaual olev link
$form.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq 'V' -and -not $search.Focused) {
        $t = ''; try { $t = [Windows.Forms.Clipboard]::GetText().Trim() } catch {}
        if ($t -match '^https?://\S+$') { $_.Handled = $true; Add-ModFromLink $t }
    }
})
