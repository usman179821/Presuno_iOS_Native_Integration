import GRDB

class IncomingConnection: BaseConnection {
    var buffering: Int32

    required init() {
        self.buffering = 500
        super.init()
        self.mode = ConnectionMode.audioOnly.rawValue
        self.url = "srt://"
        self.latency = 500
    }
    
    // MARK: Record overrides
    override class var databaseTableName: String {
        return "incoming_connection"
    }
    
    required init(row: Row) {
        buffering = row["buffering"]
        super.init(row: row)
    }
    
    override func encode(to container: inout PersistenceContainer) {
        super.encode(to: &container)
        container["buffering"] = buffering
    }
    
    func toGrove() -> [URLQueryItem] {
        var config: [URLQueryItem] = []
        let modeMap: [Int32: String] = [0: "va", 1: "v", 2: "a"]
        let srtModeMap: [Int32: String] = [0: "c", 1: "l", 2: "r"]

        config.append(URLQueryItem(name: "tb[][url]", value: url))
        config.append(URLQueryItem(name: "tb[][name]", value: name))
        config.append(URLQueryItem(name: "tb[][overwrite]", value: "on"))
        config.append(URLQueryItem(name: "tb[][buffer]", value: String(buffering)))
        if !active {
            config.append(URLQueryItem(name: "tb[][active]", value: "off"))
        }
        if let mode = modeMap[mode] {
            config.append(URLQueryItem(name: "tb[][mode]", value: mode))
        }
        if url.starts(with: "srt") {
            config.append(URLQueryItem(name: "tb[][srtlatency]", value: String(latency)))

            if let srtpass = passphrase {
                config.append(URLQueryItem(name: "tb[][srtpass]", value: srtpass))
                config.append(URLQueryItem(name: "tb[][srtpbkl]", value: String(pbkeylen)))
            }
            if let srtMode = srtModeMap[srtConnectMode] {
                config.append(URLQueryItem(name: "tb[][srtmode]", value: srtMode))
            }

            if let srtstreamid = streamid {
                config.append(URLQueryItem(name: "tb[][srtstreamid]", value: srtstreamid))
            }
        }

        return config
    }
    
    
}
