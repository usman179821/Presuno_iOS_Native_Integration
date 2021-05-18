import Foundation
import UIKit
import Eureka
import GRDB
import CocoaLumberjackSwift

class QuickSettings: UIViewController, UITabBarControllerDelegate {
    
    var evValue: Float = 0.0
    var flashEnabled: Bool = false
    var flashOn: Bool = false
    var multiCamMode: Settings.MultiCamMode = .off
    var displayRatioMatch: Bool = false
    
    var zoom: CGFloat = 1.0
    var maxZoom: CGFloat = 1.0
    var initZoom: CGFloat = 1.0
    var overlays = Set<Int64>()
    
    var onFlashChange: ((Bool) -> Void)?
    var onEvChange: ((Float, AVCaptureDevice.Position) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    var onPreviewModeChange: ((String) -> Void)?
    var onGridModeChange: (() -> Void)?
    var onOverlaysChange: (() -> Void)?

    @IBOutlet weak var innerView: UIView!
    var tabView: UITabBarController?
    
    @IBAction func onSegmentChanged(_ sender: Any) {
        guard let segment = sender as? UISegmentedControl else {
            return
        }
        tabView?.selectedIndex = segment.selectedSegmentIndex
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
        let tabView = UITabBarController()
        tabView.view.frame = innerView.bounds
        innerView.addSubview(tabView.view)
        tabView.tabBar.isHidden = true
        
        self.tabView = tabView
        
        let camSettings = QuickSettingsCamera()
        camSettings.root = self
        let displaySettings = QuickSettingsDisplay()
        displaySettings.root = self
        let overlaySettings = QuickSettingsOverlays()
        overlaySettings.root = self
        
        tabView.viewControllers = [camSettings, displaySettings, overlaySettings]
        self.tabView = tabView
    }
}



class QuickSettingsCamera: FormViewController {
    var root: QuickSettings?
    
    private let evStep: Float = 1.0 / 3.0
    private let evMax: Float = 3.0
    private let stepperMax: Float = 10.0
    private let stepperMid:Float = 5.0

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
        loadSettings()
    }
    
    func loadSettings() {
        guard let root = root else {
            return
        }
        let camSection = Section()
        form +++ camSection
        if root.flashEnabled {
            camSection <<< SwitchRow("flash") {
                $0.title = NSLocalizedString("Torch", comment: "")
                $0.value = root.flashOn
            }.onChange({ (row) in
                if let val = row.value {
                    root.flashOn = val
                    if let handler = root.onFlashChange {
                        handler(val)
                    }
                }
            })
        }
        if root.multiCamMode == .off {
            camSection <<< addExposureComp(title: NSLocalizedString("Exposure comp.", comment: ""), tag: "")
        } else {
            camSection <<< addExposureComp(title: NSLocalizedString("Exp. comp.(front)", comment: ""), tag: "front")
            camSection <<< addExposureComp(title: NSLocalizedString("Exp. comp.(back)", comment: ""), tag: "back")
        }
        if root.maxZoom > 1.0 {
            let minZoom = 1.0 / root.initZoom
            let fullZoom = root.maxZoom / root.initZoom
            let step = Float((fullZoom - minZoom) / 10)
            camSection <<< SliderRow("zoom") {
                $0.title = NSLocalizedString("Zoom", comment: "")
                $0.value = Float(root.zoom / root.initZoom - minZoom) / step
                $0.steps = UInt(100*step)
                $0.displayValueFor =  { val in
                    let absVal = (val ?? 0.0) * step + Float(minZoom)
                    let valF = NSNumber(value: absVal)
                    let fmt = NumberFormatter()
                    fmt.minimumFractionDigits = 1
                    fmt.maximumFractionDigits = 1
                    fmt.numberStyle = .decimal
                    fmt.positiveSuffix = "x"
                    let s = fmt.string(from: valF)
                    return s
                    }
                }.onChange{ (row) in
                    let absVal = (row.value ?? 0.0) * step + Float(minZoom)
                    let val = CGFloat(absVal) * root.initZoom
                    if let handler = root.onZoomChange {
                        handler(val)
                    }
                }
        }

    }

