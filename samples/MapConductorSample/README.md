# MapConductor Sample (iOS)

This is a minimal SwiftUI sample that lets you switch between Google Maps and MapLibre using a dropdown menu.

## How to Run

1. Create a new iOS App project in Xcode (iOS 14+).
2. Add this package as a dependency (File > Add Packages... > Add Local).
3. Add these files to your app target:
   - `samples/MapConductorSample/ContentView.swift`
   - `samples/MapConductorSample/MapConductorSampleApp.swift`
4. Replace the placeholder Google Maps API key in `ContentView.swift`.

## Notes

- The sample uses native SDK callouts for `InfoBubble`.
- MapLibre uses the default style URL.
