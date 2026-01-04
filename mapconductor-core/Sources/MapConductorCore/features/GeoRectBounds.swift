import Foundation

public final class GeoRectBounds: Equatable, Hashable {
    private var southWestValue: GeoPoint?
    private var northEastValue: GeoPoint?

    public init(
        southWest: GeoPoint? = nil,
        northEast: GeoPoint? = nil
    ) {
        self.southWestValue = southWest
        self.northEastValue = northEast
    }

    public var isEmpty: Bool {
        southWestValue == nil || northEastValue == nil
    }

    public var southWest: GeoPoint? {
        southWestValue
    }

    public var northEast: GeoPoint? {
        northEastValue
    }

    public func extend(point: GeoPointProtocol) {
        let wrapped = GeoPoint.from(position: point).wrap()
        let position = GeoPoint.from(position: wrapped)

        switch (southWestValue, northEastValue) {
        case (nil, nil):
            southWestValue = position
            northEastValue = position
            return
        case (let southWest?, nil):
            let south = min(southWest.latitude, position.latitude)
            let north = max(southWest.latitude, position.latitude)
            let west = min(southWest.longitude, position.longitude)
            let east = max(southWest.longitude, position.longitude)
            southWestValue = GeoPoint(latitude: south, longitude: west)
            northEastValue = GeoPoint(latitude: north, longitude: east)
            return
        case (nil, let northEast?):
            let south = min(northEast.latitude, position.latitude)
            let north = max(northEast.latitude, position.latitude)
            let west = min(northEast.longitude, position.longitude)
            let east = max(northEast.longitude, position.longitude)
            southWestValue = GeoPoint(latitude: south, longitude: west)
            northEastValue = GeoPoint(latitude: north, longitude: east)
            return
        case (.some, .some):
            var south = min(position.latitude, southWestValue!.latitude)
            var north = max(position.latitude, northEastValue!.latitude)

            var west = southWestValue!.longitude
            var east = northEastValue!.longitude

            if west > 0 && east < 0 {
                if position.longitude > 0 {
                    west = min(position.longitude, west)
                } else {
                    east = max(position.longitude, east)
                }
            } else {
                west = min(position.longitude, southWestValue!.longitude)
                east = max(position.longitude, northEastValue!.longitude)
            }

            let span = (east - west + 360).truncatingRemainder(dividingBy: 360)
            if span > 180.0 {
                let newWest = east
                let newEast = west
                west = newWest
                east = newEast
            }

            southWestValue = GeoPoint(latitude: south, longitude: west)
            northEastValue = GeoPoint(latitude: north, longitude: east)
        }
    }

    private func containsLongitude(_ lon: Double, west: Double, east: Double) -> Bool {
        if west <= east {
            return lon >= west && lon <= east
        }
        return lon >= west || lon <= east
    }

    public func contains(point: GeoPointProtocol) -> Bool {
        if isEmpty { return false }

        let wrappedPoint = GeoPoint.from(position: point).wrap()
        let wrapped = GeoPoint.from(position: wrappedPoint)
        let sw = GeoPoint.from(position: southWestValue!.wrap())
        let ne = GeoPoint.from(position: northEastValue!.wrap())

        let withinLat = wrapped.latitude >= sw.latitude && wrapped.latitude <= ne.latitude
        let withinLng = containsLongitude(wrapped.longitude, west: sw.longitude, east: ne.longitude)
        return withinLat && withinLng
    }

    public var center: GeoPoint? {
        if isEmpty { return nil }

        let sw = GeoPoint.from(position: southWestValue!.wrap())
        let ne = GeoPoint.from(position: northEastValue!.wrap())
        let centerLat = (sw.latitude + ne.latitude) / 2.0

        let lng1 = sw.longitude
        let lng2 = ne.longitude
        let centerLng: Double
        if lng1 <= lng2 {
            centerLng = (lng1 + lng2) / 2.0
        } else {
            let centerLongitude = (lng1 + (lng2 + 360.0)) / 2.0
            centerLng = centerLongitude > 180.0 ? centerLongitude - 360.0 : centerLongitude
        }

        return GeoPoint(latitude: centerLat, longitude: centerLng)
    }

    public func union(other: GeoRectBounds) -> GeoRectBounds {
        if other.isEmpty { return self }
        if isEmpty {
            southWestValue = other.southWest
            northEastValue = other.northEast
            return self
        }

        let newBounds = GeoRectBounds(southWest: southWest, northEast: northEast)
        if let southWest = other.southWestValue {
            newBounds.extend(point: southWest.wrap())
        }
        if let northEast = other.northEastValue {
            newBounds.extend(point: northEast.wrap())
        }
        return newBounds
    }

