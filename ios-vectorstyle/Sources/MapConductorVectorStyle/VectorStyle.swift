import Foundation
import MapConductorCore

/**
 A vector style, with adjustments, as the map's appearance.

 ```swift
 MapLibreMapView(
     state: state,
     style: VectorStyle(rules: StyleRules.build {
         $0.all { $0.color = .black }
         $0.role(LayerRole.label) { $0.visible = false }
         $0.role(LayerRole.road) { $0.color = .white }
     })
 )
 ```

 What happens underneath depends on the backend, and the app does not have
 to know:

 - **A map that reads vector styles** (MapLibre, Mapbox, MapTiler) is given
   the document and told the per-layer differences. Changing the rules later
   sends new differences and **reloads nothing** -- which is the whole reason
   the adjustments are compiled into deltas as well as a document.
 - **A map that cannot** (Google Maps, MapKit, HERE, ArcGIS...) is handed
   raster tiles drawn from the adjusted document, if the app passed a
   `rasteriser`. Changing the rules re-rasterises and refetches nothing.

 Either way the same rules produce the same map, because both paths start
 from one compilation of one style.

 ## What it reports

 Quietly doing nothing is the failure this design is built against, so
 `onDiagnostics` always hears how many layers each rule matched, which
 matched none, what this backend would not take, and what the rasteriser
 will not draw. A rule written for the wrong tile schema produces a
 perfectly good map with nothing changed on it; nothing else says so.
 */
public struct VectorStyle: MapViewStyle {
    /// Which style to adjust. Defaults to whatever the map is already drawing.
    public let document: VectorStyleSource
    public let rules: StyleRules
    /**
     Draws the style for a backend that cannot read one.

     `MapConductorVectorTile` supplies one. Left out, a map without vector
     style support is told so in the diagnostics rather than left blank --
     there is nothing sensible this can do on its own.
     */
    /**
     Draws the style for a backend that cannot read one.

     `MapConductorVectorTile` supplies one. Left out, a map without vector
     style support is told so in the diagnostics rather than left blank.

     **Hold it, do not rebuild it.** Two styles count as the same one only
     if they name the same rasteriser *instance*, so a `let` on a `View`
     makes every evaluation a different style — the map tears the old one
     down and installs a new one each time, and the result is tiles fetched
     forever with nothing drawn. `@State private var rasteriser = …`.
     */
    public let rasteriser: VectorStyleRasteriser?
    public let onUnsupported: UnsupportedPolicy
    public let onDiagnostics: (([String]) -> Void)?

    public init(
        document: VectorStyleSource = .currentDesign,
        rules: StyleRules = .none,
        rasteriser: VectorStyleRasteriser? = nil,
        onUnsupported: UnsupportedPolicy = .report,
        onDiagnostics: (([String]) -> Void)? = nil
    ) {
        self.document = document
        self.rules = rules
        self.rasteriser = rasteriser
        self.onUnsupported = onUnsupported
        self.onDiagnostics = onDiagnostics
    }

    public var key: String { "\(document.key)|\(rules.json.hashValue)" }

    /// The message an error carries, rather than Foundation's stand-in for one.
    static func describe(_ error: Error) -> String {
        if let known = error as? VectorStyleError { return known.message }
        return (error as NSError).localizedDescription
    }

    /// Whether `next` differs from this only in its adjustments.
    func sameStyle(as next: VectorStyle) -> Bool {
        next.document == document
            && next.rasteriser === rasteriser
            && next.onUnsupported == onUnsupported
    }

    public func install(host: MapStyleHost) -> MapStyleInstallation {
        let installation = Installation(style: self, host: host)
        installation.start()
        return MapStyleInstallation(
            dispose: { installation.dispose() },
            update: { next in
                guard let next = next as? VectorStyle else { return false }
                return installation.update(next)
            }
        )
    }
}

extension UnsupportedPolicy: Equatable {}

/**
 One style's life on one map.

 Resolving the document can mean a network round trip, so the work starts on
 a queue and ``start()`` returns at once; everything after that checks
 `disposed` before touching the map, because a view can be gone before its
 style arrives.
 */
final class Installation: @unchecked Sendable {
    private let lock = NSLock()
    private var style: VectorStyle
    private let host: MapStyleHost
    private var disposed = false
    private let documentId = "vectorstyle-\(UUID().uuidString)"
    // Accessed on the main thread along with the native style handoff.
    private var documentRevision = 0

    /// The style as its author wrote it, kept so later rules compile against it.
    private var base: String?
    private var rasterisation: VectorStyleRasterisation?
    private var servedDocument = false
    private var styleLoaded: MapStyleInstallation?

