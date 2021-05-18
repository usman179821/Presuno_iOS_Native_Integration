import Foundation
import Eureka
import GRDB
import CocoaLumberjackSwift


class ImageLayerListElem: CustomStringConvertible, Equatable, Hashable {
    let id: Int64
    let name: String

    init(id: Int64?, name: String) {
        self.id = id ?? 0
        self.name = name
    }

    static func == (lhs: ImageLayerListElem, rhs: ImageLayerListElem) -> Bool {
        return lhs.id == rhs.id
    }
    
    var description: String {
        return name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
}


class ImageLayersSetupController: FormViewController, CompositeImageLayerDelegate {

    var testLayer: CompositeImageLayer?
    var testMessage: String = ""
    var newRec: ImageLayerConfig?
    var editRec: ImageLayerConfig?
    let standbyHint = "Long tap Start/Stop button in stopped state to start streaming in Standby mode.\n"
    let pauseHint = "Long tap Start/Stop button in Recording state to activate pause."

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        var needUpdate = false
        if let rec = newRec, rec.id != nil, let section = form.sectionBy(tag: "layers") {
            section <<< layerRow(layer: rec)
            newRec = nil
            needUpdate = true
        }
        if let rec = editRec {
            let id = String(rec.id ?? 0)
            //Check is record still exist
            let recordOpt = try? dbQueue.read { db in
                try? ImageLayerConfig.fetchOne(db, key: id)
            }
            if checkOrderUpdate() {
                needUpdate = true
            } else  if let row = form.rowBy(tag: id) as? CheckRow {
                if recordOpt == nil, let section = form.sectionBy(tag: "layers") {
                    section.removeAll(where: {$0.tag == id} )
                } else {
                    row.title = rec.name
                    row.value = rec.active
                }
            }
            editRec = nil
            needUpdate = true
        }
        if needUpdate {
            updateOptions()
        }
        navigationController?.isToolbarHidden = false
    }
    
