import Foundation
import GRDB
import UIKit
import Eureka
import CocoaLumberjackSwift
import SwiftMessages

class ImageLayerEditController: FormViewController {
    
    var layer: ImageLayerConfig?
    var discard: Bool = false
    var saved: Bool = false
    var newRecord: Bool = true
    let defaultPosLabel = ["Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right", "Custom"]
    let defaultPosValues: [CGPoint] = [CGPoint(x:0.0, y:0.0), CGPoint(x:1.0,y:0.0),
                                       CGPoint(x:0.5, y:0.5),
                                       CGPoint(x:0.0, y:1.0), CGPoint(x:1.0, y:1.0)]
    
    @objc func cancelAction(barButtonItem: UIBarButtonItem) {
        discard = true
        _ = self.navigationController?.popViewController(animated: true)
    }
    
    @objc func updateAction(barButtonItem: UIBarButtonItem) {
        if let section = form.sectionBy(tag: "layer") {
            let updated = section.contains(where: \.wasChanged)
            let name = layer?.name ?? ""
            if updated {
                if save() {
                    let titleFmt = newRecord ? "Added: \"%@\"" : "Updated: \"%@\""
                    Toast(text: String.localizedStringWithFormat(NSLocalizedString(titleFmt, comment: ""), name), theme: .info, layout: .statusLine)
                    _ = self.navigationController?.popViewController(animated: true)
                }
            } else if !newRecord {
                Toast(text: String.localizedStringWithFormat(NSLocalizedString("\"%@\" is not changed", comment: ""), name), theme: .warning, layout: .statusLine)
                _ = self.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    @objc func saveButtonPressed(_ sender: UIBarButtonItem) {
        if save() {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc func deleteButtonPressed(_ sender: UIBarButtonItem) {
        var name: String = ""
        if let nameVal = layer?.name {
            name = nameVal
        }
        let message = String.localizedStringWithFormat(NSLocalizedString("Delete \"%@\"?", comment: ""), name)
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let delete = UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { action in
            self.deleteRecord()
            _ = self.navigationController?.popViewController(animated: true)
        }
        alertController.addAction(delete)
        let cancel = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        alertController.addAction(cancel)
        present(alertController, animated: true, completion: nil)
    }
    
    func deleteRecord() {
        guard let layer = self.layer else {
            return
        }
        _ = try! dbQueue.write { db in
            try! layer.delete(db)
        }
        let message = String.localizedStringWithFormat(NSLocalizedString("Deleted: \"%@\"", comment: ""), layer.name)
        Toast(text: message, theme: .success, layout: .statusLine)
        self.layer = nil
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        newRecord = layer?.id == nil
        title = NSLocalizedString("Overlay", comment: "")
        
        if !newRecord {
            let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(self.deleteButtonPressed(_:)))
            navigationItem.rightBarButtonItem = deleteButton
        }
        
        let cancel = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: ""), style: .plain, target: self, action: #selector(cancelAction(barButtonItem:)))
        
        let updateTitle = newRecord ? "Add" : "Update"
        let update = UIBarButtonItem(title: NSLocalizedString(updateTitle, comment: ""), style: .plain, target: self, action: #selector(updateAction(barButtonItem:)))

        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        toolbarItems = [cancel, flexible, update]
        initForm()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SwiftMessages.hideAll()

        if !self.isMovingFromParent || discard || saved || newRecord {
            return
        }
        if !newRecord {
            save()
        }
        navigationController?.isToolbarHidden = true
    }

    func initForm() {
        guard let layer = layer else {
            return
        }
        if newRecord {
            layer.zIndex = min(getMaxZOrder(), Int32.max - 1) + 1
        }

        let posX = CGFloat(layer.displayPosX)
        let posY = CGFloat(layer.displayPosY)
        var posIdx = defaultPosValues.firstIndex(where: { point in
            abs(point.x - posX) < 0.01 && abs(point.y - posY) < 0.01
        })
        if posIdx == nil {
            posIdx = defaultPosLabel.count - 1
        }
        let originLocal = NSLocalizedString("Local file", comment: "")
        let originRemote = NSLocalizedString("Remote URL", comment: "")
        let pictureOrigins = [originLocal, originRemote]
        
        let section = Section()
        section.tag = "layer"
        section <<< TextRow("name") {
            $0.title = NSLocalizedString("Name", comment: "")
            $0.placeholder = NSLocalizedString("Layer #1", comment: "")
            $0.value = layer.name
        }
        <<< SegmentedRow<String>("origin") {
            $0.title = NSLocalizedString("Location", comment: "")
            $0.options = pictureOrigins
            $0.value = layer.url.isEmpty && !newRecord ? originLocal : originRemote
        }
        <<< URLRow("url") {
            $0.title = NSLocalizedString("URL", comment: "")
            $0.placeholder = "https://presuno.com/img/presuno_broadcaster_logo.png"
            $0.value = URL(string: layer.url)
            $0.add(rule: RuleURL(allowsEmpty: false, requiresProtocol: true))
            $0.hidden = Condition.predicate(NSPredicate(format:"$origin == '\(originLocal)'"))
            $0.onChange { (row) in
                if row.value != nil {
                    let fileRow = self.form.rowBy(tag: "file") as? ImageSelectorRow
                    fileRow?.value = nil
                }
            }
        }
        <<< ImageSelectorRow("file") {
            $0.title = "File name"
            $0.value = layer.localName
            $0.hidden = Condition.predicate(NSPredicate(format:"$origin == '\(originRemote)'"))
            $0.onChange { (row) in
                if row.value != nil {
                    let urlRow = self.form.rowBy(tag: "url") as? URLRow
                    urlRow?.value = nil
                }
            }
        }
        <<< TextAreaRow("url_hint") {
            $0.value = NSLocalizedString("Remote file will be downloaded only once before the first usage.", comment: "")
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
            $0.hidden = Condition.predicate(NSPredicate(format:"$origin == '\(originLocal)'"))
        }.cellSetup { (cell, row) in
            row.textAreaMode = .readOnly
            cell.textView.font = .systemFont(ofSize: 14)
        }
        <<< TextAreaRow("file_hint") {
            $0.value = NSLocalizedString("You may also import file into Presuno using Share.", comment: "")
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
            $0.hidden = Condition.predicate(NSPredicate(format:"$origin == '\(originRemote)'"))
        }.cellSetup { (cell, row) in
            row.textAreaMode = .readOnly
            cell.textView.font = .systemFont(ofSize: 14)
        }
        <<< SwitchRow("active") {
            $0.title = NSLocalizedString("Active", comment: "")
            $0.value = layer.active
        }
        <<< SliderRow("scale") {
            $0.title = NSLocalizedString("Scale", comment: "")
            $0.steps = 100
            $0.value = Float(layer.displaySize) * 10
            $0.displayValueFor =  { val in
                let absVal = (val ?? 0) * 10
                if absVal == 0 {
                    return NSLocalizedString("Off", comment: "")
                }
                let valF = NSNumber(value: absVal)
                let fmt = NumberFormatter()
                fmt.maximumFractionDigits = 0
                fmt.numberStyle = .decimal
                fmt.positiveSuffix = "%"
                let s = fmt.string(from: valF)
                return s
            }
        }
        <<< TextAreaRow("scale_hint") {
            $0.value = NSLocalizedString("Scale is relative to video resolition, on 100% it fills entire screen. When set to “Off”, original size is used.", comment: "")
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
        }.cellSetup { (cell, row) in
            row.textAreaMode = .readOnly
            cell.textView.font = .systemFont(ofSize: 14)
        }

        <<< PushRow<String>("pos") {
            $0.options = defaultPosLabel
            $0.title = NSLocalizedString("Position", comment: "")
            $0.value = posIdx != nil ? defaultPosLabel[posIdx!] : nil
        }.onChange({ (row) in
            let s = row.value ?? ""
            let idx = self.defaultPosLabel.firstIndex(of: s) ?? -1
            if idx >= 0 && idx < self.defaultPosValues.count {
                let point = self.defaultPosValues[idx]
                if let xRow = self.form.rowBy(tag: "posX") as? SliderRow,
                   let yRow = self.form.rowBy(tag: "posY") as? SliderRow {
                    xRow.value = Float(point.x * 10)
                    yRow.value = Float(point.y * 10)
                }
            }
        })
        
        <<< SliderRow("posX") {
            $0.title = NSLocalizedString("H position", comment: "")
            $0.steps = 100
            $0.value = Float(layer.displayPosX) * 10.0
            $0.hidden = Condition.function(["pos"]) { form in
                if let posRow = form.rowBy(tag: "pos") as? PushRow<String>,
                   let value = posRow.value {
                    return value != self.defaultPosLabel.last
                }
                return false
            }
            $0.displayValueFor =  { val in
                let absVal = (val ?? 0) * 10
                if round(absVal) == 0 {
                    return NSLocalizedString("Left", comment: "")
                }
                if round(absVal) == 50.0 {
                    return NSLocalizedString("Center", comment: "")
                }
                if round(absVal) == 100.0 {
                    return NSLocalizedString("Right", comment: "")
                }
                let fmt = NumberFormatter()
                fmt.maximumFractionDigits = 0
                fmt.positiveSuffix = "%"
                var valF: NSNumber = 0.0
                if absVal < 50.0 {
                    valF = NSNumber(value: 100.0 - absVal * 2)
                    fmt.positivePrefix = NSLocalizedString("Left ", comment: "")
                } else {
                    valF = NSNumber(value: absVal * 2 - 100.0)
                    fmt.positivePrefix = NSLocalizedString("Right ", comment: "")
                }
                let s = fmt.string(from: valF)
                return s
            }
        }
        .cellSetup(setupPosRow)

        <<< SliderRow("posY") {
            $0.title = NSLocalizedString("V position", comment: "")
            $0.steps = 100
            $0.value = Float(layer.displayPosY) * 10.0
            $0.hidden = Condition.function(["pos"]) { form in
                if let posRow = form.rowBy(tag: "pos") as? PushRow<String>,
                   let value = posRow.value {
                    return value != self.defaultPosLabel.last
                }
                return false
            }

            $0.displayValueFor =  { val in
                let absVal = (val ?? 0) * 10
                if round(absVal) == 0 {
                    return NSLocalizedString("Top", comment: "")
                }
                if round(absVal) == 50.0 {
                    return NSLocalizedString("Center", comment: "")
                }
                if round(absVal) == 100.0 {
                    return NSLocalizedString("Bottom", comment: "")
                }
                let fmt = NumberFormatter()
                fmt.maximumFractionDigits = 0
                fmt.positiveSuffix = "%"
                var valF: NSNumber = 0.0
                if absVal < 50.0 {
                    valF = NSNumber(value: 100.0 - absVal * 2)
                    fmt.positivePrefix = NSLocalizedString("Top ", comment: "")
                } else {
                    valF = NSNumber(value: absVal * 2 - 100.0)
                    fmt.positivePrefix = NSLocalizedString("Bottom ", comment: "")
                }
                let s = fmt.string(from: valF)
                return s
            }
        }
        .cellSetup(setupPosRow)
        
        <<< IntRow("zIndex") {
            $0.title = NSLocalizedString("Z Order", comment: "")
            $0.value = Int(layer.zIndex)
            $0.add(rule: RuleGreaterThan(min: -1000000))
            $0.add(rule: RuleSmallerThan(max: 1000000))
        }
        <<< TextAreaRow("zindex_hint") {
            $0.value = NSLocalizedString("Layers with greater Z Order will appear at front", comment: "")
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
        }.cellSetup { (cell, row) in
            row.textAreaMode = .readOnly
            cell.textView.font = .systemFont(ofSize: 14)
        }

        form +++ section
    }
    
    func setupPosRow(_ cell: SliderCell,  _: SliderRow) {
        guard let label = cell.valueLabel else {
            return
        }
        let maxString = NSString(stringLiteral: "Bottom 188%")
        let size = maxString.size(withAttributes: [NSAttributedString.Key.font: label.font!])
        let constraint =  NSLayoutConstraint(item: label, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: size.width)
        cell.contentView.addConstraint(constraint)
    }
    
    
    //customefunction for overlay layers   ..--custom layer
    func HideMainCamLayer() -> Bool {
            guard let layer = layer else {
                return false
            }
            let countOpt = try? dbQueue.read { db in
                try? ImageLayerConfig.fetchCount(db)
            }
        
            let count = countOpt ?? 0
            layer.name = "hideMainCamLayer"
            let url = form.rowBy(tag: "url")?.baseValue as? URL
            if newRecord || (url != nil && layer.url != url?.absoluteString) {
                layer.lastRequest = nil
                layer.deleteLocalFile()
            }
            let scheme = url?.scheme
            if url != nil && scheme != "https"  && scheme != "http" {
                let message = NSLocalizedString("Only HTTPS protocol supported", comment: "")
                Toast(text: message, theme: .error)
                return false

            }
            layer.url = url?.absoluteString ?? ""
            if layer.url.isEmpty {
                let localName = form.rowBy(tag: "file")?.baseValue as? String ?? ""
                if localName.isEmpty {
                    let message = NSLocalizedString("Please select file or specify URL", comment: "")
                    Toast(text: message, theme: .error)
                    return false
                }
                layer.localName = localName
            }
            
            if let zIndex = form.rowBy(tag: "zIndex")?.baseValue as? Int {
                layer.zIndex = Int32(max(min(zIndex, 999_999), -999_999))
            }
            layer.active = form.rowBy(tag: "active")?.baseValue as? Bool ?? false
            let scale = form.rowBy(tag: "scale")?.baseValue as? Float ?? 0.0
            layer.displaySize = Double(scale * 0.1)
            let posX = 0.1 * (form.rowBy(tag: "posX")?.baseValue as? Float ?? 5.0)
            let posY = 0.1 * (form.rowBy(tag: "posY")?.baseValue as? Float ?? 5.0)
            layer.displayPosX = Double(posX)
            layer.displayPosY = Double(posY)
            
            do {
                try dbQueue.write { db in
                    if newRecord {
                        try layer.insert(db)
                        layer.id = db.lastInsertedRowID
                    } else {
                        try layer.update(db)
                    }
                }
                saved = true
            } catch {
                let message = NSLocalizedString("Failed to save", comment: "")
                DDLogError("Save failed: \(error.localizedDescription)")
                Toast(text: message, theme: .error)
                return false
            }
            
            return true

        
    }
    
    @discardableResult
    func save() -> Bool {
        guard let layer = layer else {
            return false
        }
        let countOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.fetchCount(db)
        }
        let count = countOpt ?? 0
        var name = form.rowBy(tag: "name")?.baseValue as? String ?? ""
        if name.isEmpty {
            name = String(format: "Layer #%d", count + 1)
        }
        layer.name = name
        let url = form.rowBy(tag: "url")?.baseValue as? URL
        if newRecord || (url != nil && layer.url != url?.absoluteString) {
            layer.lastRequest = nil
            layer.deleteLocalFile()
        }
        let scheme = url?.scheme
        if url != nil && scheme != "https"  && scheme != "http" {
            let message = NSLocalizedString("Only HTTPS protocol supported", comment: "")
            Toast(text: message, theme: .error)
            return false

        }
        layer.url = url?.absoluteString ?? ""
        if layer.url.isEmpty {
            let localName = form.rowBy(tag: "file")?.baseValue as? String ?? ""
            if localName.isEmpty {
                let message = NSLocalizedString("Please select file or specify URL", comment: "")
                Toast(text: message, theme: .error)
                return false
            }
            layer.localName = localName
        }
        
        if let zIndex = form.rowBy(tag: "zIndex")?.baseValue as? Int {
            layer.zIndex = Int32(max(min(zIndex, 999_999), -999_999))
        }
        layer.active = form.rowBy(tag: "active")?.baseValue as? Bool ?? false
        let scale = form.rowBy(tag: "scale")?.baseValue as? Float ?? 0.0
        layer.displaySize = Double(scale * 0.1)
        let posX = 0.1 * (form.rowBy(tag: "posX")?.baseValue as? Float ?? 5.0)
        let posY = 0.1 * (form.rowBy(tag: "posY")?.baseValue as? Float ?? 5.0)
        layer.displayPosX = Double(posX)
        layer.displayPosY = Double(posY)
        
        do {
            try dbQueue.write { db in
                if newRecord {
                    try layer.insert(db)
                    layer.id = db.lastInsertedRowID
                } else {
                    try layer.update(db)
                }
            }
            saved = true
        } catch {
            let message = NSLocalizedString("Failed to save", comment: "")
            DDLogError("Save failed: \(error.localizedDescription)")
            Toast(text: message, theme: .error)
            return false
        }
        
        return true
    }
    
    func getMaxZOrder() -> Int32 {
        let row = try? dbQueue.read { db in
            try? ImageLayerConfig.order(Column("z_index").desc).fetchOne(db)
        }
        return row?.zIndex ?? 0
    }
}