    init(style: VectorStyle, host: MapStyleHost) {
        self.style = style
        self.host = host
    }

    func start() {
        Installation.workers.async { [self] in
            let resolved: String
            do {
                resolved = try resolve(style.document)
            } catch {
                // `localizedDescription` on a plain Swift error is
                // "The operation couldn't be completed", which tells the app
                // nothing. The message this module wrote is the point.
                report(["the style could not be read: \(VectorStyle.describe(error))"])
                return
            }
            guard !isDisposed else { return }
            lock.lock()
            base = resolved
            lock.unlock()
            apply(style, firstTime: true)
        }
    }

    func update(_ next: VectorStyle) -> Bool {
        // A different document is a different style, whatever else matches:
        // it has to be fetched and the map has to be told.
        guard style.sameStyle(as: next) else { return false }
        lock.lock()
        let haveBase = base != nil
        if haveBase { style = next }
        lock.unlock()
        guard haveBase else { return false }
        Installation.workers.async { [self] in
            guard !isDisposed else { return }
            apply(next, firstTime: false)
        }
        return true
    }

    func dispose() {
        lock.lock()
        if disposed {
            lock.unlock()
            return
        }
        disposed = true
        let hadDocument = servedDocument
        let raster = rasterisation
        let loaded = styleLoaded
        rasterisation = nil
        styleLoaded = nil
        lock.unlock()

        loaded?.dispose()
        // Order matters: the mutations have to come off while the document
        // they were applied to is still the one loaded.
        host.serviceRegistry.get(VectorStyleMutationSupportKey.self)?.clear()
        if hadDocument {
            host.serviceRegistry.get(VectorStyleSupportKey.self)?.clearStyle()
            host.tileServer.unregisterDocument(id: documentId)
        }
        raster?.dispose()
    }

