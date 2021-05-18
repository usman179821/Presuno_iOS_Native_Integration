import AVFoundation
import UIKit
import CocoaLumberjackSwift
import GRDB
import SwiftMessages
import Photos

protocol ApplicationStateObserver: AnyObject {
    func applicationDidBecomeActive()
    func applicationWillResignActive()
    
    func mediaServicesWereLost()
    func mediaServicesWereReset()
}


var askedForOrientation: Bool = false

extension UINavigationController {
    
    override open var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        get {
            /* This function for some reason never called when been debuuged, so we want to know
                is iOS care about fixed orientation */
            if visibleViewController is ExportGroveController {
                return .portrait
            }
            if visibleViewController is ViewController, !Settings.sharedInstance.postprocess {
                //DDLogVerbose("ViewController")
                askedForOrientation = true
                let mask = Settings.sharedInstance.portrait ?
                    UIInterfaceOrientationMask.portrait : UIInterfaceOrientationMask.landscapeRight
                return mask
            }
            return super.supportedInterfaceOrientations
        }
    }
    
    override open var shouldAutorotate : Bool {
        get {
            if visibleViewController is ViewController || visibleViewController is ExportGroveController {
                return true
            }
            return super.shouldAutorotate
        }
    }
}

extension UIViewController {
}


weak var activeToast: UIView?

// Fix for toast width in fixed vertical orientation
class MyToastController: WindowViewController {
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        activeToast = self.view
        let postprocess = Settings.sharedInstance.postprocess
        var frame = view.frame
        let screenSize = UIScreen.main.bounds
        if askedForOrientation && !postprocess {
            let horizontal = !Settings.sharedInstance.portrait
            let w: CGFloat
            if horizontal {
                w = max(screenSize.size.width, screenSize.size.height)
            } else {
                w = min(screenSize.size.width, screenSize.size.height)
            }
            var frame = view.frame
            frame.size.width = w
        } else {
            frame.size.width = screenSize.size.width
        }
        view.frame = frame
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        activeToast = nil
    }
}

func Toast(text: String, theme: Theme, layout: MessageView.Layout = .messageView, duration: TimeInterval? = nil) {
    var toastConfig = SwiftMessages.defaultConfig
    toastConfig.shouldAutorotate = Settings.sharedInstance.postprocess
    toastConfig.preferredStatusBarStyle = .lightContent
    if let duration = duration {
        toastConfig.duration = .seconds(seconds: duration)
    }
    if layout == .statusLine {
        toastConfig.windowViewController = { config in
            return MyToastController(config: config)
        }
    }
    
    SwiftMessages.show(config: toastConfig, viewProvider: {
        let view = MessageView.viewFromNib(layout: layout)
        view.configureTheme(theme)
        view.button?.isHidden = true
        view.titleLabel?.isHidden = true
        view.configureContent(body: text)
        
        return view
    })
}

class ViewController: UIViewController, ApplicationStateObserver, StreamerAppDelegate, CloudNotificationDelegate {
    
    static let instance = ViewController()
    
    @IBOutlet weak var Indicator: UIActivityIndicatorView!
    @IBOutlet weak var Broadcast_Button: UIButton!
    @IBOutlet weak var Settings_Button: UIButton!
    @IBOutlet weak var Flip_Button: UIButton!
    @IBOutlet weak var Mute_Button: UIButton!
    @IBOutlet weak var Shoot_Button: UIButton!
    @IBOutlet weak var QuickSettings_Button: UIButton!
    
    @IBOutlet weak var Time_Label: UILabel!
    @IBOutlet weak var Fps_Label: UILabel!
    @IBOutlet weak var Focus_Label: UILabel!
    
    @IBOutlet weak var Name_Label0: UILabel!
    @IBOutlet weak var Name_Label1: UILabel!
    @IBOutlet weak var Name_Label2: UILabel!
    
    @IBOutlet weak var Status_Label0: UILabel!
    @IBOutlet weak var Status_Label1: UILabel!
    @IBOutlet weak var Status_Label2: UILabel!
    
    @IBOutlet weak var Message_Label: UILabel!
    @IBOutlet weak var VUMeter: AudioLevelMeter!
    @IBOutlet weak var Talkback_Label: UILabel!
    @IBOutlet weak var setMediaBtn: UIButton!
    @IBOutlet weak var secondaryFeedBtn: UIButton!
    @IBOutlet weak var onAndOffMainBtn: UIButton!
    
    @IBOutlet weak var Rec_Indicator: UIImageView!
    
    var name = [UILabel]()
    var status = [UILabel]()
    var isSecondaryFeedHide = false
    
    var alertController: UIAlertController?
    
    var streamer: Streamer?
    
    var uiTimer: Timer?
    var retryTimer: Timer?
    var retryList = [Connection]()
    var restartRecording = false
    var recordDurationTImer: Timer?
    
    var previewLayer: AVCaptureVideoPreviewLayer?       //Preview for single-cam capture
    var frontPreviewLayer: AVCaptureVideoPreviewLayer?  //Preview from front camera for multi-cam capture
    var backPreviewLayer: AVCaptureVideoPreviewLayer?   //Preview from back camera for multi-cam capture

    var batteryIndicator: BatteryIndicator?
    var lineOverlay: GridLayer?
    var horizon: HorizonMeterLayer?
    var zoomIndicator: ZoomIndicator?
    var imageLayerPreview: ImagePreviewOverlay?

    var settingsView: QuickSettings?

    var canStartCapture = true
    var cloudUtils = CloudUtilites()
    
    class ConnectionStatistics {
        var isUdp: Bool = false
        var startTime: CFTimeInterval = CACurrentMediaTime()
        var prevTime: CFTimeInterval = CACurrentMediaTime()
        var duration: CFTimeInterval = 0
        var prevBytesSent: UInt64 = 0
        var prevBytesDelivered: UInt64 = 0
        var bps: Double = 0
        var latency: Double = 0
        var packetsLost: UInt64 = 0
    }
    
    var isBroadcasting = false
    var broadcastStartTime: CFTimeInterval = CACurrentMediaTime()
    
    var connectionId:[Int32:Connection] = [:] // id -> Connection
    var connectionState:[Int32:ConnectionState] = [:] // id -> ConnectionState
    var connectionStatistics:[Int32:ConnectionStatistics] = [:] // id -> ConnectionStaistics
    
    let tapRec = UITapGestureRecognizer()
    let longPressRec = UILongPressGestureRecognizer()
    let pinchRec = UIPinchGestureRecognizer()
    
    var zoomFactor: CGFloat = 1
    
    var streamConditioner: StreamConditioner?
    var haptics: NSObject?
    
    var isMulticam: Bool = false
    var volumeChangeTime: CFTimeInterval = 0
    var mediaResetPending = false
    var backgroundStream = false
    var lostMic = false
    #if TALKBACK
    var player: TalkbackHandler?
    #endif

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
  

    @IBAction func Broadcast_Click(_ sender: UIButton) {
        DDLogVerbose("Broadcast_Click")
        hideSettingsView()
        if lostMic {
            if isBroadcasting {
                stopBroadcast()
            }
            return
        }
        if streamer?.pauseMode == .pause {
            streamer?.pauseMode = .off
            broadcastWillResume()
        } else if streamer?.pauseMode == .standby {
            streamer?.pauseMode = .off
            if !isBroadcasting {
                imageLayerPreview?.setPause(false)
                startBroadcast()
            } else {
                broadcastWillResume()
            }
        } else if !isBroadcasting {
            streamer?.pauseMode = .off
            startBroadcast()
        } else {
            stopBroadcast()
        }
    }


    @IBAction func Broadcast_LongTap(_ sender: UIButton) {
        if !isBroadcasting {
            if Settings.sharedInstance.streamStartInStandby {
                hideSettingsView()
                startBroadcast()
                imageLayerPreview?.setPause(true)
                let message = NSLocalizedString("You are now in stand-by mode, tap on recording button to go live.", comment: "")
                showStatusMessage(message: message)
            }
            return
        }
        if streamer?.pauseMode != .off {
            broadcastWillResume()
            streamer?.pauseMode = .off
        } else {
            broadcastWillPause()
            streamer?.pauseMode = .pause
        }
    }
    
