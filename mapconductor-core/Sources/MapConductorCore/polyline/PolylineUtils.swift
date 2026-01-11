import Foundation

private enum PolylineEarth {
    static let radiusMeters: Double = 6_378_137.0
    static let circumferenceMeters: Double = 2.0 * Double.pi * radiusMeters
}

public func calculateMetersPerPixel(
    latitude: Double,
    zoom: Double,
    tileSize: Double = Double(RasterSource.defaultTileSize)
) -> Double {
    let metersPerPixelAtEquator = PolylineEarth.circumferenceMeters / tileSize
    let metersPerPixelAtZoom = metersPerPixelAtEquator / pow(2.0, zoom)
    let latitudeAdjustment = cos(deg2rad(abs(latitude)))
    return metersPerPixelAtZoom * latitudeAdjustment
}

public func createInterpolatePoints(
    _ points: [GeoPointProtocol],
    maxSegmentLength: Double = 10_000.0
) -> [GeoPointProtocol] {
    guard points.count >= 2 else { return points }
    var results: [GeoPointProtocol] = [points[0]]

    for index in 1..<points.count {
        let from = points[index - 1]
        let to = points[index]
        let distance = haversineDistance(from: from, to: to)
        let segments = max(1, Int(distance / maxSegmentLength))
        let step = 1.0 / Double(segments)

        var fraction = step
        while fraction < 1.0 {
            results.append(geodesicInterpolate(from: from, to: to, fraction: fraction))
            fraction += step
        }
        results.append(to)
    }
    return results
}

public func createLinearInterpolatePoints(
    _ points: [GeoPointProtocol],
    fractionStep: Double = 0.01
) -> [GeoPointProtocol] {
    guard points.count >= 2 else { return points }
    var results: [GeoPointProtocol] = [points[0]]

    for index in 1..<points.count {
        let from = points[index - 1]
        let to = points[index]
        var fraction = fractionStep
        while fraction <= 1.0 {
            results.append(linearInterpolate(from: from, to: to, fraction: fraction))
            fraction += fractionStep
        }
        results.append(to)
    }
    return results
}

public func splitByMeridian(
    _ points: [GeoPointProtocol],
    geodesic: Bool
) -> [[GeoPointProtocol]] {
    guard !points.isEmpty else { return [] }
    var results: [[GeoPointProtocol]] = []
    var fragment: [GeoPointProtocol] = []

    for point in points {
        if fragment.isEmpty {
            fragment.append(point)
            continue
        }

        let previousPoint = fragment.last!
        let prevLng = previousPoint.longitude
        let currLng = point.longitude
        let lngDiff = currLng - prevLng
        let crossesMeridian = abs(lngDiff) > 180.0

        if !crossesMeridian {
            fragment.append(point)
            continue
        }

        let meridianPoint = interpolateAtMeridian(from: previousPoint, to: point, geodesic: geodesic)
        fragment.append(meridianPoint)
        results.append(fragment)
        fragment = []

        let opposite = createOppositeMeridianPoint(meridianPoint)
        fragment.append(opposite)
        fragment.append(point)
    }

    if !fragment.isEmpty {
        results.append(fragment)
    }

    return results
}

func pointOnGeodesicSegmentOrNull(
    from: GeoPointProtocol,
    to: GeoPointProtocol,
    position: GeoPointProtocol,
    thresholdMeters: Double
) -> (GeoPointProtocol, Double)? {
    let totalDistance = haversineDistance(from: from, to: to)
    if totalDistance == 0.0 {
        let distFrom = haversineDistance(from: from, to: position)
        if distFrom <= thresholdMeters {
            return (GeoPoint.from(position: from), distFrom)
        }
        return nil
    }

    var left = 0.0
    var right = 1.0
    let epsilon = 1e-6

    while right - left > epsilon {
        let m1 = left + (right - left) / 3.0
        let m2 = right - (right - left) / 3.0

        let point1 = geodesicInterpolate(from: from, to: to, fraction: m1)
        let dist1 = haversineDistance(from: point1, to: position)

        let point2 = geodesicInterpolate(from: from, to: to, fraction: m2)
        let dist2 = haversineDistance(from: point2, to: position)

        if dist1 > dist2 {
            left = m1
        } else {
            right = m2
        }
    }

    let bestFraction = (left + right) / 2.0

    if bestFraction <= 0.0 || bestFraction >= 1.0 {
        let distFrom = haversineDistance(from: from, to: position)
        let distTo = haversineDistance(from: to, to: position)
        let minDistance = min(distFrom, distTo)
        if minDistance > thresholdMeters { return nil }

        let chosen = distFrom <= distTo ? from : to
        return (GeoPoint.from(position: chosen), minDistance)
    }

    let closestPoint = geodesicInterpolate(from: from, to: to, fraction: bestFraction)
    let minDistance = haversineDistance(from: closestPoint, to: position)
    if minDistance > thresholdMeters { return nil }

    let altitude = interpolateAltitude(from: from, to: to, fraction: bestFraction)
    return (GeoPoint(latitude: closestPoint.latitude, longitude: closestPoint.longitude, altitude: altitude), minDistance)
}