    public func toSpan() -> GeoPoint? {
        if isEmpty { return nil }

        let sw = GeoPoint.from(position: southWestValue!.wrap())
        let ne = GeoPoint.from(position: northEastValue!.wrap())
        let latSpan = ne.latitude - sw.latitude
        let lngSpan = (ne.longitude - sw.longitude + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
        let resolvedLngSpan = lngSpan == 0.0 ? 360.0 : lngSpan

        return GeoPoint(latitude: latSpan, longitude: resolvedLngSpan)
    }

    public func toUrlValue(precision: Int = 6) -> String {
        if isEmpty { return "1.0,180.0,-1.0,-180.0" }

        let sw = GeoPoint.from(position: southWestValue!.wrap())
        let ne = GeoPoint.from(position: northEastValue!.wrap())

        func toFixed(_ value: Double) -> String {
            String(format: "%.\(precision)f", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        return [
            toFixed(sw.latitude),
            toFixed(sw.longitude),
            toFixed(ne.latitude),
            toFixed(ne.longitude)
        ].joined(separator: ",")
    }

    public func expandedByDegrees(latPad: Double, lonPad: Double) -> GeoRectBounds {
        if isEmpty { return self }

        let sw = GeoPoint.from(position: southWestValue!.wrap())
        let ne = GeoPoint.from(position: northEastValue!.wrap())

        let south = max(-90.0, sw.latitude - latPad)
        let north = min(90.0, ne.latitude + latPad)

        func norm(_ lon: Double) -> Double {
            var value = (lon + 180.0).truncatingRemainder(dividingBy: 360.0)
            if value < 0 { value += 360.0 }
            return value - 180.0
        }

        var west = norm(sw.longitude - lonPad)
        var east = norm(ne.longitude + lonPad)

        let span = (east - west + 360.0).truncatingRemainder(dividingBy: 360.0)
        if span > 180.0 {
            let newWest = east
            let newEast = west
            west = newWest
            east = newEast
        }

        return GeoRectBounds(
            southWest: GeoPoint(latitude: south, longitude: west),
            northEast: GeoPoint(latitude: north, longitude: east)
        )
    }

    public func intersects(other: GeoRectBounds) -> Bool {
        if isEmpty || other.isEmpty { return false }

        let sw1 = GeoPoint.from(position: southWestValue!.wrap())
        let ne1 = GeoPoint.from(position: northEastValue!.wrap())
        let sw2 = GeoPoint.from(position: other.southWestValue!.wrap())
        let ne2 = GeoPoint.from(position: other.northEastValue!.wrap())

        let epsilon = 1e-9
        let latOverlap = ne1.latitude >= sw2.latitude - epsilon &&
            ne2.latitude >= sw1.latitude - epsilon
        if !latOverlap { return false }

        func norm(_ lon: Double) -> Double {
            var value = (lon + 180.0).truncatingRemainder(dividingBy: 360.0)
            if value < 0 { value += 360.0 }
            return value - 180.0
        }

        let w1 = norm(sw1.longitude)
        let e1 = norm(ne1.longitude)
        let w2 = norm(sw2.longitude)
        let e2 = norm(ne2.longitude)

        func lonIntervals(west: Double, east: Double) -> [(Double, Double)] {
            if west <= east {
                let span = east - west
                if span <= 180.0 {
                    return [(west, east)]
                }
                return [(west, 180.0), (-180.0, east)]
            }
            return [(west, 180.0), (-180.0, east)]
        }

        let intervals1 = lonIntervals(west: w1, east: e1)
        let intervals2 = lonIntervals(west: w2, east: e2)

        for (aStart, aEnd) in intervals1 {
            for (bStart, bEnd) in intervals2 {
                if aStart <= bEnd && aEnd >= bStart {
                    return true
                }
            }
        }

        return false
    }

    public func equals(other: GeoRectBounds) -> Bool {
        southWest == other.southWest && northEast == other.northEast
    }

    public func toString() -> String {
        if isEmpty {
            return "((1, 180), (-1, -180))"
        }
        guard let southWest = southWestValue, let northEast = northEastValue else {
            return "((1, 180), (-1, -180))"
        }
        return "((\(southWest.latitude), \(southWest.longitude)), (\(northEast.latitude), \(northEast.longitude)))"
    }

    public static func == (lhs: GeoRectBounds, rhs: GeoRectBounds) -> Bool {
        lhs.equals(other: rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(southWest)
        hasher.combine(northEast)
    }
}
