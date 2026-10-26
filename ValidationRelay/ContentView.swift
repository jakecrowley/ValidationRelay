//
//  ContentView.swift
//  ValidationRelay
//
//  Created by James Gill on 3/24/24.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("autoConnect") private var wantRelayConnected = true
    @AppStorage("keepAwake") private var keepAwake = true
    
    @AppStorage("selectedRelay") private var selectedRelay = "Beeper"
    @AppStorage("customRelayURL") private var customRelayURL = ""
    
    @State private var confirmRegenerate = false
    
    @ObservedObject var relayConnectionManager: RelayConnectionManager
    
    init(relayConnectionManager: RelayConnectionManager) {
        self.relayConnectionManager = relayConnectionManager
        if wantRelayConnected {
            relayConnectionManager.connect(getCurrentRelayURL())
        }
        if keepAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    
    func getCurrentRelayURL() -> URL {
        if selectedRelay == "Custom" {
            if let url = URL(string: customRelayURL) {
                return url
            }
        } else if selectedRelay == "pypush" {
            return URL(string: "wss://registration-relay.jjtech.dev/api/v1/provider")!
        }
        
        // Default to Beeper relay
        selectedRelay = "Beeper"
        return URL(string: "wss://registration-relay.beeper.com/api/v1/provider")!
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Relay", isOn: $wantRelayConnected)
                        .onChange(of: wantRelayConnected) { newValue in
                            // Connect or disconnect the relay
                            if newValue {
                                relayConnectionManager.connect(getCurrentRelayURL())
                            } else {
                                relayConnectionManager.disconnect()
                            }
                        }
                    HStack {
                        Text("Registration Code")
                        Spacer()
                        Text(relayConnectionManager.registrationCode)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } footer: {
                    Text(relayConnectionManager.connectionStatusMessage)
                }
                Section {
                    //Toggle("Run in Background", isOn: .constant(false))
                    //    .disabled(true)
                    Picker("Relay", selection: $selectedRelay) {
                        Text("Beeper").tag("Beeper")
                        //Text("pypush").tag("pypush")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedRelay) { newValue in
                        // Disconnect when the user is switching relay servers
                        wantRelayConnected = false
                    }
                    if (selectedRelay == "Custom") {
                        TextField("Custom Relay Server URL", text: $customRelayURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                    }
                } header: {
                    Text("Connection settings")
                } footer: {
                    Text("Beeper's relay server is recommended for most users")
                }
                
                Section {
                    Toggle("Hybrid Mac Identity", isOn: $relayConnectionManager.useHybridIdentity)
                    if relayConnectionManager.useHybridIdentity {
                        HStack {
                            Text("Serial Number")
                            Spacer()
                            Text(relayConnectionManager.hybridSerialNumber)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("UUID")
                            Spacer()
                            Text(relayConnectionManager.hybridUniqueDeviceID)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button("Regenerate Identity") {
                            confirmRegenerate = true
                        }
                        .foregroundColor(.red)
                        .alert(isPresented: $confirmRegenerate) {
                            Alert(
                                title: Text("Regenerate identity?"),
                                message: Text("Apple activates each identity only once. This abandons the current registration, and you will need to register again in OpenBubbles."),
                                primaryButton: .destructive(Text("Regenerate")) {
                                    relayConnectionManager.regenerateHybridIdentity()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    }
                } header: {
                    Text("Identity settings")
                } footer: {
                    Text("Spoofs serial_number (12-char iMac13,1) and unique_device_id (UUID) in get-version-info. Each registration code gets its own identity, which is kept until the code changes. Deleting the app loses it.")
                }
                
                Section {
                    // Navigation to Log page
                    NavigationLink(destination: LogView(logItems: relayConnectionManager.logItems)) {
                        Text("Log")
                    }
                    Button("Dim Display") {
                        UIScreen.main.brightness = 0.0
                        UIScreen.main.wantsSoftwareDimming = true
                    }
                    Toggle("Keep Awake", isOn: $keepAwake)
                        .onChange(of: keepAwake) { newValue in
                            if keepAwake {
                                UIApplication.shared.isIdleTimerDisabled = true
                            } else {
                                UIApplication.shared.isIdleTimerDisabled = false
                            }
                        }
                    Button("Reset Registration Code") {
                        relayConnectionManager.savedRegistrationURL = ""
                        relayConnectionManager.savedRegistrationCode = ""
                        relayConnectionManager.savedRegistrationSecret = ""
                        relayConnectionManager.registrationCode = "None"
                        relayConnectionManager.regenerateHybridIdentity()
                        wantRelayConnected = false
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("You will need to re-enter the code on your other devices")
                }
            }
            .listStyle(.grouped)
            .navigationBarHidden(true)
            .navigationBarTitle("", displayMode: .inline)
        }
        
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(relayConnectionManager: RelayConnectionManager())
    }
}
