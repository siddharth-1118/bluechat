import Flutter
import UIKit
import MultipeerConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {

    private let serviceType = "bluechat-mesh"
    private var myPeerId: MCPeerID!
    private var mcSession: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private var discoveredPeers = [String: MCPeerID]()
    private var connectedPeers = [String: MCPeerID]()

    private var deviceDiscoverySink: FlutterEventSink?
    private var connectionStateSink: FlutterEventSink?
    private var messageSink: FlutterEventSink?
    private var transferProgressSink: FlutterEventSink?

    private var myAddress: String {
        if let stored = UserDefaults.standard.string(forKey: "bluechat_ios_my_address") {
            return stored
        }
        let newId = "IOS_" + UUID().uuidString.prefix(8).uppercased()
        UserDefaults.standard.set(newId, forKey: "bluechat_ios_my_address")
        return newId
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupMultipeer()

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        setupChannels(controller: controller)
        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func setupMultipeer() {
        let name = UIDevice.current.name + " (" + myAddress + ")"
        myPeerId = MCPeerID(displayName: name)
        mcSession = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: ["address": myAddress], serviceType: serviceType)
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
    }

    private func setupChannels(controller: FlutterViewController) {
        let methodChannel = FlutterMethodChannel(name: "com.example.bluechat/methods", binaryMessenger: controller.binaryMessenger)
        methodChannel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call: call, result: result)
        }

        let discoveryChannel = FlutterEventChannel(name: "com.example.bluechat/events/discovery", binaryMessenger: controller.binaryMessenger)
        discoveryChannel.setStreamHandler(DiscoveryStreamHandler(owner: self))

        let connectionChannel = FlutterEventChannel(name: "com.example.bluechat/events/connection", binaryMessenger: controller.binaryMessenger)
        connectionChannel.setStreamHandler(ConnectionStreamHandler(owner: self))

        let messageChannel = FlutterEventChannel(name: "com.example.bluechat/events/messages", binaryMessenger: controller.binaryMessenger)
        messageChannel.setStreamHandler(MessageStreamHandler(owner: self))

        let progressChannel = FlutterEventChannel(name: "com.example.bluechat/events/progress", binaryMessenger: controller.binaryMessenger)
        progressChannel.setStreamHandler(ProgressStreamHandler(owner: self))
    }

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startBluetoothService":
            advertiser.startAdvertisingPeer()
            result(true)

        case "checkBluetoothPermission", "requestPermissions":
            result(true)

        case "startDiscovery":
            discoveredPeers.removeAll()
            browser.startBrowsingForPeers()
            sendDiscoveryEvent(["type": "discoveryStarted"])
            result(true)

        case "stopDiscovery":
            browser.stopBrowsingForPeers()
            sendDiscoveryEvent(["type": "discoveryFinished"])
            result(true)

        case "startServer":
            advertiser.startAdvertisingPeer()
            result(true)

        case "stopServer":
            advertiser.stopAdvertisingPeer()
            result(true)

        case "connectToDevice":
            guard let args = call.arguments as? [String: Any],
                  let address = args["address"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "Address required", details: nil))
                return
            }
            if let peer = discoveredPeers[address] {
                browser.invitePeer(peer, to: mcSession, withContext: nil, timeout: 30)
                sendConnectionEvent(["state": "connecting", "address": address, "name": peer.displayName])
                result(true)
            } else {
                result(false)
            }

        case "disconnect":
            mcSession.disconnect()
            result(true)

        case "disconnectAll":
            mcSession.disconnect()
            result(true)

        case "sendMessage", "broadcastMessage":
            guard let args = call.arguments as? [String: Any],
                  let messageJson = args["messageJson"] as? String,
                  let data = messageJson.data(using: .utf8) else {
                result(false)
                return
            }

            var targetPeers = mcSession.connectedPeers
            if let targetAddr = args["address"] as? String, let peer = connectedPeers[targetAddr] {
                targetPeers = [peer]
            }

            if targetPeers.isEmpty {
                result(false)
                return
            }

            do {
                try mcSession.send(data, toPeers: targetPeers, with: .reliable)
                result(true)
            } catch {
                result(false)
            }

        case "sendFile":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String,
                  let fileUrl = URL(string: "file://" + filePath) ?? URL(fileURLWithPath: filePath) as URL? else {
                result(false)
                return
            }

            let fileName = args["fileName"] as? String ?? fileUrl.lastPathComponent
            let targetPeers = mcSession.connectedPeers
            guard let firstPeer = targetPeers.first else {
                result(false)
                return
            }

            mcSession.sendResource(at: fileUrl, withName: fileName, toPeer: firstPeer) { [weak self] error in
                if let error = error {
                    print("Error sending file to peer: \(error.localizedDescription)")
                } else {
                    let fileId = args["fileId"] as? String ?? ""
                    self?.sendProgressEvent([
                        "fileId": fileId,
                        "progress": 1.0,
                        "bytesTransferred": 100,
                        "totalBytes": 100,
                        "status": "success",
                        "filePath": filePath
                    ])
                }
            }
            result(true)

        case "getMyAddress":
            result(myAddress)

        case "getMyName":
            result(UIDevice.current.name)

        case "getBondedDevices":
            result([])

        case "isBluetoothEnabled":
            result(true)

        case "openBluetoothSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            result(true)

        case "startAudioCall", "stopAudioCall":
            result(true)

        case "dismissNotification", "setActiveSessionId", "cancelFileTransfer":
            result(true)

        case "shareFile":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(false)
                return
            }
            let fileUrl = URL(fileURLWithPath: filePath)
            let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
            window?.rootViewController?.present(activityVC, animated: true)
            result(true)

        case "getInstalledUpiApps":
            result([])

        case "launchUpiPayment":
            result(false)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from nearby BlueChat peers
        invitationHandler(true, mcSession)
    }

    // MARK: - MCNearbyServiceBrowserDelegate
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        let peerAddress = info?["address"] ?? peerID.displayName
        discoveredPeers[peerAddress] = peerID

        let deviceMap: [String: Any] = [
            "name": peerID.displayName,
            "address": peerAddress,
            "isBonded": false
        ]
        sendDiscoveryEvent([
            "type": "deviceFound",
            "device": deviceMap
        ])
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Peer lost
    }

    // MARK: - MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let address = peerID.displayName
            switch state {
            case .connected:
                self.connectedPeers[address] = peerID
                self.sendConnectionEvent(["state": "connected", "address": address, "name": peerID.displayName])
            case .connecting:
                self.sendConnectionEvent(["state": "connecting", "address": address, "name": peerID.displayName])
            case .notConnected:
                self.connectedPeers.removeValue(forKey: address)
                self.sendConnectionEvent(["state": "disconnected", "address": address, "name": peerID.displayName])
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let messageJson = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.sendMessageEvent([
                "type": "message",
                "message": messageJson
            ])
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard let localURL = localURL else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent(resourceName)
        try? FileManager.default.removeItem(at: destinationURL)
        do {
            try FileManager.default.copyItem(at: localURL, to: destinationURL)
            DispatchQueue.main.async { [weak self] in
                self?.sendProgressEvent([
                    "fileId": UUID().uuidString,
                    "progress": 1.0,
                    "status": "success",
                    "filePath": destinationURL.path
                ])
            }
        } catch {
            print("Failed to save incoming file: \(error)")
        }
    }

    // MARK: - Event Helpers
    func sendDiscoveryEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.deviceDiscoverySink?(event)
        }
    }

    func sendConnectionEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionStateSink?(event)
        }
    }

    func sendMessageEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.messageSink?(event)
        }
    }

    func sendProgressEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.transferProgressSink?(event)
        }
    }

    // MARK: - Stream Handlers
    class DiscoveryStreamHandler: NSObject, FlutterStreamHandler {
        weak var owner: AppDelegate?
        init(owner: AppDelegate) { self.owner = owner }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            owner?.deviceDiscoverySink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            owner?.deviceDiscoverySink = nil
            return nil
        }
    }

    class ConnectionStreamHandler: NSObject, FlutterStreamHandler {
        weak var owner: AppDelegate?
        init(owner: AppDelegate) { self.owner = owner }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            owner?.connectionStateSink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            owner?.connectionStateSink = nil
            return nil
        }
    }

    class MessageStreamHandler: NSObject, FlutterStreamHandler {
        weak var owner: AppDelegate?
        init(owner: AppDelegate) { self.owner = owner }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            owner?.messageSink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            owner?.messageSink = nil
            return nil
        }
    }

    class ProgressStreamHandler: NSObject, FlutterStreamHandler {
        weak var owner: AppDelegate?
        init(owner: AppDelegate) { self.owner = owner }
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            owner?.transferProgressSink = events
            return nil
        }
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            owner?.transferProgressSink = nil
            return nil
        }
    }
}
