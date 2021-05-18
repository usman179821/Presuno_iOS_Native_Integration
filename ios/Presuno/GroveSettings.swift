import Foundation
import Eureka
import UIKit

class GroveSettingsController: FormViewController {
    
    let groveHint = "Grove format allows distributing streaming settings across mobile devices."
    override func viewDidLoad() {
        super.viewDidLoad()
        form.removeAll()
        
        form +++ Section()
            <<< TextAreaRow("grove_hint") {
                $0.value = NSLocalizedString(groveHint, comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
            }.cellSetup({ (cell, row) in
                row.textAreaMode = .readOnly
                if #available(iOS 13.0, *) {
                    cell.backgroundColor = UIColor.secondarySystemBackground
                }
            })

            <<< ButtonRow() {
                $0.title = NSLocalizedString("Import Grove setting", comment: "")
                $0.onCellSelection { (_, _) in
                    self.performSegue(withIdentifier: "openImportGrove", sender: self)
                }
            }
            <<< ButtonRow() {
                $0.title = NSLocalizedString("Export Grove settings", comment: "")
                $0.onCellSelection { (_, _) in
                    self.performSegue(withIdentifier: "openExportGrove", sender: self)
                }
            }

        form +++ Section()
            <<< ButtonRow() {
                $0.title = NSLocalizedString("Read Presuno Grove description ", comment: "")
                $0.onCellSelection { (_, _) in
                    if let url = URL(string: "https://softvelum.com/larix/grove/") {
                        UIApplication.shared.open(url, options: [:])
                    }
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
    }

}
