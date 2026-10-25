<?php
declare(strict_types=1);

/** Build PikoPe launcher icons (requires PHP GD). Run: php tool/make_pikope_icon.php */

$root = dirname(__DIR__);
$res = $root . '/android/app/src/main/res';
$iconDir = $root . '/assets/icon';

$sources = [
    $root . '/site-pikope.com/assets/pikope_logo.png',
    $iconDir . '/app_icon.jpg',
    $root . '/assets/images/pikope_logo.png',
];

$srcPath = null;
foreach ($sources as $p) {
    if (is_file($p)) {
        $srcPath = $p;
        break;
    }
}
if ($srcPath === null) {
    fwrite(STDERR, "No logo source found.\n");
    exit(1);
}

$logo = loadImage($srcPath);
if ($logo === false) {
    fwrite(STDERR, "Could not load $srcPath\n");
    exit(1);
}
echo "source: $srcPath\n";

$S = 1024;
$bg = imagecreatetruecolor($S, $S);
$col = imagecolorallocate($bg, 30, 30, 33);
imagefilledrectangle($bg, 0, 0, $S, $S, $col);

$full = pasteScaled($bg, $logo, 0.78, true);
savePng($full, $iconDir . '/app_icon.png', $S);

$fgCanvas = imagecreatetruecolor($S, $S);
imagealphablending($fgCanvas, false);
imagesavealpha($fgCanvas, true);
$trans = imagecolorallocatealpha($fgCanvas, 0, 0, 0, 127);
imagefilledrectangle($fgCanvas, 0, 0, $S, $S, $trans);
imagealphablending($fgCanvas, true);
$fg = pasteScaled($fgCanvas, $logo, 0.72, false);
savePng($fg, $iconDir . '/app_icon_foreground.png', $S);

$legacy = roundedLegacy($full);
$mipmaps = ['mdpi' => 48, 'hdpi' => 72, 'xhdpi' => 96, 'xxhdpi' => 144, 'xxxhdpi' => 192];
foreach ($mipmaps as $folder => $size) {
    savePng($legacy, "$res/mipmap-$folder/ic_launcher.png", $size);
}
$drawables = ['mdpi' => 108, 'hdpi' => 162, 'xhdpi' => 216, 'xxhdpi' => 324, 'xxxhdpi' => 432];
foreach ($drawables as $folder => $size) {
    savePng($fg, "$res/drawable-$folder/ic_launcher_foreground.png", $size);
}

imagedestroy($logo);
imagedestroy($bg);
imagedestroy($full);
imagedestroy($fgCanvas);
imagedestroy($fg);
imagedestroy($legacy);

echo "PikoPe launcher icons updated.\n";

function loadImage(string $path)
{
    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    return match ($ext) {
        'png' => @imagecreatefrompng($path),
        'jpg', 'jpeg' => @imagecreatefromjpeg($path),
        default => false,
    };
}

/** @param GdImage $canvas */
function pasteScaled($canvas, $logo, float $scale, bool $opaque): GdImage
{
    $S = imagesx($canvas);
    $lw = imagesx($logo);
    $lh = imagesy($logo);
    $target = (int) ($S * $scale);
    $ratio = min($target / $lw, $target / $lh);
    $nw = max(1, (int) round($lw * $ratio));
    $nh = max(1, (int) round($lh * $ratio));
    $scaled = imagecreatetruecolor($nw, $nh);
    if (!$opaque) {
        imagealphablending($scaled, false);
        imagesavealpha($scaled, true);
        $t = imagecolorallocatealpha($scaled, 0, 0, 0, 127);
        imagefilledrectangle($scaled, 0, 0, $nw, $nh, $t);
        imagealphablending($scaled, true);
    }
    imagecopyresampled($scaled, $logo, 0, 0, 0, 0, $nw, $nh, $lw, $lh);
    $x = (int) (($S - $nw) / 2);
    $y = (int) (($S - $nh) / 2);
    imagecopy($canvas, $scaled, $x, $y, 0, 0, $nw, $nh);
    imagedestroy($scaled);
    return $canvas;
}

/** @param GdImage $full */
function roundedLegacy($full): GdImage
{
    $S = imagesx($full);
    $out = imagecreatetruecolor($S, $S);
    imagealphablending($out, false);
    imagesavealpha($out, true);
    $trans = imagecolorallocatealpha($out, 0, 0, 0, 127);
    imagefilledrectangle($out, 0, 0, $S, $S, $trans);
    imagealphablending($out, true);
    imagecopy($out, $full, 0, 0, 0, 0, $S, $S);
    $r = (int) ($S * 0.22);
    for ($y = 0; $y < $S; $y++) {
        for ($x = 0; $x < $S; $x++) {
            if (!insideRoundedRect($x, $y, $S, $S, $r)) {
                imagesetpixel($out, $x, $y, $trans);
            }
        }
    }
    return $out;
}

function insideRoundedRect(int $x, int $y, int $w, int $h, int $r): bool
{
    if ($x >= $r && $x < $w - $r) {
        return true;
    }
    if ($y >= $r && $y < $h - $r) {
        return true;
    }
    $cx = $x < $r ? $r : $w - $r - 1;
    $cy = $y < $r ? $r : $h - $r - 1;
    return ($x - $cx) ** 2 + ($y - $cy) ** 2 <= $r ** 2;
}

function savePng($img, string $path, int $size): void
{
    $dir = dirname($path);
    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }
    if (imagesx($img) !== $size) {
        $out = imagecreatetruecolor($size, $size);
        imagealphablending($out, false);
        imagesavealpha($out, true);
        imagecopyresampled($out, $img, 0, 0, 0, 0, $size, $size, imagesx($img), imagesy($img));
        imagepng($out, $path, 6);
        imagedestroy($out);
        return;
    }
    imagepng($img, $path, 6);
}
