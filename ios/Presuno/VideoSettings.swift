import Foundation
import Eureka
import AVFoundation

class VideoSettingsViewController: BundleSettingsViewController {
    private var allResolutions: [SettingListElem] = []
    private var allFps: [SettingListElem] = []
    private var allBackCam: [SettingListElem] = []
    
    var multicamEnabled: Bool {
        if !isMulticamSupported() {
            return false
        }
        let val = UserDefaults.standard.string(forKey: SK.multi_cam_key) ?? "off"
        return val != "off"
    }
   
    override func addText(item: NSDictionary, section: Section) {
        guard let title = item.object(forKey: "Title") as? String,
              let pref = item.object(forKey: "Key") as? String else { return }

        if pref == SK.video_bitrate_key {
            var value = UserDefaults.standard.integer(forKey: pref)
            var autoBitrate = UserDefaults.standard.bool(forKey: SK.auto_birate_key)
            if value == 0 {
                autoBitrate = true
                value = Settings.sharedInstance.recommendedBitrate
            }
            section <<< SwitchRow(SK.auto_birate_key) {
                $0.title =  NSLocalizedString("Bitrate matches resolution", comment: "")
                $0.value = autoBitrate
                $0.onChange { (row) in
                    let matchVal = row.value
                    if let bitrateRow = self.form.rowBy(tag: SK.video_bitrate_key) as? IntRow, matchVal == true {
                        let birateVal = Settings.sharedInstance.recommendedBitrate
                            bitrateRow.value = birateVal
                            bitrateRow.reload()
                        }
                    }
            }

            let item = IntRow(pref) {
                $0.title = NSLocalizedString(title, comment: "")
                $0.value = value
                $0.add(rule: RuleGreaterOrEqualThan(min: 100))
                $0.add(rule: RuleSmallerThan(max: 100000))
                $0.disabled = getDisableCondition(tag: pref)
                $0.validationOptions = .validatesOnChange
            }.cellUpdate { cell, row in
                if !row.isValid {
                    cell.titleLabel?.textColor = .systemRed
                }
            }
            
            section <<< item
            return
        }
        super.addText(item: item, section: section)
    }
    
    override func getHideCondition(tag: String) -> Condition? {
        if tag == SK.live_rotation_key {
            return Condition.function([SK.core_image_key], { form in
                if let rotation = form.rowBy(tag: SK.core_image_key) as? SwitchRow {
                    return rotation.value != true
                }
                return true
            })
        }
        if tag == SK.avc_profile_key {
            return Condition.function([SK.video_codec_type_key], { form in
                if let codec = form.rowBy(tag: SK.video_codec_type_key) as? PushRow<SettingListElem> {
                    return (codec.value?.value ?? "") != "h264"
                }
                return true
            })
        }
        if tag == SK.hevc_profile_key {
            return Condition.function([SK.video_codec_type_key], { form in
                if let codec = form.rowBy(tag: SK.video_codec_type_key) as? PushRow<SettingListElem> {
                    return (codec.value?.value ?? "") != "hevc"
                }
                return true
            })
        }
        if tag == SK.adaptive_fps_key {
            return Condition.function([SK.abr_mode_key], { form in
                if let mode = form.rowBy(tag: SK.abr_mode_key) as? PushRow<SettingListElem> {
                    return (mode.value?.value ?? "0") == "0"
                }
                return true
            })
        }
        return nil
    }
    
    override func getDisableCondition(tag: String) -> Condition? {
        if tag == SK.core_image_key {
            return Condition.function([SK.video_resolution_key], { _ in !Settings.sharedInstance.canPostprocess } )
        }
        if tag == SK.video_bitrate_key {
            return Condition.function([SK.auto_birate_key ], { form in
                if let autoRow = form.rowBy(tag: SK.auto_birate_key) as? SwitchRow {
                    return autoRow.value ?? false
                }
                return false
                
            } )

        }
        return nil
    }

    
    override func filterValues(_ list: [SettingListElem], forParam key: String) -> [SettingListElem] {
        if key == SK.camera_type_key {
            allBackCam = list
            return getAvailableCameras(list)
        }
        if key == SK.multi_cam_key && !isMulticamSupported() {
            return []
        }
        if key == SK.video_resolution_key {
            allResolutions = list
            return getAvailableResolutions(list)
        }
        if key == SK.video_framerate_key{
            allFps = list
            return getAvailableFps(list)
        }
        return list
    }
    
