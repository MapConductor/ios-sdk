import SwiftUI
import UIKit

struct Sidebar: View {
    let items: [SidebarItem]
    let selectedItemId: String
    let onItemClick: (SidebarItem) -> Void
    let isExpanded: Bool
    let onToggleSidebar: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if isExpanded {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onToggleSidebar)
            }

            if isExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button(action: onToggleSidebar) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }

                        Text("MapConductor Demo")
                            .font(.system(size: 18, weight: .bold))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { item in
                                SidebarItemView(
                                    item: item,
                                    isSelected: item.id == selectedItemId
                                ) {
                                    onItemClick(item)
                                    onToggleSidebar()
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
                .frame(width: 280)
                .background(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.2), radius: 16, x: 4, y: 0)
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }
}

private struct SidebarItemView: View {
    let item: SidebarItem
    let isSelected: Bool
    let onClick: () -> Void

    var body: some View {
        VStack {
            Button(action: onClick) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
    }
}
