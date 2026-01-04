import Combine

final class NavigationViewModel: ObservableObject {
    @Published var currentPage: String
    @Published var isSidebarExpanded: Bool = false

    init(initPage: String) {
        self.currentPage = initPage
    }

    func navigateTo(_ pageId: String) {
        currentPage = pageId
    }

    func toggleSidebar() {
        isSidebarExpanded.toggle()
    }
}
