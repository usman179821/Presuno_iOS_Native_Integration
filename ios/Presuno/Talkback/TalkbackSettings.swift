import Foundation
import Eureka

class TalkbackEditorViewController: BaseConnEditorViewController {
    let talkbackHint = """
Talkback allows receiving connection to give audio feed output. \
We recommend to run SRT source in Push (Caller) mode to connect to this Larix instance, \
but other protocols (RTMP, SLDP, Icecast) are also acceptable.
"""
    
    let listnenerHintTb = "On sender side, specify your public IP address and the same port as you use in URL above."
    
    override var isOutgoing: Bool {
        return false
    }
    
    override func addMainSection(uri connUri: ConnectionUri?) -> Section {
        var section = super.addMainSection(uri: connUri)
        let hint = TextAreaRow("tb_hint") {
            $0.value = NSLocalizedString(talkbackHint, comment: "")
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
        }.cellSetup(setupTextArea)
        
        section.insert(hint, at: 0)
        
        if let url: URLRow = section.rowBy(tag: "url") {
            url.placeholder = "srt://192.168.1.1:9000"
        }
       
        return section
    }
    
    override func addSrtSection(uri connUri: ConnectionUri?) -> Section? {
        let section = super.addSrtSection(uri: connUri)
        if let lisenerHint = form.rowBy(tag: "listener_hint") as? TextAreaRow {
            lisenerHint.value = NSLocalizedString(listnenerHintTb, comment: "")
        }
        return section
    }
    
    override func addTalkbackSection(uri connUri: ConnectionUri?) -> Section? {
        guard let connIn = connection as? IncomingConnection else {
            return nil
        }
        let section = Section()
            <<< StepperRow("buffering") {
                $0.title = NSLocalizedString("Buffering (msec)", comment: "")
                $0.displayValueFor = { value in
                    return String(format:"%d", Int(value ?? 0))
                }
                $0.value = Double(connIn.buffering)
                $0.cell.stepper.stepValue = 100
                $0.cell.stepper.minimumValue = 100
                $0.cell.stepper.maximumValue = 3000
            }
        
        return section
    }
    
    override func getCount() -> Int {
        let count = try? dbQueue.read { db in
            try IncomingConnection.fetchCount(db)
        }
        return count ?? 0
    }
    
    override func validateForm() -> String? {
        let err = super.validateForm()
        if err == nil, let connIn = connection as? IncomingConnection {
            connIn.mode = ConnectionMode.audioOnly.rawValue
            if let buffering = form.rowBy(tag: "buffering")?.baseValue as? Double {
                connIn.buffering = Int32(buffering)
            } else {
                connIn.buffering = 500
            }
        }
        return err
    }
}

class TalkbackManagerViewController: BaseConnManagerViewController<IncomingConnection> {
    override func createEditor() -> FormViewController? {
        return TalkbackEditorViewController()
    }
    
}
