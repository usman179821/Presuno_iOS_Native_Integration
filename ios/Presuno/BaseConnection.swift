import GRDB

class BaseConnection: Record {
    var id: Int64?
    var name: String
    var url: String
    var mode: Int32
    var active: Bool
    // SRT-only options
    var srtConnectMode: Int32
    var passphrase: String?
    var pbkeylen: Int32
    var latency: Int32
    var streamid: String?
    // RIST options
    var rist_profile: Int32
    
    required override init() {
        self.name = ""
        self.url = ""
        self.mode = ConnectionAuthMode.default.rawValue
        self.active = false
        self.srtConnectMode = 0
        self.passphrase = nil
        self.pbkeylen = 16
        self.latency = 2000
        self.streamid = nil
        self.rist_profile = 1
        super.init()
    }
    
    // MARK: Record overrides
    
    override class var databaseTableName: String {
        return "connection"
    }
    
    required init(row: Row) {
        id = row["id"]
        name = row["name"]
        url = row["url"]
        mode = row["mode"]
        active = row["active"]
        srtConnectMode = row["srt_connect_mode"]
        passphrase = row["passphrase"]
        pbkeylen = row["pbkeylen"]
        latency = row["latency"]
        streamid = row["streamid"]
        rist_profile = row["rist_profile"]
        super.init(row: row)
    }
    
    override func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["url"] = url
        container["mode"] = mode
        container["active"] = active
        container["srt_connect_mode"] = srtConnectMode
        container["passphrase"] = passphrase
        container["pbkeylen"] = pbkeylen
        container["latency"] = latency
        container["streamid"] = streamid
        container["rist_profile"] = rist_profile
    }
    
    override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
    
}
