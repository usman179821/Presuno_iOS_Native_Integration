import UIKit
import SwiftMessages
import CocoaLumberjackSwift

class CloudFileViewController: UITableViewController {

    var imgCloud: UIImage?
    var imgCloudUploading: UIImage?
    var imgCloudDownloading: UIImage?
    var imgCloudDownloaded: UIImage?
    var imgCloudUploaded: UIImage?
    var imgCloudError: UIImage?
    weak var cloudQuery: NSMetadataQuery?
    var cloudUpdating = false
    var rowMapping: [Date: Int] = [:]
    var rowOrderMap: [Int] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        if let mainView = parent as? FileManagerController {
            cloudQuery = mainView.cloudQuery
            cloudUpdating = mainView.searchInProgress
        }
        if #available(iOS 13.0, *) {
            imgCloud  = UIImage(systemName: "icloud")
            imgCloudUploading  = UIImage(systemName: "icloud.and.arrow.up")
            imgCloudDownloading  = UIImage(systemName: "icloud.and.arrow.down")
            imgCloudDownloaded  = UIImage(systemName: "icloud.fill")
            imgCloudError  = UIImage(systemName: "xmark.icloud")
        }
        tableView.allowsMultipleSelectionDuringEditing = true
    }
        
    override func viewWillAppear(_ animated: Bool) {
        updateMapping()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if cloudUpdating { return 1 }
        let count = cloudQuery?.resultCount ?? 0
        DDLogInfo("Has \(count) files")
        return count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let i = indexPath.row
        if cloudUpdating || cloudQuery == nil {
            return tableView.dequeueReusableCell(withIdentifier: "updating", for: indexPath)
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "cloudItem", for: indexPath)
        guard let query = cloudQuery else {return cell}
        
        let metadata = query.result(at: rowOrderMap[i]) as? NSMetadataItem

        let name = metadata?.value(forAttribute: NSMetadataItemFSNameKey) as? String
        cell.textLabel?.text = name ?? "Unknown"
        cell.accessoryType = .none
        let size: Int = metadata?.value(forAttribute: NSMetadataItemFSSizeKey) as? Int ?? 0
        var detailsStr = ""
        if let date = metadata?.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date {
            let dateFmt = DateFormatter()
            dateFmt.dateStyle = .medium
            dateFmt.timeStyle = .short
            dateFmt.doesRelativeDateFormatting = true
            detailsStr.append(dateFmt.string(from: date))
            detailsStr.append("\t\t")
        }
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        detailsStr.append(sizeStr)
        let downStatus = metadata?.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        if metadata?.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? Error != nil {
            if imgCloudError != nil {
                cell.imageView!.image = imgCloudError
            } else {
                detailsStr.append(" [Error]")
            }
            cell.accessoryType = .detailButton
        } else if metadata?.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool == true {
            cell.imageView!.image = imgCloudUploading
            let percent = metadata?.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double ?? 0.0
            let uploadSize = Double(size) * percent / 100.0
            let uploadStr = ByteCountFormatter.string(fromByteCount: Int64(uploadSize), countStyle: .file)
            detailsStr = String(format: "Uploading %@ / %@", uploadStr, sizeStr)
        } else if downStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
            let percent = metadata?.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0.0
            if (percent == 0.0) {
                if imgCloud != nil {
                    cell.imageView!.image = imgCloud
                } else {
                    detailsStr.append(" [iCloud only]")
                }
            } else {
                let downloadSize = Double(size) * percent / 100.0
                let downloadStr = ByteCountFormatter.string(fromByteCount: Int64(downloadSize), countStyle: .file)
                detailsStr = String(format: "Downloading %@ / %@", downloadStr, sizeStr)
                cell.imageView!.image = imgCloudDownloading
            }
        } else {
            cell.imageView!.image = imgCloudDownloaded
        }
        cell.detailTextLabel?.text = detailsStr

        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let i = indexPath.row
        if let metadata = cloudQuery?.result(at: rowOrderMap[i]) as? NSMetadataItem, let error = metadata.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
            let errorAlert = UIAlertController(title: "iCloud Error", message: error.localizedDescription, preferredStyle: .alert)
            let cancel = UIAlertAction(title: "Done", style: .cancel)
            errorAlert.addAction(cancel)

            present(errorAlert, animated: true, completion: nil)
        }
    }
    
    
    func cloudQueryComplete() {
        if (cloudUpdating) {
            cloudQuery?.disableUpdates()
            updateMapping()
            tableView.reloadData()
            cloudUpdating = false
            cloudQuery?.enableUpdates()
        }
    }
    
    func updateMapping() {
        rowMapping.removeAll()
        setOrderMap()
        if (cloudQuery?.resultCount ?? 0) == 0 { return }
        for i in 0..<cloudQuery!.resultCount {
            if let metadata = cloudQuery!.result(at: i) as? NSMetadataItem, let createDate = metadata.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date {
                rowMapping[createDate] = rowOrderMap[i]
            }
        }
    }
    
    func refreshData(notification: Notification) {
        let addedItems     = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]
        let remItems       = notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem]
        let changedItems   = notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]
        DDLogVerbose(String(format: "Added %d changed %d removed %d", addedItems?.count ?? 0, changedItems?.count ?? 0, remItems?.count ?? 0))
        cloudQuery?.disableUpdates()
        self.tableView.beginUpdates()
        let dates = rowMapping.keys.sorted { (d1, d2) -> Bool in
            return d1 > d2
        }
        if (remItems?.count ?? 0) > 0 {
            var remRows: [IndexPath] = []
            for del in remItems! {
                    if let createDate = del.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date {
                        if let idx = dates.firstIndex(of:createDate) {
                            remRows.append(IndexPath(item: idx, section: 0))
                        }
                }
            }
            
            for i in 0..<remRows.count {
                DDLogVerbose("Remove row \(remRows[i].row)")
            }
            self.tableView.deleteRows(at: remRows, with: .automatic)
        }
        if (changedItems?.count ?? 0) > 0 {
            var updRows: [IndexPath] = []
            for upd in changedItems! {
                    if let createDate = upd.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date {
                        if let idx = dates.firstIndex(of:createDate) {
                            updRows.append(IndexPath(item: idx, section: 0))
                        }
                }
            }
            for i in 0..<updRows.count {
                DDLogVerbose("Change row \(updRows[i].row)")
            }
            self.tableView.reloadRows(at: updRows, with: .automatic)
        }
        if (addedItems?.count ?? 0) > 0 {
            var insertedRows: [IndexPath] = []
            for ins in addedItems! {
                if let createDate = ins.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date {
                    var insPos = dates.firstIndex(where: {$0 < createDate}) ?? dates.count
                    for i in 0..<insertedRows.count {
                        if insertedRows[i].row >= insPos {
                            insertedRows[i].row += 1
                        } else {
                            insPos += 1
                        }
                    }
                    insertedRows.append(IndexPath(row: insPos, section: 0))
                }
            }
            for i in 0..<insertedRows.count {
                DDLogVerbose("Insert row \(insertedRows[i].row)")
            }
            self.tableView.insertRows(at: insertedRows, with: .automatic)
        }
        updateMapping()
        SwiftTryCatch.try({
            self.tableView.endUpdates()
        }, catch: { (error) in
            self.tableView.reloadData()
            DDLogError("Table partial refresh failed, perform full refresh instead")
        }, finally: {
            self.cloudQuery?.enableUpdates()
        })
    }
    
    override func tableView(_ tableView: UITableView,
                            leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let i = indexPath.row
        let idx = self.rowOrderMap[i]
        var items:[UIContextualAction] = []
        guard let metadata = self.cloudQuery?.result(at: idx) as? NSMetadataItem else {return UISwipeActionsConfiguration(actions: items)}
        let downloadStatus = metadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        if (downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded) {
            let downloadItem = UIContextualAction(style: .normal, title: "Download") { (action, view, postAction) in
                if let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL {
                    DDLogInfo("URL: \(url.absoluteString)")
                    do {
                        try FileManager.default.startDownloadingUbiquitousItem(at: url)
                        postAction(true)
                        DDLogInfo("Set to download")
                    } catch {
                        postAction(false)
                        DDLogError("Download failed")
                    }
                } else {
                    postAction(false)
                }
            }
            items.append(downloadItem)
        } else if (downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent) {
            if let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL, let fileName = metadata.value(forAttribute: NSMetadataItemFSNameKey) as? String  {
                let moveItem = UIContextualAction(style: .normal, title: "Move to local") { (action, view, postAction) in
                    do {
                        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                        let localUrl = documents.appendingPathComponent(fileName)
                        DDLogVerbose(String(format: "Get %@ to %@", url.absoluteString, localUrl.absoluteString))
                        try FileManager.default.setUbiquitous(false, itemAt: url, destinationURL: localUrl)
                        postAction(true)

                    } catch {
                        DDLogError("Download failed: \(error.localizedDescription)")
                        postAction(false)
                    }
                }
                items.append(moveItem)
            }
        }

        return UISwipeActionsConfiguration(actions: items)
    }
    
    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        let i = indexPath.row
        let idx = self.rowOrderMap[i]
        var items:[UIContextualAction] = []
        guard let metadata = self.cloudQuery?.result(at: idx) as? NSMetadataItem else {return UISwipeActionsConfiguration(actions: items)}
        let downloadStatus = metadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        if (downloadStatus != NSMetadataUbiquitousItemDownloadingStatusNotDownloaded) {

            let deleteItem = UIContextualAction(style: .destructive, title: "Delete") { (action, view, postAction) in
                self.cloudQuery?.disableUpdates()
                if let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL {
                    do {
                        DDLogVerbose("Deleting \(url.absoluteString)")
                        try FileManager.default.removeItem(at: url)
                        Toast(text: NSLocalizedString("File deleted", comment: ""), theme: .success)
                        postAction(true)
                    } catch {
                        DDLogError("Failed to remove: \(error.localizedDescription)" )
                        Toast(text: NSLocalizedString("Failed to delete file", comment: ""), theme: .error)
                        postAction(false)
                    }
                } else {
                    postAction(false)
                }
                self.cloudQuery?.enableUpdates()
            }
            items.append(deleteItem)
        }
        
        let percent = metadata.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0.0
        if (percent > 0.0) {
            if let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL {
                let title = percent < 100.0 ? "Cancel" : "Purge local"
                let purgeItem = UIContextualAction(style: .normal, title: title ) { (action, view, postAction) in
                    do {
                        try FileManager.default.evictUbiquitousItem(at: url)
                        postAction(true)
                    } catch {
                        DDLogError("Remove failed: \(error.localizedDescription)")
                        postAction(false)
                    }
                    self.cloudQuery?.enableUpdates()

                }
                items.append(purgeItem)
            }
        }
        
        return UISwipeActionsConfiguration(actions: items)
    }
    
    func setOrderMap () {
        var dateArray:[Date] = []
        rowOrderMap.removeAll()
        rowOrderMap.reserveCapacity(cloudQuery!.resultCount)
        dateArray.reserveCapacity(cloudQuery!.resultCount)
        for i in 0..<cloudQuery!.resultCount {
            let metadata = cloudQuery!.result(at: i) as? NSMetadataItem
            let date = metadata?.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date()
            dateArray.append(date)
            rowOrderMap.append(i)
        }
        rowOrderMap.sort { (a, b) -> Bool in
            let date1 = dateArray[a]
            let date2 = dateArray[b]
            return date1 >= date2
        }
    }
    
    var anySelected: Bool {
        return tableView.isEditing && tableView.indexPathForSelectedRow != nil
    }
    
    func selectAll() {
        guard let tv = tableView else {return}
        let allSelected = tv.indexPathsForSelectedRows?.count == self.cloudQuery?.resultCount
        for i in 0..<(cloudQuery?.resultCount ?? 0) {
            let row = rowOrderMap[i]
            let path = IndexPath(row: row , section: 0)
            if allSelected {
                tv.deselectRow(at: path, animated: false)
            } else {
                tv.selectRow(at: path, animated: false, scrollPosition: .none)
            }
        }

    }
    
    func confirmDelete() {
        let selCount = tableView.indexPathsForSelectedRows?.count ?? 0
        if selCount == 0 { return }
        
        let message = String.localizedStringWithFormat(NSLocalizedString("Do you want to delete %d file(s) from iCloud Drive?\nUse Actions/Purge Local instead to preserve iCloud content", comment: ""), selCount)
        let alert = UIAlertController(title: NSLocalizedString("Delete", comment: ""), message: message, preferredStyle: .alert)
        
        let actionYes = UIAlertAction(title: "Yes", style: .default) { (_) in self.deleteSelected() }
        alert.addAction(actionYes)
    
        let actionNo = UIAlertAction(title: "No", style: .cancel)
        alert.addAction(actionNo)
        
        present(alert, animated: true)

    }
    
    func deleteSelected() {
        let count = performOnSelected { (metadata) in
            do {
                guard let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                    return false
                }
                DDLogVerbose("Deleting \(url.lastPathComponent)")
                try FileManager.default.removeItem(at: url)
            } catch {
                return false
            }
            return true
        }
        Toast(text: NSLocalizedString("Deleted \(count) files", comment: ""), theme: .success)
        DispatchQueue.main.async {
            self.tableView.setEditing(false, animated: false)
        }
    }
    
    func downloadSelected() {
        let count = performOnSelected { (metadata) in
            guard let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                return false
            }
            let downloadStatus = metadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if (downloadStatus != NSMetadataUbiquitousItemDownloadingStatusNotDownloaded) {
                return false
            }
            DDLogVerbose("Downloading \(url.lastPathComponent)")
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                return false
            }
            return true
        }
        Toast(text: NSLocalizedString("Downloading \(count) files", comment: ""), theme: .info)
        DispatchQueue.main.async {
            self.tableView.setEditing(false, animated: true)
            self.navigationController?.setToolbarHidden(true, animated: true)
        }
    }
    
    func moveSelected() {
        let documents = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        let count = performOnSelected { (metadata) in
            guard let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                return false
            }
            let downloadStatus = metadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let fileName = metadata.value(forAttribute: NSMetadataItemFSNameKey) as? String
            if (downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent || fileName == nil) {
                return false
            }
            DDLogVerbose("Moving \(url.lastPathComponent)")
            do {
                let localUrl = documents.appendingPathComponent(fileName!, isDirectory: false)
                try FileManager.default.setUbiquitous(false, itemAt: url, destinationURL: localUrl)
            } catch {
                return false
            }
            return true
        }
        Toast(text: NSLocalizedString("Moved \(count) files", comment: ""), theme: .success)
        DispatchQueue.main.async {
            self.tableView.setEditing(false, animated: true)
            self.navigationController?.setToolbarHidden(true, animated: true)
        }
    }
    
    func purgeSelected() {
        let count = performOnSelected { (metadata) in
            guard let url = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                return false
            }
            let downloadStatus = metadata.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if (downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent) {
                return false
            }
            DDLogVerbose("Purge \(url.lastPathComponent)")
            do {
                try FileManager.default.evictUbiquitousItem(at: url)
            } catch {
                return false
            }
            return true
        }
        Toast(text: NSLocalizedString("Purged \(count) files", comment: ""), theme: .success)
        DispatchQueue.main.async {
            self.tableView.setEditing(false, animated: true)
            self.navigationController?.setToolbarHidden(true, animated: true)
        }
    }
    
    func performOnSelected(_ action: (NSMetadataItem)->Bool) -> Int {
        guard let selected = tableView.indexPathsForSelectedRows else {return 0}
        var actionCount:Int = 0
        for indexPath in selected {
            let row = indexPath.row
            if row >= self.rowOrderMap.count { continue }
            let idx = self.rowOrderMap[row]
            guard let query = self.cloudQuery,
                  idx < query.resultCount,
                  let metadata = query.result(at: idx) as? NSMetadataItem else { continue }
            if action(metadata) {
                actionCount += 1
            }
        }
        return actionCount
    }

}
