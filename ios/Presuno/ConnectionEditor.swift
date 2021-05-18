import CocoaLumberjackSwift
import Eureka
import GRDB
import SwiftMessages
import UIKit

enum ModeSelection : String, CustomStringConvertible {
    case VideoAudio = "Audio + Video"
    case VideoOnly = "Video only"
    case AudioOnly = "Audio only"
    
    var description : String { return NSLocalizedString(rawValue, comment: "") }
    
    static let allValues = [VideoAudio, VideoOnly, AudioOnly]
    init(fromInt val: Int32) {
        self = val >= 0 && val < Self.allValues.count ? Self.allValues[Int(val)] : .VideoAudio
    }
    var intValue: Int32 {
        return Int32(Self.allValues.firstIndex(of: self) ?? 0)
    }
}

enum CdnSelection : String, CustomStringConvertible {
    case Default = "Default (no authorization)"
    case Llnw = "Limelight Networks"
    case Periscope = "Periscope Producer"
    case RTMP = "RTMP authorization"
    case Akamai = "Akamai/Dacast"
    var description : String { return NSLocalizedString(rawValue, comment: "") }
    
    static let allValues = [Default, RTMP, Akamai, Llnw, Periscope]
    static let ordered = [Default, Llnw, Periscope, RTMP, Akamai] // As it presented in ConnectionAuthMode
    init(fromInt val: Int32) {
        self = val >= 0 && val < Self.allValues.count ? Self.ordered[Int(val)] : .Default
    }
    var intValue: Int32 {
        return Int32(Self.ordered.firstIndex(of: self) ?? 0)
    }

}

enum RistProfileSelection : String, CustomStringConvertible {
    case Simple = "Simple"
    case Main = "Main"
    case Advanced = "Advanced"
    var description : String { return NSLocalizedString(rawValue, comment: "") }
    var intValue: Int32 {
        switch self {
        case .Simple:
            return 0
        case .Main:
            return 1
        case .Advanced:
            return 2
        }
    }
    init(fromInt i: Int32) {
        switch i {
        case 0:
            self = .Simple
        case 1:
            self = .Main
        case 2:
            self = .Advanced
        default:
            self = .Main
        }
    }
    static let allValues = [Simple, Main]
}

enum SrtConnectModeSelection : String, CustomStringConvertible {
    case Pull = "Caller"
    case Listen = "Listen"
    case Rendezvous = "Rendezvous"
    
    init(intValue: Int32) {
        if (intValue >= 0 && intValue < Self.allValues.count) {
            self = Self.allValues[Int(intValue)]
        } else {
            self = .Pull
        }
    }
    var description : String { return NSLocalizedString(rawValue, comment: "") }
    var intValue: Int32 {
        return Int32(Self.allValues.firstIndex(of: self) ?? 0)
    }
    
    static let allValues = [Pull, Listen, Rendezvous]
}


enum SrtRetransmitAlgoSelection : String, CustomStringConvertible {
    case Default = "Default"
    case Reduced = "Reduced"
    
    init(intValue: Int32) {
        if (intValue >= 0 && intValue < Self.allValues.count) {
            self = Self.allValues[Int(intValue)]
        } else {
            self = .Default
        }
    }
    var description : String { return NSLocalizedString(rawValue, comment: "") }
    var intValue: Int32 {
        return Int32(Self.allValues.firstIndex(of: self) ?? 0)
    }
    
    static let allValues = [Default, Reduced]
}

class BaseConnEditorViewController: FormViewController {
    
    var connection: BaseConnection?
    var newRecord: Bool = false

    var discard = false
    
    var cancel: UIBarButtonItem?
    var update: UIBarButtonItem?
    
    let wizardHint = "Start typing or paste URL to view protocol-specific fields for authentication etc."
    
