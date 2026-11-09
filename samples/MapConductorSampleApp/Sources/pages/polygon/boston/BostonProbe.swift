import Foundation
import MapConductorCore
import QuartzCore

/**
 Measurement hooks for the Boston page, off unless asked for at launch.

 - `MAPCONDUCTOR_SAMPLE_BOSTON_PROBE=1` prints the main thread's frame rate once
   a second (`BOSTON frames fps=.. dropped=.. worst=..ms`). The map SDKs draw from
   the main thread's display link, so a gap here is a stutter on screen. Unlike
   the app-wide FrameGapProbe it also runs in Release, which is what is measured.
 - `MAPCONDUCTOR_SAMPLE_AUTOPAN="dLat,dLng,count,seconds[,delay]"` pans the camera
   back and forth `count` times, each move animated over `seconds`, starting
   `delay` seconds (8 by default) after the polygons are shown, and prints the frames of each pan
   (`BOSTON pan i=.. fps=.. dropped=.. worst=..ms`).
 */
@MainActor
final class BostonProbe {
    static let enabled = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_BOSTON_PROBE"] == "1"
        || ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_AUTOPAN"] != nil

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var ticks = 0
    private var dropped = 0
    private var worst: CFTimeInterval = 0
    private var panTicks = 0
    private var panDropped = 0
    private var panWorst: CFTimeInterval = 0
    private var autopanStarted = false

    func start() {
        guard Self.enabled, link == nil else { return }
        let proxy = Proxy(owner: self)
        let created = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        created.add(to: .main, forMode: .common)
        link = created
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Starts the launch-requested pans once, after the polygons are shown.
    func autopan(from camera: MapCameraPosition, move: @escaping (MapCameraPosition, Int) -> Void) {
        guard !autopanStarted,
              let raw = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_AUTOPAN"] else { return }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count >= 4 else { return }
        autopanStarted = true
        let (dLat, dLng, count, seconds) = (parts[0], parts[1], Int(parts[2]), parts[3])
        let delay = parts.count > 4 ? parts[4] : 8
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            for i in 0..<count {
                let sign = i % 2 == 0 ? 1.0 : 0.0
                let target = MapCameraPosition(
                    position: GeoPoint(
                        latitude: camera.position.latitude + dLat * sign,
                        longitude: camera.position.longitude + dLng * sign
                    ),
                    zoom: camera.zoom, bearing: 0, tilt: 0, paddings: nil
                )
                self.panTicks = 0
                self.panDropped = 0
                self.panWorst = 0
                move(target, Int(seconds * 1000))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                let fps = Double(self.panTicks) / seconds
                print(String(
                    format: "BOSTON pan i=%d fps=%.0f dropped=%d worst=%.0fms",
                    i, fps, self.panDropped, self.panWorst * 1000
                ))
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            print("BOSTON autopan done")
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if last == 0 {
            last = now
            windowStart = now
            return
        }
        let gap = now - last
        let expected = link.duration > 0 ? link.duration : 1.0 / 60.0
        ticks += 1
        panTicks += 1
        if gap > expected * 1.5 {
            let missed = Int((gap / expected).rounded()) - 1
            dropped += missed
            panDropped += missed
            worst = max(worst, gap)
            panWorst = max(panWorst, gap)
        }
        last = now
        if now - windowStart >= 1.0 {
            print(String(
                format: "BOSTON frames t=%.3f fps=%.0f dropped=%d worst=%.0fms",
                now, Double(ticks) / (now - windowStart), dropped, worst * 1000
            ))
            windowStart = now
            ticks = 0
            dropped = 0
            worst = 0
        }
    }

    private final class Proxy: NSObject {
        weak var owner: BostonProbe?
        init(owner: BostonProbe) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            MainActor.assumeIsolated { owner?.tick(link) }
        }
    }
}
