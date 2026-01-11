import CoreGraphics
import Foundation
import QuartzCore

public final class MarkerAnimationRunner {
    private let duration: CFTimeInterval
    private let pointAtProgress: (CGFloat) -> GeoPoint
    private let onUpdate: (GeoPoint) -> Void
    private let onCompletion: () -> Void

    private var startTime: CFTimeInterval = 0
    private var isRunning = false

    private final class DisplayLinkTarget: NSObject {
        @objc func step() {
            MarkerAnimationRunner.tickAll()
        }
    }

    private static let sharedTarget = DisplayLinkTarget()
    private static var sharedDisplayLink: CADisplayLink?
    private static var activeRunners: [ObjectIdentifier: MarkerAnimationRunner] = [:]

    public init(
        duration: CFTimeInterval,
        pointAtProgress: @escaping (CGFloat) -> GeoPoint,
        onUpdate: @escaping (GeoPoint) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        self.duration = duration
        self.pointAtProgress = pointAtProgress
        self.onUpdate = onUpdate
        self.onCompletion = onCompletion
    }

    public convenience init(
        duration: CFTimeInterval,
        pathPoints: [GeoPoint],
        onUpdate: @escaping (GeoPoint) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        self.init(
            duration: duration,
            pointAtProgress: { progress in
                MarkerAnimationRunner.interpolate(pathPoints: pathPoints, progress: progress)
            },
            onUpdate: onUpdate,
            onCompletion: onCompletion
        )
    }

    public func start() {
        stop()
        onUpdate(pointAtProgress(0))
        startTime = CACurrentMediaTime()
        isRunning = true
        MarkerAnimationRunner.register(self)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        MarkerAnimationRunner.unregister(self)
    }

    private func step(at time: CFTimeInterval) {
        let elapsed = time - startTime
        let progress = min(CGFloat(elapsed / duration), 1.0)
        onUpdate(pointAtProgress(progress))
        if progress >= 1.0 {
            stop()
            onCompletion()
        }
    }

    private static func interpolate(pathPoints: [GeoPoint], progress: CGFloat) -> GeoPoint {
        guard pathPoints.count > 1 else { return pathPoints.first ?? GeoPoint(latitude: 0, longitude: 0) }

        let totalSegments = pathPoints.count - 1
        let segmentProgress = CGFloat(totalSegments) * progress
        let segment = min(totalSegments - 1, Int(segmentProgress))
        let localProgress = segmentProgress - CGFloat(segment)
        let startPoint = pathPoints[segment]
        let endPoint = pathPoints[segment + 1]
        let latitude = localProgress * endPoint.latitude + (1 - localProgress) * startPoint.latitude
        let longitude = localProgress * endPoint.longitude + (1 - localProgress) * startPoint.longitude
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    public static func makeLinearPath(start: GeoPoint, target: GeoPoint) -> [GeoPoint] {
        [start, target]
    }

    public static func makeEaseOutBounceSamples(
        start: GeoPoint,
        target: GeoPoint,
        samples: Int = 30
    ) -> [GeoPoint] {
        guard samples >= 2 else { return [start, target] }
        return (0..<samples).map { i in
            let t = CGFloat(i) / CGFloat(samples - 1)
            let e = easeOutBounce(t)
            let latitude = e * target.latitude + (1 - e) * start.latitude
            let longitude = e * target.longitude + (1 - e) * start.longitude
            return GeoPoint(latitude: latitude, longitude: longitude)
        }
    }

    private static func easeOutBounce(_ t: CGFloat) -> CGFloat {
        let n1: CGFloat = 7.5625
        let d1: CGFloat = 2.75
        var value = t
        if value < 1 / d1 {
            return n1 * value * value
        } else if value < 2 / d1 {
            value -= 1.5 / d1
            return n1 * value * value + 0.75
        } else if value < 2.5 / d1 {
            value -= 2.25 / d1
            return n1 * value * value + 0.9375
        } else {
            value -= 2.625 / d1
            return n1 * value * value + 0.984375
        }
    }

    private static func register(_ runner: MarkerAnimationRunner) {
        let key = ObjectIdentifier(runner)
        activeRunners[key] = runner
        ensureDisplayLink()
    }

    private static func unregister(_ runner: MarkerAnimationRunner) {
        let key = ObjectIdentifier(runner)
        activeRunners.removeValue(forKey: key)
        if activeRunners.isEmpty {
            sharedDisplayLink?.invalidate()
            sharedDisplayLink = nil
        }
    }

    private static func ensureDisplayLink() {
        guard sharedDisplayLink == nil else { return }
        let link = CADisplayLink(target: sharedTarget, selector: #selector(DisplayLinkTarget.step))
        link.add(to: .main, forMode: .common)
        sharedDisplayLink = link
    }

    private static func tickAll() {
        let now = CACurrentMediaTime()
        let runners = activeRunners.values
        for runner in runners {
            runner.step(at: now)
        }
    }
}