    let listnenerHint = "On receiver side, specify your public IP address and the same port as you use in URL above."
    let latencyHint = """
\"latency\" parameter defines the time interval for buffering and resending packets. \
If the value is too low, retransmission of lost packets is not possible.
In general it is 4 times RTT between source and destination.
"""

    let maxBwHint = """
\"maxbw\" parameter specifies maximum bandwidth (in bytes per second) \
which Presuno will use for stream transmission and for re-sending packets, combined.
Keep it blank by default to make it relative to input rate.
"""
    let srtHint = "If you don\'t want to set any specific value, then leave the field empty."
    let ristHint = "Define your additional RIST parameters in URL, e.g. rist://192.168.1.1:5000?aes-type=128&secret=abcde."
    let ristProfileHint = "If you stream to Amazon MediaConnect, then use Simple Profile."
    
    let unsupportedAuth = NSLocalizedString("Presuno doesn't support this type of RTMP authorization. Please use rtmpauth URL parameter or other \"Target type\" for authorization.", comment: "")
    
    var isOutgoing: Bool {
        return true
    }
    
    var localIP: (String?, String?) {
        let ipList = IpUtils.getLocalIP()
        var localIp = ipList["en0"]
        var ipType = NSLocalizedString("Wi-Fi", comment: "")
        if localIp == nil {
            localIp = ipList["pdp_ip0"]
            ipType = NSLocalizedString("Mobile", comment: "")
        }
        if localIp == nil {
            let some = ipList.first(where: { (key, value) in
                !key.starts(with: "lo")
            })
            localIp = some?.value
            ipType = some?.key ?? ""
        }
        return (localIp, ipType)
    }

    @objc func deleteButtonPressed(_ sender: UIBarButtonItem) {
        self.presentDeleteAlert()
    }
    
    func presentDeleteAlert() {
        var name: String = ""
        if let nameVal = self.connection?.name {
            name = nameVal
        }
        let message = String.localizedStringWithFormat(NSLocalizedString("Delete \"%@\"?", comment: ""), name)
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let delete = UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive, handler: { action in
            _ = try! dbQueue.write { db in
                try! self.connection?.delete(db)
                if let name = self.connection?.name {
                    let message = String.localizedStringWithFormat(NSLocalizedString("Deleted: \"%@\"", comment: ""), name)
                    Toast(text: message, theme: .success, layout: .statusLine)
                }
                self.connection = nil
            }
            _ = self.navigationController?.popViewController(animated: true) })
        alertController.addAction(delete)
        let cancel = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        alertController.addAction(cancel)
        present(alertController, animated: true, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        connection = DataHolder.sharedInstance.connecion
        newRecord = connection?.id == nil

        if newRecord {
            let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(self.saveButtonPressed(_:)))
            navigationItem.rightBarButtonItem = saveButton
        } else {

            let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(self.deleteButtonPressed(_:)))
            navigationItem.rightBarButtonItem = deleteButton
            
