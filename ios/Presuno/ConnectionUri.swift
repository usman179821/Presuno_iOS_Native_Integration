let supportedOutputSchemes = ["rtsp", "rtsps", "rtmp", "rtmps", "srt", "rist"]
let supportedOutputDesc = "\"rtmp(s)://\", \"rtsp(s)://\", \"srt://\" or \"rist://\""
let supportedInputSchemes = ["rtmp", "sldp", "ws", "http", "rtmps", "sldps", "wss", "https", "srt"]
let supportedInputeDesc = "rtmp(s)://\", \"sldp(s)://\", \"srt://\" or \"http(s)://\""

let httpSchemes = ["http", "https"]
let rtmpSchemes = ["rtmp", "rtmps"]
let rtspSchemes = ["rtsp", "rtsps"]
let udpSchemes = ["srt", "rist"]

class ConnectionUri {
    var scheme: String?
    var host: String?
    var uri: String?
    var port: Int?
    var username: String?
    var password: String?
    var message: String?
    var query: String?
    var queryParams: [String: String] = [:]

    var isHttp: Bool {
        return httpSchemes.contains(scheme ?? "")
    }

    var isRtmp: Bool {
        return rtmpSchemes.contains(scheme ?? "")
    }
    
    var isRtsp: Bool {
        return rtspSchemes.contains(scheme ?? "")
    }
    
    var isSrt: Bool {
        return scheme == "srt"
    }

    var isRist: Bool {
        return scheme == "rist"
    }
    
    var isUdpBased: Bool {
        return udpSchemes.contains(scheme ?? "")
    }

    
    init(url: URL, outgoing: Bool = true) {
        let schemes = outgoing ? supportedOutputSchemes : supportedInputSchemes
        let schemesDesc = outgoing ? supportedOutputDesc : supportedInputeDesc 
        if let scheme = url.scheme?.lowercased(), let host = url.host {
            
            if !schemes.contains(scheme) {
                self.message = String.localizedStringWithFormat(NSLocalizedString("Presuno doesn't support this type of protocol (%@). Please enter %@", comment: ""), scheme, schemesDesc)
                return
            }

            self.scheme = scheme
            self.username = url.user
            self.password = url.password
            self.host = host
            if url.port != nil && url.port! > 0 {
                self.port = url.port
            }
            self.query = url.query
            self.queryParams.removeAll()
            
            if isRtmp {
                let originalUri = url.absoluteString
                let splittedPath = originalUri.split(separator: "/")
                if splittedPath.count < 4 { // since "//" is considered as one cut, there should be only 4 parts
                    self.message = NSLocalizedString("Invalid URL. Can't find rtmp app and stream. Please provide rtmp://host:port/app/stream.", comment: "")
                    return
                }
            }

            if isUdpBased && port == nil {
                self.message = NSLocalizedString("Port number is missing. Please provide valid host and port information like \"srt://host:9000\".", comment: "")
                return
            }
            
            if url.user != nil {
                self.message = NSLocalizedString("User information found in URL. Please fill in \"Login\" and \"Password\" input fields to define stream credentials.", comment: "")
                return

            }
            
            if let components = URLComponents.init(url: url, resolvingAgainstBaseURL: false),
                let items = components.queryItems {
                for item in items {
                    queryParams[item.name] = item.value ?? ""
                }
            }
            
            self.uri = url.absoluteString
            
        } else {
            self.message = NSLocalizedString("Please enter a valid URL. For example rtmp://192.168.1.1:1935/live/stream.", comment: "")
        }
    }
    
    func removeParams(_ params: Set<String>) -> URL? {
        guard let uri = self.uri,
            var components = URLComponents(string: uri),
            let items = components.queryItems else {return URL(string: self.uri ?? "")}
        
        let otherItems = items.filter { (item) -> Bool in
            !params.contains(item.name)
        }
        if otherItems.isEmpty {
            components.queryItems = nil
        } else {
            components.queryItems = otherItems
        }
        return components.url
    }
    
    func updateParams(_ params: [String: String]) -> String? {
        guard var components = URLComponents.init(string: uri!) else {return self.uri}
        var queryItems = components.queryItems ?? []
        for (key,value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = queryItems
        if let url = components.url {
            self.uri = url.absoluteString
        }
        return self.uri
        
    }
}

fileprivate extension String {
    func indexOf(target: String) -> Int? {
        let range = (self as NSString).range(of: target)
        guard Range.init(range) != nil else {
            return nil
        }
        return range.location
    }
    func lastIndexOf(target: String) -> Int? {
        let range = (self as NSString).range(of: target, options: NSString.CompareOptions.backwards)
        guard Range.init(range) != nil else {
            return nil
        }
        return self.count - range.location - 1
    }
}
