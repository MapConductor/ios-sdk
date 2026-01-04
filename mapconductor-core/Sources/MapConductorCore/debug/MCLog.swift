import Foundation
import os

public enum MCLog {
    private static let subsystem = "com.mapconductor"

    public static let isEnabled: Bool = {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["MAPCONDUCTOR_DEBUG_LOG"]?.lowercased() {
            return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
        }
        return false
        #else
        return false
        #endif
    }()

    private static let markerLogger = Logger(subsystem: subsystem, category: "Marker")
    private static let mapLogger = Logger(subsystem: subsystem, category: "MapView")

    public static func marker(_ message: String) {
        guard isEnabled else { return }
        markerLogger.debug("\(message, privacy: .public)")
    }

    public static func map(_ message: String) {
        guard isEnabled else { return }
        mapLogger.debug("\(message, privacy: .public)")
    }
}

