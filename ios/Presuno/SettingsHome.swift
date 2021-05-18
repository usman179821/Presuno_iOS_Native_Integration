import CocoaLumberjackSwift
import Eureka
import GRDB

class OptionsHomeViewController: FormViewController {
    
    var alertController: UIAlertController?
    
    let versionText =
"""
© Presuno, LLC
Visit Presuno.com for more

"""
    let resetAppSettingsText = "Your connections will remain untouched but all other settings will be reset to default"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = NSLocalizedString("Settings", comment: "")
        let connSection = Section()
            <<< ButtonRow() { row in
                row.title = NSLocalizedString("Connections", comment: "")
                row.presentationMode = .segueName(segueName: "openConnectionsList", onDismiss: nil)
        }
        #if TALKBACK
         connSection <<< ButtonRow() { row in
                row.title = NSLocalizedString("Talkback", comment: "")
                row.presentationMode = .segueName(segueName: "openTalkbackSettings", onDismiss: nil)
        }
        #endif
        connSection <<< ButtonRow() { row in
               row.title = NSLocalizedString("Presuno Grove", comment: "")
            row.presentationMode = .segueName(segueName: "openGrove", onDismiss: nil)
        }

        form +++ connSection

        form +++ Section()
            <<< ButtonRow() { row in
                  row.title = NSLocalizedString("Video", comment: "")
               row.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                   return VideoSettingsViewController(bundle: "Video")
               }, onDismiss: nil)
               
            }
            <<< ButtonRow() { row in
                  row.title = NSLocalizedString("Audio", comment: "")
               row.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                   return AudioSettingsViewController(bundle: "Audio")
               }, onDismiss: nil)
            }
            <<< ButtonRow() { row in
                     row.title = NSLocalizedString("Record", comment: "")
                  row.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                      return RecordSettingsViewController(bundle: "Record")
                  }, onDismiss: nil)
               }
            <<< ButtonRow() { row in
                  row.title = NSLocalizedString("Display", comment: "")
               row.presentationMode = .show(controllerProvider: ControllerProvider.callback {
                   return DisplaySettingsViewController(bundle: "Display")
               }, onDismiss: nil)
            }
            <<< ButtonRow() { row in
                row.title = NSLocalizedString("Overlays", comment: "")
                row.presentationMode = .segueName(segueName: "openLayersList", onDismiss: nil)
            }


            <<< ButtonRow() { row in
                     row.title = NSLocalizedString("Reset app settings", comment: "")
            }.onCellSelection({ (_, _) in
                let message = NSLocalizedString(self.resetAppSettingsText, comment: "")
                let alert = UIAlertController(title: NSLocalizedString("Reset App settings", comment: ""), message: message, preferredStyle: .alert)
                
                let actionYes = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { (_) in
                    Settings.sharedInstance.resetDefaults()
                    Toast(text: "Settings have been reset to default", theme: .success, layout: .messageView)
                })
                alert.addAction(actionYes)
                let actionNo = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
                alert.addAction(actionNo)
                self.present(alert, animated: true)
                
            })
            .cellUpdate { cell, row in
                cell.textLabel?.textAlignment = .natural
            }
        form +++ Section()
            <<< ButtonRow() { row in
                row.title = NSLocalizedString("Manage saved files", comment: "")
                }
                .cellUpdate { cell, row in
                    cell.textLabel?.textAlignment = .natural
                }
                .onCellSelection { _, _ in self.openFileManager() }
        
      //  let ver = versionText.appending(getVersionString())
//        form +++ Section("About Presuno Broadcaster")
//            <<< ButtonRow() {
//                $0.title = NSLocalizedString(ver, comment: "")
//            }.cellSetup{ (cell, row) in
//                cell.textLabel?.numberOfLines = 0
//                cell.textLabel?.font = .systemFont(ofSize: 16)
//            }.onCellSelection { _,_ in
//                if let url = URL(string: "https://softvelum.com/mobile/") {
//                    UIApplication.shared.open(url)
//                }
//            }.cellUpdate({ (cell, row) in
//                //Eureka change these attributes after setup, so set it here
//                cell.textLabel?.textAlignment = .natural
//                cell.textLabel?.textColor = nil
//            })
    }
        
    func getVersionString() -> String {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let resourceFileDictionary = NSDictionary(contentsOfFile: path) else { return "" }
        
        let version = resourceFileDictionary.value(forKey: "CFBundleShortVersionString") as! String
        let build = resourceFileDictionary.value(forKey: "CFBundleVersion") as! String

        let ver = String.localizedStringWithFormat(NSLocalizedString("Version %@ build %@", comment: ""), version, build)
        
        return ver
    }

    func openSettings() {
        let settingsUrl = URL(string: UIApplication.openSettingsURLString)
        if let url = settingsUrl {
            UIApplication.shared.open(url, options: [:])
        }
    }
    
    func openFileManager() {
        performSegue(withIdentifier: "openFileManager", sender: self)
    }
    
    
    func resetSettings() {
        
    }
  

}
