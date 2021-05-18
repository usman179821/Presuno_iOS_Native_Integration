import GRDB

class Connection: BaseConnection {
    // RTSP and RTMP options
    var auth: Int32
    var username: String?
    var password: String?
    // SRT-only options
    var maxbw: Int32
    var retransmitAlgo: Int32

    required init() {
        self.auth = 0
        self.username = nil
        self.password = nil
        self.maxbw = 0
        self.retransmitAlgo = 0
        super.init()
    }

    
    init(name: String, url: String, mode: ConnectionMode, active: Bool) {
        self.auth = 0
        self.username = nil
        self.password = nil
        self.maxbw = 0
        self.retransmitAlgo = 0
        super.init()
        self.name = name
        self.url = url
        self.mode = mode.rawValue
        self.active = active
    }
    
    required init(row: Row) {
        auth = row["auth"]
        username = row["username"]
        password = row["password"]
        maxbw = row["maxbw"]
        retransmitAlgo = row["retransmit_algo"]
        super.init(row: row)
    }
    
    override func encode(to container: inout PersistenceContainer) {
        super.encode(to: &container)
        container["auth"] = auth
        container["username"] = username
        container["password"] = password
        container["maxbw"] = maxbw
        container["retransmit_algo"] = retransmitAlgo
    }
    
    override class var databaseTableName: String {
        return "connection"
    }

    func toGrove() -> [URLQueryItem] {
        var config: [URLQueryItem] = []
        let modeMap: [Int32: String] = [0: "va", 1: "v", 2: "a"]
        let targetMap: [Int32: String] = [1: "lime", 2: "peri", 3: "rtmp", 4: "aka"]
        let ristProfileMap: [Int32: String] = [0: "s", 1: "m", 2: "a"]
        let srtModeMap: [Int32: String] = [0: "c", 1: "l", 2: "r"]

        config.append(URLQueryItem(name: "conn[][url]", value: url))
        config.append(URLQueryItem(name: "conn[][name]", value: name))
        config.append(URLQueryItem(name: "conn[][overwrite]", value: "on"))
        if !active {
            config.append(URLQueryItem(name: "conn[][active]", value: "off"))
        }
        if let user = username {
            config.append(URLQueryItem(name: "conn[][user]", value: user))
        }
        if let pass = password {
            config.append(URLQueryItem(name: "conn[][pass]", value: pass))
        }
        if let mode = modeMap[mode] {
            config.append(URLQueryItem(name: "conn[][mode]", value: mode))
        }
        if url.starts(with: "rtmp"), let target = targetMap[auth] {
            config.append(URLQueryItem(name: "conn[][target]", value: target))
        }
        if url.starts(with: "srt") {
            config.append(URLQueryItem(name: "conn[][srtlatency]", value: String(latency)))
            config.append(URLQueryItem(name: "conn[][srtmaxbw]", value: String(maxbw)))

            if let srtpass = passphrase {
                config.append(URLQueryItem(name: "conn[][srtpass]", value: srtpass))
                config.append(URLQueryItem(name: "conn[][srtpbkl]", value: String(pbkeylen)))
            }
            if let srtMode = srtModeMap[srtConnectMode] {
                config.append(URLQueryItem(name: "conn[][srtmode]", value: srtMode))
            }

            if let srtstreamid = streamid {
                config.append(URLQueryItem(name: "conn[][srtstreamid]", value: srtstreamid))
            }
        }
        if url.starts(with: "rist"), let profile = ristProfileMap[rist_profile] {
            config.append(URLQueryItem(name: "conn[][ristProfile]", value: profile))
        }

        return config
    }
    
    override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    
}
