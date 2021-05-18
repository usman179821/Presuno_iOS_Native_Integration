import UIKit

class ImportGroveController: UIViewController {

    @IBOutlet weak var inputGroveUrl: UITextField!
    
    @IBAction func onCancel(_ sender: Any) {
        dismiss(animated: true)
    }
    
    @IBAction func onOK(_ sender: Any) {
        var imported = false
        if let urlStr = inputGroveUrl.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let url = URL(string: urlStr)
            imported = importGrove(url)
        }
        if !imported {
            showGroveImportFailed()
            dismiss(animated: true)
        }
    }
    
    @IBAction func onAboutClick(_ sender: Any) {
        if let url = URL(string: "https://softvelum.com/larix/grove/") {
            UIApplication.shared.open(url, options: [:])
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        var frame = view.frame
        frame.size.height = 180
        frame.origin.y = view.center.y - 180.0 * 2/3
        view.frame = frame
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        let pasteboard = UIPasteboard.general
        if pasteboard.hasStrings {
            if let string = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string:string) {
                if DeepLink.sharedInstance.isDeepLinkUrl(url) {
                    inputGroveUrl.text = string
                }
            }
        } else if pasteboard.hasURLs, let url = pasteboard.url {
            if DeepLink.sharedInstance.isDeepLinkUrl(url) {
                inputGroveUrl.text = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
    }
    
    private func importGrove(_ uri: URL?) ->Bool {
        if (!DeepLink.sharedInstance.isDeepLinkUrl(uri)) {
            return false
        }
        let deepLink = DeepLink.sharedInstance
        deepLink.clear()
        deepLink.parseDeepLink(request: uri!)
        if !deepLink.hasParsedData() {
            //Nothing to import
            return false
        }
        let message = deepLink.getImportConfirmationBody()

        let alert = UIAlertController(title: NSLocalizedString("Import settings", comment: ""), message: "Import", preferredStyle: .alert)
        alert.setValue(message, forKey: "attributedMessage")
        
        let actionYes = UIAlertAction(title: "Yes", style: .default, handler: { (_) in
            DeepLink.sharedInstance.importSettings()
            self.showGroveImportSuccess()
        })
        alert.addAction(actionYes)
        let actionNo = UIAlertAction(title: "No", style: .cancel, handler: { (_) in
            DeepLink.sharedInstance.clear()
            self.dismiss(animated: true)

        })
        alert.addAction(actionNo)
        present(alert, animated: true, completion: nil)
        return true
    }
    
    private func showGroveImportFailed() {
        showGroveImportResult(NSLocalizedString("Import failed, please check link format", comment: ""))
    }
    
    private func showGroveImportSuccess() {
        let count = DeepLink.sharedInstance.getImportConnectionCount()
        var importStatus = DeepLink.sharedInstance.getImportResultBody()
        if  importStatus.isEmpty {
            importStatus = NSLocalizedString("Import failed, please check link format", comment: "")
        }
        showGroveImportResult(importStatus, connCount: count)
        DeepLink.sharedInstance.clear()
    }
    
    private func showGroveImportResult(_ message: String, connCount: Int = 0) {
        let alert = UIAlertController(title: NSLocalizedString("Import settings", comment: ""), message: message, preferredStyle: .alert)
        let actionOk = UIAlertAction(title: "OK", style: .default, handler: { (_) in
            self.dismiss(animated: true)
            if connCount > 0 {
                let appDelegate = UIApplication.shared.delegate as? AppDelegate
                if  appDelegate?.onConnectionsUpdate != nil {
                    appDelegate?.onConnectionsUpdate?()
                }
            }
        })
        alert.addAction(actionOk)
        present(alert, animated: true, completion: nil)
    }

}
