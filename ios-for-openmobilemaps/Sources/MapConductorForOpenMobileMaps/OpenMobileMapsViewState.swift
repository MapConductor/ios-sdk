import Combine
import Foundation
import MapConductorCore

/// アプリ側の状態（実装点 G）。
///
/// カメラの保持・``MapViewState/moveCameraTo(cameraPosition:durationMillis:)``・
/// `fitBounds`・`uiSettings`・`id` はコアの ``MapViewState`` が持つ。
/// ドライバーが書くのは **Open Mobile Maps 固有のもの**だけ:
///
///  - `mapDesignType`（プロバイダ固有の型）
///  - プロバイダ型のホルダーと、それを返す `getMapViewHolder()` の絞り込み
///
/// `getMapViewHolder()` の絞り込みは**消さないこと**。消すとアプリ側の
/// `state.getMapViewHolder()?.map` が静的型を失う（ソース非互換）。
/// 1 行に縮めるのは可、消すのは不可。
///
/// android-for-openmobilemaps の `OpenMobileMapsViewState` と同じ内容。
public final class OpenMobileMapsViewState: MapViewState<any OpenMobileMapsMapDesignTypeProtocol> {
    @Published private var _mapDesignType: any OpenMobileMapsMapDesignTypeProtocol

    /// プロバイダ型のホルダー。`map` は `MCMapInterface`、`mapView` は
    /// ``OpenMobileMapsMapSurface`` で、キャストが要らない。
    public private(set) var mapViewHolder: OpenMobileMapsMapViewHolder?

    /// 地図デザイン。
    ///
    /// この SDK には「素の地図」が無く、デザイン ＝ **一番下に敷くタイルレイヤ**なので、
    /// 差し替えはレイヤの入れ替えになる（``OpenMobileMapsDesign`` を参照）。
    ///
    /// android の state はここでコントローラを直接呼んでいるが、iOS では**呼ばない**。
    /// SwiftUI では `updateUIView` が状態の変化を受け取る場所で、他の 9 プロバイダも
    /// そちらでネイティブへ反映している。ここから呼ぶと反映の入口が 2 つになる。
    override public var mapDesignType: any OpenMobileMapsMapDesignTypeProtocol {
        get { _mapDesignType }
        set { _mapDesignType = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        mapDesignType: any OpenMobileMapsMapDesignTypeProtocol = OpenMobileMapsDesign.openStreetMap,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        _mapDesignType = mapDesignType
        super.init(id: id, initialCameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    /// 戻り型をこのプロバイダのホルダーへ絞る（アプリが `?.map` を取れる形を保つため）。
    override public func getMapViewHolder() -> AnyMapViewHolder? {
        mapViewHolder.map { AnyMapViewHolder($0) }
    }

    func setController(_ controller: OpenMobileMapsMapViewController?) {
        attachController(controller)
    }

    func setMapViewHolder(_ holder: OpenMobileMapsMapViewHolder?) {
        mapViewHolder = holder
    }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) {
        setCameraPositionInternal(cameraPosition)
    }
}
