import Foundation

/// 直近に選んだ地図プロバイダ。**ページをまたいで引き継ぐ**ための入れ物。
///
/// ## なぜ要るのか
///
/// 各ページは `@State private var provider = MapProvider.initial()` で選択状態を持つ。
/// これはそのページの View の寿命に紐づくので、ページを移ると毎回既定へ戻ってしまう。
/// react-sdk はプロバイダの地図インスタンスをシングルトンで持っているので既に
/// 引き継がれていて、**android と iOS だけが揃っていなかった**。
///
/// ## 永続化しない
///
/// プロセス内だけ。アプリを再起動したら既定へ戻る。サンプルアプリなので
/// 「前回の続き」より「毎回同じ状態から始められる」ほうが都合がよい。
@MainActor
enum SelectedProviderStore {
    /// 直近に選ばれたプロバイダ。まだ何も選ばれていなければ nil。
    private(set) static var provider: MapProvider?

    static func remember(_ provider: MapProvider) {
        self.provider = provider
    }
}