    func getAvailableCameras(_ list: [SettingListElem]) -> [SettingListElem] {
        var result: [SettingListElem] = []
        var devices: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera]
        if #available(iOS 13.0, *) {
            devices.append(.builtInUltraWideCamera)
        }
        let discovery = AVCaptureDevice.DiscoverySession.init(deviceTypes: devices, mediaType: .video, position: .back)
        
        for cam in discovery.devices {
            let type = cam.deviceType.rawValue
            if let elem = list.first(where: { $0.value == type }) {
                result.append(elem)
            }
        }
        if result.count > 1 {
            let title = getDefaultBackCamera()
            let autoTitle = String.localizedStringWithFormat("Auto (%@)", title)

            let auto = SettingListElem(title: NSLocalizedString(autoTitle, comment: ""), value: "Auto")
            result.insert(auto, at: 0)
        } else {
            result.removeAll()
        }
        return result
    }
    
    func getAvailableResolutions(_ list: [SettingListElem]) -> [SettingListElem] {
        let supported = getResolutions()
        let res = list.filter { supported.contains($0.value) }
        return res
    }
    
    func getAvailableFps(_ list: [SettingListElem]) -> [SettingListElem] {
        let supported = getFps(list)
        let res = list.filter { supported.contains($0.value) }
        return res
    }
    
    func getResolutions() -> Set<String> {
        let multiCam = multicamEnabled
        let fps = Float64(UserDefaults.standard.string(forKey: "pref_fps") ?? "30") ?? 30.0

        var resolutions = Set<String>()
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {return [] }
        for format in cam.formats {
            if #available(iOS 13.0, *) {
                if multiCam && format.isMultiCamSupported == false { continue }
            }
            let hasFps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= fps && $0.minFrameRate <= fps }
            if !hasFps { continue }
            let camRes = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            resolutions.insert(String(camRes.height))
        }
        return resolutions
    }
    
    func getFps(_ list: [SettingListElem]) -> Set<String> {
        let multiCam = multicamEnabled
        let height = Int(UserDefaults.standard.string(forKey: SK.video_resolution_key) ?? "720") ?? 720

        var fpsList = Set<String>()
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {return [] }
        for format in cam.formats {
            if #available(iOS 13.0, *) {
                if multiCam && format.isMultiCamSupported == false { continue }
            }
            let camRes = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if camRes.height != height { continue }
            for elem in list {
                let fps = Float64(elem.value) ?? 0.0
                let hasFps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= fps && $0.minFrameRate <= fps }
                if hasFps {
                    fpsList.insert(elem.value)
                }
            }
            if fpsList.count == list.count {
                break //Already find all
            }
        }
        return fpsList
    }
        
    func isMulticamSupported() -> Bool {
        if #available(iOS 13.0, *) {
            return AVCaptureMultiCamSession.isMultiCamSupported 
        } else {
            return false
        }
    }
    
    func getDefaultBackCamera() -> String {
        var defaultType = AVCaptureDevice.DeviceType.builtInDualCamera
        var virtualCamera: AVCaptureDevice?
        var title = "Dual"
        if #available(iOS 13.0, *) {
            defaultType = AVCaptureDevice.DeviceType.builtInTripleCamera
            title = "Triple"
            virtualCamera = AVCaptureDevice.default(defaultType, for: .video, position: .back)
            if virtualCamera == nil || supportedCamera(virtualCamera!) == false {
                defaultType = AVCaptureDevice.DeviceType.builtInDualWideCamera
                title = "Dual"
            }
        }
        virtualCamera = AVCaptureDevice.default(defaultType, for: .video, position: .back)
        if virtualCamera == nil || supportedCamera(virtualCamera!) == false {
            defaultType = .builtInWideAngleCamera
            title = "Dual"
        }
        return title
    }
    
    func supportedCamera(_ camera: AVCaptureDevice) -> Bool {
        let multiCam = multicamEnabled
        let height = Int(UserDefaults.standard.string(forKey: SK.video_resolution_key) ?? "720") ?? 720
        let fps = Float64(UserDefaults.standard.string(forKey: SK.video_framerate_key) ?? "30") ?? 30.0
        if  multiCam && probeMultiCam(camera) == false { return false }
        for format in camera.formats {
            if #available(iOS 13.0, *) {
                if multiCam && format.isMultiCamSupported == false { continue }
            }
            if CMFormatDescriptionGetMediaType(format.formatDescription) != kCMMediaType_Video { continue }
            let camRes = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if camRes.height != height { continue }
            let hasFps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= fps && $0.minFrameRate <= fps }
            if hasFps {
                return true
            }
        }
        return false
    }
    
    
    func probeMultiCam(_ camera: AVCaptureDevice) -> Bool {
        guard #available(iOS 13.0, *) else { return false }

        let discovery = AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera, camera.deviceType], mediaType: .video, position: .unspecified)
        let multicam = discovery.supportedMultiCamDeviceSets
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return false
        }
        let supported = multicam.contains { (devices) -> Bool in
            devices.contains(frontCamera) && devices.contains(camera)
        }
        return supported
    }

    
    override func valueHasBeenChanged(for row: BaseRow, oldValue: Any?, newValue: Any?) {
        if row.tag == SK.video_bitrate_key {
            let intVal = newValue as? Int ?? 0
            if intVal < 100 || intVal > 100000 {
                return
            }
        }
        super.valueHasBeenChanged(for: row, oldValue: oldValue, newValue: newValue)
        if row.tag == SK.multi_cam_key || row.tag == SK.video_resolution_key {
            guard let fps = form.rowBy(tag: SK.video_framerate_key) as? PushRow<SettingListElem>, fps.value != nil else { return }
            updateValue(row: fps, all: allFps, available: getAvailableFps(allFps))
        }
        if row.tag == SK.multi_cam_key || row.tag == SK.video_framerate_key {
            guard let res = form.rowBy(tag: SK.video_resolution_key) as? PushRow<SettingListElem>, res.value != nil else { return }
            updateValue(row: res, all: allResolutions, available: getAvailableResolutions(allResolutions))
        }
        
        if row.tag == SK.multi_cam_key || row.tag == SK.video_framerate_key || row.tag == SK.video_resolution_key {
            if let cam = form.rowBy(tag: SK.camera_type_key) as? PushRow<SettingListElem>, cam.value != nil {
                let available = getAvailableCameras(allBackCam)
                updateValue(row: cam, all: allBackCam, available: available)
                if cam.value?.value == "Auto" && cam.value?.title != available[0].title {
                    //Updated description for Auto
                    cam.value = available[0]
                    cam.updateCell()
                }
            }
        }
        if row.tag == SK.video_resolution_key {
            if let liveRotation = form.rowBy(tag: SK.core_image_key) as? SwitchRow, liveRotation.value != nil {
                if !Settings.sharedInstance.postprocess {
                    liveRotation.value = false
                }
            }
        }
        if row.tag == SK.video_framerate_key || row.tag == SK.video_resolution_key || row.tag == SK.video_codec_type_key {
            let autoBitrate = form.rowBy(tag: SK.auto_birate_key) as? SwitchRow
            if autoBitrate?.value == true,
               let bitrateRow = form.rowBy(tag: SK.video_bitrate_key) as? IntRow {
                let birateVal = Settings.sharedInstance.recommendedBitrate
                bitrateRow.value = birateVal
                bitrateRow.updateCell()
            }
        }
        if row.tag == SK.camera_type_key {
            //Reset zoom on back camera lens change
            Settings.sharedInstance.backCameraZoom = 0
        }
    }
    
    func updateValue(row: PushRow<SettingListElem>, all: [SettingListElem], available: [SettingListElem]) {
        if !available.contains(row.value!) {
            guard var idx = all.firstIndex(of: row.value!) else {return}
            while idx < all.count && !available.contains(all[idx]) {
                idx += 1
            }
            if idx < all.count {
                row.value = all[idx]
            } else if !available.isEmpty {
                row.value = available.last
            }
            if let setting = row.value {
                UserDefaults.standard.setValue(setting.value, forKey: row.tag!)
            }
        }
        row.options = available
    }

}
