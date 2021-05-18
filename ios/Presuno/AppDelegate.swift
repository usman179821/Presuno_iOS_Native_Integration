import CocoaLumberjackSwift
import Network
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    weak var mainView: ApplicationStateObserver?
    var onConnectionsUpdate: (()->Void)?
    
    lazy private(set) var monitor = NWPathMonitor()
    var canConnect = true


    // Handle "Presuno:" URLs. For custom app based on Presuno sdk remove this function.
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        let parser = DeepLink.sharedInstance
        parser.parseDeepLink(request: url)
        DDLogVerbose("didFinishLaunchingWithUrl \(url.absoluteString)")
        return true
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        try! setupDatabase(application)
        #if DEBUG
        dynamicLogLevel = DDLogLevel.all
        #else
        dynamicLogLevel = DDLogLevel.error
        #endif
        DDLog.add(DDOSLogger.sharedInstance)

//        let fileLogger: DDFileLogger = DDFileLogger() // File Logger
//        fileLogger.rollingFrequency = TimeInterval(60*60*24)  // 24 hours
//        fileLogger.logFileManager.maximumNumberOfLogFiles = 7
//        DDLog.add(fileLogger)

        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                DDLogVerbose("Yay! We have internet!")
                self?.canConnect = true
            } else {
                DDLogVerbose("No internet connection?")
                self?.canConnect = false
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))

        startAudio()

        DDLogVerbose("didFinishLaunchingWithOptions")
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        DDLogVerbose("applicationWillResignActive")
        mainView?.applicationWillResignActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        DDLogVerbose("applicationDidEnterBackground")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        DDLogVerbose("applicationWillEnterForeground")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        DDLogVerbose("applicationDidBecomeActive")
        mainView?.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        DDLogVerbose("applicationWillTerminate")
        stopAudio()
    }
    
    // MARK: - Handle audio sessions
    struct holder {
        static var isAudioSessionActive = false
    }
    
    func startAudio() {
        // Each app running in iOS has a single audio session, which in turn has a single category. You can change your audio session’s category while your app is running.
        // You can refine the configuration provided by the AVAudioSessionCategoryPlayback, AVAudioSessionCategoryRecord, and AVAudioSessionCategoryPlayAndRecord categories by using an audio session mode, as described in Audio Session Modes.
        // https://developer.apple.com/reference/avfoundation/avaudiosession
        
        // While AVAudioSessionCategoryRecord works for the builtin mics and other bluetooth devices it did not work with AirPods. Instead, setting the category to AVAudioSessionCategoryPlayAndRecord allows recording to work with the AirPods.

        // AVAudioSession is completely managed by application, libmbl2 doesn't modify AVAudioSession settings.

        observeAudioSessionNotifications(true)
        activateAudioSession()
    }
    
    func activateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetooth])
            try audioSession.setActive(true)
            holder.isAudioSessionActive = true
        } catch {
            holder.isAudioSessionActive = false
            DDLogError("activateAudioSession: \(error.localizedDescription)")
        }
        DDLogVerbose("\(#function) isActive:\(holder.isAudioSessionActive), AVAudioSession Activated with category:\(audioSession.category)")
    }
    
    class var isAudioSessionActive: Bool {
        return holder.isAudioSessionActive
    }
    
    func stopAudio() {
        deactivateAudioSession()
        observeAudioSessionNotifications(false)
    }
    
    func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            holder.isAudioSessionActive = false
        } catch {
            DDLogError("deactivateAudioSession: \(error.localizedDescription)")
        }
        DDLogVerbose("\(#function) isActive:\(holder.isAudioSessionActive)")
    }
    
    func observeAudioSessionNotifications(_ observe:Bool) {
        let audioSession = AVAudioSession.sharedInstance()
        let center = NotificationCenter.default
        if observe {
            center.addObserver(self, selector: #selector(handleAudioSessionInterruption(notification:)), name: AVAudioSession.interruptionNotification, object: audioSession)
            center.addObserver(self, selector: #selector(handleAudioSessionMediaServicesWereLost(notification:)), name: AVAudioSession.mediaServicesWereLostNotification, object: audioSession)
            center.addObserver(self, selector: #selector(handleAudioSessionMediaServicesWereReset(notification:)), name: AVAudioSession.mediaServicesWereResetNotification, object: audioSession)
        } else {
            center.removeObserver(self, name: AVAudioSession.interruptionNotification, object: audioSession)
            center.removeObserver(self, name: AVAudioSession.mediaServicesWereLostNotification, object: audioSession)
            center.removeObserver(self, name: AVAudioSession.mediaServicesWereResetNotification, object: audioSession)
        }
    }
    
    @objc func handleAudioSessionInterruption(notification: Notification) {
        
        if let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber, let interruptionType = AVAudioSession.InterruptionType(rawValue: UInt(value.intValue)) {
            
            let isAppActive = UIApplication.shared.applicationState == UIApplication.State.active ? true:false
            DDLogVerbose("\(#function) [Main:\(Thread.isMainThread)] [Active:\(isAppActive)] AVAudioSession Interruption:\(String(describing: notification.object)) withInfo:\(String(describing: notification.userInfo))")
            
            switch interruptionType {
            case .began:
                deactivateAudioSession()
            case .ended:
                activateAudioSession()
            default:
                break
            }
        }
    }
    
    // MARK: Respond to the media server crashing and restarting
    // https://developer.apple.com/library/archive/qa/qa1749/_index.html
    
    @objc func handleAudioSessionMediaServicesWereLost(notification: Notification) {
        DDLogVerbose("\(#function) [Main:\(Thread.isMainThread)] Object:\(String(describing: notification.object)) withInfo:\(String(describing: notification.userInfo))")
        mainView?.mediaServicesWereLost()
    }
    
    @objc func handleAudioSessionMediaServicesWereReset(notification: Notification) {
        DDLogVerbose("\(#function) [Main:\(Thread.isMainThread)] Object:\(String(describing: notification.object)) withInfo:\(String(describing: notification.userInfo))")
        deactivateAudioSession()
        activateAudioSession()
        mainView?.mediaServicesWereReset()
    }
    
}
