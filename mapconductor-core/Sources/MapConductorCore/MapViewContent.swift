import SwiftUI
import UIKit

public typealias OnMapLoadedHandler<State: MapViewStateProtocol> = (State) -> Void
public typealias OnMapEventHandler = (GeoPoint) -> Void
public typealias OnCameraMoveHandler = (MapCameraPosition) -> Void

public protocol MapOverlayItemProtocol {
    func append(to content: inout MapViewContent)
}

public struct MapViewContent {
    public var markers: [Marker] = []
    public var infoBubbles: [InfoBubble] = []
    public var polylines: [Polyline] = []
    public var polygons: [Polygon] = []
    public var circles: [Circle] = []
    public var rasterLayers: [RasterLayer] = []

    public init() {}

    mutating func append(_ item: MapOverlayItemProtocol) {
        item.append(to: &self)
    }

    mutating func merge(_ other: MapViewContent) {
        markers.append(contentsOf: other.markers)
        infoBubbles.append(contentsOf: other.infoBubbles)
        polylines.append(contentsOf: other.polylines)
        polygons.append(contentsOf: other.polygons)
        circles.append(contentsOf: other.circles)
        rasterLayers.append(contentsOf: other.rasterLayers)
    }
}

@resultBuilder
public enum MapViewContentBuilder {
    public static func buildBlock() -> MapViewContent {
        MapViewContent()
    }

    public static func buildBlock(_ components: MapViewContent...) -> MapViewContent {
        var content = MapViewContent()
        for component in components {
            content.merge(component)
        }
        return content
    }

    public static func buildOptional(_ component: MapViewContent?) -> MapViewContent {
        component ?? MapViewContent()
    }

    public static func buildEither(first component: MapViewContent) -> MapViewContent {
        component
    }

    public static func buildEither(second component: MapViewContent) -> MapViewContent {
        component
    }

    public static func buildArray(_ components: [MapViewContent]) -> MapViewContent {
        var content = MapViewContent()
        for component in components {
            content.merge(component)
        }
        return content
    }

    public static func buildExpression(_ expression: MapOverlayItemProtocol) -> MapViewContent {
        var content = MapViewContent()
        content.append(expression)
        return content
    }

    public static func buildExpression(_ expression: MapViewContent) -> MapViewContent {
        expression
    }
}

public struct Marker: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let state: MarkerState

    public init(state: MarkerState) {
        self.state = state
        self.id = state.id
    }

    public init(
        position: GeoPointProtocol,
        id: String? = nil,
        extra: Any? = nil,
        icon: (any MarkerIconProtocol)? = nil,
        animation: MarkerAnimation? = nil,
        clickable: Bool = true,
        draggable: Bool = false,
        onClick: OnMarkerEventHandler? = nil,
        onDragStart: OnMarkerEventHandler? = nil,
        onDrag: OnMarkerEventHandler? = nil,
        onDragEnd: OnMarkerEventHandler? = nil,
        onAnimateStart: OnMarkerEventHandler? = nil,
        onAnimateEnd: OnMarkerEventHandler? = nil
    ) {
        let state = MarkerState(
            position: position,
            id: id,
            extra: extra,
            icon: icon,
            animation: animation,
            clickable: clickable,
            draggable: draggable,
            onClick: onClick,
            onDragStart: onDragStart,
            onDrag: onDrag,
            onDragEnd: onDragEnd,
            onAnimateStart: onAnimateStart,
            onAnimateEnd: onAnimateEnd
        )
        self.state = state
        self.id = state.id
    }

    public init(
        position: GeoPointProtocol,
        id: String? = nil,
        extra: Any? = nil,
        icon: DefaultMarkerIcon,
        animation: MarkerAnimation? = nil,
        clickable: Bool = true,
        draggable: Bool = false,
        onClick: OnMarkerEventHandler? = nil,
        onDragStart: OnMarkerEventHandler? = nil,
        onDrag: OnMarkerEventHandler? = nil,
        onDragEnd: OnMarkerEventHandler? = nil,
        onAnimateStart: OnMarkerEventHandler? = nil,
        onAnimateEnd: OnMarkerEventHandler? = nil
    ) {
        let state = MarkerState(
            position: position,
            id: id,
            extra: extra,
            icon: icon,
            animation: animation,
            clickable: clickable,
            draggable: draggable,
            onClick: onClick,
            onDragStart: onDragStart,
            onDrag: onDrag,
            onDragEnd: onDragEnd,
            onAnimateStart: onAnimateStart,
            onAnimateEnd: onAnimateEnd
        )
        self.state = state
        self.id = state.id
    }

    public func append(to content: inout MapViewContent) {
        content.markers.append(self)
    }
}

public struct InfoBubble: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let marker: MarkerState
    public let tailOffset: CGPoint
    public let content: AnyView

    public init<Content: View>(
        marker: MarkerState,
        tailOffset: CGPoint = CGPoint(x: 0.5, y: 1.0),
        useDefaultStyle: Bool = true,
        style: InfoBubbleStyle = .Default,
        @ViewBuilder content: () -> Content
    ) {
        self.id = marker.id
        self.marker = marker
        self.tailOffset = tailOffset
        let builtContent = AnyView(content())
        if useDefaultStyle {
            self.content = AnyView(DefaultInfoBubbleView(style: style, content: builtContent))
        } else {
            self.content = builtContent
        }
    }

    public func append(to content: inout MapViewContent) {
        content.infoBubbles.append(self)
    }
}

