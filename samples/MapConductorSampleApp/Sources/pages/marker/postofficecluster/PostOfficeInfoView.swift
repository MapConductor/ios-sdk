import SwiftUI

struct PostOfficeInfoView: View {
    let info: PostOffice
    let onClick: ((PostOffice) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.name)
                .font(.headline)
            Text(info.address)
                .font(.subheadline)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onClick?(info)
        }
    }
}
