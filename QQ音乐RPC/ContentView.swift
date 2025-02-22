//
//  ContentView.swift
//  QQ音乐RPC
//
//  Created by Hunter Han on 2/21/25.
//

import SwiftUI
import AppKit
import WebKit
import SwiftData
import PrivateMediaRemote

func getAppBundleIdentifier(for pid: pid_t) -> String? {
    // Get the running application for the given PID
    if let app = NSRunningApplication(processIdentifier: pid) {
        // Return the bundle identifier
        return app.bundleIdentifier
    }
    return nil
}


struct ContentView: View {
    @Environment(\.modelContext) var modelContext

    let allowedBundleIdentifiers: Set<String> = ["com.tencent.QQMusicMac"]
    @ObservedObject private var nowPlayingInfo: NowPlayingInfoManager
    @State private var numChanges: Int = 0
    private var webView: WKWebView = WKWebView()
    private let customDiscordRPC = CustomDiscordRPC(clientId: "1076426618874101871")
    
    
    func extractNowPlayingInfo() {
        func handleNowPlayingInfo() {
            MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main, {
                if let info = $0 {
                    DispatchQueue.main.async {
                        self.nowPlayingInfo.setNowPlayingInfo(info)
                        self.numChanges += 1
                        nowPlayingInfo.setDiscordActivity(discordRPC: customDiscordRPC)
                    }
                }
            })
        }
        
        MRMediaRemoteGetNowPlayingApplicationPID(DispatchQueue.main) { pid in
            if pid <= 0 {
                return
            }
            
            if let bundleIdentifier = getAppBundleIdentifier(for: pid), allowedBundleIdentifiers.contains(bundleIdentifier) {
                handleNowPlayingInfo()
            }
        }
    }
    
    init() {
        self.nowPlayingInfo = NowPlayingInfoManager()
        MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)
    }
    
    var body: some View {
        VStack {
            if let info = nowPlayingInfo.getNowPlayingInfo() {
                Text(info.title ?? "Unknown Title")
                    .font(.title)
                Text(info.artist ?? "Unknown Artist")
                    .font(.subheadline)
                Text(info.album ?? "Unknown Album")
                    .font(.caption)
            } else {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
            }
            Button("Press me") {
                extractNowPlayingInfo()
            }
            Text("Number of changes: \(numChanges)")
        }
        .padding()
        .onReceive(NotificationCenter.default
            .publisher(for: Notification.Name.mrMediaRemoteNowPlayingInfoDidChange)) { _ in
                self.extractNowPlayingInfo()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.mrMediaRemoteNowPlayingApplicationIsPlayingDidChange)) { _ in
                self.nowPlayingInfo.callIfPlaying(discordRPC: customDiscordRPC) {}
            }
    }
}

#Preview {
    ContentView()
}
