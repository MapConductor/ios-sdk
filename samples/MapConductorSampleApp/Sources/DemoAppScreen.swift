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

    private let sidebarItems: [SidebarItem] = [
        SidebarItem(id: "map-basic", title: "Map"),
        SidebarItem(id: "map-design", title: "Map Design"),
        SidebarItem(id: "camera-sync", title: "Camera Sync Test"),
        SidebarItem(id: "simple-info-bubble", title: "Simple Text Bubble"),
        SidebarItem(id: "styled-info-bubble", title: "Custom Styled Bubble"),
        SidebarItem(id: "rich-content-info-bubble", title: "Rich Content Bubble"),
        SidebarItem(id: "multiple-info-bubbles", title: "Multiple Bubbles"),
        SidebarItem(id: "marker-animation", title: "Marker Animation"),
        SidebarItem(id: "marker-postoffice-cluster", title: "Marker Cluster"),
        SidebarItem(id: "polyline", title: "Polyline"),
        SidebarItem(id: "polyline-click", title: "Polyline Click"),
        SidebarItem(id: "map-flyto", title: "Fly To"),
        SidebarItem(id: "circle", title: "Circle"),
        SidebarItem(id: "groundimage", title: "Ground Image"),
        SidebarItem(id: "raster-layer", title: "Raster Layer"),
        SidebarItem(id: "heatmap", title: "Heatmap"),
        SidebarItem(id: "polygon-basic", title: "Polygon"),
        SidebarItem(id: "polygon-click", title: "Polygon Click"),
        SidebarItem(id: "polygon-geodesic", title: "Polygon Geodesic")
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
                case "camera-sync":
                    CameraSyncTestPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "marker-animation":
                    AnimationMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "marker-postoffice-cluster":
                    PostOfficeClusterMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polyline":
                    PolylineMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polyline-click":
                    PolylineClickMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "map-flyto":
                    FlyToMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "circle":
                    CircleMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "groundimage":
                    GroundImageMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "raster-layer":
                    RasterLayerMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "heatmap":
                    HeatmapMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-basic":
                    PolygonMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-click":
                    PolygonClickMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                case "polygon-geodesic":
                    PolygonGeodesicPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                default:
                    StoreMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
                }
            }

            Sidebar(
                items: sidebarItems,
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
