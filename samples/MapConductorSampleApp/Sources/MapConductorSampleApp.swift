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
        // 「重い」を数字にする常駐の物差し。Debug ビルドでだけ動く。
        MainActor.assumeIsolated { FrameGapProbe.start() }
        // 止まったとき「どこで」を採る側。FrameGapProbe が「どれだけ」を数える。
        MainActor.assumeIsolated { MainThreadHangSampler.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
