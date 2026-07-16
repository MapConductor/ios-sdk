#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/xcframeworks}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export MAPCONDUCTOR_BUILD_XCFRAMEWORK=1

default_modules=(core geojson heatmap marker-cluster googlemaps maplibre)
all_modules=(core geojson heatmap marker-cluster mapkit googlemaps maplibre mapbox arcgis here)

module_config() {
  case "$1" in
    core) package_dir="ios-sdk-core"; scheme="mapconductor-core"; product="MapConductorCore" ;;
    geojson) package_dir="ios-geojson-layer"; scheme="mapconductor-geojson-layer"; product="MapConductorGeoJSON" ;;
    heatmap) package_dir="ios-heatmap"; scheme="mapconductor-heatmap"; product="MapConductorHeatmap" ;;
    marker-cluster) package_dir="ios-marker-cluster"; scheme="mapconductor-marker-cluster"; product="MapConductorMarkerCluster" ;;
    mapkit) package_dir="ios-for-mapkit"; scheme="mapconductor-for-mapkit"; product="MapConductorForMapKit" ;;
    googlemaps) package_dir="ios-for-googlemaps"; scheme="mapconductor-for-googlemaps"; product="MapConductorForGoogleMaps" ;;
    maplibre) package_dir="ios-for-maplibre"; scheme="mapconductor-for-maplibre"; product="MapConductorForMapLibre" ;;
    mapbox) package_dir="ios-for-mapbox"; scheme="mapconductor-for-mapbox"; product="MapConductorForMapbox" ;;
    arcgis) package_dir="ios-for-arcgis"; scheme="mapconductor-for-arcgis"; product="MapConductorForArcGIS" ;;
    here) package_dir="ios-for-here"; scheme="mapconductor-for-here"; product="MapConductorForHERE" ;;
    *) echo "Unknown module: $1" >&2; exit 2 ;;
  esac
}

if [[ "${1:-}" == "--all" ]]; then
  modules=("${all_modules[@]}")
elif [[ "$#" -gt 0 ]]; then
  modules=("$@")
else
  modules=("${default_modules[@]}")
fi

mkdir -p "$BUILD_DIR/archives" "$BUILD_DIR/output"

archive_module() {
  local module="$1"
  local package_dir scheme product
  module_config "$module"

  local source_dir="$ROOT_DIR/$package_dir"
  local device_archive="$BUILD_DIR/archives/$product-iOS.xcarchive"
  local simulator_archive="$BUILD_DIR/archives/$product-Simulator.xcarchive"
  local device_derived="$BUILD_DIR/derived/$product-iOS"
  local simulator_derived="$BUILD_DIR/derived/$product-Simulator"
  local output="$BUILD_DIR/output/$product.xcframework"

  rm -rf "$device_archive" "$simulator_archive" "$device_derived" "$simulator_derived" "$output"

  echo "Archiving $product for iOS"
  (
    cd "$source_dir"
    xcodebuild archive \
      -scheme "$scheme" \
      -destination "generic/platform=iOS" \
      -archivePath "$device_archive" \
      -derivedDataPath "$device_derived" \
      SKIP_INSTALL=NO \
      BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
      CODE_SIGNING_ALLOWED=NO \
      -quiet
  )

  echo "Archiving $product for iOS Simulator"
  (
    cd "$source_dir"
    xcodebuild archive \
      -scheme "$scheme" \
      -destination "generic/platform=iOS Simulator" \
      -archivePath "$simulator_archive" \
      -derivedDataPath "$simulator_derived" \
      SKIP_INSTALL=NO \
      BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
      CODE_SIGNING_ALLOWED=NO \
      -quiet
  )

  local device_framework="$device_archive/Products/usr/local/lib/$product.framework"
  local simulator_framework="$simulator_archive/Products/usr/local/lib/$product.framework"
  if [[ ! -d "$device_framework" || ! -d "$simulator_framework" ]]; then
    echo "Framework archive missing for $product" >&2
    exit 1
  fi

  install_swift_modules "$device_derived" "$device_framework" "$product" "iphoneos" "ios"
  install_swift_modules "$simulator_derived" "$simulator_framework" "$product" "iphonesimulator" "ios-simulator"

  local create_args=(
    -create-xcframework
    -framework "$device_framework"
    -framework "$simulator_framework"
  )
  local device_dsym="$device_archive/dSYMs/$product.framework.dSYM"
  [[ -d "$device_dsym" ]] && create_args+=( -debug-symbols "$device_dsym" )
  create_args+=( -output "$output" )

  xcodebuild "${create_args[@]}"
}

install_swift_modules() {
  local derived_data="$1"
  local framework="$2"
  local product="$3"
  local sdk="$4"
  local triple_suffix="$5"
  local modules_dir="$framework/Modules/$product.swiftmodule"
  local found=false

  mkdir -p "$modules_dir"
  for architecture in arm64 x86_64; do
    local objects_dir
    objects_dir="$(find "$derived_data/Build/Intermediates.noindex/ArchiveIntermediates" \
      -path "*/Release-$sdk/$product.build/Objects-normal/$architecture" \
      -type d -print -quit)"
    [[ -n "$objects_dir" ]] || continue
    found=true

    for extension in swiftinterface private.swiftinterface package.swiftinterface swiftdoc swiftmodule abi.json; do
      local source="$objects_dir/$product.$extension"
      [[ -f "$source" ]] || continue
      cp "$source" "$modules_dir/$architecture-apple-$triple_suffix.$extension"
    done
  done

  if [[ "$found" != true ]]; then
    echo "Swift module interfaces missing for $product ($sdk)" >&2
    exit 1
  fi
}

for module in "${modules[@]}"; do
  archive_module "$module"
done

echo "XCFrameworks written to $BUILD_DIR/output"
