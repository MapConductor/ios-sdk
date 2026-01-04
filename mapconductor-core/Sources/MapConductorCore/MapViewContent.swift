import SwiftUI

public typealias OnMapLoadedHandler<State: MapViewStateProtocol> = (State) -> Void
public typealias OnMapEventHandler = (GeoPoint) -> Void
public typealias OnCameraMoveHandler = (MapCameraPosition) -> Void

public protocol MapOverlayItemProtocol {
    func append(to content: inout MapViewContent)
}

public struct MapViewContent {
    public var markers: [Marker] = []
    public var infoBubbles: [InfoBubble] = []

    public init() {}

    mutating func append(_ item: MapOverlayItemProtocol) {
        item.append(to: &self)
    }

    mutating func merge(_ other: MapViewContent) {
        markers.append(contentsOf: other.markers)
        infoBubbles.append(contentsOf: other.infoBubbles)
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
