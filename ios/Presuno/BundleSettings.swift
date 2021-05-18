
import Foundation
import Eureka

class SettingListElem: CustomStringConvertible, Equatable, Hashable {
    let title: String
    let value: String

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    static func == (lhs: SettingListElem, rhs: SettingListElem) -> Bool {
        return lhs.value == rhs.value
    }
    
    var description: String {
        return title
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

class BundleSettingsViewController: FormViewController {
    var PLIST: String = ""
    let BUNDLE_PATH = "Settings.bundle/"
    
    init(bundle: String) {
        super.init(nibName: nil, bundle: nil)
        PLIST = BUNDLE_PATH.appending(bundle)
        title = bundle
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
    }
    
    
    internal func loadSettings() {
        guard let path = Bundle.main.path(forResource: PLIST, ofType: "plist"),
              let videoPlist = NSDictionary(contentsOfFile: path) else { return }
        
        var section: Section?

        guard let prefs = videoPlist.object(forKey: "PreferenceSpecifiers") as? NSArray else {return }
        for pref in prefs {
            guard let item = pref as? NSDictionary,
                  let itemType = item.object(forKey: "Type") as? String else {continue}
            
            switch itemType {
            case "PSGroupSpecifier":
                if section != nil {
                    form.append(section!)
                }
                section = addSection(item: item)
            case "PSMultiValueSpecifier":
                if section == nil {
                    section = Section()
                }
                addSelector(item: item, section: section!)
            case "PSToggleSwitchSpecifier":
                if section == nil {
                    section = Section()
                }
                addToggle(item: item, section: section!)
            case "PSTextFieldSpecifier":
                if section == nil {
                    section = Section()
                }
                addText(item: item, section: section!)

            default:
                break
            }
            
        }
        
        if section != nil {
            form.append(section!)
        }
    }
    
    internal func addSection(item: NSDictionary) -> Section {
        let title = item.object(forKey: "Title") as? String ?? ""
        return Section(title)
    }

    internal func addSelector(item: NSDictionary, section: Section) {
        guard let title = item.object(forKey: "Title") as? String,
              let pref = item.object(forKey: "Key") as? String,
              let titles = item.object(forKey: "Titles") as? [String],
              let values = item.object(forKey: "Values") as? [String] else { return }
        
        let defVal = item.object(forKey: "DefaultValue") as? String ?? values[0]
        let value = UserDefaults.standard.string(forKey: pref) ?? defVal
        
        var options = Array<SettingListElem>()
        let n = min(titles.count, values.count)
        for i in 0..<n {
            let el = SettingListElem(title: titles[i], value: values[i])
            options.append(el)
        }
        let filtered = filterValues(options, forParam: pref)
        if filtered.isEmpty { return }
        var sel = filtered.first(where: { $0.value == value })
        if sel == nil {
            sel = filtered.first
        }
        let item = PushRow<SettingListElem>(pref) {
            $0.title = NSLocalizedString(title, comment: "")
            $0.selectorTitle = NSLocalizedString(title, comment:"")
            $0.options = filtered
            $0.value = sel
            $0.hidden = getHideCondition(tag: pref)
        }.onPresent { (_, vc) in vc.enableDeselection = false }
        
        section <<< item
    }
    
    internal func addToggle(item: NSDictionary, section: Section) {
        guard let title = item.object(forKey: "Title") as? String,
              let pref = item.object(forKey: "Key") as? String else { return }
        
        let defVal = item.object(forKey: "DefaultValue") as? String ?? "0"
        var value = UserDefaults.standard.bool(forKey: pref)
        if UserDefaults.standard.string(forKey: pref) == nil {
            value = defVal != "0"
        }
        let item = SwitchRow(pref) {
            $0.title = NSLocalizedString(title, comment: "")
            $0.value = value
            $0.hidden = getHideCondition(tag: pref)
            $0.disabled = getDisableCondition(tag: pref)
        }
        
        section <<< item
    }
    
    internal func addText(item: NSDictionary, section: Section) {
        guard let title = item.object(forKey: "Title") as? String,
              let pref = item.object(forKey: "Key") as? String else { return }
        
        let defVal = item.object(forKey: "DefaultValue") as? String ?? ""
        let value = UserDefaults.standard.string(forKey: pref) ?? defVal
        let item = TextRow(pref) {
            $0.title = NSLocalizedString(title, comment: "")
            $0.value = value
            $0.hidden = getHideCondition(tag: pref)
            $0.disabled = getDisableCondition(tag: pref)
        }
        
        section <<< item
    }
    
    override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
        guard let tag = row.tag else { return }
        if let listSet = newValue as? Set<SettingListElem> {
            var selVal: String = listSet.reduce("") { (resStr, elem) -> String in
                resStr.appending(elem.value + ",")
            }
            if !selVal.isEmpty {
                selVal.removeLast()
            }
            UserDefaults.standard.setValue(selVal, forKey: tag)
        } else if let listElem = newValue as? SettingListElem {
            let value = listElem.value
            UserDefaults.standard.setValue(value, forKey: tag)
        } else if let intVal = newValue as? Int, intVal >= 100 {
            UserDefaults.standard.setValue(intVal, forKey: tag)
        } else if let toggle = newValue as? Bool {
            UserDefaults.standard.setValue(toggle, forKey: tag)
        }
    }
    
    func filterValues(_ list: [SettingListElem], forParam key: String) -> [SettingListElem] {
        return list
    }

    func getHideCondition(tag: String) -> Condition? {
        return nil
    }
    
    func getDisableCondition(tag: String) -> Condition? {
        return nil
    }
    
    
}
