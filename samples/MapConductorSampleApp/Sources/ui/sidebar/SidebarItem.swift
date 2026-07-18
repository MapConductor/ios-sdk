import Foundation

struct SidebarItem: Identifiable {
    let id: String
    let title: String
}

struct SidebarSection: Identifiable {
    let id: String
    let title: String
    let items: [SidebarItem]
}