    func addExposureComp(title: String, tag: String) -> SliderRow {
        SliderRow("ev:" + tag) {
            $0.title = title
            $0.value = ((root?.evValue ?? 0.0) + evMax) / (2 * evMax) * 10
            $0.steps = UInt(evMax * 2.0 / evStep + 0.1)
            $0.displayValueFor =  { val in
                let absVal = ((val ?? self.stepperMid) - self.stepperMid) / self.stepperMax * (2 * self.evMax)
                let valF = NSNumber(value: absVal)
                let fmt = NumberFormatter()
                fmt.minimumFractionDigits = 1
                fmt.maximumFractionDigits = 1
                fmt.numberStyle = .decimal
                fmt.positivePrefix = "+"
                fmt.positiveSuffix = "EV"
                fmt.negativeSuffix = "EV"
                let s = fmt.string(from: valF)
                return s
                }
            }.onChange{ (row) in
                let val = ((row.value ?? self.stepperMid) - self.stepperMid) / self.stepperMax * (2 * self.evMax)
                self.root?.evValue = val
                var pos = AVCaptureDevice.Position.unspecified
                if tag.hasSuffix("front") {
                    pos = .front
                } else if tag.hasSuffix("back") {
                    pos = .back
                }
                if let handler = self.root?.onEvChange {
                    handler(val, pos)
                }
            }
        .cellSetup { (cell, row) in
            let fontSize = UIFont.systemFontSize
            cell.titleLabel?.font = .systemFont(ofSize: fontSize)
        }
    }
}

class QuickSettingsDisplay: FormViewController {
    var root: QuickSettings?

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
        loadSettings()
    }
    
    func loadSettings() {
        guard let root = root else {
            return
        }
        let previewModes = [SettingListElem(title: "Fill", value: "fill"), SettingListElem(title: "Fit", value: "fit")]
        let activeMode = UserDefaults.standard.string(forKey: SK.view_mode_key) ?? "fill"
        let valIdx = activeMode == "fill" ? 0 : 1
        let displaySection = Section()
        if root.multiCamMode == .off && root.displayRatioMatch == false {
                displaySection <<< SegmentedRow<SettingListElem>(SK.view_mode_key) {
                    $0.title = NSLocalizedString("Preview", comment: "")
                    $0.options = previewModes
                    $0.value = previewModes[valIdx]
                }.onChange { (row) in
                    if let val = row.value?.value {
                        UserDefaults.standard.setValue(val, forKey: SK.view_mode_key)
                        if let handler = root.onPreviewModeChange {
                            handler(val)
                        }
                    }
                }
        }
        if root.multiCamMode != .sideBySide {
            displaySection <<< SwitchRow(SK.view_display_3x3Grid_key) {
                $0.title = NSLocalizedString("Grid", comment: "")
                $0.value = UserDefaults.standard.bool(forKey: SK.view_display_3x3Grid_key)
                $0.onChange(self.onGridModeChange)
            }
            <<< SwitchRow(SK.view_display_safe_margin) {
                $0.title = NSLocalizedString("Safe margins", comment: "")
                $0.value = UserDefaults.standard.bool(forKey: SK.view_display_safe_margin)
                $0.onChange(self.onGridModeChange)
            }
        }
        displaySection <<< SwitchRow(SK.view_display_horizon_level) {
            $0.title = NSLocalizedString("Horizon level", comment: "")
            $0.value = UserDefaults.standard.bool(forKey: SK.view_display_horizon_level)
            $0.onChange(self.onGridModeChange)
            }
        form +++ displaySection
    }
    
    func onGridModeChange(_ row: SwitchRow) {
        if let val = row.value, let tag = row.tag {
            UserDefaults.standard.setValue(val, forKey: tag)
            if let handler = root?.onGridModeChange {
                handler()
            }
        }

    }

}

class QuickSettingsOverlays: FormViewController {
    
    var root: QuickSettings?

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
        loadSettings()
    }
    
    func loadSettings() {
        guard let root = root else {
            return
        }
        let active = root.overlays
        let layersOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.order(Column("z_index").asc).fetchAll(db)
        }
        let layers = layersOpt ?? []
        let section = Section()
        for layer in layers {
            let id = layer.id ?? 0
            section <<< SwitchRow() {
                $0.tag = String(id)
                $0.title = layer.name
                $0.value = active.contains(id)
                $0.onChange { (row) in
                    if let tag = row.tag, let id = Int64(tag) {
                        let checked = row.value ?? false
                        self.updateLayer(id: id, value: checked)
                    }
                }
            }
        }
        form +++ section
    }
    
    func updateLayer(id: Int64, value: Bool) {
        do {
            try dbQueue.write() { db in
                if let rec = try ImageLayerConfig.fetchOne(db, key: id) {
                    rec.active = value
                    try rec.update(db)
                }
            }
        } catch {
            DDLogError("Failed to update record: \(error.localizedDescription)")
        }
        if value {
            root?.overlays.insert(id)
        } else {
            root?.overlays.remove(id)
        }
        if let handler = root?.onOverlaysChange {
            handler()
        }

    }
}
