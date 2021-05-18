import Foundation
import Eureka
import AVFoundation

class AudioSettingsViewController: BundleSettingsViewController {

    override func loadSettings() {
        super.loadSettings()
        if let section = form.allSections.first {
            section <<< TextAreaRow() {
                $0.value = NSLocalizedString("Stream could be recorded only while application is in foreground due to iOS restrictions", comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
                $0.hidden = Condition.function([SK.radio_mode], { _ in
                    !(Settings.sharedInstance.radioMode && Settings.sharedInstance.record)
                })
            }.cellSetup { (cell, row) in
                row.textAreaMode = .readOnly
                cell.textView.font = .systemFont(ofSize: 14)
            }
        }
    }

}
