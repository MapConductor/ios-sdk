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
        SidebarItem(id: "simple-info-bubble", title: "Simple Text Bubble"),
        SidebarItem(id: "styled-info-bubble", title: "Custom Styled Bubble"),
        SidebarItem(id: "rich-content-info-bubble", title: "Rich Content Bubble"),
        SidebarItem(id: "multiple-info-bubbles", title: "Multiple Bubbles"),
        SidebarItem(id: "marker-animation", title: "Marker Animation")
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
                case "marker-animation":
                    AnimationMapPage(onToggleSidebar: navigationViewModel.toggleSidebar)
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
