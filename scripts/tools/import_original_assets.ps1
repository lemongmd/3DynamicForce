# Импорт ассетов оригинальной игры (проект Construct 3 от Mace Dev) в assets/original/.
#
# Запуск из корня проекта (PowerShell):
#   powershell -ExecutionPolicy Bypass -File scripts/tools/import_original_assets.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/tools/import_original_assets.ps1 -Source "путь\к\проекту C3"
#
# Что делает:
#   * картинки  -> assets/original/textures/<категория>/<объект>[-<анимация>]-<кадр>.png
#                 (категории — папки objectTypes оригинала; имена в нижнем регистре,
#                 «-animation 1» убрано, пробелы -> «_», кириллическая «с» в «Сolumn» -> латинская);
#   * тайлы трассы -> assets/original/textures/tiles/tile_NN.png (нарезка tilemap.png);
#   * звуки     -> assets/original/sounds/<имя>.wav (Godot не читает .webm; WAV — без затрат на декодирование);
#   * музыка    -> assets/original/music/<имя>.ogg (Ogg Vorbis);
#   * шрифты, иконки -> assets/original/fonts, assets/original/icons.
# Нужен ffmpeg в PATH. Повторный запуск перезаписывает файлы.

param(
    [string]$Source = "DF C3 project",
    [string]$Target = "assets/original"
)

$ErrorActionPreference = "Stop"
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw "ffmpeg не найден в PATH" }
if (-not (Test-Path $Source)) { throw "Нет папки проекта Construct 3: $Source" }

$cyrillicEs = [string][char]0x0441   # «с» в имени объекта «Сolumn»

function Normalize([string]$name) {
    $n = $name.ToLowerInvariant().Replace($cyrillicEs, "c")
    $n = $n.Replace("-animation 1", "")
    return ($n -replace "\s+", "_")
}

# Объект -> категория (папка в objectTypes оригинала).
$category = @{}
Get-ChildItem (Join-Path $Source "objectTypes") -Recurse -File -Filter *.json |
    Where-Object { $_.Name -notlike "*.uistate.json" } |
    ForEach-Object {
        $folder = Split-Path $_.DirectoryName -Leaf
        if ($folder -eq "objectTypes") { $folder = "misc" }
        $category[(Normalize $_.BaseName)] = (Normalize $folder)
    }

# Картинки. Перерисованные вручную (assets/hand_drawn.txt) не перезаписываются.
$handDrawn = @()
$handList = Join-Path $PSScriptRoot "../../assets/hand_drawn.txt"
if (Test-Path $handList) {
    $handDrawn = Get-Content $handList -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() }
}
$images = 0
Get-ChildItem (Join-Path $Source "images") -File -Filter *.png | ForEach-Object {
    $name = Normalize $_.BaseName
    $object = ($name -split "-")[0]
    $cat = $category[$object]
    if (-not $cat) { $cat = "misc" }
    $dir = Join-Path $Target "textures/$cat"
    New-Item -ItemType Directory -Force $dir | Out-Null
    if ($handDrawn -contains "assets/original/textures/$cat/$name.png") { return }
    Copy-Item $_.FullName (Join-Path $dir "$name.png") -Force
    $images++
}
Get-ChildItem (Join-Path $Source "files") -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $dir = Join-Path $Target "textures/misc"
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item $_.FullName (Join-Path $dir (Normalize $_.Name)) -Force
    $images++
}

# Тайлы трассы: tilemap.png (4×6 тайлов по 24 px) -> textures/tiles/tile_NN.png,
# чтобы дорогу и кирпич можно было повторять материалом. Номер — индекс тайла
# в оригинале (0 — кирпич-стена, 2 — дорога, см. CLAUDE.md).
$tileset = Join-Path $Target "textures/main/tilemap.png"
$tilesDir = Join-Path $Target "textures/tiles"
New-Item -ItemType Directory -Force $tilesDir | Out-Null
$tileCount = 0
for ($i = 0; $i -lt 24; $i++) {
    $x = ($i % 4) * 24
    $y = [math]::Floor($i / 4) * 24
    $out = Join-Path $tilesDir ("tile_{0:D2}.png" -f $i)
    & $ffmpeg -hide_banner -loglevel error -y -i $tileset -vf "crop=24:24:${x}:${y}" -pix_fmt rgba $out
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg не смог вырезать тайл $i" }
    $tileCount++
}

# Звуки и музыка.
function Convert-Audio([string]$from, [string]$to, [string[]]$codecArgs) {
    New-Item -ItemType Directory -Force $to | Out-Null
    $count = 0
    Get-ChildItem $from -File -Filter *.webm | ForEach-Object {
        $out = Join-Path $to ((Normalize $_.BaseName) + $codecArgs[0])
        $args = @("-hide_banner", "-loglevel", "error", "-y", "-i", $_.FullName) + $codecArgs[1..($codecArgs.Count - 1)] + @($out)
        & $ffmpeg @args
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg не смог перекодировать $($_.Name)" }
        $count++
    }
    return $count
}
$sounds = Convert-Audio (Join-Path $Source "sounds") (Join-Path $Target "sounds") @(".wav", "-ar", "44100", "-c:a", "pcm_s16le")
$music = Convert-Audio (Join-Path $Source "music") (Join-Path $Target "music") @(".ogg", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5")

# Шрифты и иконки.
foreach ($pair in @(@("fonts", "fonts"), @("icons", "icons"))) {
    $dir = Join-Path $Target $pair[1]
    New-Item -ItemType Directory -Force $dir | Out-Null
    Get-ChildItem (Join-Path $Source $pair[0]) -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $dir (Normalize $_.Name)) -Force
    }
}

Write-Output "images: $images, tiles: $tileCount, sounds: $sounds, music: $music -> $Target"
