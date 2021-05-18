import UIKit
import CocoaLumberjackSwift

class FileManagerController: UITabBarController, UITabBarControllerDelegate {
    
    @IBOutlet weak var editButton: UIBarButtonItem!
    
    @IBOutlet weak var itmSelectAll: UIBarButtonItem!
    @IBOutlet weak var itmDelete: UIBarButtonItem!
    @IBOutlet weak var itmDownload: UIBarButtonItem!
    @IBOutlet weak var itmSpacer: UIBarButtonItem!
    @IBOutlet weak var itmSpacerLeft: UIBarButtonItem!
    @IBOutlet weak var itmMoveTo: UIBarButtonItem!
    @IBOutlet weak var itmFixedSpacer: UIBarButtonItem!
    
    @IBOutlet weak var itmCloudActions: UIBarButtonItem!
    @objc public dynamic var cloudQuery = NSMetadataQuery()
    var nc = NotificationCenter.default
    var queue: OperationQueue?
    var searchInProgress = false
    var gathered = false
    var observation: NSKeyValueObservation?
    var havePendingCloudChanges = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        delegate = self
        startSearch()
    }
    
    public var cloudUpdating: Bool {
        return gathered && !searchInProgress
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSearch()
        navigationController?.setToolbarHidden(true, animated: animated)
    }
    
    @IBAction func selectAllAction(_ sender: Any) {
        if let localFile = self.selectedViewController as? LocalFileViewController {
            localFile.selectAll()
        } else if let cloudFile = self.selectedViewController as? CloudFileViewController {
            cloudFile.selectAll()
        }
    }
    
    @IBAction func deleteAction(_ sender: UIBarButtonItem) {
        if let localFile = self.selectedViewController as? LocalFileViewController {
            localFile.deleteSelected()
            localFile.setEditing(false, animated: false)
        } else if let cloudFile = self.selectedViewController as? CloudFileViewController {
            cloudFile.confirmDelete()
        }
    }
    
    @IBAction func moveToAction(_ sender: UIBarButtonItem) {
        if let localFile = self.selectedViewController as? LocalFileViewController {
            if !localFile.anySelected { return }
        }
        let moveMenu = UIAlertController(title: "", message: "Local file operation", preferredStyle: .actionSheet)
        if let popoverController = moveMenu.popoverPresentationController { //This required to present action sheet on iPad
            if let originView = sender.value(forKey: "view") as? UIView {
                let rect = originView.frame
                //Specify origin (toolbar) and button position
                popoverController.sourceView = self.navigationController!.toolbar
                popoverController.sourceRect = rect
                popoverController.permittedArrowDirections = [.down]
            }
        }
        let moveToCloud = UIAlertAction(title: "Move to iCloud", style: .default) { (_ :UIAlertAction) in
            if let localFile = self.selectedViewController as? LocalFileViewController {
                localFile.moveSelected(to: .iCloud)
            }
        }
        moveMenu.addAction(moveToCloud)

        let moveToPhotos = UIAlertAction(title: "Move to Photo Album", style: .default) { (_ :UIAlertAction) in
            if let localFile = self.selectedViewController as? LocalFileViewController {
                localFile.moveSelected(to: .photoLibrary)
            }
        }
        moveMenu.addAction(moveToPhotos)
        
        let share = UIAlertAction(title: "Share", style: .default) { (_ :UIAlertAction) in
            if let localFile = self.selectedViewController as? LocalFileViewController {
                localFile.shareSelected(button: self.itmMoveTo)
            }
        }
        moveMenu.addAction(share)

        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            if let localFile = self.selectedViewController as? LocalFileViewController {
                localFile.setEditing(false, animated: true)
                self.navigationController?.setToolbarHidden(true, animated: true)
            }
        }
        moveMenu.addAction(cancel)
        selectedViewController?.present(moveMenu, animated: true, completion: nil)
    }
    
    
    @IBAction func cloudAction(_ sender: UIBarButtonItem) {
        if let cloudFile = self.selectedViewController as? CloudFileViewController {
            if !cloudFile.anySelected { return }
        }
        let moveMenu = UIAlertController(title: "", message: "iCloud files operation", preferredStyle: .actionSheet)
        
        if let popoverController = moveMenu.popoverPresentationController { //This required to present action sheet on iPad
            if let originView = sender.value(forKey: "view") as? UIView {
                let rect = originView.frame
                //Specify origin (toolbar) and button position
                popoverController.sourceView = self.navigationController!.toolbar
                popoverController.sourceRect = rect
                popoverController.permittedArrowDirections = [.down]
            }
        }
        let download = UIAlertAction(title: "Download", style: .default) { (_ :UIAlertAction) in
            if let cloudFile = self.selectedViewController as? CloudFileViewController {
                cloudFile.downloadSelected()
            }
        }
        moveMenu.addAction(download)

        let moveToLocal = UIAlertAction(title: "Move to Presuno", style: .default) { (_ :UIAlertAction) in
            if let cloudFile = self.selectedViewController as? CloudFileViewController {
                cloudFile.moveSelected()
            }

        }
        moveMenu.addAction(moveToLocal)
        
        let purge = UIAlertAction(title: "Purge local", style: .default) { (_ :UIAlertAction) in
            if let cloudFile = self.selectedViewController as? CloudFileViewController {
                cloudFile.purgeSelected()
            }
        }
        moveMenu.addAction(purge)
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            if let cloudFile = self.selectedViewController as? CloudFileViewController {
                cloudFile.setEditing(false, animated: true)
                self.navigationController?.setToolbarHidden(true, animated: true)
            }
        }
        moveMenu.addAction(cancel)
        selectedViewController?.present(moveMenu, animated: true, completion: nil)
    }
    
    @IBAction func editAction(_ sender: UIBarButtonItem) {
        if let aciveView = self.selectedViewController as? UITableViewController {
            let editing = aciveView.isEditing
            navigationController?.setToolbarHidden(editing, animated: true)
            if aciveView.isKind(of: LocalFileViewController.self) {
                navigationController?.toolbar.items = [itmSelectAll, itmSpacerLeft, itmMoveTo, itmSpacer, itmDelete]
            } else {
                navigationController?.toolbar.items = [itmSelectAll, itmSpacerLeft, itmCloudActions, itmSpacer, itmDelete]

            }
            aciveView.setEditing(!editing, animated: true)
        }
    }
    
    func startSearch() {
        if queue == nil {
            queue = OperationQueue()
            queue?.maxConcurrentOperationCount = 1
        }
        if cloudQuery.isStarted {
            DDLogVerbose("Already started")
            return
        }
        cloudQuery.operationQueue = queue
        cloudQuery.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        //cloudQuery.predicate = NSPredicate(format: "%K like[cd] %@", NSMetadataItemFSNameKey, "*.mov")
        //cloudQuery.sortDescriptors = [NSSortDescriptor(key: "foo", ascending: false!)] - this doesn't work anyway
        
        searchInProgress = true
        queue!.addOperation({
            if (self.cloudQuery.start()) {
                DDLogVerbose("Search started")
            } else {
                DDLogVerbose("Don't want to search")

            }
        })
        nc.addObserver(forName: NSNotification.Name.NSMetadataQueryDidStartGathering, object: cloudQuery, queue: queue) { _ in
            self.gathered = false
        }
        nc.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: cloudQuery, queue: queue) { (notification) in
            DDLogVerbose("Metadata update")
            DispatchQueue.main.async {
                if let cloudFile = self.selectedViewController as? CloudFileViewController {
                    cloudFile.refreshData(notification: notification)
                } else {
                    self.havePendingCloudChanges = true
                }
            }
        }
        nc.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: cloudQuery, queue: queue) { _ in
            DDLogVerbose("Search finished")
            self.gathered = true
            self.onFinishGahtering()
        }
    }

    func onFinishGahtering() {
        searchInProgress = false
        DispatchQueue.main.async {
            if let cloudFile = self.selectedViewController as? CloudFileViewController {
                cloudFile.cloudQueryComplete()
            }
        }
    }
    
    func stopSearch() {
        cloudQuery.stop()
    }

    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let cloudView = viewController as? CloudFileViewController {
            cloudView.tableView.reloadData()
            havePendingCloudChanges = false
        }
        title = viewController.title
    }

}