    func checkOrderUpdate() -> Bool {
        guard var section = form.sectionBy(tag: "layers"),
              let rec = editRec,
              let id = rec.id else {
            return false
        }
        let rows = section.allRows
        guard let rowIdx = rows.firstIndex(where: { $0.tag == String(id) }) else {
            return false
        }
        let row = rows[rowIdx]

        let layersOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.order(Column("z_index").asc).fetchAll(db)
        }
        let layers = layersOpt ?? []
        let layerIdx = layers.firstIndex(where: { $0.id == id })
        if layerIdx == nil || layerIdx == rowIdx {
            return false
        }
        section.remove(at: rowIdx)
        section.insert(row, at: layerIdx!)
        return true


    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !self.isMovingFromParent {
            return
        }
        navigationController?.isToolbarHidden = true
        form.removeAll()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
    }
    
    @IBAction func addButtonAction(_ sender: Any) {
        let editorView = ImageLayerEditController()
        newRec = ImageLayerConfig()
        editorView.layer = newRec
        self.navigationController?.pushViewController(editorView, animated: true)
    }
    
    internal func loadSettings() {
        let layersOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.order(Column("z_index").asc).fetchAll(db)
        }
        let layers = layersOpt ?? []
        
        var hintStr: String
        if Settings.sharedInstance.streamStartInStandby {
            hintStr = standbyHint.appending(pauseHint)
        } else {
            hintStr = pauseHint
        }
        
        
        let layersSel: [ImageLayerListElem] = layers.map { ImageLayerListElem(id: $0.id, name: $0.name) }
        var standbySel = Set<ImageLayerListElem>()
        var pauseSel = Set<ImageLayerListElem>()
        let stadnbyArr = Settings.sharedInstance.standbyLayers
        let pauseArr = Settings.sharedInstance.pauseLayers
        for layer in layersSel {
            if stadnbyArr.contains(layer.id) {
                standbySel.insert(layer)
            }
            if pauseArr.contains(layer.id) {
                pauseSel.insert(layer)
            }
        }

        let section = Section()
        section <<< SwitchRow() { row in
            row.title = NSLocalizedString("Show layers on preview", comment: "")
            row.value = Settings.sharedInstance.showLayersPreview
        }.onChange{ (row) in
            let val = row.value ?? true
            Settings.sharedInstance.showLayersPreview = val
        }
        section <<< SwitchRow("standby") { row in
            row.title = NSLocalizedString("Enable standby mode", comment: "")
            row.value = Settings.sharedInstance.streamStartInStandby
        }.onChange{ (row) in
            let val = row.value ?? false
            Settings.sharedInstance.streamStartInStandby = val
            if let hintRow = self.form.rowBy(tag: "standby_hint") as? TextAreaRow {
                let hint: String
                if val {
                    hint = self.standbyHint.appending(self.pauseHint)
                } else {
                    hint = self.pauseHint
                }
                hintRow.value = hint
                hintRow.updateCell()
            }
        }

        section <<< MultipleSelectorRow<ImageLayerListElem>("standby_layers") {
            $0.title = NSLocalizedString("Standby Overlays", comment: "")
            $0.options = layersSel
            $0.value = standbySel
            $0.hidden = Condition.function(["standby"], { form in
                if let standby = form.rowBy(tag: "standby") as? SwitchRow {
                    return standby.value != true
                }
                return true
            })
        }
        .onChange{ (row) in
            if let val = row.value {
                let idList: [Int64] = val.map { $0.id }
                Settings.sharedInstance.standbyLayers = idList
            }
        }
        .onPresent { from, to in
            to.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: from, action: #selector(ImageLayersSetupController.multipleSelectorDone(_:)))
        }
        section <<< MultipleSelectorRow<ImageLayerListElem>("pause_layers") {
            $0.title = NSLocalizedString("Pause Overlays", comment: "")
            $0.options = layersSel
            $0.value = pauseSel
        }
        .onChange{ (row) in
            if let val = row.value {
                let idList: [Int64] = val.map { $0.id }
                Settings.sharedInstance.pauseLayers = idList
            }
        }
        .onPresent { from, to in
            to.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: from, action: #selector(ImageLayersSetupController.multipleSelectorDone(_:)))
        }
        <<< TextAreaRow("standby_hint") {
            $0.value = hintStr
            $0.textAreaHeight = .dynamic(initialTextViewHeight: 20)
        }.cellSetup { (cell, row) in
            row.textAreaMode = .readOnly
            cell.textView.font = .systemFont(ofSize: 14)
        }
        
        form +++ section
        
        let list = Section(NSLocalizedString("Layers", comment: "")) {
            $0.tag = "layers"
        }
        for layer in layers {
            list <<< layerRow(layer: layer)
        }
        form +++ list
        
        let testSection = Section {
            $0.tag = "test"
        }
        testSection <<< ButtonRow() {
            $0.title = NSLocalizedString("Check layers' images availability", comment: "")
            }.onCellSelection { (_, _) in
                self.testLoad()
            }
        .cellUpdate { cell, row in
            cell.textLabel?.textAlignment = .natural
        }
        testSection <<< ButtonRow() { row in
               row.title = NSLocalizedString("Preview", comment: "")
            row.presentationMode = .segueName(segueName: "showOverlayPreview", onDismiss: nil)
        }

        form +++ testSection

    }
    
    func updateOptions() {
        let layersOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.order(Column("z_index").asc).fetchAll(db)
        }
        let layers = layersOpt ?? []
        
        let layersSel: [ImageLayerListElem] = layers.map { ImageLayerListElem(id: $0.id, name: $0.name) }
        var standbySel = Set<ImageLayerListElem>()
        var pauseSel = Set<ImageLayerListElem>()
        let stadnbyArr = Settings.sharedInstance.standbyLayers
        let pauseArr = Settings.sharedInstance.pauseLayers
        for layer in layersSel {
            if stadnbyArr.contains(layer.id) {
                standbySel.insert(layer)
            }
            if pauseArr.contains(layer.id) {
                pauseSel.insert(layer)
            }
        }
        let standbyRow = form.rowBy(tag: "standby_layers") as? MultipleSelectorRow<ImageLayerListElem>
        let pauseRow = form.rowBy(tag: "pause_layers") as? MultipleSelectorRow<ImageLayerListElem>
        standbyRow?.options = layersSel
        pauseRow?.options = layersSel
        standbyRow?.value = standbySel
        pauseRow?.value = pauseSel
    }
    
    func layerRow(layer: ImageLayerConfig) -> CheckRow {
        let deleteAction = SwipeAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: ""),
            handler: { (action, row, completionHandler) in
                let section = row.section
                if let i = row.indexPath?.row, let id = row.tag {
                    let recordOpt = try? dbQueue.read { db in
                        try? ImageLayerConfig.fetchOne(db, key: id)
                    }
                    guard let record = recordOpt else {
                        completionHandler?(false)
                        return
                    }
                    record.deleteLocalFile()
                    _ = try! dbQueue.write { db in
                        try! record.delete(db)

                        let message = String.localizedStringWithFormat(NSLocalizedString("Deleted: \"%@\"", comment: ""), record.name)
                        Toast(text: message, theme: .success, layout: .statusLine)
                    }
                    section?.remove(at: i)
                }
                completionHandler?(true)
        })
        let editAction = SwipeAction(
            style: .normal,
            title: NSLocalizedString("Edit", comment: ""),
            handler: { (action, row, completionHandler) in
                guard let id = Int64(row.tag ?? "") else {
                    completionHandler?(false)
                    return
                }
                let layerOpt = try? dbQueue.read { db in
                    try? ImageLayerConfig.fetchOne(db, key: id)
                }
                if let layer = layerOpt {
                    let editorView = ImageLayerEditController()
                    self.editRec = layer
                    editorView.layer = self.editRec
                    editorView.newRecord = false
                    self.navigationController?.pushViewController(editorView, animated: true)
                }
                completionHandler?(true)
        })
        
        return CheckRow() { row in
            row.title = layer.name
            row.value = layer.active
            row.tag = String(layer.id ?? 0)
            row.trailingSwipe.actions = [deleteAction, editAction]
            row.trailingSwipe.performsFirstActionWithFullSwipe = true
            row.onChange(toggleCheckbox)
        }
    }
    
    func toggleCheckbox(_ row: CheckRow) {
        guard let id = row.tag else {
            return
        }
        let layerOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.fetchOne(db, key: id)
        }
        guard let layer = layerOpt, let checked = row.value else {
            return
        }
        layer.active = checked
        do {
            try dbQueue.write({ db in
                try layer.save(db)
            })
        } catch {
            DDLogError("Failed to update record: \(error.localizedDescription)")
            let text = NSLocalizedString("Failed to update record", comment: "")
            Toast(text: text, theme: .error)
        }
    }
    
    func testLoad() {
        if testLayer != nil {
            testLayer?.invalidate()
            testLayer = nil
        }
        let imageLayer = CompositeImageLayer()
        imageLayer.delegate = self
        imageLayer.loadConfig()
        testLayer = imageLayer
    }
    
    
    func onImageLoadComplete() {
        DispatchQueue.main.async {
            if self.testMessage.isEmpty {
                let message = NSLocalizedString("No layers to test", comment: "")
                Toast(text: message, theme: .warning)
                self.testLayer?.invalidate()
                self.testLayer = nil
                return
            }
            let alert = UIAlertController(title: NSLocalizedString("Image loading result", comment: ""), message: self.testMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true) {
                self.testLayer?.invalidate()
                self.testLayer = nil
            }
        }
    }
    
    func onImageLoaded(name: String) {
        let text = String.localizedStringWithFormat(NSLocalizedString("%@: success\n", comment: ""), name)
        testMessage.append(text)
    }
    
    func onLoadError(name: String, error: String) {
        let text = String.localizedStringWithFormat(NSLocalizedString("%@: %@\n", comment: ""), name, error)
        testMessage.append(text)

    }

    @objc func multipleSelectorDone(_ item:UIBarButtonItem) {
        _ = navigationController?.popViewController(animated: true)
    }

}