    @IBAction func Flip_Click(_ sender: UIButton)
        
        
        {
            
            if #available(iOS 13.0, *) {
                if !AVCaptureMultiCamSession.isMultiCamSupported{
                    DispatchQueue.main.async {
                        DDLogVerbose("Flip_Click")
                        self.hideSettingsView()
                        self.Focus_Label.isHidden = true
                        self.streamer?.changeCamera()
                        self.zoomIndicator?.removeFromSuperlayer()
                        self.adjustPipPosition()
                        
                    }
                    return
                } else {
                    if isSecondaryFeedHide {
                        DDLogVerbose("Flip_Click")
                        hideSettingsView()
                        Focus_Label.isHidden = true
                        streamer?.changeCamera()
                        zoomIndicator?.removeFromSuperlayer()
                        adjustPipPosition()
                        
                    }else {
                        sharedClass.sharedInstance.alert(view: self, title: "Presuno", message: "Please hide the secondary feed first for switch camera")
                        
                        
                    }
                }
            } else {
                // Fallback on earlier versions
            }
        }
        
        
    
    @IBAction func showSecondary_Click(_ sender: UIButton) {
        
        if #available(iOS 13.0, *) {
            if !AVCaptureMultiCamSession.isMultiCamSupported{
                DispatchQueue.main.async {
                    
                    sharedClass.sharedInstance.alert(view: self, title: "Presuno", message: "Secondary feed is not available in this device")
                   
                    
                }
                return
            } else {
                showSecondaryFeed()
                secondaryFeedBtn.flash()
                isSecondaryFeedHide = !isSecondaryFeedHide
            }
        } else {
            // Fallback on earlier versions
        }
        
    }
        //MARK:- Hide Secondary feed
    
    func showSecondaryFeed(){
        if isSecondaryFeedHide  {
            isSecondaryFeedHide = true
            //   SecondaryFeedShow()
            secondaryFeedHideNShow()
            secondaryFeedBtn.setTitle("Hide Secondary", for: .normal)
        }else {
            isSecondaryFeedHide = false
            secondaryFeedHideNShow()
            secondaryFeedBtn.setTitle("Show Secondary", for: .normal)
        }
        print("checking isSingleCamSelected: ",isSecondaryFeedHide)
    }
        
       
    
    
    @IBAction func hideMain(_ sender: Any) {
        
        if settingsView == nil {
            showSettingsView()
        } else {
            hideSettingsView()
        }
    }
    
    
    func SetMedia(){
//        if isMediaSelected {
//            videoSetUp()
//            mediaImage.isHidden = false
//            setMediaBtn.setTitle("Hide Media", for: .normal)
//            avPlayer.play()
//        }else {
//            avPlayer.play()
//            // videoSetUp()
//            mediaImage.isHidden = true
//            setMediaBtn.setTitle("Set Media", for: .normal)
//        }
    }
    
    @IBAction func Mute_Click(_ sender: UIButton) {
        DDLogVerbose("Mute_Click")
        isMuted = !isMuted
    }
    
    @IBAction func Shoot_Click(_ sender: UIButton) {
        DDLogVerbose("Shoot_Click")
        streamer?.captureStillImage()
    }
    
    @IBAction func QuickSettings_Click(_ sender: Any) {
        if settingsView == nil {
            showSettingsView()
        } else {
            hideSettingsView()
        }
    }
    
    // MARK: ViewController state transition
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        // Called after init(coder:) when the view is loaded into memory, this method is also called only once during the life of the view controller object. It’s a great place to do any view initialization or setup you didn’t do in the Storyboard. Perhaps you want to add subviews or auto layout constraints programmatically – if so, this is a great place to do either of those. Note that just because the view has been loaded into memory doesn’t necessarily mean that it’s going to be displayed soon – for that, you’ll want to look at viewWillAppear. Oh, and remember to call super.viewDidLoad() in your implementation to make sure your superclass’s viewDidLoad gets a chance to do its work – I usually call super right at the beginning of the implementation.
        DDLogVerbose("viewDidLoad")
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.mainView = self
        name = [Name_Label0, Name_Label1, Name_Label2]
        status = [Status_Label0, Status_Label1, Status_Label2]
        
        makeRoundButttons()
        
        tapRec.addTarget(self, action: #selector(tappedView))
        longPressRec.addTarget(self, action: #selector(longPressedView))
        pinchRec.addTarget(self, action: #selector(pinchHandler))
        
        view.addGestureRecognizer(tapRec)
        view.addGestureRecognizer(longPressRec)
        view.addGestureRecognizer(pinchRec)
        haptics = UIImpactFeedbackGenerator()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Always called after viewDidLoad (for obvious reasons, if you think about it), and just before the view appears on the screen to the user, viewWillAppear is called. This gives you a chance to do any last-minute view setup, kick off a network request (in another class, of course), or refresh the screen. Unlike viewDidLoad, viewWillAppear is called the first time the view is displayed as well as when the view is displayed again, so it can be called multiple times during the life of the view controller object. It’s called when the view is about to appear as a result of the user tapping the back button, closing a modal dialog, when the view controller’s tab is selected in a tab bar controller, or a variety of other reasons. Make sure to call super.viewWillAppear() at some point in the implementation – I generally do it first thing.
        DDLogVerbose("viewWillAppear")
        
        navigationController?.setNavigationBarHidden(true, animated: false)
        cloudUtils.delegate = self
        cloudUtils.activate()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // viewDidAppear is called when the view is actually visible, and can be called multiple times during the lifecycle of a View Controller (for instance, when a Modal View Controller is dismissed and the view becomes visible again). This is where you want to perform any layout actions or do any drawing in the UI - for example, presenting a modal view controller. However, anything you do here should be repeatable. It's best not to retain things here, or else you'll get memory leaks if you don't release them when the view disappears.
        DDLogVerbose("viewDidAppear")
        Self.attemptRotationToDeviceOrientation()

        Settings.sharedInstance.resetDefaultsIfRequested()
        // For custom app based on Presuno sdk remove DeepLink condition check
        if DeepLink.sharedInstance.hasParsedData() {
            // Present import settings dialog later and then start capture
            return
        }
        
        // Handle "Back" from Settings page or first app launch
        if deviceAuthorized {
            startCaptureWithDualCamWithSuportingDevice()
        } else {
            checkForAuthorizationStatus()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Similar to viewWillAppear, this method is called just before the view disappears from the screen. And like viewWillAppear, this method can be called multiple times during the life of the view controller object. It’s called when the user navigates away from the screen – perhaps dismissing the screen, selecting another tab, tapping a button that shows a modal view, or navigating further down the navigation hierarchy. This is a great place to hide the keyboard, save state, and possibly cancel running timers or network requests. Like the other methods in the view controller lifecycle, be sure to call super at some point in viewWillDisappear.
        DDLogVerbose("viewWillDisappear")
        SwiftMessages.hideAll()
        dismissAlertController()
        hideSettingsView()

        stopBroadcast()
        stopCapture()
        
        cloudUtils.deactivate()
        cloudUtils.delegate = nil
        
        navigationController?.setNavigationBarHidden(false, animated: false)
        askedForOrientation = false
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // viewDidDisappear is an optional method that your view can utilize to execute custom code when the view does indeed disappear. You aren't required to have this in your view, and your code should (almost?) never need to call it.
        DDLogVerbose("viewDidDisappear")
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
        DDLogVerbose("didReceiveMemoryWarning")
    }
    
    // MARK: Application state transition
    func applicationDidBecomeActive() {
        Settings.sharedInstance.resetDefaultsIfRequested()

        // For custom app based on Presuno sdk remove DeepLink condition check
        if DeepLink.sharedInstance.hasParsedData() {
            presentImportDialog()
            return
        }
        let audioOnly = Settings.sharedInstance.radioMode
        var needResume = true
        if backgroundStream {
            if !audioOnly {
                //Was turned off while in backround
                stopBroadcast()
                stopCapture()
            } else {
                endBackgroundCapture()
                startRecord()
                needResume = false
            }
            backgroundStream = false
        }
        if needResume {
            resumeCapture(shouldRequestPermissions: false)
        }
    }
    
    func resumeCapture(shouldRequestPermissions: Bool) {
        if viewIfLoaded?.window != nil {
            DDLogVerbose("didBecomeActive")
            // Handle view transition from background
            if deviceAuthorized {
                startCaptureWithDualCamWithSuportingDevice()
            } else {
                if shouldRequestPermissions {
                    checkForAuthorizationStatus()
                } else {
                    // permission request already in progress and app is returning from permission request dialog
                    // capture will start on permission granted
                    DDLogVerbose("skip resumeCapture")
                }
            }
        }
    }
    
    func applicationWillResignActive() {
        dismissAlertController()
        
        if viewIfLoaded?.window != nil {
            DDLogVerbose("willResignActive")
            
            if deviceAuthorized {
                let keepStreaming = Settings.sharedInstance.radioMode && !connectionId.isEmpty
                if keepStreaming {
                    setBackgroundCapture()
                    //iOS terminates app if it record stream in background
                    stopRecord()
                } else {
                    stopBroadcast()
                    removePreview()
                    stopCapture()
                }
                SwiftMessages.hideAll()
            }
        }
    }
    
    // MARK: Respond to the media server crashing and restarting
    // https://developer.apple.com/library/archive/qa/qa1749/_index.html
    
    func mediaServicesWereLost() {
        if viewIfLoaded?.window != nil, deviceAuthorized {
            DDLogVerbose("mediaServicesWereLost")
            mediaResetPending = streamer?.session != nil
            stopBroadcast()
            removePreview()
            stopCapture()
            
            Indicator.isHidden = false
            Indicator.startAnimating()
            
          ///  hideUI()
            Settings_Button.isHidden = false
            
            showStatusMessage(message: NSLocalizedString("Waiting for media services initialize.", comment: ""))
        }
    }
    
    func mediaServicesWereReset() {
        if viewIfLoaded?.window != nil, deviceAuthorized {
            DDLogVerbose("mediaServicesWereReset, pending:\(mediaResetPending)")
            if mediaResetPending {
                startCaptureWithDualCamWithSuportingDevice()
                mediaResetPending = false
            }
        }
    }
    
    // MARK: Start broadcasting
    func startBroadcast() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if !appDelegate.canConnect {
            let message = NSLocalizedString("No internet connection.", comment: "")
            Toast(text: message, theme: .error)
            return
        }
        let connectionsOpt = try? dbQueue.read { db in
            try? Connection.filter(sql: "active=?", arguments: ["1"]).order(Column("name")).fetchAll(db)
        }
        guard let connections = connectionsOpt, connections.count > 0 else {
            let message = NSLocalizedString("You have no active connections, please go to settings and setup connection.", comment: "")
            Toast(text: message, theme: .warning)
            return
        }
        broadcastWillStart()
        for connection in connections {
            createConnection(connection: connection)
        }
        showConnectionInfo()
        startRecord()
        
        streamConditioner?.start(bitrate: Settings.sharedInstance.videoBitrate, id: Array(connectionId.keys))
    }
    
    func stopBroadcast() {
        broadcastWillStop()
        
        let ids = Array(connectionId.keys)
        for id in ids {
            releaseConnection(id: id)
        }
        stopRecord()
        
        streamConditioner?.stop()
        if Settings.sharedInstance.streamStartInStandby {
            streamer?.pauseMode = .standby
        }
    }
    
    // MARK: Update UI on broadcast start
    func broadcastWillStart() {
        if !isBroadcasting {
            DDLogVerbose("start broadcasting")
            
            let deviceOrientation = UIApplication.shared.statusBarOrientation
            let newOrientation = toAVCaptureVideoOrientation(deviceOrientation: deviceOrientation, defaultOrientation: AVCaptureVideoOrientation.portrait)
            streamer?.orientation = newOrientation
            
            if let stereoOrientation = AVAudioSession.StereoOrientation(rawValue: newOrientation.rawValue) {
                streamer?.stereoOrientation = stereoOrientation
            }
            broadcastStartTime = CACurrentMediaTime()
            Time_Label.isHidden = false
            Time_Label.text = "00:00:00"
            if (streamer?.pauseMode == .standby) {
                Broadcast_Button.setImage(#imageLiteral(resourceName: "pause"), for: .normal)
            } else {
                Broadcast_Button.setImage(#imageLiteral(resourceName: "stopVideo"), for: .normal)
            }
         //   Settings_Button.isEnabled = false
            
            isBroadcasting = true
        }
    }
    
    func broadcastWillStop() {
        if isBroadcasting {
            DDLogVerbose("stop broadcasting")
            
            retryTimer?.invalidate()
            retryTimer = nil
            
            retryList.removeAll()
            
            Time_Label.isHidden = true
            Time_Label.text = "00:00:00"
            Broadcast_Button.setImage(#imageLiteral(resourceName: "playVideo"), for: .normal)
            Settings_Button.isEnabled = true
            hideConnectionInfo()
            
            isBroadcasting = false
            if streamer?.pauseMode != .off {
                //In a case we failed while been paused
                streamer?.pauseMode = .off
                broadcastWillResume()
            }
        }
    }
    
    func broadcastWillPause() {
        
        Broadcast_Button.setImage(#imageLiteral(resourceName: "pause"), for: .normal)
        let message = NSLocalizedString("You are now in pause mode, tap on recording button to go live.", comment: "")
        showStatusMessage(message: message)

        Flip_Button.isEnabled = false
        Mute_Button.isEnabled = false
        Shoot_Button.isEnabled = false
        previewLayer?.isHidden = true
        frontPreviewLayer?.isHidden = true
        backPreviewLayer?.isHidden = true
        imageLayerPreview?.setPause(true)
    }

    func broadcastWillResume() {
        if isBroadcasting {
            Broadcast_Button.setImage(#imageLiteral(resourceName: "stopVideo"), for: .normal)
        } else {
            Broadcast_Button.setImage(#imageLiteral(resourceName: "playVideo"), for: .normal)
        }
        hideStatusMessage()
        Flip_Button.isEnabled = true
        Mute_Button.isEnabled = true
        Shoot_Button.isEnabled = true
        previewLayer?.isHidden = false
        frontPreviewLayer?.isHidden = false
        backPreviewLayer?.isHidden = false
        imageLayerPreview?.isHidden = false
        imageLayerPreview?.setPause(false)

    }

    // MARK: Capture utitlies
    
    /* Note: method is called on a background thread after permission request. Move your UI update codes inside the main queue. */
    func startCaptureSingleCam() {
        DDLogVerbose("ViewController::startCapture")
        
        guard canStartCapture else {
            return
        }
        do {
            let settings = Settings.sharedInstance
            let audioOnly = settings.radioMode
            canStartCapture = false
            
            removePreview()
            
            DispatchQueue.main.async {
           //     self.hideUI()
                self.hideStatusMessage()
                self.Indicator.isHidden = false
                self.Indicator.startAnimating()
                
                UIApplication.shared.isIdleTimerDisabled = true
            }
            if #available(iOS 13.0, *) {
                if !audioOnly && StreamerMultiCam.isSupported() {
                    streamer = StreamerMultiCam()
                    isMulticam = streamer != nil
                }
            }
            if streamer == nil {
                streamer = StreamerSingleCam()
                isMulticam = false
            }
            streamer?.delegate = self
            if !audioOnly {
                streamer?.videoConfig = settings.videoConfig
            }
            let audioConfig = settings.audioConfig
            streamer?.audioConfig = audioConfig
            if settings.displayVuMeter {
                streamer?.uvMeter = VUMeter
                VUMeter.channels = audioConfig.channelCount
            }
            streamer?.imageLayerPreview = imageLayerPreview
            DispatchQueue.main.async {
                let deviceOrientation = UIApplication.shared.statusBarOrientation
                let newOrientation = self.toAVCaptureVideoOrientation(deviceOrientation: deviceOrientation, defaultOrientation: AVCaptureVideoOrientation.portrait)
                if let stereoOrientation = AVAudioSession.StereoOrientation(rawValue: newOrientation.rawValue) {
                    self.streamer?.stereoOrientation = stereoOrientation
                }
            }
            if settings.streamStartInStandby {
                streamer?.pauseMode = .standby
            }
            try streamer?.startCapture(startAudio: true, startVideo: !audioOnly)
            
            let nc = NotificationCenter.default
            nc.addObserver(
                self,
                selector: #selector(orientationDidChange(notification:)),
                name: UIDevice.orientationDidChangeNotification,
                object: nil)
            
        } catch {
            DDLogError("can't start capture: \(error.localizedDescription)")
            canStartCapture = true
        }
        #if TALKBACK
        player = TalkbackHandler()
        player?.label = Talkback_Label
        player?.start()
        #endif
    }
    func startCaptureMultiCam() {
        DDLogVerbose("ViewController::startCapture")
        
        guard canStartCapture else {
            return
        }
        do {
            let settings = Settings.sharedInstance
            let audioOnly = settings.radioMode
            canStartCapture = false
            
            removePreview()
            
            DispatchQueue.main.async {
           //     self.hideUI()
                self.hideStatusMessage()
                self.Indicator.isHidden = false
                self.Indicator.startAnimating()
                
                UIApplication.shared.isIdleTimerDisabled = true
            }
            if #available(iOS 13.0, *) {
                if !audioOnly && StreamerMultiCam.isSupported() {
                    streamer = StreamerMultiCam()
                    isMulticam = streamer != nil
                }
            }
            if streamer == nil {
                if #available(iOS 13.0, *) {
                    streamer = StreamerMultiCam()
                } else {
                    // Fallback on earlier versions
                }
                isMulticam = true
            }
            streamer?.delegate = self
            if !audioOnly {
                streamer?.videoConfig = settings.videoConfig
            }
            let audioConfig = settings.audioConfig
            streamer?.audioConfig = audioConfig
            if settings.displayVuMeter {
                streamer?.uvMeter = VUMeter
                VUMeter.channels = audioConfig.channelCount
            }
            streamer?.imageLayerPreview = imageLayerPreview
            DispatchQueue.main.async {
                let deviceOrientation = UIApplication.shared.statusBarOrientation
                let newOrientation = self.toAVCaptureVideoOrientation(deviceOrientation: deviceOrientation, defaultOrientation: AVCaptureVideoOrientation.portrait)
                if let stereoOrientation = AVAudioSession.StereoOrientation(rawValue: newOrientation.rawValue) {
                    self.streamer?.stereoOrientation = stereoOrientation
                }
            }
            if settings.streamStartInStandby {
                streamer?.pauseMode = .standby
            }
            try streamer?.startCapture(startAudio: true, startVideo: !audioOnly)
            
            let nc = NotificationCenter.default
            nc.addObserver(
                self,
                selector: #selector(orientationDidChange(notification:)),
                name: UIDevice.orientationDidChangeNotification,
                object: nil)
            
        } catch {
            DDLogError("can't start capture: \(error.localizedDescription)")
            canStartCapture = true
        }
        #if TALKBACK
        player = TalkbackHandler()
        player?.label = Talkback_Label
        player?.start()
        #endif
    }
    
    //MARK:- Applying permission
    
    
    func startCaptureWithDualCamWithSuportingDevice() {
        
        if #available(iOS 13.0, *) {
            if !AVCaptureMultiCamSession.isMultiCamSupported{
                DispatchQueue.main.async {
                    sharedClass.sharedInstance.alert(view: self, title: "Presuno", message: "Device is not supporting multicam feature")
                   
                    self.startCaptureSingleCam()
                    
                }
                return
            } else {
                self.startCaptureMultiCam()
            }
        } else {
            // Fallback on earlier versions
        }
        
    }
    
    
    func stopCapture() {
        DDLogVerbose("ViewController::stopCapture")
        canStartCapture = true
        #if TALKBACK
        player?.stop()
        #endif

        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.isIdleTimerDisabled = false
        
        invalidateTimers()
        
        retryList.removeAll()
        
        streamConditioner?.stop()
        streamConditioner = nil
        
        streamer?.stopCapture()
        streamer = nil
        horizon?.stopQueuedUpdates()

    }
    
    func setBackgroundCapture() {
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.isIdleTimerDisabled = false
        
        uiTimer?.invalidate()
        uiTimer = nil
        backgroundStream = true
        
    }

    func endBackgroundCapture() {
        UIApplication.shared.isIdleTimerDisabled = true

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(orientationDidChange(notification:)),
            name: UIDevice.orientationDidChangeNotification,
            object: nil)

        uiTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateInfo), userInfo: nil, repeats: true)
    }

    
    func invalidateTimers() {
        uiTimer?.invalidate()
        uiTimer = nil
        
        retryTimer?.invalidate()
        retryTimer = nil
        
        recordDurationTImer?.invalidate()
        recordDurationTImer = nil
    }
    
    // Method may be called on a background thread. Move UI update code inside the main queue.
    func captureStateDidChange(state: CaptureState, status: Error) {
        DispatchQueue.main.async {
            self.onCaptureStateChange(state: state, status: status)
        }
    }
    
    func onCaptureStateChange(state: CaptureState, status: Error) {
        DDLogVerbose("captureStateDidChange: \(state) \(status.localizedDescription)")
        
        switch (state) {
        case .CaptureStateStarted:
            Indicator.stopAnimating()
            Indicator.isHidden = true
            showUI()
            isMuted = false
            zoomFactor = streamer?.getCurrentZoom() ?? 1.0
            
            hideStatusMessage()
            uiTimer?.invalidate()
            uiTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateInfo), userInfo: nil, repeats: true)
            
            if lostMic {
                #if TALKBACK
                player?.start()
                #endif
                lostMic = false
                return
            }
            
            createPreview()
            
            // enable adaptive bitrate
            createStreamConditioner()
            
            //Subcribe to volume change to start capture
            volumeChangeTime = CACurrentMediaTime()
            NotificationCenter.default.addObserver(self, selector: #selector(volumeChanged(_:)), name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"), object: nil)
            
        case .CaptureStateFailed:
            if (streamer == nil) {
                DDLogWarn("Capture failed, but we're not running anyway")
                return
            }
            showStatusMessage(message: String.localizedStringWithFormat(NSLocalizedString("Presuno Broadcaster: %@.", comment: ""), status.localizedDescription))
            if let error = status as? CaptureStatus, error == .CaptureStatusErrorMicInUse {
                DDLogWarn("Lost mic access, pausing")
                lostMic = true
                Indicator.startAnimating()
                Indicator.isHidden = false
                #if TALKBACK
                player?.stop()
                #endif

                return
            }
            stopBroadcast()
            removePreview()
            stopCapture()
            
            Indicator.stopAnimating()
            Indicator.isHidden = true
            
          //  hideUI()
            Settings_Button.isHidden = false
            Settings_Button.isEnabled = true
            
            
        case .CaptureStateCanRestart:
            if lostMic {
                DDLogWarn("Got back a microphone")
                showStatusMessage(message: NSLocalizedString("Got back a microphone, restarting...", comment: ""))
            } else {
                showStatusMessage(message: String.localizedStringWithFormat(NSLocalizedString("You can try to restart capture now.", comment: ""), status.localizedDescription))
            }
            
        case .CaptureStateSetup:
            showStatusMessage(message: status.localizedDescription)
            
        default: break
        }
    }
    
    func createPreview() {
        guard let session = streamer?.session else { return }
        if isMulticam {
            backPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            guard backPreviewLayer != nil else {
                return
            }
            frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            guard frontPreviewLayer != nil else {
                return
            }
            if streamer?.connectPreview(back: backPreviewLayer!, front: frontPreviewLayer!) == false {
                return
            }
            backPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspect
            frontPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspect
            
            view.layer.addSublayer(backPreviewLayer!)
            view.layer.insertSublayer(frontPreviewLayer!, above: backPreviewLayer!)

        } else if !Settings.sharedInstance.radioMode {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            let gravity = Settings.sharedInstance.displayLayerGravity
            previewLayer?.videoGravity = gravity
            guard previewLayer != nil else {
                return
            }
            view.layer.addSublayer(previewLayer!)
        }
        addOverlays()
        updateOrientation()
        bringPreviewToBottom()
    }
    
    func addOverlays() {
        let settings = Settings.sharedInstance
        let ratios = settings.safeMarginRatios
        let multicam = settings.multiCamMode
        guard let layer = previewLayer ?? frontPreviewLayer else { return }
        
        if multicam != .sideBySide && (settings.showOverlayGrid || !ratios.isEmpty) {
            let overlay = GridLayer()
            overlay.fillScreen = multicam == .off && Settings.sharedInstance.displayLayerGravity == .resizeAspectFill
            if let videoSize = streamer?.videoConfig?.videoSize {
                overlay.streamWidth = Int(videoSize.width)
                overlay.streamHeight = Int(videoSize.height)
            }
            overlay.rectMargin = CGFloat(settings.safeMarginOffset)
            overlay.rectRatio = ratios
            if settings.showOverlayGrid {
                overlay.gridLinesX = 3
                overlay.gridLinesY = 3
            } else {
                overlay.gridLinesX = 0
                overlay.gridLinesY = 0
            }
            view.layer.insertSublayer(overlay, above: layer)
            self.lineOverlay = overlay
        }
        
        if settings.showHorizonLevel {
            let horizon = HorizonMeterLayer()
            view.layer.insertSublayer(horizon, above: layer)
            horizon.startQueuedUpdates()
            self.horizon = horizon
        }
        
        addZoomIndicator(above: layer)
        self.zoomIndicator?.isHidden = streamer!.getCurrentZoom() == streamer!.baseZoomFactor
        
        if settings.showLayersPreview {
            let overlay = imageLayerPreview ?? ImagePreviewOverlay()
            overlay.fillScreen = multicam == .off && Settings.sharedInstance.displayLayerGravity == .resizeAspectFill
            if let videoSize = streamer?.videoConfig?.videoSize {
                if settings.portrait {
                    overlay.streamWidth = Int(videoSize.height)
                    overlay.streamHeight = Int(videoSize.width)
                } else {
                    overlay.streamWidth = Int(videoSize.width)
                    overlay.streamHeight = Int(videoSize.height)
                }
            }
            view.layer.insertSublayer(overlay, above: layer)
            imageLayerPreview = overlay
            
            streamer?.imageLayerPreview = overlay
        }
    }
    
    func addZoomIndicator(above layer: CALayer) {
        if let oldIndicator = self.zoomIndicator {
            oldIndicator.removeFromSuperlayer()
            self.zoomIndicator = nil
        }
        guard let streamer = streamer, streamer.maxZoomFactor > 1 else { return }
        let zoom = ZoomIndicator()
        zoom.zoomLevels = streamer.getSwitchZoomFactors()
        zoom.initZoom = streamer.baseZoomFactor
        zoom.maxZoom = streamer.maxZoomFactor
        zoom.zoom = streamer.getCurrentZoom()
        zoom.frame = getZoomFrame()
        view.layer.insertSublayer(zoom, above: layer)
        
        self.zoomIndicator = zoom

    }
    
    func addBatteryIndicator() {
        let orientation = UIApplication.shared.statusBarOrientation
        if orientation == .portrait {
            if let oldIndicator = batteryIndicator {
                oldIndicator.removeFromSuperlayer()
                batteryIndicator = nil
            }
            return
        }
        if batteryIndicator == nil {
            batteryIndicator = BatteryIndicator()
            batteryIndicator?.displayThreshold = CGFloat(Settings.sharedInstance.batteryIndicatorThreshold)
            if let layer = previewLayer ?? frontPreviewLayer {
                view.layer.insertSublayer(batteryIndicator!, above: layer)
            } else {
                view.layer.addSublayer(batteryIndicator!)
            }
        }
        let insets = view.safeAreaInsets
        let batRect = CGRect(x: view.frame.width - insets.right - 25, y: insets.top + 2, width: 25, height: 10)
        batteryIndicator!.frame = batRect
    }
    
    func getZoomFrame() -> CGRect {
        var frame = Flip_Button.frame
        frame = frame.offsetBy(dx: frame.width, dy: 0).insetBy(dx: 4.0, dy: -40.0)
        return frame

    }
    
    func removePreview() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        backPreviewLayer?.removeFromSuperlayer()
        backPreviewLayer = nil
        frontPreviewLayer?.removeFromSuperlayer()
        frontPreviewLayer = nil
        lineOverlay?.removeFromSuperlayer()
        lineOverlay = nil
        zoomIndicator?.removeFromSuperlayer()
        zoomIndicator = nil
        horizon?.stopQueuedUpdates()
        horizon?.removeFromSuperlayer()
        horizon = nil
        batteryIndicator?.removeFromSuperlayer()
        batteryIndicator = nil
        imageLayerPreview?.removeFromSuperlayer()
        imageLayerPreview = nil
    }
    
    // MARK: RTMP connection utitlites
    func createConnection(connection: Connection) {
        DDLogVerbose("connection: \(connection.name)")
        
        var id: Int32 = -1
        let url = URL.init(string: connection.url)
        var isSrt = false
        let audioOnly = Settings.sharedInstance.radioMode
        
        if let scheme = url?.scheme?.lowercased(), let host = url?.host {
            let connMode = audioOnly ? .audioOnly : ConnectionMode.init(rawValue: connection.mode)!

            if connMode != .audioOnly && scheme.hasPrefix("rtmp") && streamer?.videoCodecType == kCMVideoCodecType_HEVC {
                let name = connection.name
                let message = String.localizedStringWithFormat(NSLocalizedString("%@: RTMP support for HEVC is a non-standard experimental feature. In case of issues please contact our helpdesk.", comment: ""), name)
                Toast(text: message, theme: .warning)
            }
            if scheme.hasPrefix("rtmp") || scheme.hasPrefix("rtsp") {
                
                let config = ConnectionConfig()
                
                config.uri = URL(string: connection.url)!
                config.auth = ConnectionAuthMode.init(rawValue: connection.auth)!
                config.mode = connMode
                
                if connection.username != nil || connection.password != nil {
                    config.username = connection.username ?? ""
                    config.password = connection.password ?? ""
                }
                
                DDLogVerbose("url: \(config.uri.absoluteString)")
                DDLogVerbose("mode: \(config.mode.rawValue)")
                DDLogVerbose("auth: \(config.auth.rawValue)")
                DDLogVerbose("user: \(String(describing: connection.username))")
                DDLogVerbose("pass: \(String(describing: connection.password))")
                
                id = streamer?.createConnection(config: config) ?? -1
                
            } else if scheme == "srt", let port = url?.port {
                checkMaxBw(connection: connection)
                let config = SrtConfig()
                
                config.host = host
                config.port = Int32(port)
                config.mode = connMode
                config.connectMode = SrtConnectMode(rawValue: connection.srtConnectMode) ?? .caller
                config.pbkeylen = connection.pbkeylen
                config.passphrase = connection.passphrase
                config.latency = connection.latency
                config.maxbw = connection.maxbw
                config.streamid = connection.streamid
                config.retransmitAlgo = ConnectionRetransmitAlgo(rawValue: connection.retransmitAlgo) ?? .default
                
                DDLogVerbose("host: \(String(describing: config.host))")
                DDLogVerbose("port: \(config.port)")
                DDLogVerbose("mode: \(config.mode.rawValue)")
                DDLogVerbose("passphrase: \(String(describing: config.passphrase))")
                DDLogVerbose("pbkeylen: \(config.pbkeylen)")
                DDLogVerbose("latency: \(config.latency)")
                DDLogVerbose("maxbw: \(config.maxbw)")
                DDLogVerbose("streamid: \(String(describing: config.streamid))")
                
                id = streamer?.createConnection(config: config) ?? -1
                isSrt = true
            } else if scheme == "rist" {
                
                let config = RistConfig()
                
                config.uri = URL(string: connection.url)!
                config.mode = connMode
                config.profile = RistProfile(rawValue: connection.rist_profile) ?? .main

                id = streamer?.createRistConnection(config: config) ?? -1
                isSrt = true
            }
            
        }
        
        if id != -1 {
            connectionId[id] = connection
            connectionState[id] = .disconnected
            connectionStatistics[id] = ConnectionStatistics()
            connectionStatistics[id]?.isUdp = isSrt
            
            streamConditioner?.addConnection(id: id)
        } else {
            let message = String.localizedStringWithFormat(NSLocalizedString("Could not create connection \"%@\" (%@).", comment: ""), connection.name, connection.url)
            Toast(text: message, theme: .error)
        }
        DDLogVerbose("SwiftApp::create connection: \(id), \(connection.name), \(connection.url)" )
    }
    
    func checkMaxBw(connection: Connection) {
        if connection.maxbw == 0 || connection.maxbw > 10500 {
            return
        }
        let message = """
Notice that your "maxbw" parameter of SRT connection seem to have incorrect value, \
so we've set it to "0" to be relative to input rate. We recommend you using this value by default.
"""
        connection.maxbw = 0
        do {
            try dbQueue.write { (db) in
                try connection.save(db)
            }
        } catch {
            DDLogError("Update failed")
        }
        Toast(text: NSLocalizedString(message, comment: ""), theme: .warning)
    }
    
    func releaseConnection(id: Int32) {
        if id != -1 {
            DDLogVerbose("SwiftApp::release connection: \(id)")
            
            connectionId.removeValue(forKey: id)
            connectionState.removeValue(forKey: id)
            connectionStatistics.removeValue(forKey: id)
            
            streamConditioner?.removeConnection(id: id)
            
            streamer?.releaseConnection(id: id)
        }
    }
    
    // Method is called on a background thread. Move UI update code inside the main queue.
    func connectionStateDidChange(id: Int32, state: ConnectionState, status: ConnectionStatus, info: [AnyHashable:Any]!) {
        DispatchQueue.main.async {
            self.onConnectionStateChange(id: id, state: state, status: status, info: info)
        }
    }
    
    func onConnectionStateChange(id: Int32, state: ConnectionState, status: ConnectionStatus, info: [AnyHashable:Any]!) {
        DDLogVerbose("connectionStateDidChange id:\(id) state:\(state.rawValue) status:\(status.rawValue)")
        
        // ignore disconnect confirmation after releaseConnection call
        if let connection = connectionId[id], let _ = connectionState[id], let statistics = connectionStatistics[id] {
            
            connectionState[id] = state
            
            switch (state) {
                
            case .connected:
                let time = CACurrentMediaTime()
                statistics.startTime = time
                statistics.prevTime = time
                statistics.prevBytesDelivered = streamer?.bytesDelivered(connection: id) ?? 0
                statistics.prevBytesSent = streamer?.bytesSent(connection: id) ?? 0
                
            case .disconnected where isBroadcasting:
                let name = connection.name
                
                var retry = false
                
                releaseConnection(id: id)
                
                switch (status) {
                case .connectionFail:
//                    let message = String.localizedStringWithFormat(NSLocalizedString("%@: Could not connect to server. Please check stream URL and network connection. Retrying in 3 seconds.", comment: ""), name)
//                    Toast(text: message, theme: .error)
                    
                    sharedClass.sharedInstance.alert(view: self, title: "Presuno", message: "Could not connect to server. Please check stream URL and network connection. Retrying in 3 seconds.")
                    
                 //   retry = true
                    
                case .unknownFail:
                    var status: String?
                    if let info = info, info.count > 0 {
                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: info)
                            status = String(data: jsonData, encoding: .utf8)
                        } catch {
                        }
                    }                    
                    
                    let message: String
                    if let status = status {
                        message = String.localizedStringWithFormat(NSLocalizedString("%@: Error: \(status), retrying in 3 seconds.", comment: ""), name)
                    } else {
                        message = String.localizedStringWithFormat(NSLocalizedString("%@: Unknown connection error, retrying in 3 seconds.", comment: ""), name)
                    }
                    Toast(text: message, theme: .error)
                    
                    retry = true
                    
                case .authFail:
                    var badType = false
                    if let info = info, info.count > 0 {
                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: info)
                            if let json = String(data: jsonData, encoding: .utf8) {
                                if json.contains("authmod=adobe"), connection.auth != ConnectionAuthMode.rtmp.rawValue, connection.auth != ConnectionAuthMode.akamai.rawValue {
                                    badType = true
                                } else if json.contains("authmod=llnw"), connection.auth != ConnectionAuthMode.llnw.rawValue {
                                    badType = true
                                }
                            }
                        } catch {
                        }
                    }
                    
                    let message: String
                    if badType {
                        message = String.localizedStringWithFormat(NSLocalizedString("%@: Presuno doesn't support this type of RTMP authorization. Please use rtmpauth URL parameter or other \"Target type\" for authorization.", comment: ""), name)
                    } else {
                        message = String.localizedStringWithFormat(NSLocalizedString("%@: Authentication error. Please check stream credentials.", comment: ""), name)
                    }
                    Toast(text: message, theme: .error)
                    
                case .success: break
                @unknown default: break
                }
                
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                let canConnect = appDelegate.canConnect
                
                if retry, canConnect {
                    retryList.append(connection)
                    
                    retryTimer?.invalidate()
                    retryTimer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(autoRetry), userInfo: nil, repeats: false)
                }
                
                if !canConnect || (retryList.count == 0 && connectionId.count == 0) {
                    stopBroadcast()
                }
                
            case .initialized, .setup, .record, .disconnected: break
            @unknown default: break
            }
        }
    }
    
    @objc func autoRetry() {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if !appDelegate.canConnect {
            DispatchQueue.main.async {
                self.stopBroadcast()
            }
        } else {
            for connection in retryList {
                createConnection(connection: connection)
            }
            retryList.removeAll()
        }
    }
    
    // MARK: mp4 record
    func startRecord() {
        if Settings.sharedInstance.record {
            restartRecording = false
            streamer?.startRecord()
            Rec_Indicator.isHidden = false
        }
    }
    
    @objc func restartRecord() {
        streamer?.stopRecord(restart: true)
    }
    
    
    func stopRecord() {
        recordDurationTImer?.invalidate()
        recordDurationTImer = nil
        
        streamer?.stopRecord(restart: false)
        Rec_Indicator.isHidden = true
    }
    
    // MARK: Mute sound
    var isMuted: Bool = false {
        didSet {
            if isMuted {
                Mute_Button.layer.backgroundColor = UIColor.white.cgColor
                Mute_Button.alpha = 1.0
                Mute_Button.setImage(#imageLiteral(resourceName: "mute_on"), for: .normal)
            } else {
                Mute_Button.layer.backgroundColor = UIColor(white: 0.3, alpha: 1.0).cgColor
                Mute_Button.alpha = 0.6
                Mute_Button.setImage(#imageLiteral(resourceName: "mute_off"), for: .normal)
            }
            streamer?.isMuted = isMuted
        }
    }
    
    // MARK: Can't change camera
    func notification(notification: StreamerNotification) {
        switch (notification) {
        case .ActiveCameraDidChange:
            DispatchQueue.main.async {
                self.zoomFactor = self.streamer?.getCurrentZoom() ?? 1.0
                if let maxZoom = self.streamer?.maxZoomFactor, maxZoom > 1,
                   let layer = self.previewLayer ?? self.frontPreviewLayer {
                    self.addZoomIndicator(above: layer)
                }
                self.imageLayerPreview?.flip = self.streamer?.cameraPosition == .front
            }

        case .ChangeCameraFailed:
            let message = NSLocalizedString("The selected video size or frame rate is not supported by the destination camera. Decrease the video size or frame rate before switching cameras.", comment: "")
            Toast(text: message, theme: .warning)

        case .FrameRateNotSupported:
            let message = (Settings.sharedInstance.cameraPosition == .front) ?
                NSLocalizedString("The selected frame rate is not supported by this camera. Try to start app with Back Camera.", comment: "") :
                NSLocalizedString("The selected frame rate is not supported by this camera.", comment: "")
            Toast(text: message, theme: .warning)
        }
    }
    
    // MARK: Device orientation
    @objc func orientationDidChange(notification: Notification) {
        DDLogVerbose("orientationDidChange")
        updateOrientation()

    }
    
    // 1 - Set the preview layer frame so that the frame of the preview layer changes when the screen rotates.
    // 2 - Rotate the preview layer connection with the rotation of the device.
    func updateOrientation() {
        DDLogVerbose("updateOrientation")
        hideSettingsView()
        previewLayer?.frame = view.layer.frame
        
        let deviceOrientation = UIApplication.shared.statusBarOrientation
        let newOrientation = toAVCaptureVideoOrientation(deviceOrientation: deviceOrientation, defaultOrientation: AVCaptureVideoOrientation.portrait)
        previewLayer?.connection?.videoOrientation = newOrientation

        if backPreviewLayer?.connection?.isVideoOrientationSupported ?? false {
            backPreviewLayer?.connection?.videoOrientation = newOrientation
        }
        if frontPreviewLayer?.connection?.isVideoOrientationSupported ?? false {
            frontPreviewLayer?.connection?.videoOrientation = newOrientation
        }
        lineOverlay?.frame = view.layer.frame
        horizon?.frame = view.layer.frame
        if let zoom = self.zoomIndicator {
            zoom.frame = getZoomFrame()
        }
        
        addBatteryIndicator()
        let postprocess = Settings.sharedInstance.postprocess
        if postprocess {
            streamer?.resetFocus()
            Focus_Label.isHidden = true
            
            if Settings.sharedInstance.liveRotation {
                streamer?.orientation = newOrientation
            }
        }
        adjustImagePreview(orientation: newOrientation)
        
        adjustVuMeter()
        adjustPipPosition()
        adjustToast(orientation: deviceOrientation)
    }
    
    func adjustImagePreview(orientation newOrientation: AVCaptureVideoOrientation) {
        guard let imageLayerPreview = imageLayerPreview else {
            return
        }
        let settings = Settings.sharedInstance
        var streamerOrientation = newOrientation
        var rotateImage = 0
        let postprocess = settings.postprocess
        let portraitStream = settings.portrait
        let multicamMode = settings.multiCamMode
        if postprocess {
            if isBroadcasting {
                // Should rotate only we rotate with active stream when rotation is locked
                // (otherwise it match current orientation)
                let orientation = streamer?.orientation ?? .portrait
                streamerOrientation = orientation
                rotateImage = getRotationAngle(origin: orientation, current: newOrientation)
            }
            let portraitScreen = streamerOrientation == .portrait || streamerOrientation == .portraitUpsideDown
            let virtualBars = multicamMode != .sideBySide && portraitStream != portraitScreen
            imageLayerPreview.virtualBlackBars = virtualBars
        } else {
            let fixedOrientation = portraitStream ? AVCaptureVideoOrientation.portrait : AVCaptureVideoOrientation.landscapeRight
            rotateImage = getRotationAngle(origin: fixedOrientation, current: newOrientation)
        }
        imageLayerPreview.rotateQuad = rotateImage
        imageLayerPreview.frame = view.layer.frame
    }
    
    func getRotationAngle(origin: AVCaptureVideoOrientation, current: AVCaptureVideoOrientation) -> Int {
        let roationMap: [AVCaptureVideoOrientation: Int] = [
            .portrait: 0,
            .landscapeLeft: -1,
            .landscapeRight: 1,
            .portraitUpsideDown: 2
        ]
        let a = roationMap[origin] ?? 0
        let b = roationMap[current] ?? 0
        return a - b
     }
    
    func adjustVuMeter() {
        if VUMeter.isHidden {
            return
        }
        let deviceOrientation = UIApplication.shared.statusBarOrientation
        let newOrientation = toAVCaptureVideoOrientation(deviceOrientation: deviceOrientation, defaultOrientation: AVCaptureVideoOrientation.portrait)

        let frame = VUMeter.frame
        let w = frame.width
        let h = frame.height
        let isPortrait = deviceOrientation == .portrait || newOrientation == .portraitUpsideDown
//        if isPortrait {
//            (w, h) = (min(w,h), max(w,h))
//        } else {
//            (w, h) = (max(w,h), min(w,h))
//        }
        let top = view.layer.frame.height - h - 16.0
        let left = isPortrait ? CGFloat(10.0) : CGFloat(30.0)
        VUMeter.frame = CGRect(x: left, y: top, width: w, height: h)
        VUMeter.arrangeLayers()
    }
    
    func adjustToast(orientation: UIInterfaceOrientation) {
        let postprocess = Settings.sharedInstance.postprocess
        guard  let toastView = activeToast else { return }
        let originFrame = toastView.frame
        if originFrame.origin.y > 0 {
            return
        }

        let horizontal = orientation == .landscapeLeft || orientation == .landscapeRight
        let screenSize = UIScreen.main.bounds
        let w: CGFloat
        if horizontal || postprocess {
            w = max(screenSize.size.width, screenSize.size.height)
        } else {
            w = min(screenSize.size.width, screenSize.size.height)
        }
        DDLogInfo("Toast new width: \(w)")
        let frame = CGRect(x: 0, y: 0, width: w, height: originFrame.height)
        if !postprocess {
            toastView.frame = frame
        }
        toastView.bounds = frame
    }
    
    func toAVCaptureVideoOrientation(deviceOrientation: UIInterfaceOrientation, defaultOrientation: AVCaptureVideoOrientation) -> AVCaptureVideoOrientation {
        
        var captureOrientation: AVCaptureVideoOrientation
        
        switch (deviceOrientation) {
        case .portrait:
            // Device oriented vertically, home button on the bottom
            //DDLogVerbose("AVCaptureVideoOrientationPortrait")
            captureOrientation = AVCaptureVideoOrientation.portrait
        case .portraitUpsideDown:
            // Device oriented vertically, home button on the top
            //DDLogVerbose("AVCaptureVideoOrientationPortraitUpsideDown")
            captureOrientation = AVCaptureVideoOrientation.portraitUpsideDown
        case .landscapeLeft:
            // Device oriented horizontally, home button on the right
            //DDLogVerbose("AVCaptureVideoOrientationLandscapeLeft")
            captureOrientation = AVCaptureVideoOrientation.landscapeLeft
        case .landscapeRight:
            // Device oriented horizontally, home button on the left
            //DDLogVerbose("AVCaptureVideoOrientationLandscapeRight")
            captureOrientation = AVCaptureVideoOrientation.landscapeRight
        default:
            captureOrientation = defaultOrientation
        }
        return captureOrientation
    }
    
    // MARK: Request permissions
    var cameraAuthorized: Bool = false {
        // Swift has a simple and classy solution called property observers, and it lets you execute code whenever a property has changed. To make them work, you need to declare your data type explicitly (in our case we need an Bool), then use either didSet to execute code when a property has just been set, or willSet to execute code before a property has been set.
        didSet {
            if cameraAuthorized {
                DDLogVerbose("cameraAuthorized")
                checkMicAuthorizationStatus()
            } else {
                DispatchQueue.main.async {
                    self.presentCameraAccessAlert()
                }
            }
        }
    }
    
    var micAuthorized: Bool = false {
        didSet {
            if micAuthorized {
                DDLogVerbose("micAuthorized")
                startCaptureWithDualCamWithSuportingDevice()
            } else {
                DispatchQueue.main.async {
                    self.presentMicAccessAlert()
                }
            }
        }
    }
    
    var deviceAuthorized: Bool {
        get {
            return cameraAuthorized && micAuthorized
        }
    }
    
    func checkForAuthorizationStatus() {
        DDLogVerbose("checkForAuthorizationStatus")
        if (Settings.sharedInstance.radioMode) {
            cameraAuthorized = true
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        
        switch (status) {
        case AVAuthorizationStatus.authorized:
            cameraAuthorized = true
        case AVAuthorizationStatus.notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: {
                granted in
                if granted {
                    DDLogVerbose("cam granted: \(granted)")
                    self.cameraAuthorized = true
                    DDLogVerbose("raw value: \(AVCaptureDevice.authorizationStatus(for: AVMediaType.video).rawValue)")
                } else {
                    self.cameraAuthorized = false
                }
            })
        default:
            cameraAuthorized = false
        }
    }
    
    func checkMicAuthorizationStatus() {
        DDLogVerbose("checkMicAuthorizationStatus")
        
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio)
        
        switch (status) {
        case AVAuthorizationStatus.authorized:
            micAuthorized = true
        case AVAuthorizationStatus.notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.audio, completionHandler: {
                granted in
                if granted {
                    DDLogVerbose("mic granted: \(granted)")
                    self.micAuthorized = true
                    DDLogVerbose("raw value: \(AVCaptureDevice.authorizationStatus(for: AVMediaType.audio).rawValue)")
                } else {
                    self.micAuthorized = false
                }
            })
        default:
            micAuthorized = false
        }
    }
    
    func openSettings() {
        let settingsUrl = URL(string: UIApplication.openSettingsURLString)
        if let url = settingsUrl {
            UIApplication.shared.open(url, options: [:])
        }
    }
    
    // MARK: UI utilities
    func showConnectionInfo() {
        let ids = Array(connectionId.keys).sorted(by: <)
        for i in 0..<name.count {
            if i < ids.count {
                if let connection = connectionId[ids[i]], let statistics = connectionStatistics[ids[i]] {
                    name[i].text = connection.name
                    
                    let tr = trafficToString(bytes: statistics.prevBytesDelivered)
                    let bw = bandwidthToString(bps: statistics.bps)
                    status[i].text = bw + ", " + tr
                    let packetsLost = streamer?.udpPacketsLost(connection: ids[i]) ?? 0

                    var color = UIColor.white
                    if statistics.isUdp && statistics.packetsLost != packetsLost {
                        statistics.packetsLost = packetsLost
                        color = UIColor.yellow
                    } else if !statistics.isUdp {
                        if statistics.latency > 5.0 {
                            color = UIColor.red
                        } else if statistics.latency > 1.0 {
                            color = UIColor.yellow
                        }
                    }
                    status[i].textColor = color
                    
                    name[i].isHidden = false
                    status[i].isHidden = false
                }
            } else {
                name[i].isHidden = true
                status[i].isHidden = true
                name[i].text = ""
                status[i].text = NSLocalizedString("Connecting...", comment: "")
            }
        }
    }
    
    func hideConnectionInfo() {
        for label in name {
            label.text = ""
            label.isHidden = true
        }
        let text = NSLocalizedString("Connecting...", comment: "")
        for label in status {
            label.text = text
            label.isHidden = true
        }
    }
    
    func showUI() {
        let audioOnly = Settings.sharedInstance.radioMode
        let showMeter = Settings.sharedInstance.displayVuMeter
        hideStatusMessage()
        
        Fps_Label.isHidden = audioOnly
        Focus_Label.isHidden = true
        
        Broadcast_Button.isHidden = false
        Settings_Button.isHidden = false
        setMediaBtn.isHidden = false
        onAndOffMainBtn.isHidden = false
        secondaryFeedBtn.isHidden = false
        Flip_Button.isHidden = audioOnly
        Mute_Button.isHidden = false
        Shoot_Button.isHidden = audioOnly
        QuickSettings_Button.isHidden = audioOnly
        VUMeter.isHidden = !showMeter
        adjustVuMeter()
    }
    
