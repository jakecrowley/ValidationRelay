//
//  Relay.swift
//  ValidationRelay
//
//  Created by James Gill on 3/25/24.
//

import Foundation
import Network
#if canImport(NWWebSocket)
import NWWebSocket
#endif
import SwiftUI

private let imac131Suffixes = [
    "DNCT", "DNCR", "DNML", "DNMM", "F8QM", "F8QN", "F9RN",
    "FC6M", "FC6N", "FC6P", "FD55", "FD5Y", "FF7L"
]
private let serialYears = Array("CDFGHJKLMNPQRSTUVWX")
private let serialWeeks = Array("123456789CDFGHJKLMNPQRSTVW")
private let serialAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789")

func generateHybridSerial() -> String {
    let year = String(serialYears.randomElement()!)
    let week = String(serialWeeks.randomElement()!)
    let uniq = String((0..<3).map { _ in serialAlphabet.randomElement()! })
    let suffix = imac131Suffixes.randomElement()!
    return "C02" + year + week + uniq + suffix
}

func generateHybridUDID() -> String {
    return UUID().uuidString.uppercased()
}

func machineIdentifier() -> String {
    var ustruct: utsname = utsname()
    uname(&ustruct)
    var ustruct2 = ustruct
    return withUnsafePointer(to: &ustruct2.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: ustruct.machine)) {
            String(cString: $0)
        }
    }
}

func realUniqueDeviceID() -> String {
    return MGCopyAnswer("UniqueDeviceID" as CFString)!.takeRetainedValue() as! String
}

func realSerialNumber() -> String {
    return MGCopyAnswer("SerialNumber" as CFString)!.takeRetainedValue() as! String
}

// Apple activates each serial exactly once, so a hybrid identity must stay stable for the
// life of a registration and must never be shared between devices. Identities are keyed by
// the real UDID and record the registration code they were issued for: a new code means a
// new registration, which gets a fresh identity. Old identities are kept under
// "<udid>.retired-<time>" keys rather than deleted. Same JSON format as OpenBubblesProxy's
// registry.json, so an entry for this phone can be carried over from the proxy.
struct HybridIdentity: Codable {
    var serial: String
    var udid: String
    var relayCode: String? // nil for entries from OpenBubblesProxy, which doesn't track codes
    var realSerial: String?
    var hardwareVersion: String?
    var created: String?

    enum CodingKeys: String, CodingKey {
        case serial = "hybrid_serial"
        case udid = "hybrid_udid"
        case relayCode = "relay_code"
        case realSerial = "real_serial"
        case hardwareVersion = "hardware_version"
        case created
    }
}

class IdentityRegistry {
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("identity_registry.json")
    private var entries: [String: HybridIdentity] = [:]
    // false if the file couldn't be read or moved aside; we then refuse to overwrite it
    private var persist = true
    private let logItems: LogItems

    init(logItems: LogItems) {
        self.logItems = logItems
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            entries = try JSONDecoder().decode([String: HybridIdentity].self, from: Data(contentsOf: url))
        } catch {
            // never silently replace a registry we couldn't read; move it aside first
            let backup = url.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                logItems.log("Identity registry unreadable (\(error)); moved to \(backup.lastPathComponent)", isError: true)
            } catch let moveError {
                persist = false
                logItems.log("Identity registry unreadable (\(error)) and could not be moved aside (\(moveError)); identities will NOT be saved", isError: true)
            }
        }
    }

    // Identities from earlier builds of this fork were stored in UserDefaults
    func migrateFromUserDefaults(realUDID: String) {
        let defaults = UserDefaults.standard
        guard entries[realUDID] == nil,
              let serial = defaults.string(forKey: "hybridSerialNumber"), serial.count == 12,
              let udid = defaults.string(forKey: "hybridUniqueDeviceID"), !udid.isEmpty else { return }
        entries[realUDID] = HybridIdentity(serial: serial, udid: udid)
        save()
        defaults.removeObject(forKey: "hybridSerialNumber")
        defaults.removeObject(forKey: "hybridUniqueDeviceID")
        logItems.log("Moved existing hybrid identity \(serial) into the identity registry")
    }

    // The identity already issued for this registration, if any
    func existing(realUDID: String, relayCode: String) -> HybridIdentity? {
        guard let entry = entries[realUDID], entry.relayCode == nil || entry.relayCode == relayCode else { return nil }
        return entry
    }

    // The identity to report for this registration, issuing one if needed
    func identity(realUDID: String, realSerial: String, hardwareVersion: String, relayCode: String) -> HybridIdentity {
        if let entry = entries[realUDID] {
            if entry.relayCode == relayCode {
                return entry
            }
            if entry.relayCode == nil {
                // carried over from OpenBubblesProxy or an earlier build; it belongs to this registration
                var adopted = entry
                adopted.relayCode = relayCode
                entries[realUDID] = adopted
                save()
                logItems.log("Using existing hybrid identity \(adopted.serial) for registration code \(relayCode)")
                return adopted
            }
            retire(realUDID: realUDID)
            logItems.log("New registration code: retired hybrid identity \(entry.serial)")
        }

        let identity = HybridIdentity(
            serial: generateHybridSerial(),
            udid: generateHybridUDID(),
            relayCode: relayCode,
            realSerial: realSerial,
            hardwareVersion: hardwareVersion,
            created: ISO8601DateFormatter().string(from: Date())
        )
        entries[realUDID] = identity
        save()
        logItems.log("Issued new hybrid identity \(identity.serial)")
        return identity
    }

    // Abandon the current identity; a new one is issued at the next registration
    @discardableResult
    func retire(realUDID: String) -> Bool {
        guard let entry = entries.removeValue(forKey: realUDID) else { return false }
        entries["\(realUDID).retired-\(Int(Date().timeIntervalSince1970))"] = entry
        save()
        return true
    }

    private func save() {
        guard persist else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: url, options: .atomic)
        } catch {
            // still stable while the app is running, but would change after a relaunch
            logItems.log("FAILED to save identity registry: \(error)", isError: true)
        }
    }
}

