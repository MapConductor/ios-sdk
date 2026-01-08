import Foundation

public enum Spherical {
    private static let radToDeg = 180.0 / Double.pi
    private static let degToRad = Double.pi / 180.0
    private static let earthRadiusMeters: Double = 6_378_137.0

    public static func computeDistanceBetween(
        from: GeoPointProtocol,
        to: GeoPointProtocol
    ) -> Double {
        let lat1Rad = from.latitude * degToRad
        let lat2Rad = to.latitude * degToRad
        let deltaLat = (to.latitude - from.latitude) * degToRad
        let deltaLng = (to.longitude - from.longitude) * degToRad

        let haversineA =
            sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1Rad) * cos(lat2Rad) *
            sin(deltaLng / 2) * sin(deltaLng / 2)

        let centralAngle = 2 * atan2(sqrt(haversineA), sqrt(1 - haversineA))
        return earthRadiusMeters * centralAngle
    }

    public static func computeHeading(
        from: GeoPointProtocol,
        to: GeoPointProtocol
    ) -> Double {
        let lat1Rad = from.latitude * degToRad
        let lat2Rad = to.latitude * degToRad
        let deltaLng = (to.longitude - from.longitude) * degToRad

        let deltaY = sin(deltaLng) * cos(lat2Rad)
        let deltaX = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(deltaLng)

        var heading = atan2(deltaY, deltaX) * radToDeg
        while heading > 180 { heading -= 360 }
        while heading <= -180 { heading += 360 }
        return heading
    }

    public static func computeOffset(
        origin: GeoPointProtocol,
        distance: Double,
        heading: Double
    ) -> GeoPoint {
        let distanceRad = distance / earthRadiusMeters
        let headingRad = heading * degToRad
        let lat1Rad = origin.latitude * degToRad
        let lng1Rad = origin.longitude * degToRad

        let lat2Rad =
            asin(
                sin(lat1Rad) * cos(distanceRad) +
                cos(lat1Rad) * sin(distanceRad) * cos(headingRad)
            )

        let lng2Rad =
            lng1Rad +
            atan2(
                sin(headingRad) * sin(distanceRad) * cos(lat1Rad),
                cos(distanceRad) - sin(lat1Rad) * sin(lat2Rad)
            )

        return GeoPoint(
            latitude: lat2Rad * radToDeg,
            longitude: lng2Rad * radToDeg,
            altitude: origin.altitude ?? 0.0
        )
    }

    public static func computeOffsetOrigin(
        to: GeoPointProtocol,
        distance: Double,
        heading: Double
    ) -> GeoPoint? {
        let reverseHeading = (heading + 180).truncatingRemainder(dividingBy: 360)
        return computeOffset(origin: to, distance: distance, heading: reverseHeading)
    }

    public static func computeLength(_ path: [GeoPointProtocol]) -> Double {
        guard path.count >= 2 else { return 0.0 }
        var length = 0.0
        for index in 1..<path.count {
            length += computeDistanceBetween(from: path[index - 1], to: path[index])
        }
        return length
    }

    public static func computeArea(_ path: [GeoPointProtocol]) -> Double {
        abs(computeSignedArea(path))
    }

    public static func computeSignedArea(_ path: [GeoPointProtocol]) -> Double {
        guard path.count >= 3 else { return 0.0 }
        var area = 0.0
        let pointCount = path.count
        for i in 0..<pointCount {
            let j = (i + 1) % pointCount
            let lat1 = path[i].latitude * degToRad
            let lat2 = path[j].latitude * degToRad
            let deltaLng = (path[j].longitude - path[i].longitude) * degToRad
            area += deltaLng * (2 + sin(lat1) + sin(lat2))
        }
        return area * earthRadiusMeters * earthRadiusMeters / 2.0
    }

    public static func sphericalInterpolate(
        from: GeoPointProtocol,
        to: GeoPointProtocol,
        fraction: Double
    ) -> GeoPoint {
        let lat1 = from.latitude * degToRad
        let lng1 = from.longitude * degToRad
        let lat2 = to.latitude * degToRad
        let lng2 = to.longitude * degToRad

        let x1 = cos(lat1) * cos(lng1)
        let y1 = cos(lat1) * sin(lng1)
        let z1 = sin(lat1)

        let x2 = cos(lat2) * cos(lng2)
        let y2 = cos(lat2) * sin(lng2)
        let z2 = sin(lat2)

        let dot = x1 * x2 + y1 * y2 + z1 * z2
        let angle = acos(min(max(dot, -1.0), 1.0))

        if angle < 1e-6 {
            let interpolatedAltitude = interpolateAltitude(from: from, to: to, fraction: fraction)
            return GeoPoint(
                latitude: from.latitude + fraction * (to.latitude - from.latitude),
                longitude: from.longitude + fraction * (to.longitude - from.longitude),
                altitude: interpolatedAltitude
            )
        }

        let sinAngle = sin(angle)
        let weightFrom = sin((1 - fraction) * angle) / sinAngle
        let weightTo = sin(fraction * angle) / sinAngle

        let vectorX = weightFrom * x1 + weightTo * x2
        let vectorY = weightFrom * y1 + weightTo * y2
        let vectorZ = weightFrom * z1 + weightTo * z2

        let lat = asin(vectorZ) * radToDeg
        let lng = atan2(vectorY, vectorX) * radToDeg
        let interpolatedAltitude = interpolateAltitude(from: from, to: to, fraction: fraction)

        return GeoPoint(
            latitude: lat,
            longitude: lng,
            altitude: interpolatedAltitude
        )
    }

    public static func linearInterpolate(
        from: GeoPointProtocol,
        to: GeoPointProtocol,
        fraction: Double
    ) -> GeoPoint {
        let interpolatedAltitude = interpolateAltitude(from: from, to: to, fraction: fraction)
        let interpolatedLatitude = from.latitude + fraction * (to.latitude - from.latitude)

        let fromLng = from.longitude
        let toLng = to.longitude
        let directDiff = toLng - fromLng
        let crossMeridianDiff: Double
        if directDiff > 180 {
            crossMeridianDiff = directDiff - 360
        } else if directDiff < -180 {
            crossMeridianDiff = directDiff + 360
        } else {
            crossMeridianDiff = directDiff
        }
        let interpolatedLongitude = fromLng + fraction * crossMeridianDiff
        let normalizedLongitude = normalizeLng(interpolatedLongitude)

        return GeoPoint(
            latitude: interpolatedLatitude,
            longitude: normalizedLongitude,
            altitude: interpolatedAltitude
        )
    }

    private static func normalizeLng(_ lng: Double) -> Double {
        (((lng + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
    }

    private static func interpolateAltitude(
        from: GeoPointProtocol,
        to: GeoPointProtocol,
        fraction: Double
    ) -> Double {
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
}
