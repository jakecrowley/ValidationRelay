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

func getOrCreateHybridIdentity() -> (serial: String, udid: String) {
    let defaults = UserDefaults.standard
    var serial = defaults.string(forKey: "hybridSerialNumber") ?? ""
    var udid = defaults.string(forKey: "hybridUniqueDeviceID") ?? ""
    if serial.count != 12 {
        serial = generateHybridSerial()
        defaults.set(serial, forKey: "hybridSerialNumber")
    }
    if udid.isEmpty {
        udid = generateHybridUDID()
        defaults.set(udid, forKey: "hybridUniqueDeviceID")
    }
    return (serial, udid)
}

func getIdentifiers() -> [String: String] {
    var ustruct: utsname = utsname()
    uname(&ustruct)
    var ustruct2 = ustruct
    let machine = withUnsafePointer(to: &ustruct2.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: ustruct.machine)) {
            String(cString: $0)
        }
    }

    let defaults = UserDefaults.standard
    let useHybrid = (defaults.object(forKey: "useHybridIdentity") as? Bool) ?? true

    let udid: String
    let serial: String
    if useHybrid {
        let hybrid = getOrCreateHybridIdentity()
        udid = hybrid.udid
        serial = hybrid.serial
    } else {
        udid = MGCopyAnswer("UniqueDeviceID" as CFString)!.takeRetainedValue() as! String
        serial = MGCopyAnswer("SerialNumber" as CFString)!.takeRetainedValue() as! String
    }

    let identifiers = [
        "hardware_version": machine,
        "software_name": "iPhone OS",
        "software_version": UIDevice.current.systemVersion,
        "software_build_id": buildNumber()!,
        "unique_device_id": udid,
        "serial_number": serial
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
    @AppStorage("hybridSerialNumber") public var hybridSerialNumber = ""
    @AppStorage("hybridUniqueDeviceID") public var hybridUniqueDeviceID = ""
    
    var currentURL: URL? = nil
    var connectionDelegate: RelayConnectionDelegate? = nil
    
    var reconnectWork: DispatchWorkItem? = nil
    
    var backoff: Int = 2
    let maxBackoff: Int = 64

    init() {
        ensureHybridIdentity()
    }

    func ensureHybridIdentity() {
        let hybrid = getOrCreateHybridIdentity()
        if hybridSerialNumber != hybrid.serial {
            hybridSerialNumber = hybrid.serial
        }
        if hybridUniqueDeviceID != hybrid.udid {
            hybridUniqueDeviceID = hybrid.udid
        }
    }

    func regenerateHybridIdentity() {
        let newSerial = generateHybridSerial()
        let newUDID = generateHybridUDID()
        UserDefaults.standard.set(newSerial, forKey: "hybridSerialNumber")
        UserDefaults.standard.set(newUDID, forKey: "hybridUniqueDeviceID")
        hybridSerialNumber = newSerial
        hybridUniqueDeviceID = newUDID
        logItems.log("Generated new hybrid identity: \(newSerial)")
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
                }
            }
            if let command = jsonDict["command"] as? String {
                if command == "get-version-info" {
                    let versionInfo = ["command": "response", "data": ["versions": getIdentifiers()], "id": jsonDict["id"]!] as [String : Any]
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