func isPointOnLinearLine(
    from: GeoPointProtocol,
    to: GeoPointProtocol,
    position: GeoPointProtocol,
    thresholdMeters: Double
) -> (GeoPointProtocol, Double)? {
    let fromLng = from.longitude
    let directDiff = to.longitude - fromLng
    let crossMeridianDiff: Double
    if directDiff > 180.0 {
        crossMeridianDiff = directDiff - 360.0
    } else if directDiff < -180.0 {
        crossMeridianDiff = directDiff + 360.0
    } else {
        crossMeridianDiff = directDiff
    }

    func unwrapLngRelative(baseLng: Double, targetLng: Double) -> Double {
        var diff = targetLng - baseLng
        while diff > 180.0 { diff -= 360.0 }
        while diff < -180.0 { diff += 360.0 }
        return baseLng + diff
    }

    let toLngUnwrapped = fromLng + crossMeridianDiff
    let posLngUnwrapped = unwrapLngRelative(baseLng: fromLng, targetLng: position.longitude)

    let lat0Rad = deg2rad((from.latitude + to.latitude) / 2.0)
    let metersPerDegLat = 111_132.954
    let metersPerDegLng = metersPerDegLat * cos(lat0Rad)

    func toMetersPoint(lat: Double, lng: Double) -> (Double, Double) {
        (lng * metersPerDegLng, lat * metersPerDegLat)
    }

    let a = toMetersPoint(lat: from.latitude, lng: fromLng)
    let b = toMetersPoint(lat: to.latitude, lng: toLngUnwrapped)
    let pp = toMetersPoint(lat: position.latitude, lng: posLngUnwrapped)

    let segmentVectorX = b.0 - a.0
    let segmentVectorY = b.1 - a.1
    let pointVectorX = pp.0 - a.0
    let pointVectorY = pp.1 - a.1
    let segmentLengthSquared = segmentVectorX * segmentVectorX + segmentVectorY * segmentVectorY

    if segmentLengthSquared == 0.0 {
        let deltaX = pp.0 - a.0
        let deltaY = pp.1 - a.1
        let d = sqrt(deltaX * deltaX + deltaY * deltaY)
        if d > thresholdMeters { return nil }
        let altitude = from.altitude ?? to.altitude ?? 0.0
        return (
            GeoPoint(latitude: from.latitude, longitude: normalizeLng(fromLng), altitude: altitude),
            d
        )
    }

    let t = max(0.0, min(1.0, (pointVectorX * segmentVectorX + pointVectorY * segmentVectorY) / segmentLengthSquared))
    let projectionX = a.0 + t * segmentVectorX
    let projectionY = a.1 + t * segmentVectorY
    let deltaX = pp.0 - projectionX
    let deltaY = pp.1 - projectionY
    let distanceMeters = sqrt(deltaX * deltaX + deltaY * deltaY)

    if distanceMeters > thresholdMeters { return nil }

    let latitude = from.latitude + t * (to.latitude - from.latitude)
    let longitude = fromLng + t * crossMeridianDiff
    let altitude = interpolateAltitude(from: from, to: to, fraction: t)

    return (
        GeoPoint(latitude: latitude, longitude: normalizeLng(longitude), altitude: altitude),
        distanceMeters
    )
}

private func interpolateAtMeridian(
    from: GeoPointProtocol,
    to: GeoPointProtocol,
    geodesic: Bool
) -> GeoPoint {
    if geodesic {
        return interpolateAtMeridianGeodesic(from: from, to: to)
    }
    return interpolateAtMeridianLinear(from: from, to: to)
}

private func interpolateAtMeridianLinear(
    from: GeoPointProtocol,
    to: GeoPointProtocol
) -> GeoPoint {
    let fromLng = from.longitude
    let toLng = to.longitude
    let targetMeridian = fromLng >= 0 ? 180.0 : -180.0
    let totalLngDiff = toLng - fromLng
    let meridianDiff = targetMeridian - fromLng
    let fraction = meridianDiff / totalLngDiff

    let latitude = from.latitude + fraction * (to.latitude - from.latitude)
    let altitude = interpolateAltitude(from: from, to: to, fraction: fraction)

    return GeoPoint(latitude: latitude, longitude: targetMeridian, altitude: altitude)
}

