import UIKit
import SwiftMessages
import AVKit
import CocoaLumberjackSwift
//import SwiftTryCatch

class LocalFileViewController: UITableViewController, CloudNotificationDelegate {
    let fm = FileManager.default
    var fileList: [URL] = []
    var cloudUtils = CloudUtilites()
    var onActionComplete: [String: (Bool) -> Void] = [:]
    var batchUpdate = false
    var batchUpdateFileCount: Int = 0
    var deletedRows: [IndexPath] = []
    private let imageFormats: Set<String> = ["jpg", "jpeg", "heic", "gif", "png", "webp"]
    private let videoFormats: Set<String> = ["mp4", "mov"]
    private let audioFormats: Set<String> = ["m4a"]

    typealias CompletionHandler = (Bool) -> Void
    
    @IBOutlet var toolbar: [UIToolbar]!
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateFileList()
        batchUpdate = false
        batchUpdateFileCount = 0
        cloudUtils.delegate = self
        cloudUtils.activate()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cloudUtils.deactivate()
        cloudUtils.delegate = nil
    }
    
    func updateFileList(forceUpdate: Bool = false) {
        do {
            let localPath = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let count = fileList.count
            fileList = try fm.contentsOfDirectory(at: localPath, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .effectiveIconKey ], options: [.skipsHiddenFiles])
            sortFileList(byAttr: .creationDateKey, descending: true)
            if (forceUpdate || fileList.count != count) {
                tableView.reloadData()
            }
        } catch {
            DDLogVerbose("Get file contents failed")
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if !tableView.isEditing {
            return true
        } else {
            return false
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let source = sender as? UITableViewCell else {return}
        guard let selected = tableView.indexPath(for: source) else { return }
        let i = selected.row
        let url = fileList[i]
        if let dest = segue.destination as? AVPlayerViewController {
            let player = AVPlayer(url: url)
            player.play()
            dest.player = player
        } else {
            if let image = UIImage(contentsOfFile: url.path) {
                DDLogVerbose("Open image: orientation \(image.imageOrientation.rawValue)")
                
                let view = UIImageView(image: image)
                view.contentMode = .scaleAspectFit
                view.isUserInteractionEnabled = true
                let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(LocalFileViewController.pictureTap(_:)))
                view.addGestureRecognizer(tapGestureRecognizer)
                segue.destination.view = view

            } else {
                DDLogVerbose("open failed")
            }
        }
        segue.destination.title = url.lastPathComponent

    }
    
    @objc func pictureTap(_ tapGestureRecognizer: UITapGestureRecognizer) {
        let view = tapGestureRecognizer.view
        view?.removeGestureRecognizer(tapGestureRecognizer)
        navigationController?.dismiss(animated: true, completion: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.allowsMultipleSelectionDuringEditing = true
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let num = fileList.count
        DDLogVerbose("Got \(num) files")
        return num
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let i = indexPath.row
        var cellType: String?
        if i >= fileList.count {
            let cell = tableView.dequeueReusableCell(withIdentifier: "filItem", for: indexPath)
            cell.textLabel?.text = NSLocalizedString("Unknown", comment: "")
            return cell
        }
        let url = fileList[i]
        let ext = url.pathExtension
        if imageFormats.contains(ext) {
            cellType = "photoItem"
        } else if videoFormats.contains(ext) {
            cellType = "videoItem"
        } else if audioFormats.contains(ext) {
            cellType = "audioItem"
        } else {
            cellType = "fileItem"
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: cellType!, for: indexPath)
        cell.textLabel?.text = url.lastPathComponent
        var detailsStr = ""
        if let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .effectiveIconKey]) {
        
            if let date = attrs.creationDate {
                let dateFmt = DateFormatter()
                dateFmt.dateStyle = .medium
                dateFmt.timeStyle = .short
                dateFmt.doesRelativeDateFormatting = true
                detailsStr.append(dateFmt.string(from: date))
                detailsStr.append("\t\t")
            }
            let size = attrs.fileSize ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            detailsStr.append(sizeStr)
        }
        cell.detailTextLabel?.text = detailsStr
        return cell
    }

    func sortFileList(byAttr: URLResourceKey, descending: Bool) {
        fileList = fileList.filter { $0.pathExtension != "sqlite"}
        fileList.sort { (url1, url2) -> Bool in
            var val1:URLResourceValues
            var val2:URLResourceValues
            do {
                val1 = try url1.resourceValues(forKeys: [byAttr])
                val2 = try url2.resourceValues(forKeys: [byAttr])
            } catch {
                return true
            }
            var res = true
            switch byAttr {
            case .fileSizeKey:
                res = val1.fileSize ?? 0 < val2.fileSize ?? 0
            case .creationDateKey where val1.creationDate != nil && val2.creationDate != nil:
                res = val1.creationDate! < val2.creationDate!
            default:
                res = false
            }
            if descending {
                res = !res
            }
            return res
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView,
                            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let i = indexPath.row
        var items: [UIContextualAction] = []
        if i < fileList.count {
            let url = self.fileList[i]
            let cloudItem = UIContextualAction(style: .normal, title: "iCloud") { (action, view, postAction) in
                if self.batchUpdate {
                    postAction(false)
                    return
                }
                self.moveFile(url, to: .iCloud)
                postAction(true)
            }
            cloudItem.backgroundColor = UIColor.systemBlue
            items.append(cloudItem)
            if url.pathExtension != "m4a" {
                let photoItem = UIContextualAction(style: .normal, title: "Photos") { (action, view, postAction) in
                    if self.batchUpdate {
                        postAction(false)
                        return
                    }
                    self.moveFile(url, to: .photoLibrary)
                    postAction(true)
                }
                photoItem.backgroundColor = UIColor.systemGreen
                items.append(photoItem)
            }
            
            let shareItem = UIContextualAction(style: .normal, title: "Share") { (action, view, postAction) in
                let shareController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                let frame = CGRect(origin: view.frame.origin, size: view.frame.size)
                shareController.popoverPresentationController?.sourceView = view.superview
                shareController.popoverPresentationController?.sourceRect = frame

                self.present(shareController, animated: true) {
                    postAction(true)
                }

            }
            items.append(shareItem)
        }
        return UISwipeActionsConfiguration(actions: items)
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteItem = UIContextualAction(style: .destructive, title: "Delete") { (action, view, postAction) in
            let i = indexPath.row
            if i < self.fileList.count && self.batchUpdate == false {
                let url = self.fileList[i]
                do {
                    try self.fm.removeItem(at: url)
                    self.fileList.remove(at: i)
                    postAction(true)
                    self.tryToDeleteRows(at: [indexPath])
                } catch {
                    postAction(false)
                }
            } else {
                postAction(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [deleteItem])
    }
    
    func moveFile(_ url: URL, to: Settings.RecordStorage, handler: CompletionHandler? = nil) {
        if url.pathExtension == "mov" {
            self.cloudUtils.moveVideo(fileUrl: url, to: to)
        } else {
            self.cloudUtils.movePhoto(fileUrl: url, to: to)
        }
        if handler != nil {
            self.onActionComplete[url.absoluteString] = handler
        }
    }
    
    func movedToPhotos(source: URL) {
        onCloudComplete(source: source, target: .photoLibrary, success: true)
    }
    
    func movedToCloud(source: URL) {
        onCloudComplete(source: source, target: .iCloud, success: true)

    }
    
    func moveToPhotosFailed(source: URL) {
        onCloudComplete(source: source, target: .photoLibrary, success: false)
        DispatchQueue.main.async {
            let selected = self.tableView.indexPathsForSelectedRows
            if selected == nil {
                Toast(text: NSLocalizedString("Moving to Photo library failed", comment: ""), theme: .error)
            }
        }
    }
    
    func moveToCloudFailed(source: URL) {
        onCloudComplete(source: source, target: .iCloud, success: false)
        DispatchQueue.main.async {
            let selected = self.tableView.indexPathsForSelectedRows
            if selected == nil {
                Toast(text: NSLocalizedString("Moving to iCloud failed", comment: ""), theme: .error)
            }
        }
    }
    
    func onCloudComplete(source: URL, target: Settings.RecordStorage, success: Bool) {
        if !fileList.contains(source)  {
            DDLogVerbose("Not found")
            return
        }
        
        if onActionComplete.keys.contains(source.absoluteString), let action = onActionComplete[source.absoluteString] {
            action(success)
        } else if !success && !batchUpdate {
            DispatchQueue.main.async {
                self.updateFileList(forceUpdate: true)
            }
            return
        }
        if batchUpdate {
            if let i = fileList.firstIndex(of: source) {
                let pos = IndexPath(row: i, section: 0)
                self.deletedRows.append(pos)
            }
        } else {
            DispatchQueue.main.async {
                if let i = self.fileList.firstIndex(of: source) {
                    let pos = IndexPath(row: i, section: 0)
                    self.fileList.remove(at: i)
                    self.tryToDeleteRows(at: [pos])
                } else {
                    self.updateFileList(forceUpdate: true)
                }
            }
        }
    }
    
    func selectAll() {
        guard let tv = tableView else {return}
        DispatchQueue.main.async {
            let allSelected = tv.indexPathsForSelectedRows?.count == self.fileList.count
            for i in 0..<self.fileList.count {
                let path = IndexPath(row: i, section: 0)
                if allSelected {
                    tv.deselectRow(at: path, animated: false)
                } else {
                    tv.selectRow(at: path, animated: false, scrollPosition: .none)
                }
            }
        }
    }
    
    func deleteSelected() {
        let selected = tableView.indexPathsForSelectedRows
        var deletedRows: [IndexPath] = []
        var deletedUrls: [URL] = []
        if (selected?.count ?? 0) == 0 { return }
        var failCount:Int = 0
        for indexPath in selected! {
            do {
                let row = indexPath.row
                if row < fileList.count {
                    let url = fileList[row]
                    try fm.removeItem(at: url)
                    deletedRows.append(indexPath)
                    deletedUrls.append(url)
                } else {
                    failCount += 1
                }
            } catch {
                failCount += 1
            }
        }
        fileList.removeAll(where: { deletedUrls.contains($0) } )
        self.tryToDeleteRows(at: deletedRows)
        if failCount > 0 {
            Toast(text: NSLocalizedString("Some files did not deleted", comment: ""), theme: .warning)
        } else {
            let num = deletedRows.count
            Toast(text: NSLocalizedString("Deleted \(num) files", comment: ""), theme: .success)
            DispatchQueue.main.async {
                self.navigationController?.setToolbarHidden(true, animated: true)
                self.tableView.setEditing(false, animated: true)
            }
        }
    }
    
    func shareSelected(button: UIBarButtonItem) {
        if batchUpdate {
            Toast(text: NSLocalizedString("Another operaton is in process, please wait for completion", comment: ""), theme: .error)
            return
        }
        guard let selected = tableView.indexPathsForSelectedRows else { return }
        var selectedUrls: [URL] = []
        for indexPath in selected {
            let row = indexPath.row
            if row >= fileList.count {
                continue
            }
            selectedUrls.append(fileList[row])
            DDLogInfo("url: \(fileList[row].absoluteString)")
        }
        if selectedUrls.isEmpty { return }

        let shareController = UIActivityViewController(activityItems: selectedUrls, applicationActivities: nil)
        shareController.popoverPresentationController?.barButtonItem = button
        present(shareController, animated: true)

    }
    
    func moveSelected(to target: Settings.RecordStorage) {
        if batchUpdate {
            Toast(text: NSLocalizedString("Another operaton is in process, please wait for completion", comment: ""), theme: .error)
            return
        }
        let selected = tableView.indexPathsForSelectedRows
        if (selected?.count ?? 0) == 0 { return }
        var failCount = 0
        var remainCount = selected?.count ?? 0
        batchUpdateFileCount = fileList.count
        batchUpdate = true
        deletedRows.removeAll()
        for indexPath in selected! {
            let row = indexPath.row
            if row >= fileList.count {
                remainCount -= 1
                failCount += 1
                continue
            }
            let url = fileList[row]
            moveFile(url, to: target) { (success) in
                remainCount -= 1
                if !success {
                    failCount += 1
                }
                if remainCount == 0 {
                    DispatchQueue.main.async {
                        self.onMoveComplete(to: target, isFailed: failCount > 0)
                        self.batchUpdate = false
                    }
                }
            }
        }
    }
    
    private func onMoveComplete(to target: Settings.RecordStorage, isFailed: Bool) {
        let removeIdx = self.deletedRows.sorted { $1.row < $0.row } //Remove from last to make index consistent
        for idx in removeIdx {
            fileList.remove(at:idx.row)
        }
        if batchUpdateFileCount == self.fileList.count {
            //Check file list didn't changed beside this operation
            tryToDeleteRows(at: removeIdx)
        } else {
            updateFileList(forceUpdate: true)
        }
        deletedRows.removeAll()
        batchUpdateFileCount = 0
        tableView.setEditing(false, animated: true)
        navigationController?.setToolbarHidden(true, animated: true)

        let textMessage: String
        if isFailed {
            textMessage = "Some files did not moved"
        } else {
            if target == .iCloud {
                textMessage = "Files moved to iCloud"
            } else {
                textMessage = "Files moved to Photo album"
            }
        }
        Toast(text: NSLocalizedString(textMessage, comment: ""), theme: isFailed ? .warning : .success)
    }
    
    private func tryToDeleteRows(at indexPaths: [IndexPath]) {
        SwiftTryCatch.try({
            self.tableView.deleteRows(at: indexPaths, with: .automatic)
        }, catch: { (error) in
            self.tableView.reloadData()
            DDLogError("Table operation failed, perform full refresh instead")
        }, finally: {
            
        })
    }
    
    var anySelected: Bool {
        return tableView.isEditing && tableView.indexPathForSelectedRow != nil
    }

}
