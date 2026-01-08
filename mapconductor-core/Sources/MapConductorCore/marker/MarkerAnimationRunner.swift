import CoreGraphics
import Foundation
import QuartzCore

public final class MarkerAnimationRunner {
    private let animation: MarkerAnimation
    private let duration: CFTimeInterval
    private let startPoint: GeoPoint
    private let targetPoint: GeoPoint
    private let onUpdate: (GeoPoint) -> Void
    private let onCompletion: () -> Void
    private let pathPoints: [GeoPoint]?

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
        animation: MarkerAnimation,
        duration: CFTimeInterval,
        startPoint: GeoPoint,
        targetPoint: GeoPoint,
        pathPoints: [GeoPoint]? = nil,
        onUpdate: @escaping (GeoPoint) -> Void,
        onCompletion: @escaping () -> Void
    ) {
        self.animation = animation
        self.duration = duration
        self.startPoint = startPoint
        self.targetPoint = targetPoint
        self.pathPoints = pathPoints
        self.onUpdate = onUpdate
        self.onCompletion = onCompletion
    }

    public func start() {
        stop()
        if let path = pathPoints, let first = path.first {
            onUpdate(first)
        } else {
            onUpdate(startPoint)
        }
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
        if let path = pathPoints, path.count > 1 {
            let totalSegments = path.count - 1
            let segmentProgress = CGFloat(totalSegments) * progress
            let segment = min(totalSegments - 1, Int(segmentProgress))
            let localProgress = segmentProgress - CGFloat(segment)
            let startPoint = path[segment]
            let endPoint = path[segment + 1]
            let latitude = localProgress * endPoint.latitude + (1 - localProgress) * startPoint.latitude
            let longitude = localProgress * endPoint.longitude + (1 - localProgress) * startPoint.longitude
            onUpdate(GeoPoint(latitude: latitude, longitude: longitude))
        } else {
            let interpolation =
                animation == .Bounce ? MarkerAnimationRunner.easeOutBounce(progress) : progress
            let latitude = interpolation * targetPoint.latitude + (1 - interpolation) * startPoint.latitude
            let longitude = interpolation * targetPoint.longitude + (1 - interpolation) * startPoint.longitude
            onUpdate(GeoPoint(latitude: latitude, longitude: longitude))
        }
        if progress >= 1.0 {
            stop()
            onCompletion()
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
