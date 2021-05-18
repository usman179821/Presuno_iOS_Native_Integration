import GRDB
import CocoaLumberjackSwift

class ImageLayerConfig: Record {
    var id: Int64?
    var name: String
    var url: String
    var active: Bool
    var pause: Bool
    var zIndex: Int32
    var localName: String?
    var lastRequest: Date?
    var displaySize: Double
    var displayPosX: Double
    var displayPosY: Double
    
    override class var databaseTableName: String {
        return "layer_config"
    }

    required override init() {
        self.name = ""
        self.url = ""
        self.active = true
        self.pause = false
        self.zIndex = 0
        self.displaySize = 0
        self.displayPosX = 0.5
        self.displayPosY = 0.5
        super.init()
    }
    
    required init(row: Row) {
        id = row["id"]
        name = row["name"]
        url = row["url"]
        active = row["active"]
        pause = row["pause"]
        zIndex = row["z_index"]
        localName = row["local_name"]
        lastRequest = row["last_request"]
        displaySize = row["display_size"]
        displayPosX = row["display_pos_x"]
        displayPosY = row["display_pos_y"]
        super.init(row: row)
    }
    
    init(name: String, url: String, active: Bool, zIndex: Int32,
              displaySize: Double, displayPosX: Double, displayPosY: Double) {
        self.name = name
        self.url = url
        self.active = active
        self.pause = false
        self.zIndex = zIndex
        self.displaySize = displaySize
        self.displayPosX = displayPosX
        self.displayPosY = displayPosY
        super.init()
    }


    override func encode(to container: inout PersistenceContainer) {
        super.encode(to: &container)
        container["id"] = id
        container["name"] = name
        container["url"] = url
        container["active"] = active
        container["pause"] = pause
        container["z_index"] = zIndex
        container["local_name"] = localName
        container["last_request"] = lastRequest
        container["display_size"] = displaySize
        container["display_pos_x"] = displayPosX
        container["display_pos_y"] = displayPosY
    }
    
    class var imageFolder: URL? {
        let downloadDest = "overlays/"
        guard let path = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return path.appendingPathComponent(downloadDest, isDirectory: true)
    }

    var localPath: URL? {
        if localName?.isEmpty != false {
            return nil
        }
        guard var path = Self.imageFolder else {
            return nil
        }
        path.appendPathComponent(localName!)
        return path
    }
    
    func deleteLocalFile() {
        guard let path = localPath else {
            return
        }
        if checkFileUsed() {
            return
        }
        do {
            try FileManager.default.removeItem(at: path)
        } catch {
            DDLogError("Failed to delete file: \(error.localizedDescription)")
            return
        }
        localName = nil

    }
    
    func checkFileUsed() -> Bool {
        var existCount = 0
        do {
            existCount = try dbQueue.read { db in
                try ImageLayerConfig.filter(Column("local_name") == self.localName).filter(Column("id") != self.id).fetchCount(db)
            }
        } catch {
            DDLogError("Failed get count: \(error.localizedDescription)")
        }
        return existCount == 0
    }
}