            cancel = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: ""), style: .plain, target: self, action: #selector(cancelAction(barButtonItem:)))

            update = UIBarButtonItem(title: NSLocalizedString("Update", comment: ""), style: .plain, target: self, action: #selector(updateAction(barButtonItem:)))

            let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
            toolbarItems = [cancel!, flexible, update!]
        }
        navigationController?.isToolbarHidden = false
 
        let connUrl = connection?.url.isEmpty == false ? URL(string: connection!.url) : nil
        let connUri = connUrl != nil ? ConnectionUri(url: connUrl!, outgoing: isOutgoing) : nil
        
        let section = addMainSection(uri: connUri)
        form +++ section

        if let cdnSection = addCdnSection(uri: connUri) {
            form +++ cdnSection
        }
        
        if let authSection = addAuthSection(uri: connUri) {
            form +++ authSection
        }
        
        if let srtSection = addSrtSection(uri: connUri) {
            form +++ srtSection
        }
        if let ristSection = addRistSection(uri: connUri) {
            form +++ ristSection
        }

        if let talkbackSection = addTalkbackSection(uri: connUri) {
            form +++ talkbackSection
        }

        if let infoSection = addInfoSection() {
            form +++ infoSection
        }

    }
    
    internal func addMainSection(uri connUri: ConnectionUri?) -> Section {
        let section = Section()
        section.tag = "connection_editor"

        section
            <<< TextRow("name") {
                $0.title = NSLocalizedString("Name", comment: "")
                $0.placeholder = NSLocalizedString("Connection #1", comment: "")
                $0.value = connection?.name
            }
            <<< URLRow("url") {
                $0.title = NSLocalizedString("URL", comment: "")
                $0.placeholder = "rtmp://192.168.1.1:1935/live/stream"
                $0.value = URL(string: connection?.url ?? "")

            }.onChange(onUrlChange)
        
            <<< TextAreaRow ("hint") {
                $0.value = wizardHint
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
            }.cellSetup(setupTextArea)
        
//        if newRecord {
//            section <<< TextAreaRow("srt_hint") {
//                $0.title = srtHint
//                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
//                $0.hidden = Condition.function(["url"], {
//                    guard let url = ($0.rowBy(tag: "url") as? URLRow)?.value else {return true}
//                    return url.scheme != "srt"
//                })
//            }.cellSetup(setupTextArea)
//        }
        return section
    }
    
    internal func addCdnSection(uri connUri: ConnectionUri?) -> Section? {
        return nil
    }
    
    internal func addAuthSection(uri connUri: ConnectionUri?) -> Section? {
        return nil
    }

    internal func addTalkbackSection(uri connUri: ConnectionUri?) -> Section? {
        return nil
    }

    internal func addInfoSection() -> Section? {
        return nil
    }
    
    internal func addSrtSection(uri connUri: ConnectionUri?) -> Section? {
        if !newRecord && connUri?.isSrt == false {
            return nil
        }
        let ifRendezvous = Condition.function(["srt_mode"], {
            guard let button = $0.rowBy(tag: "ip_list") as? ButtonRow, button.title != nil else {return false}
            if let mode = ($0.rowBy(tag: "srt_mode") as? PushRow<SrtConnectModeSelection>)?.value {
                return mode != .Rendezvous
            } else {
                return false
            }
        })
        let ifListen = Condition.function(["srt_mode"], {
            guard let button = $0.rowBy(tag: "ip_list") as? ButtonRow, button.title != nil else {return false}
            if let mode = ($0.rowBy(tag: "srt_mode") as? PushRow<SrtConnectModeSelection>)?.value {
                return mode != .Listen
            } else {
                return false
            }
        })
        let section = Section()
        let (ip, ipType) = localIP
        var ipTitle = NSLocalizedString( "Push IP for Caller" , comment: "")
        var ipList: NSMutableAttributedString?
        if ip != nil {
            ipTitle.append(String(format:" (%@):\n",ipType!))
            let attrBoldText = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: UIFont.buttonFontSize - 1.0)]
            ipList = NSMutableAttributedString(string: ipTitle, attributes: attrBoldText)
            ipList!.append(NSAttributedString(string: ip!))
        }
        section
            <<< PushRow<SrtConnectModeSelection>("srt_mode") {
                $0.title = NSLocalizedString("Srt receiver mode", comment: "")
                $0.options = SrtConnectModeSelection.allValues
                $0.value = SrtConnectModeSelection.init(intValue: connection?.srtConnectMode ?? 1)
            }.onPresent { (_, vc) in vc.enableDeselection = false }

            <<< ButtonRow("ip_list") { row in
                row.title = ip
                row.hidden = ifListen

                row.presentationMode = .presentModally(controllerProvider: ControllerProvider.callback { self.shareView(row: row, ip: ip!) }, onDismiss: nil)
            }.cellSetup{ (cell, row) in
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.font = .systemFont(ofSize: UIFont.labelFontSize)
            }.cellUpdate { (cell, row) in
                cell.textLabel?.attributedText = ipList
            }
            <<< TextAreaRow("listener_hint") {
                $0.value = NSLocalizedString(listnenerHint, comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
                $0.hidden = ifRendezvous
            }.cellSetup(setupTextArea)
            <<< IntRow() {
                $0.title = NSLocalizedString("latency (msec)", comment: "")
                $0.tag = "latency"
                $0.value = Int(connection?.latency ?? 2000)
            }
            <<< TextAreaRow("latency_hint") {
                $0.value = NSLocalizedString(latencyHint, comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
            }.cellSetup(setupTextArea)
            <<< PasswordRow() {
                $0.title = NSLocalizedString("passphrase", comment: "")
                $0.tag = "passphrase"
                $0.value = connection?.passphrase ?? ""
                $0.add(rule: RuleMinLength(minLength: 10))
                $0.add(rule: RuleMaxLength(maxLength: 79))
            }
            .cellUpdate { cell, row in
                if !row.isValid {
                    cell.titleLabel?.textColor = .red
                }
            }
            <<< PushRow<Int32>() {
                $0.title = NSLocalizedString("pbkeylen", comment: "")
                $0.tag = "pbkeylen"
                $0.options = [16, 24, 32]
                $0.value = connection?.pbkeylen ?? 16
            }.onPresent({ (_, vc) in vc.enableDeselection = false })
            
            <<< TextRow() {
                $0.title = NSLocalizedString("streamid", comment: "")
                $0.tag = "streamid"
                $0.value = connection?.streamid ?? ""
                $0.add(rule: RuleMaxLength(maxLength: 512))
            }
            .cellSetup { cell, _ in
                cell.textField.autocapitalizationType = .none
                cell.textField.autocorrectionType = .no
            }
            .cellUpdate { cell, row in
                if !row.isValid {
                    cell.titleLabel?.textColor = .red
                }
        }
        
        section.hidden = Condition.function(["url"], {
            guard let url = ($0.rowBy(tag: "url") as? URLRow)?.value else {return true}
            return url.scheme != "srt"
        })
        
        return section
    }
    
    internal func addRistSection(uri connUri: ConnectionUri?) -> Section? {
        return nil
    }
    
    func shareView( row: ButtonRow, ip: String) -> UIViewController {
        let urls = self.getSrtUrl(ip)
        let name = UIDevice.current.name
        var title: String
        var description: String
        if self is ConnectionEditorViewController {
            title = NSLocalizedString("Presuno Broadcaster SRT settings", comment: "")
            description = String.localizedStringWithFormat("The following URL(s) can be used to connect to Presuno Broadcaster to receive SRT publication from %@:", name)
        } else {
            title = NSLocalizedString("Presuno Broadcaster SRT talkback settings", comment: "")
            description = String.localizedStringWithFormat("The following URL(s) can be used to connect to Presuno Broadcaster to send the talkback stream via SRT to %@:", name)
        }
        var items: [Any] = [description]
        if urls != nil {
            items.append(contentsOf: urls!)
        }
        let shareController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // This lines is for the popover you need to show in iPad
        shareController.popoverPresentationController?.sourceView = row.cell.contentView
        shareController.popoverPresentationController?.sourceRect = row.cell.contentView.frame
        
        shareController.setValue(title, forKey: "subject")
        if #available(iOS 13.0, *) {
            // Pre-configuring activity items
            shareController.activityItemsConfiguration = [
                UIActivity.ActivityType.airDrop,
                UIActivity.ActivityType.copyToPasteboard,
                UIActivity.ActivityType.message,
                UIActivity.ActivityType.mail,
                UIActivity.ActivityType.print
            ] as? UIActivityItemsConfigurationReading
            
            shareController.isModalInPresentation = true
        }
        return shareController
    }

    func getSrtUrl(_ ip: String) -> [URL]? {
        var port: Int?
        if let url = (form.rowBy(tag: "url") as? URLRow)?.value {
              port = url.port
        }
        
        let ipList = ip.split(separator: "\n")
        let res: [URL] = ipList.map { ip in
            var url = URLComponents()
            url.scheme = "srt"
            if ip.contains(":") { //IPv6
                url.host = "[" + String(ip) + "]"
            } else {
                url.host = String(ip)
            }
            url.port = port
            return url.url!
        }
        return res
    }
    
    func onUrlChange(row: URLRow) {
        if let url = row.value {
            let parsed = ConnectionUri(url: url)
            var title = ""
            
            if parsed.isRtmp {
                 title = NSLocalizedString("RTMP URL schema is rtmp://server/application/streamkey, e.g. rtmp://a.rtmp.youtube.com/live2/abcd-efgh-abcd-efgh.", comment: "")
            } else if parsed.isRist {
                title = NSLocalizedString(ristHint, comment: "")
            } else if parsed.isSrt {
                title = NSLocalizedString(srtHint, comment: "")
            } else if parsed.uri == nil {
                title = NSLocalizedString(wizardHint, comment: "")
            }
            if let hint = self.form.rowBy(tag: "hint") as? TextAreaRow {
                if hint.value != title {
                    hint.value = title
                    hint.updateCell()
                }
            }
        }
    }
    
    func setupTextArea(cell: TextAreaCell, row: TextAreaRow) {
        row.textAreaMode = .readOnly
        cell.textView.font = .systemFont(ofSize: 14)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SwiftMessages.hideAll()

        if !self.isMovingFromParent || discard {
            return
        }
        
        if !newRecord {
            save()
        }
    }
    
    internal func getCount() -> Int {
        return 0
    }
    
    internal func validateForm() -> String? {
        guard let url = form.rowBy(tag: "url")?.baseValue as? URL else {
            return NSLocalizedString("Please enter connection URL, for example: rtmp://192.168.1.1:1935/live/stream", comment: "")
        }
        
        let connUri = ConnectionUri(url: url, outgoing: isOutgoing)
        guard let uri = connUri.uri else {
            if let error = connUri.message {
                return error
            }
            return ""
        }
        
        if let authErr = validateAuth(uri: connUri) {
            return authErr
        }
        let count = getCount()
        
        var name = form.rowBy(tag: "name")?.baseValue as? String
        if name?.isEmpty != false {
            name = String.localizedStringWithFormat(NSLocalizedString("Connection #%d (%@)", comment: ""), count + 1, connUri.host ?? "")
        }
        
        guard let connection = self.connection else {
            return ""
        }
        connection.name = name ?? ""
        connection.url = uri
        if newRecord {
            connection.active = count == 0
        }

        if let selection = form.rowBy(tag: "mode")?.baseValue as? ModeSelection {
            connection.mode = selection.intValue
        } else {
            connection.mode = 0
        }
    
        if connUri.isSrt, let error = saveSrtParams(connection, uri: connUri) {
            return error
        }
        
        if connUri.isRist {
            let profile = form.rowBy(tag: "rist_profile")?.baseValue as? RistProfileSelection ?? RistProfileSelection.Main
            connection.rist_profile = profile.intValue
            let port = connUri.port ?? 0
            if profile == .Simple && port % 2 != 0 {
                let error = NSLocalizedString("RIST \"Simple\" profile requires even number for port", comment: "")
                Toast(text: error, theme: .warning, layout: .statusLine)
            }
        }
        
        return nil
    }
    
    func validateAuth(uri connUri: ConnectionUri ) -> String? {
        guard let conn = connection as? Connection else {
            return nil
        }
        let cdn = form.rowBy(tag: "cdn")?.baseValue as? CdnSelection ?? CdnSelection.Default
        let isAuth = [.Llnw, .RTMP, .Akamai].contains(cdn)

        if let username = connUri.username, let _ = connUri.password {
            if connUri.isRtmp, !isAuth {
                return unsupportedAuth
            } else {
                return String.localizedStringWithFormat(NSLocalizedString("Username (%@) and password found in URL. Please fill in \"Login\" and \"Password\" input fields to define stream credentials.", comment: ""), username)
            }
        }
        
        if let login = form.rowBy(tag: "login")?.baseValue as? String {
            if connUri.isRtmp, !isAuth {
                return unsupportedAuth
            }
            
            let password = form.rowBy(tag: "password")?.baseValue as? String
            if connUri.isRtmp && password == nil {
                return NSLocalizedString("Presuno doesn't support empty password. Please fill in both \"Login\" and \"Password\" input fields to define stream credentials.", comment: "")
            }
            conn.username = login
            conn.password = password
            
            if connUri.isRtmp {
                conn.auth = cdn.intValue
            }
        } else {
            if let _ = form.rowBy(tag: "password")?.baseValue {
                if connUri.isRtmp, !isAuth {
                    return unsupportedAuth
                } else {
                    return NSLocalizedString("Presuno doesn't support empty username. Please fill in both \"Login\" and \"Password\" input fields to define stream credentials.", comment: "")
                }
            }
            conn.username = nil
            conn.password = nil
        }
        if connUri.isRtmp && cdn == .Periscope {
            conn.auth = ConnectionAuthMode.periscope.rawValue
        }
        return nil
    }

    @objc func cancelAction(barButtonItem: UIBarButtonItem) {
        discard = true
        _ = self.navigationController?.popViewController(animated: true)
    }
    
    @objc func updateAction(barButtonItem: UIBarButtonItem) {
        if let section = form.sectionBy(tag: "connection_editor"), let conn = connection {
            var update = false
            for row in section {
                if row.wasChanged {
                    update = true
                }
            }
            if update {
                if save() {
                    Toast(text: String.localizedStringWithFormat(NSLocalizedString("Updated: \"%@\"", comment: ""), conn.name), theme: .info, layout: .statusLine)
                }
            } else {
                Toast(text: String.localizedStringWithFormat(NSLocalizedString("\"%@\" is not changed", comment: ""), conn.name), theme: .warning, layout: .statusLine)
            }
        }
    }
    
    @objc func saveButtonPressed(_ sender: UIBarButtonItem) {
        if save() {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @discardableResult
    func save() -> Bool {
        guard let conn = connection, let _ = form.rowBy(tag: "url")?.baseValue as? URL else { return false }
        if let error = validateForm() {
            if newRecord {
                Toast(text: error, theme: .error, layout: .statusLine)
            } else {
                Toast(text: error, theme: .warning, layout: .statusLine)
            }
            return false
        }
        
        try! dbQueue.write { db in
            if newRecord {
                try! conn.insert(db)
            } else {
                try! conn.update(db)
            }
        }
        return true
    }

    internal func saveSrtParams(_ connection: BaseConnection, uri connUri: ConnectionUri) -> String? {
        var error: String?
        
        if let latency = form.rowBy(tag: "latency")?.baseValue as? Int {
            connection.latency = Int32(latency)
        } else {
            connection.latency = 2000
        }
        if let c = connection as? Connection {
            c.auth = ConnectionAuthMode.default.rawValue
            c.username = nil
            c.password = nil

            if let maxbw = form.rowBy(tag: "maxbw")?.baseValue as? Int {
                c.maxbw = Int32(maxbw)
            } else {
                c.maxbw = 0
            }
        }
        if connUri.port == nil {
            // ConnectionUri already did this check for both srt and rist, so don't duplicate message
            error = ""
        }
        
        if let mode = form.rowBy(tag: "srt_mode")?.baseValue as? SrtConnectModeSelection {
            connection.srtConnectMode = mode.intValue
        } else {
            connection.srtConnectMode = 0
        }
    
        if let pbkeylen = form.rowBy(tag: "pbkeylen")?.baseValue as? Int32 {
            connection.pbkeylen = pbkeylen
        }
        
        if let passphrase = form.rowBy(tag: "passphrase")?.baseValue as? String {
            if (passphrase.count < 10) {
                if !passphrase.isEmpty {
                    error = NSLocalizedString("The passphrase must have at least 10 characters length.", comment: "")
                }
                connection.passphrase = nil
            } else if (passphrase.count > 79) {
                error = NSLocalizedString("The passphrase must have maximum 79 characters length.", comment: "")
                connection.passphrase = nil
            } else {
                connection.passphrase = passphrase
            }
        } else {
            connection.passphrase = nil
        }
        if let streamid = form.rowBy(tag: "streamid")?.baseValue as? String {
            if (streamid.count > 512) {
                error = NSLocalizedString("The streamid must have maximum 512 characters length.", comment: "")
                connection.streamid = nil
            } else {
                connection.streamid = streamid
            }
        } else {
            connection.streamid = nil
        }
        return error
    }

}

class ConnectionEditorViewController: BaseConnEditorViewController {
    
    override func getCount() -> Int {
        let count = try? dbQueue.read { db in
            try Connection.fetchCount(db)
        }
        return count ?? 0
    }

    override func addMainSection(uri connUri: ConnectionUri?) -> Section {
        var section = super.addMainSection(uri: connUri)

        if let insertIndex = section.allRows.firstIndex(where: { $0.tag == "hint" }) {
            let mode = PushRow<ModeSelection>("mode") {
                $0.title = NSLocalizedString("Mode", comment: "")
                $0.options = ModeSelection.allValues
                $0.value = ModeSelection(fromInt: connection?.mode ?? 0)
            }.onPresent({ (_, vc) in vc.enableDeselection = false })
            
            section.insert(mode, at: insertIndex)
        }
        return section
    }
    
    override func addCdnSection(uri connUri: ConnectionUri?) -> Section?  {
        guard let conn = connection as? Connection else { return nil }
        
        let cdnSection = Section()
        cdnSection.hidden = Condition.function(["url"], {
            let url = ($0.rowBy(tag: "url") as? URLRow)?.value
            if let scheme = url?.scheme {
                // cdn selection is applicable only to rtmp
                return !rtmpSchemes.contains(scheme)
            }
            return true
        })
        cdnSection <<< PushRow<CdnSelection>("cdn") {
            $0.title = NSLocalizedString("Target type", comment: "")
            $0.options = CdnSelection.allValues
            $0.disabled = Condition(booleanLiteral: !newRecord)
            $0.value = CdnSelection(fromInt: conn.auth)
        }.onPresent({ (_, vc) in vc.enableDeselection = false })
    
        if !newRecord {
            let authHint = NSLocalizedString("Need to add or change RTMP authentication schema? Add new connection.", comment: "")
            if connUri?.isRtmp == true {
                cdnSection
                    <<< TextAreaRow("auth_hint") {
                        $0.value = authHint
                        $0.textAreaHeight = .fixed(cellHeight: 75.0)
                    }.cellSetup(setupTextArea)
            }
        }
        return cdnSection
    }
    
    override func addAuthSection(uri connUri: ConnectionUri?) -> Section?  {
        guard let conn = connection as? Connection else { return nil }

        var allowPassword = newRecord || connUri?.isRtsp == true
        if connUri?.isRtmp == true && conn.username != nil && conn.password != nil {
            // Rtmp authorization must be set explicitly via target CDN type
            // ConnectionWizard already validated CDN type, so just check that credentials are set
            allowPassword = true
        }
        
        if !allowPassword { return nil }
   
        let credentialsSection = Section()
        credentialsSection.hidden = Condition.function(["url"], {
            let url = ($0.rowBy(tag: "url") as? URLRow)?.value
            if let scheme = url?.scheme {
                return udpSchemes.contains(scheme)
            }
            return true
        })
        credentialsSection <<< AccountRow("login") {
            $0.title = NSLocalizedString("Login", comment: "")
            $0.value = conn.username
        }
        <<< PasswordRow("password") {
            $0.title = NSLocalizedString("Password", comment: "")
            $0.value = conn.password
        }
        return  credentialsSection
    }
    
    override func addInfoSection() -> Section? {
        if !newRecord { return nil }
        let section = Section()
        section
            <<< ButtonRow() {
                $0.title = NSLocalizedString("Visit docs page for setup details", comment: "")
            }.onCellSelection { cell, row  in
                if let url = URL(string: "https://softvelum.com/larix/docs") {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("Watch video tutorial", comment: "")
            $0.onCellSelection { (_, _) in
                if let url = URL(string: "https://www.youtube.com/watch?v=Dhj0_QbtfTw") {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        }
        
        return section
    }
    
    override func addSrtSection(uri connUri: ConnectionUri?) -> Section? {
        guard let outgoing = connection as? Connection else {
            return nil
        }
        
        let srtSection = super.addSrtSection(uri: connUri)
        if let mode: PushRow<SrtConnectModeSelection> = srtSection?.rowBy(tag: "srt_mode") {
            mode.title = NSLocalizedString("Srt sender mode", comment: "")
        }
        if let section = srtSection {
            section
                <<< PushRow<SrtRetransmitAlgoSelection>("retransmit_algo") {
                    $0.title = NSLocalizedString("Retransmission algorithm", comment: "")
                    $0.options = SrtRetransmitAlgoSelection.allValues
                    $0.value = SrtRetransmitAlgoSelection.init(intValue: outgoing.retransmitAlgo)
                }.onPresent { (_, vc) in vc.enableDeselection = false }
                <<< IntRow("maxbw") {
                    $0.title = NSLocalizedString("maxbw (bytes/sec)", comment: "")
                    $0.value = outgoing.maxbw == 0 ? nil : Int(outgoing.maxbw)
                }
                <<< TextAreaRow("maxbw_hint") {
                    $0.value = NSLocalizedString(maxBwHint, comment: "")
                    $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
                }.cellSetup(setupTextArea)
        }
        return srtSection
    }

    override func addRistSection(uri connUri: ConnectionUri?) -> Section? {
        guard let outgoing = connection as? Connection else {
            return nil
        }
        if !newRecord && connUri?.isRist == false {
            return nil
        }
        let ristSection = Section()
        ristSection.hidden = Condition.function(["url"], {
            guard let url = ($0.rowBy(tag: "url") as? URLRow)?.value else {return true}
            return url.scheme != "rist"
        })
        ristSection <<< PushRow<RistProfileSelection>() {
                $0.title = NSLocalizedString("Profile", comment: "")
                $0.tag = "rist_profile"
                $0.options = RistProfileSelection.allValues
                $0.value = RistProfileSelection(fromInt: outgoing.rist_profile)
            }.onPresent({ (_, vc) in vc.enableDeselection = false })
        <<< TextAreaRow("rist_profile_hint") {
            $0.value = NSLocalizedString(ristProfileHint, comment: "")
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
        }.cellSetup(setupTextArea)

        return ristSection
    }

    override func saveSrtParams(_ connection: BaseConnection, uri connUri: ConnectionUri) -> String? {
        if let outgoing = connection as? Connection {
            outgoing.auth = ConnectionAuthMode.default.rawValue
            outgoing.username = nil
            outgoing.password = nil

            if let maxbw = form.rowBy(tag: "maxbw")?.baseValue as? Int {
                outgoing.maxbw = Int32(maxbw)
            } else {
                outgoing.maxbw = 0
            }
            
            if let algo = form.rowBy(tag: "retransmit_algo")?.baseValue as? SrtRetransmitAlgoSelection {
                outgoing.retransmitAlgo = algo.intValue
            } else {
                outgoing.retransmitAlgo = 0
            }
        }
        return super.saveSrtParams(connection, uri: connUri)
    }
    
}