    private var isDisposed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return disposed
    }

    /// Compiles on a worker, then routes on the main thread.
    private func apply(_ style: VectorStyle, firstTime: Bool) {
        lock.lock()
        let base = self.base
        lock.unlock()
        guard let base else { return }

        let compiled: CompiledStyle
        do {
            compiled = try VectorStyleRules.compile(styleJSON: base, rulesJSON: style.rules.json)
        } catch {
            report(["the rules could not be applied: \(VectorStyle.describe(error))"])
            return
        }
        guard !isDisposed else { return }
        report(compiled.diagnostics)
        onMain { [weak self] in self?.route(style, compiled, firstTime: firstTime, base: base) }
    }

    /**
     Hands the compiled result to the map. **Main thread only.**

     Every branch below touches the renderer, and a renderer is a UI object.
     MapLibre on Android says so out loud -- `CalledFromWorkerThreadException:
     Method invoked from wrong thread is getLayer` -- and because
     `applyStyleMutations` catches what a mutation throws, all of them came
     back as adjustments the map "cannot" make. Here it does not throw, which
     only means the same mistake is quieter.
     */
    private func route(
        _ style: VectorStyle, _ compiled: CompiledStyle, firstTime: Bool, base: String
    ) {
        guard !isDisposed else { return }
        let registry = host.serviceRegistry
        let vector = registry.get(VectorStyleSupportKey.self)
        let mutation = registry.get(VectorStyleMutationSupportKey.self)

        if let vector, let mutation {
            // The map draws styles itself and can be told differences: give
            // it the author's document and the deltas on top. The compiled
            // document is deliberately *not* what it is given -- the next
            // rule change produces deltas against the original, and a map
            // holding an already-adjusted document would take them to mean
            // something else.
            if firstTime { serve(document: base, to: vector) }
            let unapplied = mutation.apply(compiled.mutations)
            if !unapplied.isEmpty {
                handle(unapplied: unapplied, vector: vector, compiled: compiled, style: style)
            }
        } else if let vector {
            // It draws styles but cannot be patched: the adjusted document
            // is the only way, and every rule change reloads.
            serve(document: compiled.styleJSON, to: vector)
        } else if let rasteriser = style.rasteriser {
            lock.lock()
            let current = rasterisation
            lock.unlock()
            if let current {
                current.restyle(styleJSON: compiled.styleJSON, affects: compiled.affects)
            } else {
                let started = rasteriser.install(
                    host: host, styleJSON: compiled.styleJSON, affects: compiled.affects)
                lock.lock()
                rasterisation = started
                let gone = disposed
                lock.unlock()
                if gone { started.dispose() }
            }
        } else {
            report([
                "this map cannot draw a vector style, and no rasteriser was given; "
                    + "pass `rasteriser:` from MapConductorVectorTile"
            ])
        }

        // Whatever was just applied is lost the moment the map loads a style
        // again -- an app switching basemap, a provider rebuilding. The
        // mutation store puts its own set back.
        lock.lock()
        let needsHook = firstTime && styleLoaded == nil
        lock.unlock()
        if needsHook {
            let hook = host.onStyleLoaded {}
            lock.lock()
            styleLoaded = hook
            lock.unlock()
        }
    }

    private func serve(document json: String, to vector: VectorStyleSupport) {
        host.tileServer.registerDocument(
            id: documentId, contentType: "application/json", body: Data(json.utf8))
        lock.lock()
        servedDocument = true
        lock.unlock()
        // Providers identify designs by URL, and native engines cache styles
        // by that URL. Replacing only the response body leaves the old style
        // on screen on backends without in-place mutation support (MapTiler).
        documentRevision += 1
        vector.showStyle(
            url: host.tileServer.documentUrl(id: documentId) + "?revision=\(documentRevision)",
            attributionRules: Installation.attributions(of: json).map {
                AttributionRule(attribution: $0)
            }
        )
    }

    private func handle(
        unapplied: [StyleMutation], vector: VectorStyleSupport, compiled: CompiledStyle,
        style: VectorStyle
    ) {
        // Named by property, not by layer. A backend with no property for a
        // spec key fails that key on every layer that uses it, so the layer
        // list was hundreds of names for one cause -- and never said which
        // property, which is the only part an app can act on.
        let properties = Array(Set(unapplied.map(\.propertyName))).sorted()
        let shown = properties.prefix(5)
        let more = properties.count > shown.count ? ", ..." : ""
        let layers = Set(unapplied.map(\.layerId)).count
        let message =
            "\(unapplied.count) adjustments were not applied: this map cannot set these "
            + "properties by name (\(shown.joined(separator: ", "))\(more)) "
            + "across \(layers) layers"
        switch style.onUnsupported {
        case .report:
            report([message])
        case .reload:
            report(["\(message); handing the map the adjusted document instead"])
            host.serviceRegistry.get(VectorStyleMutationSupportKey.self)?.clear()
            serve(document: compiled.styleJSON, to: vector)
        }
    }

    private func resolve(_ source: VectorStyleSource) throws -> String {
        switch source {
        case let .text(json):
            return json
        case let .url(url, headers):
            return try Installation.fetch(url, headers: headers)
        case .currentDesign:
            guard let url = host.vectorStyleUrl else {
                throw VectorStyleError.unreadable(
                    "this map is not drawing a vector style, so there is nothing to adjust; "
                        + "give `document` a style of your own")
            }
            return try Installation.fetch(url, headers: [:])
        }
    }

    private func report(_ diagnostics: [String]) {
        guard !diagnostics.isEmpty else { return }
        host.report(diagnostics)
        style.onDiagnostics?(diagnostics)
    }

    /**
     Where a style is fetched and compiled.

     Serial: a map has one style, the work is a round trip plus a parse, and
     two rule changes in flight at once would race to be the last applied.
     */
    private static let workers = DispatchQueue(
        label: "com.mapconductor.vectorstyle", qos: .userInitiated)

    /// Runs now when already on the main thread, and hops otherwise.
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private static func fetch(_ url: String, headers: [String: String]) throws -> String {
        guard let target = URL(string: url) else {
            throw VectorStyleError.unreadable("not a URL: \(url)")
        }
        var request = URLRequest(url: target, timeoutInterval: 15)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        // Synchronous on purpose: this already runs on a worker, and the
        // caller is a sequence of steps that have to happen in order.
        var answer: Result<String, Error> = .failure(
            VectorStyleError.unreadable("the style could not be fetched"))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.signal() }
            if let error {
                answer = .failure(error)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                answer = .failure(VectorStyleError.unreadable("HTTP \(status) for \(url)"))
                return
            }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                answer = .failure(VectorStyleError.unreadable("the style was not text"))
                return
            }
            answer = .success(text)
        }.resume()
        done.wait()
        return try answer.get()
    }

    /**
     The credits the style's sources ask for.

     Carried onto the design so the map's attribution overlay shows them for
     as long as the style is up. Nothing else about this can be wrong while
     still looking right: the map draws perfectly whether or not anyone is
     credited for the data.
     */
    private static func attributions(of json: String) -> [String] {
        guard
            let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any],
            let sources = parsed["sources"] as? [String: Any]
        else { return [] }
        var seen: [String] = []
        for key in sources.keys.sorted() {
            guard
                let source = sources[key] as? [String: Any],
                let credit = source["attribution"] as? String,
                !credit.isEmpty, !seen.contains(credit)
            else { continue }
            seen.append(credit)
        }
        return seen
    }
}
