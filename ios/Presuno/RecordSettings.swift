import Foundation
import Eureka

class RecordSettingsViewController: BundleSettingsViewController {

    let defaultRecordDuration = 30

    override func loadSettings() {
        
        super.loadSettings()
        if let section = form.allSections.first {
            
            section <<< TextAreaRow("split_hint") {
                $0.value = NSLocalizedString("Video recording is split into sections by default for reliability purposes. You may disable this if you need.", comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
                $0.hidden = Condition.function([SK.record_duration_key], { _ in
                    Settings.sharedInstance.recordDuration != self.defaultRecordDuration * 60
                })
            }.cellSetup { (cell, row) in
                row.textAreaMode = .readOnly
                cell.textView.font = .systemFont(ofSize: 14)
            }
            section <<< TextAreaRow("fg_hint") {
                $0.value = NSLocalizedString("Stream could be recorded only while application is in foreground due to iOS restrictions", comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
                $0.hidden = Condition.function([SK.record_stream_key], { _ in
                    !(Settings.sharedInstance.radioMode && Settings.sharedInstance.record)
                })
            }.cellSetup { (cell, row) in
                row.textAreaMode = .readOnly
                cell.textView.font = .systemFont(ofSize: 14)
            }
            section <<< TextAreaRow("photo_hint") {
                $0.value = NSLocalizedString("Audio files will be stored locally since Photos doesn't support audio", comment: "")
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 20.0)
                $0.hidden = Condition.function([SK.record_storage_key, SK.record_stream_key], { form in
                    if let storage = form.rowBy(tag: SK.record_storage_key) as? PushRow<SettingListElem>,
                       let storageVal = storage.value {
                        return !(Settings.sharedInstance.radioMode && Settings.sharedInstance.record &&
                                    storageVal.value == Settings.RecordStorage.photoLibrary.rawValue)
                    } else {
                        return false
                    }
                })
            }.cellSetup { (cell, row) in
                row.textAreaMode = .readOnly
                cell.textView.font = .systemFont(ofSize: 14)
            }
        }
    }
    
    override func getHideCondition(tag: String) -> Condition? {
        if tag == SK.record_duration_key {
            return Condition.function([SK.record_stream_key], { form in
                if let record = form.rowBy(tag: SK.record_stream_key) as? SwitchRow {
                    return record.value != true
                }
                return true
            })
        }
        return nil
    }
    
    override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
        super.valueHasBeenChanged(for: row, oldValue: oldValue, newValue: newValue)
        if row.tag == SK.record_stream_key {
            let defaultDurationStr = String(self.defaultRecordDuration)
            let enabled = newValue as? Bool ?? false
            if enabled {
                guard let durationRow = form.rowBy(tag: SK.record_duration_key) as? PushRow<SettingListElem> else {
                    return
                }
                if let elem = durationRow.options?.first(where: { $0.value == defaultDurationStr }) {
                    durationRow.value = elem
                }
                
            }
        }
    }

}
