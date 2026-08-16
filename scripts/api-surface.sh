#!/usr/bin/env bash
#
# 公開 API サーフェスのスナップショット。
#
# ドライバー層の共通化中、アプリ開発者向けの公開 API を凍結し続けるための門番。
# android-sdk/gradle/api-surface.gradle.kts（apiDump / apiCheck）の iOS 版で、
# 記録するファイルの置き場所も同じ（<module>/api/<Module>.api.swift）。
#
#   scripts/api-surface.sh dump  [module...]   ベースラインを書き出す
#   scripts/api-surface.sh check [module...]   差分があれば失敗する
#
# ## なぜ .swiftinterface なのか
#
# Swift には `-enable-library-evolution` を付けるとコンパイラが
# `.swiftinterface`（モジュールの公開 API そのもの）を吐く仕組みがある。
# 自前でソースを走査するより正確で、しかも
#
#   **@_spi(...) が付いた宣言は .swiftinterface に載らない**（.private.swiftinterface だけに載る）
#
# ので、「アプリ開発者向け API」と「ドライバー実装点」の区別がコンパイラ側で
# 済んでいる。android は @InternalMapConductorApi を自前で読み飛ばす必要が
# あったが、iOS ではその手当てが要らない。
#
# ドライバー実装点には必ず @_spi(MapConductorDriver) を付けること。付け忘れると
# ここに現れて、以後うかつに変えられなくなる。
#
# ## 正規化
#
# 先頭 4 行の `// swift-*` コメントはコンパイラのバージョンとビルドフラグで
# 変わる（マシンごとに違う）ので落とす。それ以外は一切いじらない。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${MAPCONDUCTOR_API_DERIVED_DATA:-${TMPDIR:-/tmp}/mapconductor-api-surface}"
DESTINATION="generic/platform=iOS Simulator"

# module ディレクトリ → .swiftinterface に載るモジュール名。
# ここに無いディレクトリは対象外（ios-maps-sdk は Google 提供のミラーなので入れない）。
MODULES=(
  "ios-sdk-core:MapConductorCore"
  "ios-for-arcgis:MapConductorForArcGIS"
  "ios-for-googlemaps:MapConductorForGoogleMaps"
  "ios-for-here:MapConductorForHERE"
  "ios-for-longdo:MapConductorForLongdo"
  "ios-for-mapbox:MapConductorForMapbox"
  "ios-for-mapkit:MapConductorForMapKit"
  "ios-for-maplibre:MapConductorForMapLibre"
  "ios-for-maptiler:MapConductorForMapTiler"
  # 雛形も対象に入れる。実在の地図 SDK を描かないので見落としやすいが、
  # **雛形が規約に追随できなくなったことを機械的に拾える受け皿がここしか無い**
  # （android 側は :android-for-template:apiCheck が同じ役目を持つ）。
  "ios-for-template:MapConductorForTemplate"
  "ios-for-tomtom:MapConductorForTomTom"
  "ios-geojson-layer:MapConductorGeoJSON"
  "ios-heatmap:MapConductorHeatmap"
  "ios-kml:MapConductorKML"
  "ios-icons:MapConductorIcons"
  "ios-marker-clustering:MapConductorMarkerClustering"
)

usage() {
  echo "usage: scripts/api-surface.sh {dump|check} [module...]" >&2
  exit 2
}

module_name_of() {
  local dir="$1"
  local entry
  for entry in "${MODULES[@]}"; do
    if [ "${entry%%:*}" = "$dir" ]; then
      echo "${entry#*:}"
      return 0
    fi
  done
  return 1
}

scheme_of() {
  # Package.swift の `name:` が SwiftPM のスキーム名になる。
  sed -n 's/^[[:space:]]*name: "\([^"]*\)".*/\1/p' "$ROOT/$1/Package.swift" | head -1
}

# 1 モジュールぶんの公開 API サーフェスを標準出力へ。
generate_surface() {
  local dir="$1"
  local module="$2"
  local scheme
  scheme="$(scheme_of "$dir")"

  ( cd "$ROOT/$dir" && xcodebuild \
      -scheme "$scheme" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA/$dir" \
      BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
      build ) > "$DERIVED_DATA/$dir.log" 2>&1 || {
    echo "  ! ビルドに失敗しました。ログ: $DERIVED_DATA/$dir.log" >&2
    return 1
  }

  local interface
  interface="$(find "$DERIVED_DATA/$dir/Build/Products" \
    -path "*/$module.swiftmodule/arm64-apple-ios-simulator.swiftinterface" \
    -print -quit)"
  if [ -z "$interface" ]; then
    echo "  ! .swiftinterface が見つかりません（BUILD_LIBRARY_FOR_DISTRIBUTION が効いていない）" >&2
    return 1
  fi

  # コンパイラのバージョンとビルドフラグの行だけ落とす。
  grep -v '^// swift-' "$interface"
}

baseline_of() {
  echo "$ROOT/$1/api/$2.api.swift"
}

run() {
  local action="$1"
  shift
  local targets=("$@")
  if [ "${#targets[@]}" -eq 0 ]; then
    local entry
    for entry in "${MODULES[@]}"; do targets+=("${entry%%:*}"); done
  fi

  mkdir -p "$DERIVED_DATA"
  local failed=0
  local dir module baseline actual

  for dir in "${targets[@]}"; do
    if ! module="$(module_name_of "$dir")"; then
      echo "unknown module: $dir" >&2
      failed=1
      continue
    fi
    if [ ! -f "$ROOT/$dir/Package.swift" ]; then
      echo "skip $dir (Package.swift が無い)"
      continue
    fi

    echo "==> $dir ($module)"
    if ! actual="$(generate_surface "$dir" "$module")"; then
      failed=1
      continue
    fi

    baseline="$(baseline_of "$dir" "$module")"
    case "$action" in
      dump)
        mkdir -p "$(dirname "$baseline")"
        printf '%s\n' "$actual" > "$baseline"
        echo "  wrote $(printf '%s\n' "$actual" | wc -l | tr -d ' ') lines"
        ;;
      check)
        if [ ! -f "$baseline" ]; then
          echo "  ! ベースラインがありません: $baseline（先に dump が必要）" >&2
          failed=1
          continue
        fi
        if ! diff -u "$baseline" <(printf '%s\n' "$actual"); then
          echo "  ! 公開 API が変わりました。意図した変更なら scripts/api-surface.sh dump $dir" >&2
          failed=1
        else
          echo "  ok"
        fi
        ;;
    esac
  done

  return "$failed"
}

[ "$#" -ge 1 ] || usage
case "$1" in
  dump|check) action="$1"; shift; run "$action" "$@" ;;
  *) usage ;;
esac
