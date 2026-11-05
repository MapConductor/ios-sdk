import SwiftUI

struct StreetTreeInfoView: View {
    let tree: StreetTree

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tree.species)
                .font(.headline)
            row("樹高", String(format: "%.1f m", tree.heightM))
            row("幹周", "\(tree.girthCm) cm")
            row("行政区", tree.ward)
            row("路線", tree.roadName)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
        }
    }
}
