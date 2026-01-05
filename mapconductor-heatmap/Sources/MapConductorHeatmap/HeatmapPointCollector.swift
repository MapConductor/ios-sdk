import Combine
import Foundation

public final class HeatmapPointCollector {
    private let addSubject = PassthroughSubject<HeatmapPointState, Never>()
    private let removeSubject = PassthroughSubject<String, Never>()
    private var cancellables: Set<AnyCancellable> = []

    public let flow = CurrentValueSubject<[String: HeatmapPointState], Never>([:])

    public init() {
        addSubject
            .collect(.byTimeOrCount(DispatchQueue.global(), .milliseconds(5), 100))
            .sink { [weak self] states in
                guard let self else { return }
                var next = flow.value
                for state in states {
                    next[state.id] = state
                }
                flow.send(next)
            }
            .store(in: &cancellables)

        removeSubject
            .collect(.byTimeOrCount(DispatchQueue.global(), .milliseconds(5), 300))
            .sink { [weak self] ids in
                guard let self else { return }
                var next = flow.value
                for id in ids {
                    next.removeValue(forKey: id)
                }
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