//    func hideUI() {
//        Fps_Label.isHidden = true
//        Focus_Label.isHidden = true
//
//        Broadcast_Button.isHidden = true
//        Settings_Button.isHidden = true
//        Flip_Button.isHidden = true
//        Mute_Button.isHidden = true
//        Shoot_Button.isHidden = true
//        QuickSettings_Button.isHidden = true
//        VUMeter.isHidden = true
//    }
    
    func showSettingsView() {
        if settingsView != nil {
            return
        }
        guard let streamer = streamer else {
            return
        }
        let storyboard = UIStoryboard.init(name: "Main", bundle: Bundle.main)
        guard let settings = storyboard.instantiateViewController(withIdentifier: "QuickSettings") as? QuickSettings else {
            return
        }
        //let settings = QuickSettings()
        settings.evValue = streamer.getExposureCompensation()
        settings.flashEnabled = streamer.supportFlash()
        settings.flashOn = streamer.flashOn()
        settings.multiCamMode = Settings.sharedInstance.multiCamMode
        settings.zoom = streamer.getCurrentZoom()
        settings.initZoom = streamer.baseZoomFactor
        settings.maxZoom = streamer.maxZoomFactor
        settings.overlays = streamer.imageLayer.activeLayers
        
        var streamRatio = Float(streamer.streamWidth) / Float(streamer.streamHeight)
        if streamRatio > 0 && streamRatio < 1 { streamRatio = 1.0 / streamRatio}
        var screenRatio = Float(view.frame.width) / Float(view.frame.height)
        if screenRatio > 0 && screenRatio < 1 { screenRatio = 1.0 / screenRatio}
        settings.displayRatioMatch = abs(screenRatio - streamRatio) < 0.1
        
        
        //addChild(settings)
        let insets = view.safeAreaInsets
        let origin = CGPoint(x: insets.left + 30.0, y: insets.top + 20.0)
        let size: CGSize
        if view.frame.width > view.frame.height {
            size = CGSize(width: view.frame.width * 0.5, height: view.frame.height - 60.0)
        } else {
            size = CGSize(width: view.frame.width - 60.0, height: view.frame.height * 0.5)
        }
        let rect = CGRect(origin: origin, size: size)
        settings.view.frame = rect
        settings.view.isOpaque = false
        settings.view.backgroundColor = UIColor.black
        settings.view.alpha = 0.7
        view.addSubview(settings.view)
        //settings.didMove(toParent: self)
        
        settings.onFlashChange = { (_) in
            _ = self.streamer?.toggleFlash()
        }
        settings.onEvChange = { (ev, cam) in
            self.streamer?.setExposureCompensation(ev, position: cam)
        }
        settings.onPreviewModeChange = { (mode) in
            let gravity = mode == "fill" ? AVLayerVideoGravity.resizeAspectFill : AVLayerVideoGravity.resizeAspect
            self.previewLayer?.videoGravity = gravity
            self.recreateGrid()
        }
        
        settings.onGridModeChange = { self.recreateGrid() }
        
        settings.onZoomChange = { zoom in
            streamer.zoomTo(factor: zoom)
            self.zoomFactor = zoom
        }
        
        settings.onOverlaysChange = {
            let idSet = settings.overlays
            let idList = Array(idSet)
            self.streamer?.imageLayer.loadIdList(idList)
        }
        self.settingsView = settings
        
    }
    
    func recreateGrid() {
        imageLayerPreview?.removeFromSuperlayer()
        lineOverlay?.removeFromSuperlayer()
        horizon?.removeFromSuperlayer()
        lineOverlay = nil
        horizon = nil
        addOverlays()
        let frame = view.layer.frame
        lineOverlay?.frame = frame
        horizon?.frame = frame
        imageLayerPreview?.frame = frame

    }
    
    func hideSettingsView() {
        settingsView?.view.removeFromSuperview()
        settingsView = nil
    }
    

    
    // Place the sublayer below the buttons (aka raise the buttons up in the layer).
    func bringPreviewToBottom() {
        view.bringSubviewToFront(VUMeter)
        for case let label as UILabel in view.subviews {
            view.bringSubviewToFront(label)
        }
        for case let btn as UIButton in view.subviews {
            view.bringSubviewToFront(btn)
        }
        view.bringSubviewToFront(Rec_Indicator)
    }
    
    func makeRoundButttons() {
        let labelRadius: CGFloat = 13.0
//        let btnRadius: CGFloat = 20.0
        let fillColor = UIColor(white: 0.3, alpha: 1.0).cgColor
        let borderColor = UIColor(white: 0.5, alpha: 1.0).cgColor
        
        for case let label as UILabel in view.subviews {
            label.layer.masksToBounds = true
            label.layer.cornerRadius = labelRadius
            if label == Message_Label { continue }
            label.layer.borderWidth = 1.0
            label.layer.borderColor = borderColor
            label.layer.backgroundColor = fillColor
        }
        
        for case let btn as UIButton in view.subviews {
            btn.layer.cornerRadius = 8
            if btn == Broadcast_Button {
                continue
            }
            btn.layer.borderWidth = 1.0
            btn.layer.borderColor = borderColor
          //  btn.layer.backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
    
    func adjustPipPosition() {
        guard #available(iOS 13.0, *) else {
            return
        }
        if let pipStreamer = streamer as? StreamerMultiCam {
            let pipPos = pipStreamer.pipDevicePosition
            if pipPos == .pip_back || pipPos == .pip_front {
            
                guard let fullLayer = pipPos == .pip_front ? backPreviewLayer : frontPreviewLayer,
                    let pipLayer = pipPos == .pip_back ? backPreviewLayer : frontPreviewLayer else {
                        return
                }
                let viewWidth = view.frame.width
                let viewHeight = view.frame.height
                
                lineOverlay?.removeFromSuperlayer()
                horizon?.removeFromSuperlayer()
                zoomIndicator?.removeFromSuperlayer()
                imageLayerPreview?.removeFromSuperlayer()
                pipLayer.removeFromSuperlayer()
                fullLayer.removeFromSuperlayer()
                pipLayer.frame = CGRect(x: viewWidth / 2, y: viewHeight / 2, width: viewWidth / 2, height: viewHeight / 2)
                fullLayer.frame = CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight)
                view.layer.addSublayer(fullLayer)
                if let overlays = imageLayerPreview {
                    view.layer.insertSublayer(overlays, above: pipLayer)
                }
                if let grid = lineOverlay {
                    view.layer.insertSublayer(grid, above: fullLayer)
                }
                view.layer.insertSublayer(pipLayer, above: fullLayer)
                if let horizon = horizon {
                    view.layer.insertSublayer(horizon, above: pipLayer)
                }
                if let zoom = zoomIndicator {
                    view.layer.insertSublayer(zoom, above: fullLayer)
                    zoom.frame = getZoomFrame()
                }
                
            } else {
                guard let leftLayer = pipPos == .left_front ? frontPreviewLayer : backPreviewLayer,
                    let rightLayer = pipPos == .left_front ? backPreviewLayer : frontPreviewLayer else {
                        return
                }
                let viewWidth = view.frame.width
                let viewHeight = view.frame.height
                if streamer?.videoConfig?.portrait == false {
                    
                    leftLayer.frame = CGRect(x: viewWidth / 50 , y: 0, width: viewWidth  , height: viewHeight)
                    rightLayer.frame =
                        CGRect(x: viewWidth / 1.7 , y: viewHeight / 6 , width: viewWidth / 1.5 , height: viewHeight / 3 )
                    //
//                    leftLayer.frame = CGRect(x: 0, y: 0, width: viewWidth / 2, height: viewHeight)
//                    rightLayer.frame = CGRect(x: viewWidth / 2, y: 0, width: viewWidth / 2, height: viewHeight)
                } else {
                    leftLayer.frame =  CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight / 2)
                    rightLayer.frame = CGRect(x: 0, y: viewHeight / 2, width: viewWidth, height: viewHeight / 2)
                }
                if let zoom = zoomIndicator {
                    view.layer.insertSublayer(zoom, above: leftLayer)
                    zoom.frame = getZoomFrame()
                }

            }
        }
        bringPreviewToBottom()
    }
    
    
    // MARK: Alert dialogs
    func presentCameraAccessAlert() {
        let title = NSLocalizedString("Camera is disabled", comment: "")
        let message = NSLocalizedString("Allow the app to access the camera in your device's settings.", comment: "")
        presentAccessAlert(title: title, message: message)
    }
    
    func presentMicAccessAlert() {
        let title = NSLocalizedString("Microphone is disabled", comment: "")
        let message = NSLocalizedString("Allow the app to access the microphone in your device's settings.", comment: "")
        presentAccessAlert(title: title, message: message)
    }
    
    func presentAccessAlert(title: String, message: String) {
        let settingsButtonTitle = NSLocalizedString("Go to settings", comment: "")
        let cancelButtonTitle = NSLocalizedString("Cancel", comment: "")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let settingsAction = UIAlertAction(title: settingsButtonTitle, style: .default) { [weak self] _ in
            self?.openSettings()
            self?.alertController = nil
        }
        
        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel) { [weak self] _ in
            self?.alertController = nil
        }
        
        alertController.addAction(settingsAction)
        alertController.addAction(cancelAction)
        
        presentAlertController(alertController)
        
        // Also update error message on screen, because user can occasionally cancel alert dialog
        showStatusMessage(message: NSLocalizedString("Presuno Broadcaster doesn't have all permissions to use camera and microphone, please change privacy settings.", comment: ""))
    }
    
    func presentImportDialog() {
        let deepLink = DeepLink.sharedInstance
        let message = deepLink.getImportConfirmationBody()
        //Rewind to connections list if we're inside of it
        if let activeViews = navigationController?.viewControllers {
            var backToSettings = false
            for view in activeViews {
                #if TALKBACK
                if view is TalkbackListControler {
                    navigationController?.popToViewController(view, animated: false)
                    break
                }
                #endif
                if view is ConnectionsViewController {
                    navigationController?.popToViewController(view, animated: false)
                    break
                }
                //Return to main settings if we're inside of Video/Audio/Record/Display
                if view is BundleSettingsViewController {
                    backToSettings = true
                }
            }
            if backToSettings {
                if let settingsView = activeViews.first(where: { $0 is OptionsHomeViewController }) {
                    navigationController?.popToViewController(settingsView, animated: false)
                }
            }
        }
        
        
        let alertController = UIAlertController(title: NSLocalizedString("Import settings", comment: ""), message: "Import", preferredStyle: .alert)
        alertController.setValue(message, forKey: "attributedMessage")
        
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { [weak self] _ in
            deepLink.importSettings()
            let theme: Theme = deepLink.importedWithErrors() ? .warning : .success
            let connCount = deepLink.getImportConnectionCount()
            let info = deepLink.getImportResultBody()
            deepLink.clear()
            if !info.isEmpty {
                let appDelegate = UIApplication.shared.delegate as? AppDelegate
                if connCount > 0 && appDelegate?.onConnectionsUpdate != nil {
                    appDelegate?.onConnectionsUpdate?()
                }
                Toast(text: info, theme: theme, duration: 5.0)
            }
            self?.resumeCapture(shouldRequestPermissions: true)
            self?.alertController = nil
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
            deepLink.clear()
            self?.resumeCapture(shouldRequestPermissions: true)
            self?.alertController = nil
        }
        
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        
        presentAlertController(alertController)
    }
    
    func dismissAlertController() {
        alertController?.dismiss(animated: false)
        alertController = nil
    }
    
    func presentAlertController(_ alertController: UIAlertController) {
        dismissAlertController()
        present(alertController, animated: false)
        self.alertController = alertController
    }
    
    func showStatusMessage(message: String) {
        Message_Label.isHidden = false
        Message_Label.text = message
    }
    
    func hideStatusMessage() {
        Message_Label.isHidden = true
        Message_Label.text = ""
    }
    
    // MARK: Connection status UI
    @objc func updateInfo() {
        Fps_Label.text = String.localizedStringWithFormat(NSLocalizedString("%d fps", comment: ""), streamer?.fps ?? 0)
        Rec_Indicator.isHidden = streamer?.isRecording != true
        if !isBroadcasting {
            return
        }
        
        let curTime = CACurrentMediaTime()
        let broadcastTime = curTime - broadcastStartTime
        Time_Label.text = timeToString(time: Int(broadcastTime))
        
        let ids = Array(connectionId.keys)
        for id in ids {
            if let state = connectionState[id], let statistics = connectionStatistics[id] {
                // some auth schemes require reconnection to same url multiple times, so connection will be silently closed and re-created inside library; app must not query connection statistics while auth phase is in progress
                if state == .record {
                    
                    statistics.duration = curTime - statistics.prevTime
                    
                    let bytesDelivered = streamer?.bytesDelivered(connection: id) ?? 0
                    let bytesSent = streamer?.bytesSent(connection: id) ?? 0
                    let delta = bytesDelivered > statistics.prevBytesDelivered ? bytesDelivered - statistics.prevBytesDelivered : 0
                    let deltaSent = bytesSent > statistics.prevBytesSent ? bytesSent - statistics.prevBytesSent : 0
                    if !statistics.isUdp {
                        if deltaSent > 0 {
                            statistics.latency =  bytesSent > bytesDelivered ? Double(bytesSent - bytesDelivered) / Double(deltaSent) : 0.0
                        }
                    } else {
                        statistics.packetsLost = streamer?.udpPacketsLost(connection: id) ?? 0
                    }
                    let timeDiff = curTime - statistics.prevTime
                    if timeDiff > 0 {
                        statistics.bps = 8.0 * Double(delta) / timeDiff
                    } else {
                        statistics.bps = 0
                    }
                    
                    statistics.prevTime = curTime
                    statistics.prevBytesDelivered = bytesDelivered
                    statistics.prevBytesSent = bytesSent
                }
            }
        }
        showConnectionInfo()
    }
    
    func timeToString(time: Int) -> String {
        let sec = Int(time % 60)
        let min = Int((time / 60) % 60)
        let hrs = Int(time / 3600)
        let str = String.localizedStringWithFormat(NSLocalizedString("%02d:%02d:%02d", comment: ""), hrs, min, sec)
        return str
    }
    
    func trafficToString(bytes: UInt64) -> String {
        if bytes < 1024 {
            // b
            return String.localizedStringWithFormat(NSLocalizedString("%4dB", comment: ""), bytes)
        } else if bytes < 1024 * 1024 {
            // Kb
            return String.localizedStringWithFormat(NSLocalizedString("%3.1fKB", comment: ""), Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            // Mb
            return String.localizedStringWithFormat(NSLocalizedString("%3.1fMB", comment: ""), Double(bytes) / (1024 * 1024))
        } else {
            // Gb
            return String.localizedStringWithFormat(NSLocalizedString("%3.1fGB", comment: ""), Double(bytes) / (1024 * 1024 * 1024))
        }
    }
    
    func bandwidthToString(bps: Double) -> String {
        if bps < 1000 {
            // b
            return String.localizedStringWithFormat(NSLocalizedString("%4dbps", comment: ""), Int(bps))
        } else if bps < 1000 * 1000 {
            // Kb
            return String.localizedStringWithFormat(NSLocalizedString("%3.1fKbps", comment: ""), bps / 1000)
        } else if bps < 1000 * 1000 * 1000 {
            // Mb
            return String.localizedStringWithFormat(NSLocalizedString("%3.1fMbps", comment: ""), bps / (1000 * 1000))
        } else {
            // Gb
            return String.localizedStringWithFormat(NSLocalizedString("%3.1fGbps", comment: ""), bps / (1000 * 1000 * 1000))
        }
    }
    
    // MARK: focus
    func showFocusView(at center: CGPoint, color: CGColor = UIColor.white.cgColor) {
        
        struct FocusView {
            static let focusView: UIView = {
                let focusView = UIView()
                let diameter: CGFloat = 100
                focusView.bounds.size = CGSize(width: diameter, height: diameter)
                focusView.layer.borderWidth = 2
                
                return focusView
            }()
        }
        FocusView.focusView.transform = CGAffineTransform.identity
        FocusView.focusView.center = center
        FocusView.focusView.layer.borderColor = color
        view.addSubview(FocusView.focusView)
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1.1,
                       options: UIView.AnimationOptions(), animations: { () -> Void in
                        FocusView.focusView.transform = CGAffineTransform.identity.scaledBy(x: 0.6, y: 0.6)
        }) { (Bool) -> Void in
            FocusView.focusView.removeFromSuperview()
        }
    }
    
    @objc func tappedView() {
        //DDLogVerbose("tappedView")
        if tapRec.state == .recognized {
            if settingsView != nil, let view = settingsView?.view {
                let pos = tapRec.location(in: view)
                if view.frame.contains(pos) == false {
                    hideSettingsView()
                }
                return
            }
            if previewLayer != nil || backPreviewLayer != nil {
                let touchPoint = tapRec.location(in: view)
                let (focusPoint, postion) = getFocusTarget(touchPoint)

                DDLogVerbose("tap focus point (x,y): \(focusPoint?.x ?? -1.0) \(focusPoint?.y ?? -1.0)")
                guard focusPoint != nil else {
                    return
                }
                Focus_Label.isHidden = true
                showFocusView(at: touchPoint)
                streamer?.continuousFocus(at: focusPoint!, position: postion)
            }
        }
    }
    
    @objc func longPressedView() {
        //DDLogVerbose("longPressedView")
        if previewLayer != nil || backPreviewLayer != nil {
            let touchPoint = longPressRec.location(in: view)
            if Broadcast_Button.frame.contains(touchPoint) {
                if isBroadcasting && longPressRec.state == .began,
                   let feedback = haptics as? UIImpactFeedbackGenerator {
                    feedback.impactOccurred()
                }
                if ( longPressRec.state == .recognized) {
                    Broadcast_LongTap(Broadcast_Button)
                }
                return
            }
        if longPressRec.state == .recognized {
                let (focusPoint, postion) = getFocusTarget(touchPoint)
                DDLogVerbose("long tap focus point (x,y): \(focusPoint?.x ?? -1.0) \(focusPoint?.y ?? -1.0)")
                guard focusPoint != nil else {
                    return
                }
                Focus_Label.isHidden = false
                showFocusView(at: touchPoint, color: UIColor.yellow.cgColor)
                streamer?.autoFocus(at: focusPoint!, position: postion)
            }
        }
    }
    
    func getFocusTarget(_ touchPoint: CGPoint) -> (CGPoint?, AVCaptureDevice.Position) {
        var focusPoint: CGPoint?
        var position: AVCaptureDevice.Position = .unspecified
        var previewPosition: MultiCamPicturePosition = streamer?.previewPositionPip ?? .off
        guard let backPreview = backPreviewLayer ?? previewLayer else { return (focusPoint, position) }
        var withinFront = false
        if let frontPreview = frontPreviewLayer {
            if previewPosition == .left_front || previewPosition == .left_back {
                withinFront = frontPreview.frame.contains(touchPoint)
            } else if previewPosition != .off {
                withinFront = (previewPosition == .pip_front && frontPreview.frame.contains(touchPoint)) || (previewPosition == .pip_back && !backPreview.frame.contains(touchPoint))
            }
            position = withinFront ? .front : .back
            if withinFront {
                let fpConvereted = view.layer.convert(touchPoint, to: frontPreview)
                focusPoint = frontPreview.captureDevicePointConverted(fromLayerPoint: fpConvereted)
                previewPosition = streamer?.previewPosition ?? .off
            }
        }
        if focusPoint == nil {
            let fpConvereted = view.layer.convert(touchPoint, to: backPreview)
            focusPoint = backPreview.captureDevicePointConverted(fromLayerPoint: fpConvereted)
        }
        if focusPoint == nil || focusPoint!.x < 0.0 || focusPoint!.x > 1.0 || focusPoint!.y < 0.0 || focusPoint!.y > 1.0 {
            return (nil, .unspecified)
        }
        if position == .unspecified {
            switch previewPosition {
            case .pip_back:
                position = .back
            case .pip_front:
                position = .front
            default:
                position = .unspecified
            }
        }
        if streamer?.canFocus(position: position) != true {
            return (nil, .unspecified)
        }
        return (focusPoint, position)
    }

    @objc func pinchHandler(recognizer: UIPinchGestureRecognizer) {
        guard let streamer = streamer, streamer.maxZoomFactor > 1 else { return }
        let oldZoom = zoomFactor
        zoomFactor = recognizer.scale * zoomFactor
        zoomFactor = max(1, min(zoomFactor, streamer.maxZoomFactor))
        let sw = streamer.getSwitchZoomFactors()
        if sw.contains(where: { (oldZoom < $0) != (zoomFactor < $0) } ) {
            if let feedback = haptics as? UIImpactFeedbackGenerator {
                feedback.impactOccurred()
            }
        }
        DDLogVerbose("zoom=\(zoomFactor)")
        streamer.zoomTo(factor: zoomFactor)
        zoomIndicator?.zoom = zoomFactor
        recognizer.scale = 1

    }
    
    // Start/stop broadcast on volume keys
    @objc func volumeChanged(_ notification: NSNotification) {
        if !Settings.sharedInstance.volumeKeysCapture {
            return
        }
        guard let info = notification.userInfo,
            let volume = info["AVSystemController_AudioVolumeNotificationParameter"] as? Float,
            let reason = info["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String,
            reason == "ExplicitVolumeChange"
        else {
            return
        }

        DDLogVerbose("volume: \(volume)")
        let now = CACurrentMediaTime()
        defer {
            volumeChangeTime = now
        }
        if now - volumeChangeTime < 1.0 {
            return
        }
        if !isBroadcasting {
            startBroadcast()
        } else {
            stopBroadcast()
        }
    }
    
    //MARK: Adaptive bitrate
    func createStreamConditioner() {
        guard let streamer = self.streamer else {
            return
        }
        switch Settings.sharedInstance.abrMode {
        case 1:
            streamConditioner = StreamConditionerMode1(streamer: streamer)
        case 2:
            streamConditioner = StreamConditionerMode2(streamer: streamer)
        case 3:
            streamConditioner = StreamConditionerMode3(streamer: streamer)
        default:
            break
        }
    }
    
    func photoSaved(fileUrl: URL) {
        let dest = Settings.sharedInstance.recordStorage
        cloudUtils.movePhoto(fileUrl: fileUrl, to: dest)
        if dest == .local {
            let message = String.localizedStringWithFormat(NSLocalizedString("%@ saved to app's documents folder.", comment: ""), fileUrl.lastPathComponent)
            Toast(text: message, theme: .success)
        }
    }
    
    func videoSaved(fileUrl: URL) {
        let dest = Settings.sharedInstance.recordStorage
        //Can't put audio in photo library
        if !(fileUrl.pathExtension == "m4a" && dest == .photoLibrary) {
            cloudUtils.moveVideo(fileUrl: fileUrl, to: dest)
        }
    }
    
    func videoRecordStarted() {
        let duration = Double(Settings.sharedInstance.recordDuration)
        if duration > 0 && recordDurationTImer?.isValid != true {
            let offset = 0.5
            //Trigger switch slighly earlier to made more consistent to key frames
            let firstTime = Date(timeIntervalSinceNow: (duration - offset))
            recordDurationTImer = Timer(fireAt: firstTime, interval: duration, target: self, selector: #selector(self.restartRecord), userInfo: nil, repeats: true)
            RunLoop.main.add(recordDurationTImer!, forMode: .common)
        }
    }
    
    // MARK: CloudNotificationDelegate functions
    func movedToCloud(source: URL) {
        let ext = source.pathExtension
        if ext == "jpg" || ext == "heic" {
            let name = source.lastPathComponent
            Toast(text: String.localizedStringWithFormat(NSLocalizedString("%@ saved to iCloud", comment: ""), name), theme: .success)
        }
    }
    
    func movedToPhotos(source: URL) {
        let ext = source.pathExtension
        if ext == "jpg" || ext == "heic" {
            let album = cloudUtils.photoAlbumName ?? ""
            let name = source.lastPathComponent
            Toast(text: String.localizedStringWithFormat(NSLocalizedString("%@ saved to \"%@\" album in Photos", comment: ""), name, album), theme: .success)
        }
    }
    
    func moveToPhotosFailed(source: URL) {
        Toast(text: NSLocalizedString("Saving to Photos failed, stored in to app's documents folder instead", comment: ""), theme: .error)
    }
    
    func moveToCloudFailed(source: URL) {
        Toast(text: NSLocalizedString("Saving to iCloud failed, stored in to app's documents folder instead", comment: ""), theme: .error)
    }
}

//MARK:- hide and show multi cam
extension ViewController {
    
    func secondaryFeedHideNShow() {
        DDLogVerbose("ViewController::startCapture")
        
        guard canStartCapture else {
            return
        }
        do {
            let settings = Settings.sharedInstance
            let audioOnly = settings.radioMode
            canStartCapture = false
            
            removePreview()
            
            DispatchQueue.main.async {
           //     self.hideUI()
                self.hideStatusMessage()
                self.Indicator.isHidden = false
                self.Indicator.startAnimating()
                
                UIApplication.shared.isIdleTimerDisabled = true
            }
            if #available(iOS 13.0, *) {
                if !audioOnly && StreamerMultiCam.isSupported() {
                    streamer = StreamerMultiCam()
                    isMulticam = streamer != nil
                }
            }
            
            if self.streamer != nil {
                if isSecondaryFeedHide {  if #available(iOS 13.0, *) {
                    self.streamer = StreamerSingleCam()
                    self.isMulticam = false
                } else {
                    
                }
                
                }else {
                    if #available(iOS 13.0, *) {
                        self.streamer = StreamerMultiCam()
                        self.isMulticam = true
                        
                    } else {
                        
                    }
                }
                
            }
            
            streamer?.delegate = self
            if !audioOnly {
                streamer?.videoConfig = settings.videoConfig
            }
            let audioConfig = settings.audioConfig
            streamer?.audioConfig = audioConfig
            if settings.displayVuMeter {
                streamer?.uvMeter = VUMeter
                VUMeter.channels = audioConfig.channelCount
            }
            streamer?.imageLayerPreview = imageLayerPreview
            DispatchQueue.main.async {
                let deviceOrientation = UIApplication.shared.statusBarOrientation
                let newOrientation = self.toAVCaptureVideoOrientation(deviceOrientation: deviceOrientation, defaultOrientation: AVCaptureVideoOrientation.portrait)
                if let stereoOrientation = AVAudioSession.StereoOrientation(rawValue: newOrientation.rawValue) {
                    self.streamer?.stereoOrientation = stereoOrientation
                }
            }
            if settings.streamStartInStandby {
                streamer?.pauseMode = .standby
            }
            try streamer?.startCapture(startAudio: true, startVideo: !audioOnly)
            
            let nc = NotificationCenter.default
            nc.addObserver(
                self,
                selector: #selector(orientationDidChange(notification:)),
                name: UIDevice.orientationDidChangeNotification,
                object: nil)
            
        } catch {
            DDLogError("can't start capture: \(error.localizedDescription)")
            canStartCapture = true
        }
        #if TALKBACK
        player = TalkbackHandler()
        player?.label = Talkback_Label
        player?.start()
        #endif
    }
}
