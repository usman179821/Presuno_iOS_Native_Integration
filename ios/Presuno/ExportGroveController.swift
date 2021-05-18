import Foundation
import GRDB
import UIKit
import SwiftMessages

class ExportGroveController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    
    @IBOutlet weak var linkTextView: UITextView!
    @IBOutlet weak var qrImageView: UIImageView!
    @IBOutlet weak var itemsTableView: UITableView!
    
    var connections: [Connection] = []
    var selectedParams: Set<Int> = []
    var selectedConnections: Set<Int> = []
    #if TALKBACK
    var talkback: [IncomingConnection] = []
    var selectedTalkback: Set<Int> = []
    #endif
    var enableSelection: Bool = true
    let paramsSection = ["Video", "Audio", "Record"]
    let sectionTitles = ["Parameters", "Connections", "Talkback"]
    let sectionParamsIndex = 0
    let sectionConnectionsIndex = 1
    let sectionTalkbackIndex = 2
    let videoParamIndex = 0
    let audioParmIndex = 1
    let recordParmIndex = 2
    
    @IBAction func onCopyClick(_ sender: Any) {
        if let text = linkTextView.text, let url = URL(string: text) {
            let pb = UIPasteboard.general
            pb.url = url
            let message = NSLocalizedString("Link copied", comment: "")
            Toast(text: message, theme: .success, layout: .statusLine)
        }
    }

    @IBAction func onShareClick(_ sender: Any) {
        let description = NSLocalizedString("Presuno Grove link", comment: "")
        let url: NSURL = NSURL(string: linkTextView.text)!
        
        let shareController = UIActivityViewController(activityItems: [description, url], applicationActivities: nil)
        
        // This lines is for the popover you need to show in iPad
        shareController.popoverPresentationController?.sourceView = (sender as! UIButton)
        
        if #available(iOS 13.0, *) {
            // Pre-configuring activity items
            shareController.activityItemsConfiguration = [
                UIActivity.ActivityType.message,
                UIActivity.ActivityType.mail
            ] as? UIActivityItemsConfigurationReading
            
            shareController.isModalInPresentation = true
        }
        self.present(shareController, animated: true, completion: nil)
    }
    
    override func loadView() {
        super.loadView()
        if enableSelection {
            itemsTableView.dataSource = self
            itemsTableView.delegate = self
        } else {
            itemsTableView.isHidden = true
        }
    }
    
    override func viewDidLoad() {
        linkTextView.textContainer.maximumNumberOfLines = 1
        linkTextView.textContainer.lineBreakMode = .byClipping
        if enableSelection {
            let connectionsOpt = try? dbQueue.read { db in
                try? Connection.order(Column("name").asc).fetchAll(db)
            }
            connections = connectionsOpt ?? []
            selectedConnections.removeAll()
            for i in 0..<connections.count {
                if connections[i].active {
                    selectedConnections.insert(i)
                }
            }
            #if TALKBACK
            let talkbackOpt = try? dbQueue.read { db in
                try? IncomingConnection.order(Column("name").asc).fetchAll(db)
            }
            talkback = talkbackOpt ?? []
            selectedTalkback.removeAll()
            for i in 0..<talkback.count {
                if talkback[i].active {
                    selectedTalkback.insert(i)
                }
            }
            #endif
        }
        updateQr()
    }
    
    func updateQr() {
        let linkStr = generateLink()
        linkTextView.text = linkStr
        let data = linkStr.data(using: String.Encoding.utf8)

        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 2, y: 2)

            if let output = filter.outputImage?.transformed(by: transform) {
                qrImageView.image = UIImage(ciImage: output)
            }
        }
    }
    
    func generateLink() -> String {
        
        guard var urlData = URLComponents(string: "larix://set/v1") else { return "" }
        var parsms: [URLQueryItem] = []
        if selectedParams.contains(videoParamIndex) {
            parsms += Settings.sharedInstance.groveVideoConfig()
        }
        if selectedParams.contains(audioParmIndex) {
            parsms += Settings.sharedInstance.groveAudioConfig()
        }
        if selectedParams.contains(recordParmIndex) {
            parsms += Settings.sharedInstance.groveRecordConfig()
        }
        for i in selectedConnections {
            let conn = connections[i]
            parsms += conn.toGrove()
        }
        #if TALKBACK
        for i in selectedTalkback {
            let tb = talkback[i]
            parsms += tb.toGrove()
        }
        #endif
        urlData.queryItems = parsms
        return urlData.string ?? ""
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        #if TALKBACK
            return 3
        #else
            return 2
        #endif
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case sectionParamsIndex:
            return paramsSection.count
        case sectionConnectionsIndex:
            return connections.count
        case sectionTalkbackIndex:
            #if TALKBACK
            return talkback.count
            #else
            fallthrough
            #endif
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var title = ""
        if section < sectionTitles.count {
            title = sectionTitles[section]
        }
        return NSLocalizedString(title, comment: "")
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var title: String = ""
        var selected:Bool = true
        switch indexPath.section {
        case sectionParamsIndex:
            title = paramsSection[indexPath.row]
            selected = selectedParams.contains(indexPath.row)
        case sectionConnectionsIndex:
            let record = connections[indexPath.row]
            title = record.name
            selected = selectedConnections.contains(indexPath.row)
        case sectionTalkbackIndex:
            #if TALKBACK
            let record = talkback[indexPath.row]
            title = record.name
            selected = selectedTalkback.contains(indexPath.row)
            #endif
        default:
            title = "(Unknown)"
        }
        let cell = UITableViewCell(style: .default, reuseIdentifier: "row")
        cell.textLabel?.text = title
        cell.accessoryType = selected ? .checkmark : .none
        cell.setSelected(selected, animated: false)
        cell.selectionStyle = .none
        return cell

    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        itemsTableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        switch indexPath.section {
        case sectionParamsIndex:
            selectedParams.insert(indexPath.row)
        case sectionConnectionsIndex:
            selectedConnections.insert(indexPath.row)
        case sectionTalkbackIndex:
            #if TALKBACK
            selectedTalkback.insert(indexPath.row)
            #endif
        default:
            break
        }
        updateQr()
      }

      func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        itemsTableView.cellForRow(at: indexPath)?.accessoryType = .none
        switch indexPath.section {
        case sectionParamsIndex:
            selectedParams.remove(indexPath.row)
        case sectionConnectionsIndex:
            selectedConnections.remove(indexPath.row)
        case sectionTalkbackIndex:
            #if TALKBACK
            selectedTalkback.remove(indexPath.row)
            #endif
        default:
            break
        }
        updateQr()
      }

}