func getIdentifiers(hybrid: HybridIdentity?) -> [String: String] {
    let identifiers = [
        "hardware_version": machineIdentifier(),
        "software_name": "iPhone OS",
        "software_version": UIDevice.current.systemVersion,
        "software_build_id": buildNumber()!,
        "unique_device_id": hybrid?.udid ?? realUniqueDeviceID(),
        "serial_number": hybrid?.serial ?? realSerialNumber()
    ]
    return identifiers
}

class RelayConnectionManager: ObservableObject {
    @Published var registrationCode: String = "None"
    @Published var connectionStatusMessage: String = ""
    @Published var logItems = LogItems()
    
    // These must all be saved together
    @AppStorage("savedRegistrationSecret") public var savedRegistrationSecret = ""
    @AppStorage("savedRegistrationCode") public var savedRegistrationCode = ""
    @AppStorage("savedRegistrationURL") public var savedRegistrationURL = ""
    
    @AppStorage("useHybridIdentity") public var useHybridIdentity = true
    @Published var hybridSerialNumber = ""
    @Published var hybridUniqueDeviceID = ""
    lazy var identities = IdentityRegistry(logItems: logItems)
    
    var currentURL: URL? = nil
    var connectionDelegate: RelayConnectionDelegate? = nil
    
    var reconnectWork: DispatchWorkItem? = nil
    
    var backoff: Int = 2
    let maxBackoff: Int = 64

    init() {
        identities.migrateFromUserDefaults(realUDID: realUniqueDeviceID())
        refreshHybridIdentity()
    }

    // Identity to report in get-version-info, or nil to report the real one
    func hybridIdentityForVersionInfo() -> HybridIdentity? {
        guard useHybridIdentity else { return nil }
        let identity = identities.identity(realUDID: realUniqueDeviceID(), realSerial: realSerialNumber(), hardwareVersion: machineIdentifier(), relayCode: savedRegistrationCode)
        showHybridIdentity(identity)
        return identity
    }

    func refreshHybridIdentity() {
        showHybridIdentity(identities.existing(realUDID: realUniqueDeviceID(), relayCode: savedRegistrationCode))
    }

    func regenerateHybridIdentity() {
        if identities.retire(realUDID: realUniqueDeviceID()) {
            logItems.log("Retired hybrid identity \(hybridSerialNumber); a new one is issued at the next registration")
        }
        showHybridIdentity(nil)
    }

    private func showHybridIdentity(_ identity: HybridIdentity?) {
        hybridSerialNumber = identity?.serial ?? "Issued at registration"
        hybridUniqueDeviceID = identity?.udid ?? "Issued at registration"
    }

    func connect(_ url: URL) {
        logItems.log("Connecting to \(url)")
        connectionStatusMessage = "Connecting..."
        currentURL = url
        
        backoff = 2 // Reset backoff
        
        reconnectWork?.cancel()
        reconnectWork = nil

        connectionDelegate = RelayConnectionDelegate(manager: self)
    }

    func disconnect() {
        logItems.log("Disconnecting on request")
        connectionStatusMessage = ""
        currentURL = nil
        
        reconnectWork?.cancel()
        reconnectWork = nil
        
        connectionDelegate?.disconnect()
        connectionDelegate = nil
    }

    func triggerReconnect() {
        logItems.log("Triggering reconnect")
        connectionStatusMessage = "Reconnecting..."
        // Delete the delegate so that more errors don't come in
        connectionDelegate?.disconnect()
        connectionDelegate = nil
        print("Waiting for \(backoff) backoff seconds")
        
        reconnectWork?.cancel()
        reconnectWork = nil
        
        let work = DispatchWorkItem {
            self.connectionDelegate = RelayConnectionDelegate(manager: self)
        }
        // Wait a bit then try again
        DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(backoff), execute: work)
        
