//
//  NowPlayingInfo.swift
//  QQ音乐RPC
//
//  Created by Hunter Han on 2/22/25.
//

import Foundation
import SwiftData
import PrivateMediaRemote
import AppKit
import SQLite


class NowPlayingLinkCache {
    var hash: String
    var link: String
    
    init(hash: String, link: String) {
        self.hash = hash
        self.link = link
    }
    
    var description: String {
        return "NowPlayingLinkCache(hash: \(hash), link: \(link))"
    }
}

@MainActor
class DatabaseManager {
    static let shared = DatabaseManager()
    static let cacheDbName = "NowPlayingLinkCache.sqlite"
    
    let cacheTable = Table("NowPlayingLinkCache")
    let hash = SQLite.Expression<String>("hash")
    let link = SQLite.Expression<String>("link")
    
    private var db: Connection?
    
    init() {
        do {
            let cacheDbPath = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Application Support")
                .appendingPathComponent("QQ音乐RPC")
                .appendingPathComponent(DatabaseManager.cacheDbName)
            print("Cache DB path: \(cacheDbPath.path)")
            db = try Connection(cacheDbPath.path)
            
            createCacheTable()
        } catch {
            print("Failed to get cache DB path: \(error)")
        }
    }
    
    func createCacheTable() {
        do {
            try db?.run(cacheTable.create { t in
                t.column(hash, primaryKey: true)
                t.column(link)
            })
        } catch {
            print("Failed to create cache table: \(error)")
        }
    }
    
    func fetchCache(hash: String) -> NowPlayingLinkCache? {
        do {
            let query = cacheTable.filter(self.hash == hash)
            let result = try db?.pluck(query)
            if let result = result {
                return NowPlayingLinkCache(hash: result[self.hash], link: result[link])
            }
        } catch {
            print("Failed to fetch cache: \(error)")
        }
        return nil
    }
    
    func insertCache(hash: String, link: String) {
        do {
            try db?.run(cacheTable.insert(self.hash <- hash, self.link <- link))
        } catch {
            print("Failed to insert cache: \(error)")
        }
    }
}


class NowPlayingInfoManager : ObservableObject {
    @Published private var nowPlayingInfo: NowPlayingInfo?
    
    func setNowPlayingInfo(_ info: [AnyHashable: Any]) {
        nowPlayingInfo = NowPlayingInfo(info)
    }
    
    @MainActor private func fetchCache() -> NowPlayingLinkCache? {
        guard let nowPlayingInfo else {
            return nil
        }
        
        return DatabaseManager.shared.fetchCache(hash: nowPlayingInfo.hashValue)
    }
    
    func getImageArtworkLink() async -> String? {
        guard let nowPlayingInfo else {
            return nil
        }
        
        // Query SwiftData for cached link
        let hash = nowPlayingInfo.hashValue
        if let cachedLink = await fetchCache() {
            // Found cache
            print("Found cache for \(nowPlayingInfo.title ?? "") \(nowPlayingInfo.artist ?? "") \(nowPlayingInfo.album ?? "") at link \(cachedLink.link)")
            return cachedLink.link
        }
        
        let search = "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=1&w=\(nowPlayingInfo.title ?? "") \(nowPlayingInfo.artist ?? "") \(nowPlayingInfo.album ?? "")&format=json"
        let url = URL(string: search)!
        let (data, _) = try! await URLSession.shared.data(from: url)
        
        // TODO: Find better way to do this abomination
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        let returnData = (((json["data"] as? [String: Any])?["song"] as? [String: Any])?["list"] as? [Any])?.first as? [String: Any]
        
        if let returnDict = returnData, let returnInt = returnDict["albumid"] as? Int {
            let imgLink =  "https://imgcache.qq.com/music/photo/album_300/\(returnInt % 100)/300_albumpic_\(returnInt)_0.jpg"
            
            await DatabaseManager.shared.insertCache(hash: hash, link: imgLink)
            return imgLink
        }
        
        return nil
    }
    
    func callIfPlaying(discordRPC: CustomDiscordRPC, callback: @escaping () -> Void) {
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue.main) { isPlaying in
            if isPlaying {
                callback()
            } else {
                self.clearDiscordActivity(discordRPC: discordRPC)
            }
        }
    }
    
    func clearDiscordActivity(discordRPC: CustomDiscordRPC) {
        discordRPC.clearActivity()
    }
                
        
    func setDiscordActivity(discordRPC: CustomDiscordRPC) {
        guard let nowPlayingInfo else {
            return
        }
        
        callIfPlaying(discordRPC: discordRPC) {
            Task {
                let artworkLink = await self.getImageArtworkLink() ?? ""
                discordRPC.sendActivity(CustomDiscordActivity(
                    type: .listening,
                    state: nowPlayingInfo.album ?? "",
                    details: nowPlayingInfo.title ?? "",
                    timestamps: nowPlayingInfo.getDiscordTimestamps(),
                    assets: DiscordAssets(
                        large_image: artworkLink,
                        large_text: nowPlayingInfo.artist ?? "TITLE_NIL"
                    )
                ))
            }
        }
    }
    
    func getNowPlayingInfo() -> NowPlayingInfo? {
        return nowPlayingInfo
    }
}

struct NowPlayingInfo {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?
    var duration: Int?
    var startTime: Date?
    var elapsedTime: Int?
        
    var hashValue: String {
        return "\(title ?? "");\(artist ?? "");\(album ?? "")"
    }
    
    init(_ info: [AnyHashable: Any]) {
        title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String
        artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String
        album = info[kMRMediaRemoteNowPlayingInfoAlbum] as? String
        let artworkRawData = info[kMRMediaRemoteNowPlayingInfoArtworkData] as? Data
        duration = info[kMRMediaRemoteNowPlayingInfoDuration] as? Int
        startTime = info[kMRMediaRemoteNowPlayingInfoTimestamp] as? Date
        elapsedTime = info[kMRMediaRemoteNowPlayingInfoElapsedTime] as? Int
        
        if let data = artworkRawData {
            if let image = NSImage(data: data) {
                artwork = image
            }
        }
    }
    
    func getDiscordTimestamps() -> DiscordTimestamps? {
        if let startTime, let duration {
            var realStart = startTime
            var realEnd = startTime.addingTimeInterval(TimeInterval(duration))
            if let elapsedTime {
                realStart = startTime.addingTimeInterval(TimeInterval(-elapsedTime))
                realEnd = startTime.addingTimeInterval(TimeInterval(duration - elapsedTime))
            }
            return DiscordTimestamps(
                start: Int(realStart.timeIntervalSince1970),
                end: Int(realEnd.timeIntervalSince1970)
            )
        } else {
            return nil
        }
    }
}
