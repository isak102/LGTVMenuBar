import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("WebOSClient Tests")
@MainActor
struct WebOSClientTests {

    @Test("registered message transitions client to connected state")
    func registeredMessageTransitionsToConnected() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setTestSendCommandHandler { _ in }

        client.setConnectionStateForTesting(.registering, handshakeCompleted: false)

        let registeredMessage = """
        {
          "type": "registered",
          "payload": {
            "client-key": "test-client-key"
          }
        }
        """

        await client.handleMessageForTesting(registeredMessage)

        #expect(observedStates.contains(.connected))
        #expect(client.connectionState == .connected)
    }

    @Test("sendCommand transport failure marks connection error")
    func sendCommandTransportFailureMarksConnectionError() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { _ in
            throw MockWebOSClientError.commandFailed("send failed")
        }

        await #expect(throws: LGTVError.self) {
            try await client.sendCommand(.screenOn)
        }
        #expect(client.connectionState.hasError)
        #expect(!client.connectionState.isConnected)
        #expect(observedStates.contains { $0.hasError })
    }

    @Test("getPowerStatus transport failure marks connection error")
    func getPowerStatusTransportFailureMarksConnectionError() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { command in
            if case .getPowerState = command {
                // Expected command for power status transport checks.
            } else {
                Issue.record("Expected getPowerState command")
            }
            throw MockWebOSClientError.connectionFailed("connection lost")
        }

        await #expect(throws: Error.self) {
            _ = try await client.getPowerStatus()
        }
        #expect(client.connectionState.hasError)
        #expect(!client.connectionState.isConnected)
        #expect(observedStates.contains { $0.hasError })
    }

    @Test("sendCommand rejects commands before handshake completion")
    func sendCommandRejectsBeforeHandshakeCompletion() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        client.setConnectionStateForTesting(.registering, handshakeCompleted: false)

        await #expect(throws: LGTVError.self) {
            try await client.sendCommand(.screenOn)
        }
    }

    @Test("stale connection attempt state changes are ignored")
    func staleConnectionAttemptStateChangesAreIgnored() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }

        let staleAttempt = client.beginConnectionAttemptForTesting()
        let currentAttempt = client.beginConnectionAttemptForTesting()

        client.emitConnectionStateForTesting(.registering, attemptID: staleAttempt)
        #expect(observedStates.isEmpty)
        #expect(client.connectionState == .disconnected)

        client.emitConnectionStateForTesting(.connecting, attemptID: currentAttempt)
        #expect(observedStates == [.connecting])
        #expect(client.connectionState == .connecting)
    }

    @Test("heartbeat failure marks a stale connection as errored")
    func heartbeatFailureMarksConnectionError() async {
        let client = WebOSClient(keychainManager: MockKeychainManager(), pingInterval: 0.01, pongTimeout: 0.01)
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }

        let attempt = client.beginConnectionAttemptForTesting()
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestPingHandler { false }
        client.startHeartbeatForTesting(attemptID: attempt)

        #expect(await waitUntil { client.connectionState.hasError })
        #expect(!client.connectionState.isConnected)
        #expect(!client.handshakeCompletedForTesting)
        #expect(observedStates.contains { $0.hasError })
    }

    @Test("heartbeat failure from a stale attempt is ignored")
    func staleHeartbeatFailureIsIgnored() async {
        let client = WebOSClient(keychainManager: MockKeychainManager(), pingInterval: 0.01, pongTimeout: 0.01)
        let staleAttempt = client.beginConnectionAttemptForTesting()
        _ = client.beginConnectionAttemptForTesting()
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestPingHandler { false }
        client.startHeartbeatForTesting(attemptID: staleAttempt)

        // The loop must bail on its first tick without touching the live connection.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(client.connectionState.isConnected)
        #expect(client.handshakeCompletedForTesting)
    }

    @Test("healthy heartbeat keeps pinging without dropping the connection")
    func healthyHeartbeatKeepsConnection() async {
        let client = WebOSClient(keychainManager: MockKeychainManager(), pingInterval: 0.01, pongTimeout: 0.01)
        let counter = PingCounter()
        let attempt = client.beginConnectionAttemptForTesting()
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestPingHandler { await counter.recordPing() }
        client.startHeartbeatForTesting(attemptID: attempt)

        #expect(await waitUntil { await counter.count >= 3 })
        #expect(client.connectionState.isConnected)
        #expect(client.handshakeCompletedForTesting)

        // Teardown ends the loop and the heartbeat with it.
        client.disconnect()
        #expect(await waitUntil { client.connectionState.isDisconnected })
    }

    @Test("connect while registering does not restart pairing")
    func connectWhileRegisteringDoesNotRestartPairing() async throws {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setConnectionStateForTesting(.registering, handshakeCompleted: false)

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )

        try await client.connect(to: config) { _ in }

        #expect(client.connectionState == .registering)
        #expect(observedStates.isEmpty)
    }

    @Test("response payload handles nested foreground app info")
    func responsePayloadHandlesNestedForegroundAppInfo() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setInputChangeCallback { input in
            recorder.input = input
        }

        let message = """
        {
          "type": "response",
          "payload": {
            "foregroundAppInfo": {
              "appId": "com.webos.app.hdmi2"
            }
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.input == .hdmi2)
    }

    @Test("response payload handles nested volume status")
    func responsePayloadHandlesNestedVolumeStatus() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setVolumeChangeCallback { volume, isMuted in
            recorder.volume = volume
            recorder.isMuted = isMuted
        }

        let message = """
        {
          "type": "response",
          "payload": {
            "volumeStatus": {
              "volume": 42,
              "muteStatus": true
            }
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.volume == 42)
        #expect(recorder.isMuted == true)
    }

    @Test("response payload handles nested sound output")
    func responsePayloadHandlesNestedSoundOutput() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setSoundOutputChangeCallback { output in
            recorder.soundOutput = output
        }

        let message = """
        {
          "type": "response",
          "payload": {
            "soundOutput": {
              "output": "external_arc"
            }
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.soundOutput == .externalArc)
    }

    @Test("listLaunchPoints response delivers installed apps")
    func listLaunchPointsResponseDeliversInstalledApps() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setInstalledAppsCallback { apps in
            recorder.apps = apps
        }
        client.setTestSendCommandHandler { _ in }

        let message = """
        {
          "type": "response",
          "payload": {
            "returnValue": true,
            "launchPoints": [
              {"id": "netflix", "title": "Netflix", "launchPointId": "netflix_default"},
              {"id": "youtube.leanback.v4", "title": "YouTube"},
              {"title": "No id here"}
            ]
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.apps?.map(\.id) == ["netflix", "youtube.leanback.v4"])
        #expect(recorder.apps?.first?.title == "Netflix")
        #expect(recorder.apps?.first?.launchPointId == "netflix_default")
    }

    @Test("getInstalledApps sends listLaunchPoints URI")
    func getInstalledAppsSendsListLaunchPointsURI() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var sent: [WebOSCommand] = []
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { command in
            sent.append(command)
        }

        try? await client.sendCommand(.getInstalledApps)

        guard case .getInstalledApps = sent.first else {
            Issue.record("Expected getInstalledApps command")
            return
        }
    }

    @Test("launchApp sends launch URI")
    func launchAppSendsLaunchURI() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var sent: [WebOSCommand] = []
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { command in
            sent.append(command)
        }

        try? await client.sendCommand(.launchApp("netflix"))

        guard case .launchApp(let appId) = sent.first else {
            Issue.record("Expected launchApp command")
            return
        }
        #expect(appId == "netflix")
    }

    @Test("registration manifest requests installed-apps permission")
    func registrationManifestRequestsInstalledAppsPermission() {
        let manifest = WebOSClient.registrationManifest()
        let permissions = manifest["permissions"] as? [String] ?? []
        #expect(permissions.contains("READ_INSTALLED_APPS"))
        #expect(manifest["signed"] != nil)
        let signed = manifest["signed"] as? [String: Any]
        let signedPermissions = signed?["permissions"] as? [String] ?? []
        #expect(signedPermissions.contains("READ_INSTALLED_APPS"))
    }
}

/// Pumps the main actor until `condition` holds or the timeout elapses.
/// The generous timeout only matters when other suites hog the main actor.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(20),
    _ condition: @MainActor () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

/// Counts heartbeat pings so tests can prove the loop actually runs.
@MainActor
private final class PingCounter {
    private(set) var count = 0

    /// Records a successful (ponged) ping.
    func recordPing() -> Bool {
        count += 1
        return true
    }
}

private final class WebOSPayloadRecorder: @unchecked Sendable {
    var input: TVInputType?
    var volume: Int?
    var isMuted: Bool?
    var soundOutput: TVSoundOutput?
    var apps: [TVApp]?
}
