import Foundation

/// Remote navigation buttons supported by the WebOS pointer input socket.
public enum TVNavigationButton: String, Sendable {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case enter = "ENTER"
}
