# MapConductor iOS SDK

- [English Doc](./README.md)
- [Japanese Doc](./README.ja.md)

**Una sola API de mapas para iOS que funciona con múltiples proveedores de mapas.**

MapConductor iOS SDK es una librería de mapas para iOS que te permite trabajar con múltiples SDKs de mapas a través de una API única y consistente basada en SwiftUI.

En lugar de escribir código de mapas distinto para Google Maps, Mapbox, Apple MapKit, ArcGIS, HERE Maps y MapLibre, MapConductor ofrece abstracciones compartidas para mapas, estado de cámara, marcadores, formas, superposiciones y funciones avanzadas de mapas.

Escribe tu interfaz de mapa una sola vez.
Elige el proveedor de mapas que mejor se adapte a tu producto.

---

## ¿Por qué MapConductor?

El desarrollo de mapas para móviles suele quedar fuertemente acoplado a un SDK de mapas específico. Cada proveedor tiene su propio diseño de API, modelo de ciclo de vida, comportamiento de renderizado y conjunto de funciones. Esto dificulta cambiar de proveedor, dar soporte a varios backends de mapas o mantener limpio el código relacionado con mapas en una aplicación moderna con SwiftUI.

MapConductor resuelve esto proporcionando una capa común sobre los principales SDKs de mapas para iOS.

Con MapConductor puedes:

* Usar una API orientada a SwiftUI para la interfaz de mapas
* Cambiar entre los proveedores de mapas compatibles con menos trabajo de reescritura
* Compartir la misma lógica de marcadores, círculos, polilíneas, polígonos y superposiciones
* Construir funciones de mapas independientes del proveedor, como mapas de calor y agrupamiento de marcadores
* Mantener tu código de aplicación enfocado en el comportamiento del mapa, no en las diferencias específicas de cada SDK

![](./images/es-419-comic-why-mapconductor.jpg)

---

## Proveedores de mapas compatibles

MapConductor actualmente es compatible con los siguientes proveedores de mapas para iOS:

| Proveedor        | Paquete                        | Producto                        |
| ---------------- | ------------------------------ | -------------------------------- |
| Google Maps      | `ios-for-googlemaps`          | `MapConductorForGoogleMaps`     |
| Mapbox           | `ios-for-mapbox`              | `MapConductorForMapbox`         |
| Apple MapKit     | `ios-for-mapkit`              | `MapConductorForMapKit`         |
| ArcGIS           | `ios-for-arcgis`              | `MapConductorForArcGIS`         |
| HERE Maps        | `ios-for-here`                | `MapConductorForHERE`           |
| MapLibre         | `ios-for-maplibre`            | `MapConductorForMapLibre`       |

Puedes elegir un proveedor para tu app, o estructurar tu código de modo que el proveedor pueda cambiarse más adelante.

---

## Funciones principales

MapConductor ofrece una API unificada para las funciones comunes de interfaz de mapas y geoespaciales:

* Componentes de vista de mapa para múltiples proveedores
* Estado de cámara y posición de cámara
* Marcadores
* Iconos de marcador personalizados
* Círculos con radio en metros
* Polilíneas
* Polígonos
* Imágenes de superficie (ground images)
* Capas de teselas ráster (raster tile layers)
* Mapas de calor
* Agrupamiento de marcadores
* Capas GeoJSON
* Tipos de geometría compartidos como `GeoPoint`
* Gestión de estado reactiva para objetos de mapa, construida sobre SwiftUI

El objetivo no es solo envolver el SDK de cada proveedor, sino también ofrecer un comportamiento consistente, en la medida de lo posible, entre los distintos motores de mapas.

---

## Instalación

Agrega los paquetes necesarios en Xcode (File → Add Package Dependencies) o directamente en tu `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.5"),
    .package(url: "https://github.com/MapConductor/ios-for-googlemaps", from: "1.0.5"), // o el proveedor que elijas

    // Paquetes de funciones opcionales
    .package(url: "https://github.com/MapConductor/ios-heatmap", from: "1.0.3"),
    .package(url: "https://github.com/MapConductor/ios-marker-cluster", from: "1.0.2"),
    .package(url: "https://github.com/MapConductor/ios-geojson-layer", from: "1.0.0"),
],
```

Luego agrega los productos a tu target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MapConductorCore", package: "ios-sdk-core"),
        .product(name: "MapConductorForGoogleMaps", package: "ios-for-googlemaps"),
    ]
)
```

Cada proveedor de mapas puede requerir su propia clave de API, token de acceso, o configuración del proyecto de Xcode (como entradas en el Info.plist). Por favor revisa la guía de configuración del proveedor que estés usando.

---

## Ejemplo básico

El siguiente ejemplo muestra un mapa simple con SwiftUI que incluye un marcador y un círculo.

```swift
import SwiftUI
import MapConductorCore
import MapConductorForGoogleMaps