        reconnectWork = work
        backoff = min(backoff * 2, maxBackoff)
    }
}

class RelayConnectionDelegate: WebSocketConnectionDelegate, ObservableObject {
    var connection: WebSocketConnection
    let manager: RelayConnectionManager

    init(
        manager: RelayConnectionManager
    ) {
        self.manager = manager
        connection = NWWebSocket(url: manager.currentURL!, connectAutomatically: true)
        connection.delegate = self
        connection.ping(interval: 30)
    }
    
    func disconnect() {
        connection.disconnect(closeCode: .protocolCode(.normalClosure))
    }
    
    func webSocketDidConnect(connection: WebSocketConnection) {
        manager.logItems.log("Websocket did connect")
        manager.connectionStatusMessage = "Connected"
        var registerCommand = ["command": "register", "data": ["": ""]] as [String : Any]
        if manager.currentURL?.absoluteString == manager.savedRegistrationURL {
            print("Using saved registration code")
            manager.logItems.log("Using saved registration code \(manager.savedRegistrationCode)")
            manager.logItems.log("Using saved registration secret \(manager.savedRegistrationSecret)")
            registerCommand["data"] = ["code": manager.savedRegistrationCode, "secret": manager.savedRegistrationSecret]
        }
        let data = try! JSONSerialization.data(withJSONObject: registerCommand)
        print(String(data: data, encoding: .utf8)!)
        connection.send(string: String(data: data, encoding: .utf8)!)
    }
    
    func webSocketDidDisconnect(connection: WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        manager.logItems.log("Websocket did disconnect", isError: true)
        print("Disconnected")
    }
    
    func webSocketViabilityDidChange(connection: WebSocketConnection, isViable: Bool) {
        // Respond to a WebSocket connection viability change event
        print("WebSocket connection viability changed to \(isViable), ignoring")
    }
    
    func webSocketDidAttemptBetterPathMigration(result: Result<WebSocketConnection, NWError>) {
        // Respond to when a WebSocket connection migrates to a better network path
        // (e.g. A device moves from a cellular connection to a Wi-Fi connection)
        print("WebSocket connection attempted better path migration, ignoring")
    }
    
    func webSocketDidReceiveError(connection: WebSocketConnection, error: NWError) {
        print(error)
        manager.logItems.log("Websocket error: \(error)", isError: true)
        self.manager.triggerReconnect()
    }
    
    func webSocketDidReceivePong(connection: WebSocketConnection) {
        // Respond to a WebSocket connection receiving a Pong from the peer
        //print("pong")
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        print("Got string msg")
        // Parse as JSON
        let json = try! JSONSerialization.jsonObject(with: string.data(using: .utf8)!, options: [])
        print(json)
        
        // Save registration code
        if let jsonDict = json as? [String: Any] {
            if let data = jsonDict["data"] as? [String: Any] {
                if let code = data["code"] as? String {
                    manager.registrationCode = code
                    if manager.savedRegistrationCode != code {
                        manager.logItems.log("New registration code \(code)")
                        manager.logItems.log("secret \(data["secret"] as? String ?? "")")
                    }
                    manager.savedRegistrationCode = code
                    manager.savedRegistrationSecret = data["secret"] as? String ?? ""
                    manager.savedRegistrationURL = manager.currentURL?.absoluteString ?? ""
                    manager.refreshHybridIdentity()
                }
            }
            if let command = jsonDict["command"] as? String {
                if command == "get-version-info" {
                    let versionInfo = ["command": "response", "data": ["versions": getIdentifiers(hybrid: manager.hybridIdentityForVersionInfo())], "id": jsonDict["id"]!] as [String : Any]
                    print("Sending version info: \(versionInfo)")
                    manager.logItems.log("Sending version info: \(versionInfo)")
                    let data = try! JSONSerialization.data(withJSONObject: versionInfo)
                    connection.send(string: String(data: data, encoding: .utf8)!)
                }
                if command == "get-validation-data" {
                    print("Sending val data")
                    let v = generateValidationData()
                    print("Validation data: \(v.base64EncodedString())")
                    manager.logItems.log("Generated validation data: \(v.base64EncodedString())")
                    let validationData = ["command": "response", "data": ["data": v.base64EncodedString()], "id": jsonDict["id"]!] as [String : Any]
                    let data = try! JSONSerialization.data(withJSONObject: validationData)
                    connection.send(string: String(data: data, encoding: .utf8)!)
                }
            }
        }
        // Respond to a WebSocket connection receiving a `String` message
    }
    
    func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        //  let json = try! JSONSerialization.jsonObject(with: data, options: [])
        print("got data msg")
        print(data)
    }
}