private func interpolateAtMeridianGeodesic(
    from: GeoPointProtocol,
    to: GeoPointProtocol
) -> GeoPoint {
    let fromLng = from.longitude
    let targetMeridian = fromLng >= 0 ? 180.0 : -180.0
    let targetUnwrapped = unwrapLngRelative(baseLng: fromLng, targetLng: targetMeridian)

    var low = 0.0
    var high = 1.0
    for _ in 0..<60 {
        let mid = (low + high) / 2.0
        let point = geodesicInterpolate(from: from, to: to, fraction: mid)
        let midLng = unwrapLngRelative(baseLng: fromLng, targetLng: point.longitude)

        if midLng < targetUnwrapped {
            low = mid
        } else {
            high = mid
        }
    }

    let finalFraction = (low + high) / 2.0
    let crossingPoint = geodesicInterpolate(from: from, to: to, fraction: finalFraction)

    return GeoPoint(latitude: crossingPoint.latitude, longitude: targetMeridian, altitude: crossingPoint.altitude ?? 0.0)
}

private func createOppositeMeridianPoint(_ point: GeoPointProtocol) -> GeoPoint {
    let oppositeLongitude = point.longitude >= 0 ? -180.0 : 180.0
    return GeoPoint(latitude: point.latitude, longitude: oppositeLongitude, altitude: point.altitude ?? 0.0)
}

private func geodesicInterpolate(
    from: GeoPointProtocol,
    to: GeoPointProtocol,
    fraction: Double
) -> GeoPoint {
    let f = max(0.0, min(1.0, fraction))
    let lat1 = deg2rad(from.latitude)
    let lon1 = deg2rad(from.longitude)
    let lat2 = deg2rad(to.latitude)
    let lon2 = deg2rad(to.longitude)

    let v1 = (
        x: cos(lat1) * cos(lon1),
        y: cos(lat1) * sin(lon1),
        z: sin(lat1)
    )
    let v2 = (
        x: cos(lat2) * cos(lon2),
        y: cos(lat2) * sin(lon2),
        z: sin(lat2)
    )

    var dot = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
    dot = min(1.0, max(-1.0, dot))
    let omega = acos(dot)
    if abs(omega) < 1e-12 {
        return GeoPoint.from(position: from)
    }

    let sinOmega = sin(omega)
    let t1 = sin((1.0 - f) * omega) / sinOmega
    let t2 = sin(f * omega) / sinOmega

    let x = t1 * v1.x + t2 * v2.x
    let y = t1 * v1.y + t2 * v2.y
    let z = t1 * v1.z + t2 * v2.z

    let lat = atan2(z, sqrt(x * x + y * y))
    let lon = atan2(y, x)
    let altitude = interpolateAltitude(from: from, to: to, fraction: f)

    return GeoPoint(latitude: rad2deg(lat), longitude: rad2deg(lon), altitude: altitude)
}

private func linearInterpolate(
    from: GeoPointProtocol,
    to: GeoPointProtocol,
    fraction: Double
) -> GeoPoint {
    let f = max(0.0, min(1.0, fraction))
    let latitude = from.latitude + (to.latitude - from.latitude) * f
    let fromLng = from.longitude
    let directDiff = to.longitude - fromLng
    let crossMeridianDiff: Double
    if directDiff > 180.0 {
        crossMeridianDiff = directDiff - 360.0
    } else if directDiff < -180.0 {
        crossMeridianDiff = directDiff + 360.0
    } else {
        crossMeridianDiff = directDiff
    }
    let longitude = normalizeLng(fromLng + crossMeridianDiff * f)
    let altitude = interpolateAltitude(from: from, to: to, fraction: f)
    return GeoPoint(latitude: latitude, longitude: longitude, altitude: altitude)
}

private func interpolateAltitude(from: GeoPointProtocol, to: GeoPointProtocol, fraction: Double) -> Double {
    let f = max(0.0, min(1.0, fraction))
    switch (from.altitude, to.altitude) {
    case let (fromAlt?, toAlt?):
        return fromAlt + (toAlt - fromAlt) * f
    case let (fromAlt?, nil):
        return fromAlt
    case let (nil, toAlt?):
        return toAlt
    default:
        return 0.0
    }
}

private func haversineDistance(from: GeoPointProtocol, to: GeoPointProtocol) -> Double {
    let lat1 = deg2rad(from.latitude)
    let lon1 = deg2rad(from.longitude)
    let lat2 = deg2rad(to.latitude)
    let lon2 = deg2rad(to.longitude)

    let dLat = lat2 - lat1
    let dLon = lon2 - lon1

    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return PolylineEarth.radiusMeters * c
}

private func normalizeLng(_ lng: Double) -> Double {
    (((lng + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
}

private func unwrapLngRelative(baseLng: Double, targetLng: Double) -> Double {
    var diff = targetLng - baseLng
    while diff > 180.0 { diff -= 360.0 }
    while diff < -180.0 { diff += 360.0 }
    return baseLng + diff
}

private func deg2rad(_ deg: Double) -> Double {
    deg * Double.pi / 180.0
}

private func rad2deg(_ rad: Double) -> Double {
    rad * 180.0 / Double.pi
}
