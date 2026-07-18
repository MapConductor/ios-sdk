import SwiftUI

struct DemoAppScreen: View {
    @StateObject private var navigationViewModel: NavigationViewModel

    init() {
        _navigationViewModel = StateObject(wrappedValue: NavigationViewModel(initPage: DemoAppScreen.initialPage()))
    }

    private static func initialPage() -> String {
        let env = ProcessInfo.processInfo.environment
        if let value = env["MAPCONDUCTOR_SAMPLE_INIT_PAGE"], !value.isEmpty {
            return value
        }

        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--initPage"), index + 1 < args.count {
            return args[index + 1]
        }

        return "startup"
    }

    private let sidebarSections: [SidebarSection] = [
        SidebarSection(
            id: "map",
            title: "Map",
            items: [
                SidebarItem(id: "map-basic", title: "Map"),
                SidebarItem(id: "map-design", title: "Map Design"),
                SidebarItem(id: "map-tilt", title: "Tilt"),
                SidebarItem(id: "map-visibleregion", title: "Visible Region"),
                SidebarItem(id: "camera-sync", title: "Camera Sync Test"),
                SidebarItem(id: "map-flyto", title: "Fly To"),
                SidebarItem(id: "map-fitbounds", title: "Fit Bounds"),
                SidebarItem(id: "arcgis-map-2d", title: "ArcGIS Map 2D")
            ]
        ),
        SidebarSection(
            id: "info-bubble",
            title: "Info Bubble",
            items: [
                SidebarItem(id: "simple-info-bubble", title: "Simple Text Bubble"),
                SidebarItem(id: "styled-info-bubble", title: "Custom Styled Bubble"),
                SidebarItem(id: "rich-content-info-bubble", title: "Rich Content Bubble"),
                SidebarItem(id: "multiple-info-bubbles", title: "Multiple Bubbles")
            ]
        ),
        SidebarSection(
            id: "marker",
            title: "Marker",
            items: [
                SidebarItem(id: "marker-basic", title: "Marker"),
                SidebarItem(id: "marker-animation", title: "Marker Animation"),
                SidebarItem(id: "marker-postoffice", title: "Bunch of Markers"),
                SidebarItem(id: "marker-postoffice-cluster", title: "Marker Cluster")
            ]
        ),
        SidebarSection(
            id: "circle",
            title: "Circle",
            items: [SidebarItem(id: "circle", title: "Circle")]
        ),
        SidebarSection(
            id: "ground-image",
            title: "Ground Image",
            items: [SidebarItem(id: "groundimage", title: "Ground Image")]
        ),
        SidebarSection(
            id: "polyline",
            title: "Polyline",
            items: [
                SidebarItem(id: "polyline", title: "Polyline"),
                SidebarItem(id: "polyline-click", title: "Polyline Click")
            ]
        ),
        SidebarSection(
            id: "polygon",
            title: "Polygon",
            items: [
                SidebarItem(id: "polygon-basic", title: "Polygon"),
                SidebarItem(id: "polygon-click", title: "Polygon Click"),
                SidebarItem(id: "polygon-geodesic", title: "Polygon Geodesic"),
                SidebarItem(id: "polygon-hole", title: "Polygon Hole")
            ]
        ),
        SidebarSection(
            id: "raster-layer",
            title: "Raster Layer",
            items: [SidebarItem(id: "raster-layer", title: "Raster Layer")]
        ),
        SidebarSection(
            id: "heatmap",
            title: "Heatmap",
            items: [SidebarItem(id: "heatmap", title: "Heatmap")]
        ),
        SidebarSection(
            id: "geojson",
            title: "GeoJSON",
            items: [
                SidebarItem(id: "geojson-basic", title: "GeoJSON"),
                SidebarItem(id: "geojson-layer", title: "GeoJSON Layer")
            ]
        )
    ]

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                switch navigationViewModel.currentPage {
                case "startup":
                    StartUpPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "simple-info-bubble":
                    SimpleTextBubblePage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "styled-info-bubble":
                    StyledInfoBubblePage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "rich-content-info-bubble":
                    RichContentBubblePage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "multiple-info-bubbles":
                    MultipleBubblesPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-basic":
                    StoreMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-design":
                    MapDesignMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-tilt":
                    TiltMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-visibleregion":
                    VisibleRegionPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "camera-sync":
                    CameraSyncTestPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "marker-basic":
                    MarkerBasicPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "marker-animation":
                    AnimationMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "marker-postoffice":
                    PostOfficePage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "marker-postoffice-cluster":
                    PostOfficeClusterMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polyline":
                    PolylineMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polyline-click":
                    PolylineClickMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-flyto":
                    FlyToMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-fitbounds":
                    FitBoundsMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "circle":
                    CircleMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "groundimage":
                    GroundImageMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "raster-layer":
                    RasterLayerMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "heatmap":
                    HeatmapMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "geojson-basic":
                    BasicGeoJSONMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "geojson-layer":
                    GeoJSONLayerMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-basic":
                    PolygonMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-click":
                    PolygonClickMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-geodesic":
                    PolygonGeodesicPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-hole":
                    HolePolygonMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "arcgis-map-2d":
                    ArcGISMapView2DPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                default:
                    StoreMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                }
            }

            Sidebar(
                sections: sidebarSections,
                selectedItemId: navigationViewModel.currentPage,
                onItemClick: { item in
                    navigationViewModel.navigateTo(item.id)
                },
                isExpanded: navigationViewModel.isSidebarExpanded,
                onToggleSidebar: navigationViewModel.toggleSidebar
            )
        }
    }
}
