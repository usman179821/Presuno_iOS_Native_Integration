import Foundation

import Foundation
import Eureka
import AVFoundation

class DisplaySettingsViewController: BundleSettingsViewController {
    
    let marginMaxValue:Float = 20.0
    let eurekaStepperMax:Float = 10.0
    override func loadSettings() {
        super.loadSettings()
        //TODO: Configure settings
    }
    
    func addSafeMargin() {
        
    }

    
    override func addSelector(item: NSDictionary, section: Section) {
        if let pref = item.object(forKey: "Key") as? String, pref == SK.view_safe_margin_ratio {
            addMultiSelector(item: item, section: section)
            addSlider(section: section)

            return
        }
        super.addSelector(item: item, section: section)
    }
    
    internal func addMultiSelector(item: NSDictionary, section: Section) {
        guard let title = item.object(forKey: "Title") as? String,
              let pref = item.object(forKey: "Key") as? String,
              let titles = item.object(forKey: "Titles") as? [String],
              let values = item.object(forKey: "Values") as? [String] else { return }
        
        let value = UserDefaults.standard.string(forKey: pref) ?? SK.default_safe_margn_ratio
        let valArr = value.split(separator: ",")
        var sel = Set<SettingListElem>()
        var options = Array<SettingListElem>()
        var defaultSel = Set<SettingListElem>()
        let n = min(titles.count, values.count)
        for i in 0..<n {
            let el = SettingListElem(title: titles[i], value: values[i])
            options.append(el)
            if valArr.contains(where: { String($0) == el.value }) {
                sel.insert(el)
            }
            if el.value == "16:9" {
                defaultSel.insert(el)
            }
        }
        let item = MultipleSelectorRow<SettingListElem>(pref) {
            $0.title = NSLocalizedString(title, comment: "")
            $0.selectorTitle = NSLocalizedString(title, comment:"")
            $0.options = options
            $0.value = sel
            $0.hidden = Condition.function([SK.view_display_safe_margin], { form in
                if let showMargin = form.rowBy(tag: SK.view_display_safe_margin) as? SwitchRow {
                    return showMargin.value != true
                }
                return true
            })
            $0.onChange { (row) in
                if row.value?.isEmpty != false {
                    row.value = defaultSel
                }
            }
        }
        
        section <<< item
    }
    
    internal func addSlider(section: Section) {
        
        let val = UserDefaults.standard.string(forKey: SK.view_safe_margin_percent) ?? ""
        let valF = Float(val) ?? SK.default_safe_margin_percent
        let relVal = valF * eurekaStepperMax / marginMaxValue
        section <<< SliderRow(SK.view_safe_margin_percent) {
            $0.title = NSLocalizedString("Safe margin indent", comment: "")
            $0.steps = UInt(marginMaxValue * 2.0)
            $0.value = relVal
            $0.displayValueFor =  { val in
                let absVal = (val ?? 0) * self.marginMaxValue / self.eurekaStepperMax
                let valF = NSNumber(value: absVal)
                let fmt = NumberFormatter()
                fmt.minimumFractionDigits = 1
                fmt.maximumFractionDigits = 1
                fmt.numberStyle = .decimal
                fmt.positiveSuffix = "%"
                let s = fmt.string(from: valF)
                return s
            }
            $0.hidden = Condition.function([SK.view_display_safe_margin], { form in
                if let showMargin = form.rowBy(tag: SK.view_display_safe_margin) as? SwitchRow {
                    return showMargin.value != true
                }
                return true
            })
        }
    }
    
    override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
        guard let tag = row.tag else { return }
        if row.tag == SK.view_safe_margin_percent {
            if let val = newValue as? Float {
                let absVal = val / eurekaStepperMax * marginMaxValue
                let s = String(format: "%2.1f", absVal)
                UserDefaults.standard.setValue(s, forKey: tag)
                return
            }
        }
        super.valueHasBeenChanged(for: row, oldValue: oldValue, newValue: newValue)
    }
}
