import Foundation

/// An app listed in the TV launcher (from `listLaunchPoints`).
public struct TVApp: Identifiable, Sendable, Equatable {
    /// WebOS app id (e.g. `"netflix"`, `"youtube.leanback.v4"`).
    public let id: String

    /// Display title shown in the launcher (e.g. `"Netflix"`).
    public let title: String

    /// Launch point id, when present (e.g. `"netflix_default"`).
    public let launchPointId: String?

    public init(id: String, title: String, launchPointId: String? = nil) {
        self.id = id
        self.title = title
        self.launchPointId = launchPointId
    }

    /// Parse a single `launchPoints`/`apps` entry. Returns nil when no app id is present.
    public init?(_ dict: [String: Any]) {
        guard let id = (dict["appId"] as? String) ?? (dict["id"] as? String),
              !id.isEmpty
        else {
            return nil
        }
        let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? id
        self.init(
            id: id,
            title: title,
            launchPointId: dict["launchPointId"] as? String
        )
    }

    /// Parse a `listLaunchPoints` response payload into user-visible apps.
    public static func parseListLaunchPoints(_ payload: [String: Any]) -> [TVApp] {
        let entries = (payload["launchPoints"] as? [[String: Any]])
            ?? (payload["apps"] as? [[String: Any]])
            ?? []
        return entries.compactMap(TVApp.init)
    }
}
