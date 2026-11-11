#!/bin/sh
# Records the README's demo: docs/media/demo.mp4 and demo.gif.
#
#   sh docs/demo/record.sh
#
# It stages the synthetic herdr-core and Rex server (stage.sh), opens a second
# Rex app whose home is the stage, so its sidebar holds only the stage's
# sessions, plays scene.py in it while capturing the window, encodes the
# frames, and takes the stage down. It needs Rex for Mac, herdr-core, ffmpeg,
# python3 and cua-driver (to size the window and click its sidebar), and the
# terminal it runs in needs the Screen Recording permission.
#
# The second Rex app shares your Rex app's settings. Its window comes to the
# front once, when it opens.
set -eu
kit=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$kit/../.." && pwd)
app=${REX_APP:-/Applications/Rex Beta.app}
[ -d "$app" ] || app=/Applications/Rex.app

w=$(sh "$kit/stage.sh")
trap 'sh "$kit/stage.sh" --down "$w"' EXIT
(
  # shellcheck disable=SC1091
  . "$w/env.sh"
  rex --autostart=false new shop -c "$HOME/code/shop" --window zsh --json > "$w/shop.json"
  # The app follows REX_SERVER, and CFFIXED_USER_HOME moves its home to the stage.
  env -u REX_BIN_DIR CFFIXED_USER_HOME="$HOME" /usr/bin/open -n -a "$app"
)
sleep 7
pgrep -n -f "$app/Contents/MacOS/" > "$w/app.pid"

mkdir -p "$w/frames" "$repo_root/docs/media"
python3 "$kit/scene.py" "$w"

fps=10
ffmpeg -loglevel error -y -framerate $fps -i "$w/frames/%05d.png" \
  -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2:color=0x101014" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart \
  "$repo_root/docs/media/demo.mp4"
ffmpeg -loglevel error -y -i "$repo_root/docs/media/demo.mp4" \
  -vf "fps=$fps,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
  "$repo_root/docs/media/demo.gif"
ls -l "$repo_root/docs/media"
