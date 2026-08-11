import SwiftUI

@main
struct MapConductorSampleApp: App {
    init() {
        // `MAPCONDUCTOR_SAMPLE_PROVIDER` / `--provider` は**開始時のプロバイダ**の指定。
        // 覚えている選択として一度だけ置き、あとはユーザーが選んだときと同じ扱いにする。
        // 各ページから毎回読むと、指定が常時の上書きになってページを移るたびに
        // 元のプロバイダへ戻ってしまう。
        if let provider = MapProvider.fromLaunch() {
            MainActor.assumeIsolated { SelectedProviderStore.remember(provider) }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
