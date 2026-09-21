import os
import QuartzCore
import UIKit

/// メインスレッドのコマ落ちを毎秒 1 行、ログに数える。
///
/// 「ピンチが重い」は再現している本人にしか見えず、スクリーンショットにも
/// 写らない。この端末は `devicectl` の画面録画も対応していない。そこで
/// 外から観察するのをやめ、**中から数えて**ログに出す。CADisplayLink は
/// メインスレッドで刻むので、刻みの抜け = メインスレッドが塞がっていた時間。
/// MapLibre は地図の描画をメインスレッドの display link で駆動するから、
/// これは地図のカクつきそのものでもある。
///
/// 出力は `idevicesyslog -m mapconductor` で Mac から拾える:
///
///     FRAMES fps=41 dropped=19 worst=210ms
///
/// dropped は「期待した刻みのうち来なかった数」、worst はその 1 秒で最長の
/// 空白。60fps の端末で dropped=0 が滑らか、2 桁は指に伝わる。
///
/// Debug ビルドだけ。display link 1 本と毎秒 1 行の他に何もしない。
enum FrameGapProbe {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.mapconductor", category: "Probe")
    private static var link: CADisplayLink?
    private static var windowStart: CFTimeInterval = 0
    private static var lastTick: CFTimeInterval = 0
    private static var ticks = 0
    private static var dropped = 0
    private static var worstGap: CFTimeInterval = 0

    @MainActor
    static func start() {
        guard link == nil else { return }
        let proxy = Proxy()
        let created = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        created.add(to: .main, forMode: .common)
        link = created
    }

    private final class Proxy: NSObject {
        @objc func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            if lastTick == 0 {
                lastTick = now
                windowStart = now
                return
            }
            let gap = now - lastTick
            let expected = link.duration > 0 ? link.duration : 1.0 / 60.0
            ticks += 1
            // 1.5 刻み分を超えた空白は、その間の刻みが落ちたということ。
            if gap > expected * 1.5 {
                dropped += Int((gap / expected).rounded()) - 1
                worstGap = max(worstGap, gap)
            }
            lastTick = now

            if now - windowStart >= 1.0 {
                let seconds = now - windowStart
                logger.info("FRAMES fps=\(Int(Double(ticks) / seconds)) dropped=\(dropped) worst=\(Int(worstGap * 1000))ms")
                windowStart = now
                ticks = 0
                dropped = 0
                worstGap = 0
            }
        }
    }
    #else
    @MainActor
    static func start() {}
    #endif
}
