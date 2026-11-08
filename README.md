# Deadlock Mods

Windowsi rakendus [Deadlocki](https://store.steampowered.com/app/1422450/Deadlock/) modide lisamiseks ja sisse/välja lülitamiseks.
A Windows app to add Deadlock mods and turn them on/off.

## ⬇ Allalaadimine / Download

**[Laadi alla uusim versioon / Download the latest version](../../releases/latest)** → `DeadlockMods.zip`

Ära kasuta rohelist "Code" nuppu: Release'i zipis on ka vajalikud tööriistad (Python, Source2Viewer, 7-Zip).
Don't use the green "Code" button: the release zip also contains the needed tools.

## Kasutamine

1. Paki zip lahti kausta, kuhu saad kirjutada (nt Dokumendid – mitte Program Files).
2. Käivita **`Deadlock Mods.cmd`**. Kui Windows hoiatab: "More info" → "Run anyway" (rakendus pole allkirjastatud).
3. Kui üleval on punane rida, vajuta **Enable mods** (mängu faili `gameinfo.gi` lisatakse üks rida, originaal jääb `gameinfo.gi.before_mods`).
4. **+ Add mod**: vali allalaaditud mod (`.zip .rar .7z .vpk .tar.gz …`) või kleebi GameBanana link. Faile võib ka aknale lohistada.
5. Lülita modid sisse/välja ja vajuta **Save** (Deadlock peab olema kinni).

Paremklõps modil: nimeta ümber, eemalda osi (häälread, portreed…), allika link ja uuendused, kustuta.
**Check** vaatab modid üle (vana kaamera, vanad jagatud failid, topeltnumbrid) ja parandab. **Updates** otsib GameBananast uusi versioone.

## Usage

1. Unzip to a folder you can write to (Documents – not Program Files).
2. Run **`Deadlock Mods.cmd`**. If SmartScreen warns: "More info" → "Run anyway".
3. If the top line is red, press **Enable mods** (adds one line to the game's `gameinfo.gi`; the original is kept as `gameinfo.gi.before_mods`).
4. **+ Add mod**: pick a downloaded mod or paste a GameBanana link. Dropping files on the window works too.
5. Turn mods on/off and press **Save** (Deadlock must be closed).

Mods come from [GameBanana](https://gamebanana.com/games/20948). Only cosmetic mods (skins, sounds, UI) – gameplay changes can get you banned.

## Tehniline / Technical

PowerShell 5.1 + Windows Forms (`ui.cs` is compiled at start), nothing to install. Bundled in the release:
Python 3.13 embeddable ([PSF license](https://docs.python.org/3/license.html)),
Source2Viewer CLI ([ValveResourceFormat](https://github.com/ValveResourceFormat/ValveResourceFormat), MIT),
7-Zip ([7-zip.org](https://www.7-zip.org/), LGPL).
