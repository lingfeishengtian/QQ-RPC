//
//  CustomDiscordRPC.swift
//  QQ音乐RPC
//
//  Created by Hunter Han on 2/22/25.
//

import Foundation
import Socket

enum DiscordActivityType : Int, Encodable {
    case game = 0
    case streaming = 1
    case listening = 2
    case custom = 4
}

struct DiscordTimestamps : Encodable {
    var start: Int?
    var end: Int?
}

struct DiscordAssets : Encodable {
    var large_image: String?
    var large_text: String?
    var small_image: String?
    var small_text: String?
}

struct DiscordParty : Encodable {
    var id: String?
    var size: [Int]?
}

struct DiscordSecrets : Encodable {
    var join: String?
    var spectate: String?
    var match: String?
}

struct CustomDiscordActivity : Encodable {
    var type: DiscordActivityType = .game
    var state: String?
    var details: String?
    var timestamps: DiscordTimestamps?
    var assets: DiscordAssets?
    var party: DiscordParty?
    var secrets: DiscordSecrets?
    var instance: Bool?
}

struct DiscordPayloadActivityArgs : Encodable {
    var pid: Int
    var activity: CustomDiscordActivity
}

struct DiscordPayload : Encodable {
    var cmd: String
    var args: DiscordPayloadActivityArgs
    var nonce: String
}

class CustomDiscordRPC {
    let socket: Socket
    
    init(clientId: String) {
        self.socket = try! Socket.create(family: .unix, proto: .unix)
        
        for i in 0...9 {
            let addr = "\(FileManager.default.temporaryDirectory.path)/discord-ipc-\(i)"
            try? self.socket.connect(to: addr)
            
            if self.socket.isConnected {
                print("Successfully connected to Discord RPC socket")
                try! handshake(clientId: clientId)
                return
            } else {
                self.socket.close()
                print("Failed to connect to Discord RPC socket")
            }
        }
    }
    
    func handshake(clientId: String) throws {
        let payload = [
            "v": 1,
            "client_id": clientId
        ] as [String : Any]
        
        let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        send(str: String(data: data, encoding: .utf8)!, op: .handshake)
        printResponse()
    }
    
    func printResponse() {
        let response = getResponse()
        
        print("Received response from Discord: \(String(data: response, encoding: .utf8) ?? "nil")")
    }
    
    private var lastMessageTime: Date?
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.yourapp.discordactivitysender", qos: .default)
    
    func sendActivity(_ activity: CustomDiscordActivity) {
        // Cancel any pending work item
        pendingWorkItem?.cancel()
        
        // Create a new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let swiftStruct = DiscordPayload(
                cmd: "SET_ACTIVITY",
                args: DiscordPayloadActivityArgs(
                    pid: Int(ProcessInfo.processInfo.processIdentifier),
                    activity: activity
                ),
                nonce: UUID().uuidString
            )
            
            if let payload = String(data: try! JSONEncoder().encode(swiftStruct), encoding: .utf8)?.data(using: .utf8) {
                self.send(str: String(data: payload, encoding: .utf8)!, op: .frame)
                self.printResponse()
            }
            
            self.lastMessageTime = Date()
        }
        
        // Store the work item
        pendingWorkItem = workItem
        
        // Calculate the delay
        let delay: TimeInterval
        if let lastMessageTime = lastMessageTime, Date().timeIntervalSince(lastMessageTime) < 5 {
            delay = 5 - Date().timeIntervalSince(lastMessageTime)
        } else {
            delay = 0
        }
        
        // Schedule the work item
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    func send(str: String, op: OPCode) {
        let payload = str.data(using: .utf8)!
        var buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: 8 + payload.count,
            alignment: MemoryLayout<UInt8>.alignment
        )
        defer { buffer.deallocate() }
        
        buffer.copyBytes(from: payload)
        buffer[8...] = buffer[..<payload.count]
        buffer.storeBytes(of: op.rawValue, as: UInt32.self)
        buffer.storeBytes(of: UInt32(payload.count), toByteOffset: 4, as: UInt32.self)
        
        let _ = try? self.socket.write(from: buffer.baseAddress!, bufSize: buffer.count)
    }
    
    func getResponse() -> Data {
        var data = Data()
        _ = try? socket.read(into: &data)
        return data
    }
}

enum OPCode: UInt32 {
    case handshake = 0
    case frame     = 1
    case close     = 2
    case ping      = 3
    case pong      = 4
}
