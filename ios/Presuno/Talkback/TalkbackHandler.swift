import Foundation
import CocoaLumberjackSwift
import GRDB

class TalkbackHandler: NSObject, SldpEngineDelegate {
    weak var label: UILabel?

    var streamID: Int32 = -1
    var engine: SldpEngineProxy?
    var restartTimer: Timer?
    var currentState: StreamState = .initialized
    var errorShown = false
    
    let RETRY_TIMEOUT: TimeInterval = 3.0
    
    func start() {
        if let config = getConfig() {
            engine = SldpEngineProxy()
            engine?.setDelegate(self)
            currentState = .initialized
            streamID = engine?.createStream(config) ?? -1
            //engine?.setVolume(0.10)
            label?.isHidden = false
            self.label?.text = NSLocalizedString("Talkback OFFLINE", comment: "")
            
        }
    }
    
    func stop() {
        if streamID >= 0 {
            DDLogVerbose("releaseStream")
            let id = streamID
            streamID = -1
            engine?.releaseStream(id)
            streamID = -1
        }
        label?.isHidden = true
        engine = nil

    }
    
    func streamStateDidChangeId(_ streamId: Int32, state: StreamState, status: StreamStatus) {
        DDLogVerbose("TB streamStateDidChange: id:\(streamID) state:\(state.rawValue) status:\(status.rawValue)")
        if state == .disconnected  {
            DispatchQueue.main.async {
                self.label?.text = NSLocalizedString("Talkback OFFLINE", comment: "")
                if self.streamID >= 0 {
                    self.handleError(status: status)
                    self.currentState = .disconnected
                }
            }
        }
        if state == .play {
            errorShown = false
            DispatchQueue.main.async {
                self.currentState = .connected
                self.label?.text = NSLocalizedString("Talkback ONLINE", comment: "")
                let message = NSLocalizedString("Talkback connected", comment: "")
                Toast(text: message, theme: .success, layout: .statusLine)
            }
        }
    }
    
    func getConfig() -> StreamConfig? {
        let conn = try? dbQueue.read { db in
            try? IncomingConnection.filter(sql: "active=?", arguments: ["1"]).fetchOne(db)
        }
        if conn?.active != true {
            return nil
        }
        let config = StreamConfig()
        let mode = PlayerSrtConnectMode(rawValue: conn!.srtConnectMode) ?? PlayerSrtConnectMode.listen
        if let urlStr = conn?.url {
            config.uri = URL(string: urlStr)
            config.mode = .audioOnly
            config.connectMode = mode
            config.buffering = conn!.buffering
            config.latency = conn!.latency
            config.pbkeylen = conn!.pbkeylen
            config.passphrase = conn!.passphrase
            config.streamid = conn!.streamid
            config.version = .V9
        }
        return config
    }
    
    
    func handleError(status: StreamStatus) {
        var message: String
        if currentState == .connected {
            message = NSLocalizedString("Talkback disconnected", comment: "")
        } else {
            switch status {
            case .connectionFail:
                message = String.localizedStringWithFormat(NSLocalizedString("Talkback: Could not connect to server.", comment: ""))
            case .authFail:
                message = String.localizedStringWithFormat(NSLocalizedString("Talkback: Authentication error.", comment: ""))
            case .playbackFail:
                message = String.localizedStringWithFormat(NSLocalizedString("Talkback: Unknown playback error.", comment: ""))
            case .noData:
                message = String.localizedStringWithFormat(NSLocalizedString("Talkback: Stream timeout.", comment: ""))
            default:
                message = String.localizedStringWithFormat(NSLocalizedString("Talkback:: Unknown connection error.", comment: ""))
            }
        }
        if !errorShown {
            Toast(text: message, theme: .warning, layout: .statusLine)
            errorShown = true
        }
        
        // release stream and maybe try to restart
        let cancelId = streamID
        streamID = -1 // ignore .disconnect notification processing for stream that we want to release
        engine?.releaseStream(cancelId)
        
        // if the network is unavailable, do not retry
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let canConnect = appDelegate.canConnect
        
        if !canConnect {
            let message = NSLocalizedString("Talkback: No internet connection.", comment: "")
            Toast(text: message, theme: .error)
        }

        if canConnect && (status != .authFail) {
            
            // try to restart stream
            restartTimer?.invalidate()
            let retryAt = Date(timeIntervalSinceNow: self.RETRY_TIMEOUT)
            restartTimer = Timer(fireAt: retryAt, interval: 0, target: self,
                                  selector: #selector(self.retry), userInfo: nil, repeats: false)
            RunLoop.main.add(self.restartTimer!, forMode: .common)

        }
    }
    
    @objc func retry() {
        let config = getConfig()
        streamID = engine?.createStream(config) ?? -1

    }
    

}
