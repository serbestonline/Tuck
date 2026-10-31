#!/bin/zsh
# README görsellerini gerçek uygulamadan yeniden üretir: simge, önce/sonra görüntüsü, menü görüntüsü ve GIF'ler.
# Kayıt sırasında Tuck fareyi oynatır ve uygulamaları sırayla öne getirir (yaklaşık 30 saniye); dokunmadan bekle.
# Görüntüye yalnız masaüstü, menü çubuğu ve Tuck girer. Kurulu ve izinleri verilmiş ~/Applications/Tuck.app kullanılır.
#   ./scripts/make_media.sh              → kaydeder ve üretir
#   ./scripts/make_media.sh <klasör>     → o klasördeki tuck/ ve apps/ karelerinden yeniden üretir
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets

if [[ -n "${1:-}" ]]; then
    WORK="$1"
else
    WORK=$(mktemp -d)
    ./build.sh --install >/dev/null
    pkill -x Tuck || true
    sleep 1
    open -n -W ~/Applications/Tuck.app --args --record tuck "$WORK/tuck"
    open -n -W ~/Applications/Tuck.app --args --record apps "$WORK/apps"
    open ~/Applications/Tuck.app
fi

sips -z 512 512 build/AppIcon-1024.png --out assets/icon.png >/dev/null

ffmpeg -y -loglevel error -framerate 12 -i "$WORK/tuck/f%05d.png" \
    -vf "scale=880:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    -loop 0 assets/tuck.gif
# Uygulama değiştirirken yalnız menü çubuğu değişir; sol yarısı büyütülerek gösterilir.
ffmpeg -y -loglevel error -framerate 12 -i "$WORK/apps/f%05d.png" \
    -vf "crop=480:44:0:0,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" \
    -loop 0 assets/apps.gif
# Önce ve sonra: aynı uygulamada Tuck kapalıyken ve açıkken menü çubuğu.
ffmpeg -y -loglevel error -i "$WORK/tuck/f00005.png" -i "$WORK/tuck/f00030.png" \
    -filter_complex "[0]crop=480:44:0:0[a];[1]crop=480:44:0:0[b];[a][b]vstack=inputs=2,scale=960:-1:flags=lanczos" assets/before-after.png
ffmpeg -y -loglevel error -i "$WORK/tuck/f00100.png" -vf "crop=480:620:0:0" assets/menu.png
echo "Görseller assets/ klasöründe"
