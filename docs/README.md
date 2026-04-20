# MapConductor iOS SDK Documentation

This repository contains the documentation website for the MapConductor iOS SDK built with Astro and Starlight.

## Project Structure

```
src/
├── config.ts                 # Version configuration
├── content.config.ts         # Content configuration
├── content/docs/             # Documentation markdown files
│   ├── introduction.mdx
│   ├── get-started.mdx
│   ├── modules.mdx
│   ├── index.mdx
│   ├── components/           # Component documentation
│   ├── core/                 # Core classes documentation
│   ├── setup/                # Setup guides for each provider
│   ├── mapviewholder/        # MapViewHolder documentation
│   ├── states/               # State management documentation
│   ├── event/                # Event handling documentation
│   └── experimental/         # Experimental features
└── components/               # Astro components for code examples
```

## Development

### Prerequisites

- Node.js 18+ and npm/pnpm
- Swift Package Manager (for iOS SDK reference)

### Installation

```bash
npm install
# or
pnpm install
```

### Development Server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

### Build

```bash
npm run build
```

The generated static site will be in the `dist/` directory.

## Content Structure

### Documentation Files

Documentation files are written in MDX format (Markdown + JSX) and support:

- Code blocks with syntax highlighting
- Tabs for multi-language examples
- Callout boxes (tip, caution, danger, etc.)
- Astro components for dynamic examples

### Adding New Pages

1. Create a new `.mdx` file in `src/content/docs/`
2. Add frontmatter with title and description
3. Update the sidebar configuration in `astro.config.ts` if needed

Example:

```mdx
---
title: My Page Title
description: Brief description
---

# My Page Title

Content goes here...
```

## Version Placeholders

Use `{VARIABLE_NAME}` placeholders in documentation that will be automatically replaced:

- `{CORE_MODULE_VERSION}` - MapConductor Core module version
- `{GOOGLEMAPS_MODULE_VERSION}` - Google Maps integration version
- `{MAPBOX_MODULE_VERSION}` - Mapbox integration version
- `{MAPKIT_MODULE_VERSION}` - MapKit integration version
- `{MAPLIBRE_MODULE_VERSION}` - MapLibre integration version
- `{SWIFT_PACKAGE_MANAGER_VERSION}` - Swift Package Manager version

## Styling

Custom CSS is located in `src/styles/custom.css`. Starlight provides default theming, and additional customizations can be added there.

## Contributing

When updating documentation:

1. Ensure code examples are accurate for iOS/Swift/SwiftUI
2. Replace Android/Kotlin references with iOS/Swift equivalents
3. Update provider-specific examples (replace HERE/ArcGIS with MapKit)
4. Test links and cross-references

## License

Same as MapConductor iOS SDK.
