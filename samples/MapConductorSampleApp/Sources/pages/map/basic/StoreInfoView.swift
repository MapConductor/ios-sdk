import SwiftUI

struct StoreInfoView: View {
    let info: StoreInfo
    let onClick: () -> Void

    init(info: StoreInfo, onClick: @escaping () -> Void = {}) {
        self.info = info
        self.onClick = onClick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.name)
                .font(.system(size: 15, weight: .bold))

            Text(info.address)
                .font(.system(size: 13))

            if info.instore || info.driveThrough {
                HStack(spacing: 12) {
                    if info.instore {
                        Text("• In store eating")
                    }
                    if info.driveThrough {
                        Text("• Drive Through")
                    }
                }
                .font(.system(size: 12))
            }

            Button(action: onClick) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 10, height: 10)
                    Text("Get Directions")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.95))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
        }
    }
}
