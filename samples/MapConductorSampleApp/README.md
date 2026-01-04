# MapConductorSampleApp

SwiftUI sample app with an Android-style sidebar and page layout.

## Run

1. Open `samples/MapConductorSampleApp/MapConductorSampleApp.xcworkspace` in Xcode.
2. Set your Google Maps API key in `samples/MapConductorSampleApp/Sources/SampleConfig.swift`.
3. Select an iOS simulator (iOS 14+) and run.

## Notes

- Pages live under `samples/MapConductorSampleApp/Sources/pages` to mirror Android.
- The sidebar lives under `samples/MapConductorSampleApp/Sources/ui/sidebar`.
- InfoBubble uses a SwiftUI overlay that tracks markers.
