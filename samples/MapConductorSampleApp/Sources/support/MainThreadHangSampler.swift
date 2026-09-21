import Darwin
import Foundation
import os

/// メインスレッドが止まったとき、**何をしていたか**をその場で採る。
///
/// FRAMES（`FrameGapProbe`）は「止まった」ことしか言わない。Instruments は
/// この端末に attach できない（`xctrace` が boot 待ちでタイムアウトする）。
/// そこで中から採る: 監視スレッドが 50ms ごとにメインスレッドの様子を見て、
/// 300ms 以上止まっていたら `thread_suspend` でメインスレッドを止め、
/// x29（フレームポインタ）の鎖を歩いて戻りアドレスを集め、ログに吐いて
/// すぐ再開する。採取は 1 回あたり数十 µs で、止まっている本人には見えない。
///
/// 出力は 2 種類。起動時に 1 度だけ:
///
///     HANGIMG MapConductorSampleApp.debug.dylib slide=0x104f00000
///
/// ハング中に:
///
///     HANGSTACK gap=612ms 0x104f81234 0x1a2b3c4d5 ...
///
/// Mac 側で `atos -o <dSYM> -l <slide+vmbase>` に通すと関数名になる。
/// Debug ビルド専用。
enum MainThreadHangSampler {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.mapconductor", category: "Probe")
    private static var mainThread: thread_t = 0
    private static let beat = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
    private static var started = false

    @MainActor
    static func start() {
        guard !started else { return }
        started = true
        mainThread = mach_thread_self()
        beat.pointee = 0

        // 主要イメージのロードアドレス。シンボル化はオフラインで行う。
        for image in ["MapConductorSampleApp", "MapConductorCore", "MapLibre", "Mapbox"] {
            for at in 0..<_dyld_image_count() {
                guard let name = _dyld_get_image_name(at) else { continue }
                if String(cString: name).contains(image) {
                    let header = UInt(bitPattern: _dyld_get_image_header(at))
                    logger.info("HANGIMG \(String(cString: name).split(separator: "/").last ?? "?", privacy: .public) header=0x\(String(header, radix: 16), privacy: .public)")
                }
            }
        }

        // 鼓動: メインの CFRunLoop が回るたびに刻む。Timer だと止まっている間に
        // 溜まるので、observer で回転そのものを数える。
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.afterWaiting.rawValue, true, 0
        ) { _, _ in
            beat.pointee &+= 1
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)

        Thread.detachNewThread {
            Thread.current.name = "mc.hang.sampler"
            watch()
        }
    }

    private static func watch() {
        var lastBeat: UInt64 = 0
        var stalledSince: UInt64 = 0
        var sampled = false
        while true {
            usleep(50_000)
            let now = DispatchTime.now().uptimeNanoseconds
            let current = beat.pointee
            if current != lastBeat {
                lastBeat = current
                stalledSince = now
                sampled = false
                continue
            }
            if stalledSince == 0 { stalledSince = now; continue }
            let gapMs = (now - stalledSince) / 1_000_000
            // 1 回のハングにつき 2 点採る: 300ms 時点と 1500ms 時点。長い
            // ハングが 1 つの関数なのか、別の場所を渡り歩いているのかが分かる。
            if (gapMs >= 300 && !sampled) || gapMs >= 1500 {
                sample(gapMs: gapMs)
                if gapMs >= 1500 { stalledSince = now &+ 1 } // 次の 1.5s でまた
                sampled = true
            }
        }
    }

    private static func sample(gapMs: UInt64) {
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size
        )
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return }
        let got = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        var frames: [UInt64] = []
        if got == KERN_SUCCESS {
            frames.append(state.__pc)
            frames.append(state.__lr)
            // x29 の鎖: [fp] = 呼び出し元 fp, [fp+8] = 戻りアドレス。
            var fp = state.__fp
            for _ in 0..<48 {
                guard fp > 0x1000, fp % 8 == 0 else { break }
                let pointer = UnsafeRawPointer(bitPattern: UInt(fp))
                guard let pointer else { break }
                let next = pointer.load(as: UInt64.self)
                let ret = pointer.load(fromByteOffset: 8, as: UInt64.self)
                if ret > 0x100000000 { frames.append(ret) }
                guard next > fp else { break }
                fp = next
            }
        }
        thread_resume(mainThread)
        // arm64e の戻りアドレスは上位ビットに PAC が乗る。下位 39 ビットが実アドレス。
        let text = frames.map { "0x" + String($0 & 0x0000_007F_FFFF_FFFF, radix: 16) }
            .joined(separator: " ")
        logger.info("HANGSTACK gap=\(gapMs, privacy: .public)ms \(text, privacy: .public)")
    }
    #else
    @MainActor
    static func start() {}
    #endif
}
