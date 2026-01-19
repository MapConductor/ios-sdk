# MapConductorSampleApp

SwiftUI sample app demonstrating MapConductor SDK features with an Android-style sidebar and page layout.

## Requirements

- Xcode 15+
- iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for regenerating the project)

## Run

1. Open `MapConductorSampleApp.xcworkspace` in Xcode.
2. Create a `Secrets.xcconfig` file at `Config`, then set your Google Maps API.
   ```Secrets.xcconfig
   // Config/Secrets.xcconfig
   GOOGLE_MAPS_API_KEY = xxxxxxxxxx
   ```
4. Select an iOS 17+ simulator and run.

## Regenerate Project

If you modify `project.yml`, regenerate the Xcode project:

```bash
cd samples/MapConductorSampleApp
xcodegen generate
```

## Project Structure

```
Sources/
├── pages/           # Demo pages (mirrors Android sample structure)
│   ├── map/         # Basic map, design, fly-to demos
│   ├── marker/      # Marker animation, clustering demos
│   ├── polygon/     # Polygon demos
│   ├── polyline/    # Polyline demos
│   ├── circle/      # Circle demos
│   ├── heatmap/     # Heatmap demos
│   ├── groundimage/ # Ground image overlay demos
│   ├── raster/      # Raster layer demos
│   └── infobubble/  # Info bubble demos
├── ui/sidebar/      # Sidebar navigation components
└── SampleConfig.swift  # API key configuration
```

## Notes

- The app supports switching between Google Maps, MapLibre, and MapKit at runtime.
- InfoBubble uses a SwiftUI overlay that tracks marker positions.
- Pages are structured to mirror the Android sample app for consistency.
