import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TV Controller Connection Tests")
@MainActor
struct TVControllerConnectionTests {
    @Test("duplicate connect joins in-flight pairing attempt")
    func duplicateConnectJoinsInFlightPairingAttempt() async throws {
        let mockWebOS = MockWebOSClient()
        let mockDiagnostic = MockDiagnosticLogger()
        mockWebOS.asyncDelay = 0.05

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: mockDiagnostic
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)

        let firstConnect = Task {
            try await controller.connect()
        }
        try await Task.sleep(for: .milliseconds(10))

        try await controller.connect()
        try await firstConnect.value

        #expect(mockWebOS.connectCallCount == 1)
        #expect(controller.connectionState == .connected)
        #expect(mockDiagnostic.wasLogged(message: "Joining in-flight TV connection"))
    }

    @Test("stale WebOS state callback is ignored after disconnect")
    func staleWebOSStateCallbackIsIgnoredAfterDisconnect() async throws {
        let mockWebOS = MockWebOSClient()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger()
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)
        try await controller.connect()

        controller.disconnect()
        mockWebOS.emitStaleConnectionStateCallback(.registering)
        await Task.yield()

        #expect(controller.connectionState == .disconnected)
    }

    @Test("installed apps callback updates state sorted by title")
    func installedAppsCallbackUpdatesState() async throws {
        let mockWebOS = MockWebOSClient()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger()
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)
        try await controller.connect()

        mockWebOS.simulateInstalledAppsUpdate([
            TVApp(id: "youtube.leanback.v4", title: "YouTube"),
            TVApp(id: "netflix", title: "Netflix"),
        ])
        await Task.yield()

        #expect(controller.installedApps.map(\.title) == ["Netflix", "YouTube"])
    }

    @Test("launchApp sends launch command for app id")
    func launchAppSendsLaunchCommand() async throws {
        let mockWebOS = MockWebOSClient()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger()
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)
        try await controller.connect()

        try await controller.launchApp(TVApp(id: "netflix", title: "Netflix"))

        guard case .launchApp(let appId) = mockWebOS.sendCommandCalls.last?.command else {
            Issue.record("Expected launchApp command")
            return
        }
        #expect(appId == "netflix")
    }

    @Test("send text inserts it into the focused TV field")
    func sendTextInsertsIntoFocusedTVField() async throws {
        let mockWebOS = MockWebOSClient()
        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger()
        )

        try await controller.sendText("Pasted text ✅")
        try await controller.deleteCharacters(1)
        try await controller.sendEnterKey()
        try await controller.sendNavigationButton(.enter)
        try await controller.sendPointerMove(dx: 12, dy: -8)
        try await controller.sendPointerScroll(dx: 0, dy: -3)
        try await controller.sendPointerClick()

        let sent = mockWebOS.sendCommandCalls.map(\.command)
        guard case .insertText(let text) = sent[0] else {
            Issue.record("Expected insertText command")
            return
        }
        #expect(text == "Pasted text ✅")
        guard case .deleteCharacters(let count) = sent[1] else {
            Issue.record("Expected deleteCharacters command")
            return
        }
        #expect(count == 1)
        guard case .sendEnterKey = sent[2] else {
            Issue.record("Expected sendEnterKey command")
            return
        }
        #expect(mockWebOS.navigationButtonCalls.last?.button == .enter)
        #expect(mockWebOS.pointerMoveCalls.last?.dx == 12)
        #expect(mockWebOS.pointerMoveCalls.last?.dy == -8)
        #expect(mockWebOS.pointerScrollCalls.last?.dx == 0)
        #expect(mockWebOS.pointerScrollCalls.last?.dy == -3)
        #expect(mockWebOS.pointerClickCalls.count == 1)
    }

    @Test("connect requests installed apps")
    func connectRequestsInstalledApps() async throws {
        let mockWebOS = MockWebOSClient()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger()
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)
        try await controller.connect()

        let sent = mockWebOS.sendCommandCalls.map(\.command)
        #expect(sent.contains { if case .getInstalledApps = $0 { return true }; return false })
    }
}
