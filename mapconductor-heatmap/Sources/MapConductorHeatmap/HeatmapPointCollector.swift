import Combine
import Foundation

public final class HeatmapPointCollector {
    private let addSubject = PassthroughSubject<HeatmapPointState, Never>()
    private let removeSubject = PassthroughSubject<String, Never>()
    private var cancellables: Set<AnyCancellable> = []

    public let flow = CurrentValueSubject<[String: HeatmapPointState], Never>([:])
    private var refCounts: [String: Int] = [:]

    public init() {
        addSubject
            .collect(.byTimeOrCount(DispatchQueue.main, .milliseconds(5), 100))
            .sink { [weak self] states in
                guard let self else { return }
                var next = flow.value
                for state in states {
                    let nextCount = (refCounts[state.id] ?? 0) + 1
                    refCounts[state.id] = nextCount
                    next[state.id] = state
                }
                print("HeatmapPointCollector: added \(states.count) points, total points: \(next.count)")
                flow.send(next)
            }
            .store(in: &cancellables)

        removeSubject
            .collect(.byTimeOrCount(DispatchQueue.main, .milliseconds(5), 300))
            .sink { [weak self] ids in
                guard let self else { return }
                var next = flow.value
                for id in ids {
                    let nextCount = (refCounts[id] ?? 0) - 1
                    if nextCount <= 0 {
                        refCounts.removeValue(forKey: id)
                        next.removeValue(forKey: id)
                    } else {
                        refCounts[id] = nextCount
                    }
                }
                print("HeatmapPointCollector: removed \(ids.count) points, total points: \(next.count)")
                flow.send(next)
            }
            .store(in: &cancellables)
    }

    public func add(state: HeatmapPointState) {
        addSubject.send(state)
    }

    public func remove(id: String) {
        removeSubject.send(id)
    }
}