public struct Polyline: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let state: PolylineState

    public init(state: PolylineState) {
        self.state = state
        self.id = state.id
    }

    public init(
        points: [GeoPointProtocol],
        id: String? = nil,
        strokeColor: UIColor = .black,
        strokeWidth: Double = 1.0,
        geodesic: Bool = false,
        extra: Any? = nil,
        onClick: OnPolylineEventHandler? = nil
    ) {
        let state = PolylineState(
            points: points,
            id: id,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            geodesic: geodesic,
            extra: extra,
            onClick: onClick
        )
        self.state = state
        self.id = state.id
    }

    public init(
        bounds: GeoRectBounds,
        id: String? = nil,
        strokeColor: UIColor = .black,
        strokeWidth: Double = 1.0,
        geodesic: Bool = false,
        extra: Any? = nil,
        onClick: OnPolylineEventHandler? = nil
    ) {
        if let northEast = bounds.northEast, let southWest = bounds.southWest {
            let points: [GeoPointProtocol] = [
                northEast,
                GeoPoint(latitude: southWest.latitude, longitude: northEast.longitude),
                southWest,
                GeoPoint(latitude: northEast.latitude, longitude: southWest.longitude),
                northEast
            ]
            self.init(
                points: points,
                id: id,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                geodesic: geodesic,
                extra: extra,
                onClick: onClick
            )
        } else {
            self.init(
                points: [],
                id: id,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                geodesic: geodesic,
                extra: extra,
                onClick: onClick
            )
        }
    }

    public func append(to content: inout MapViewContent) {
        content.polylines.append(self)
    }
}

public struct Polygon: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let state: PolygonState

    public init(state: PolygonState) {
        self.state = state
        self.id = state.id
    }

    public init(
        points: [GeoPointProtocol],
        id: String? = nil,
        strokeColor: UIColor = .black,
        strokeWidth: Double = 1.0,
        fillColor: UIColor = .clear,
        geodesic: Bool = false,
        zIndex: Int = 0,
        extra: Any? = nil,
        onClick: OnPolygonEventHandler? = nil
    ) {
        let state = PolygonState(
            points: points,
            id: id,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            geodesic: geodesic,
            zIndex: zIndex,
            extra: extra,
            onClick: onClick
        )
        self.state = state
        self.id = state.id
    }

    public init(
        bounds: GeoRectBounds,
        id: String? = nil,
        strokeColor: UIColor = .black,
        strokeWidth: Double = 1.0,
        fillColor: UIColor = .clear,
        geodesic: Bool = false,
        zIndex: Int = 0,
        extra: Any? = nil,
        onClick: OnPolygonEventHandler? = nil
    ) {
        if let northEast = bounds.northEast, let southWest = bounds.southWest {
            let points: [GeoPointProtocol] = [
                northEast,
                GeoPoint(latitude: southWest.latitude, longitude: northEast.longitude),
                southWest,
                GeoPoint(latitude: northEast.latitude, longitude: southWest.longitude),
                northEast
            ]
            self.init(
                points: points,
                id: id,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                fillColor: fillColor,
                geodesic: geodesic,
                zIndex: zIndex,
                extra: extra,
                onClick: onClick
            )
        } else {
            self.init(
                points: [],
                id: id,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                fillColor: fillColor,
                geodesic: geodesic,
                zIndex: zIndex,
                extra: extra,
                onClick: onClick
            )
        }
    }

    public func append(to content: inout MapViewContent) {
        content.polygons.append(self)
    }
}

public struct Circle: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let state: CircleState

    public init(state: CircleState) {
        self.state = state
        self.id = state.id
    }

    public init(
        center: GeoPointProtocol,
        radiusMeters: Double,
        geodesic: Bool = true,
        clickable: Bool = true,
        strokeColor: UIColor = .red,
        strokeWidth: Double = 1.0,
        fillColor: UIColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5),
        id: String? = nil,
        zIndex: Int? = nil,
        extra: Any? = nil,
        onClick: OnCircleEventHandler? = nil
    ) {
        let state = CircleState(
            center: center,
            radiusMeters: radiusMeters,
            geodesic: geodesic,
            clickable: clickable,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            id: id,
            zIndex: zIndex,
            extra: extra,
            onClick: onClick
        )
        self.state = state
        self.id = state.id
    }

    public func append(to content: inout MapViewContent) {
        content.circles.append(self)
    }
}

public struct RasterLayer: MapOverlayItemProtocol, Identifiable {
    public let id: String
    public let state: RasterLayerState

    public init(state: RasterLayerState) {
        self.state = state
        self.id = state.id
    }

    public init(
        source: RasterSource,
        opacity: Double = 1.0,
        visible: Bool = true,
        id: String? = nil,
        extra: Any? = nil
    ) {
        let state = RasterLayerState(
            source: source,
            opacity: opacity,
            visible: visible,
            id: id,
            extra: extra
        )
        self.state = state
        self.id = state.id
    }

    public func append(to content: inout MapViewContent) {
        content.rasterLayers.append(self)
    }
}