struct ContentView: View {
    @StateObject private var mapState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6762, longitude: 139.6503),
            zoom: 12
        )
    )

    var body: some View {
        GoogleMapView(state: mapState) {
            Marker(position: GeoPoint(latitude: 35.6762, longitude: 139.6503))
            Circle(
                center: GeoPoint(latitude: 35.6762, longitude: 139.6503),
                radiusMeters: 500
            )
        }
    }
}
```

Este ejemplo usa Google Maps, pero los objetos del mapa están escritos usando conceptos de MapConductor. La misma lógica de superposiciones se puede adaptar a otros proveedores compatibles.

---

## Cambiar de proveedor de mapas

Una de las ideas principales detrás de MapConductor es que tus superposiciones de mapa no deberían tener que reescribirse cuando cambias de proveedor de mapas.

Simplemente cambia el estado y la vista — todas las superposiciones funcionan sin cambios:

```swift
// Google Maps
GoogleMapView(state: googleMapState) { /* overlays */ }

// Mapbox
MapboxMapView(state: mapboxState) { /* overlays */ }

// Apple MapKit
MapKitMapView(state: mapKitState) { /* overlays */ }

// ArcGIS
ArcGISMapView(state: arcgisState) { /* overlays */ }

// HERE Maps
HEREMapView(state: hereMapState) { /* overlays */ }

// MapLibre
MapLibreMapView(state: maplibreState) { /* overlays */ }
```

Tu contenido de mapa reutilizable puede incluir marcadores, círculos, polilíneas, polígonos, mapas de calor, agrupaciones u otros componentes de MapConductor, sin importar qué vista de proveedor los renderice.

Aún se requiere una configuración específica por proveedor, pero la interfaz de mapas a nivel de aplicación puede ser mucho más portable.

---

## Resumen de módulos

| Módulo                        | Paquete                            | Producto                          | Descripción                                                            |
| ----------------------------- | --------------------------------- | --------------------------------- | --------------------------------------------------------------------- |
| `ios-sdk-core`                | `mapconductor-core`               | `MapConductorCore`               | Abstracciones principales, tipos de geometría, estado de superposiciones |
| `ios-for-googlemaps`          | `mapconductor-for-googlemaps`     | `MapConductorForGoogleMaps`      | Implementación del proveedor Google Maps                              |
| `ios-for-mapbox`              | `ios-for-mapbox`                  | `MapConductorForMapbox`          | Implementación del proveedor Mapbox                                   |
| `ios-for-mapkit`              | `mapconductor-for-mapkit`         | `MapConductorForMapKit`          | Implementación del proveedor Apple MapKit                             |
| `ios-for-arcgis`              | `mapconductor-for-arcgis`         | `MapConductorForArcGIS`          | Implementación del proveedor ArcGIS                                   |
| `ios-for-here`                | `mapconductor-for-here`           | `MapConductorForHERE`            | Implementación del proveedor HERE Maps                                |
| `ios-for-maplibre`            | `mapconductor-for-maplibre`       | `MapConductorForMapLibre`        | Implementación del proveedor MapLibre                                 |
| `ios-heatmap`                 | `mapconductor-heatmap`            | `MapConductorHeatmap`            | Superposición de mapa de calor independiente del proveedor            |
| `ios-marker-cluster`          | `mapconductor-marker-cluster`     | `MapConductorMarkerCluster`      | Soporte de agrupamiento de marcadores                                 |
| `ios-geojson-layer`           | `mapconductor-geojson-layer`      | `MapConductorGeoJSONLayer`       | Soporte de capas GeoJSON                                              |

---

## Estado de las funciones

| Función           | Google Maps | Mapbox   | MapKit   | ArcGIS   | HERE Maps | MapLibre |
| ------------------ | -----------: | --------: | --------: | --------: | --------: | --------: |
| Map               |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker            |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Circle            |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polyline          |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polygon           |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Ground Image      |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Heatmap           |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker Clustering |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Raster Tile Layer |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Vector Tile Layer |     &#x2610; | &#x2610; | &#x2610; | &#x2610; | &#x2610; | &#x2610; |

MapConductor está en desarrollo activo. Consulta la documentación y las notas de la versión para conocer el comportamiento y las limitaciones más recientes de cada proveedor.

---

## ¿Para quién es esto?

MapConductor te resulta útil si estás:

* Construyendo una app de iOS con SwiftUI y mapas
* Evaluando múltiples proveedores de mapas
* Planeando una posible migración de un SDK de mapas a otro
* Manteniendo funciones de mapas para distintos requisitos de clientes o regiones
* Construyendo componentes de interfaz de mapas reutilizables
* Buscando una capa de abstracción de código abierto para mapas móviles

Es especialmente útil cuando quieres que tu código de aplicación describa qué debe aparecer en el mapa, en lugar de cómo espera cada SDK de proveedor que se implemente esa función.

---

## Ejemplos

Consulta [samples/MapConductorSampleApp](samples/MapConductorSampleApp) para ver una app de demostración completa que muestra todos los módulos.

---

## Estado del proyecto

MapConductor iOS SDK ya está publicado y se encuentra en desarrollo activo.

El proyecto busca hacer que el desarrollo de mapas sea más flexible, portable y amigable con SwiftUI en los principales proveedores de mapas para iOS. Algunas funciones avanzadas pueden seguir siendo experimentales o presentar diferencias específicas por proveedor.

Los comentarios, reportes de errores y contribuciones son bienvenidos.

---

## Licencia

MapConductor iOS SDK se publica bajo la Licencia Apache 2.0.
