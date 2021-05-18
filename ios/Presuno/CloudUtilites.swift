import Foundation
import Photos
import CocoaLumberjackSwift

public protocol CloudNotificationDelegate {
    func movedToPhotos(source: URL) -> Void
    func movedToCloud(source: URL) -> Void
    func moveToPhotosFailed(source: URL) -> Void
    func moveToCloudFailed(source: URL) -> Void
}

class CloudUtilites: NSObject, PHPhotoLibraryChangeObserver, NSFilePresenter {
    public var delegate: CloudNotificationDelegate?
    
    //Photo library
    var photoLibrary: PHPhotoLibrary?
    var allCollections: PHFetchResult<PHCollection>?
    var larixCollection: PHFetchResult<PHAssetCollection>?
    var larixAssets: PHFetchResult<PHAsset>?
    let larixAlbumTitle = "Presuno Broadcaster"
    var saveFileUrl: URL?
    
    //iCloud storage
    let iCloudContainerId = "iCloud.com.wmspanel.LarixBroadcaster"
    var fileManager = FileManager.default
    var presenterOperationQueue: OperationQueue?
    var fileCoordinator: NSFileCoordinator?

    func activate() {
        NSFileCoordinator.addFilePresenter(self)
    }
    
    func deactivate() {
        NSFileCoordinator.removeFilePresenter(self)
        if photoLibrary != nil {
            photoLibrary?.unregisterChangeObserver(self)
            photoLibrary = nil
        }
    }
    
    var photoAlbumName: String? {
        return larixCollection?.firstObject?.localizedTitle
    }
    
    func movePhoto(fileUrl: URL, to storage: Settings.RecordStorage) {
        saveFileUrl = fileUrl
        switch storage {
        case .local:
            return
        case .photoLibrary:
            saveInLibrary(action: {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileUrl)
            }, completionHandler: {success, error in
             if success {
                try! self.fileManager.removeItem(at: fileUrl)
                self.delegate?.movedToPhotos(source: fileUrl)
             } else {
                self.delegate?.moveToPhotosFailed(source: fileUrl)
             }
            })
        case .iCloud:
            moveToClould(url: fileUrl)
        }
    }
    
    func moveVideo(fileUrl: URL, to storage: Settings.RecordStorage) {
        switch storage {
        case .local:
            return
        case .photoLibrary:
            saveInLibrary(action: {PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileUrl)},
                completionHandler: {success, error in
                 if success {
                    try! self.fileManager.removeItem(at: fileUrl)
                    self.delegate?.movedToPhotos(source: fileUrl)
                 } else {
                     self.delegate?.moveToPhotosFailed(source: fileUrl)
                 }
            })
        case .iCloud:
            moveToClould(url: fileUrl)
        }
    }
    
    private func saveInLibrary(action: @escaping () -> PHAssetChangeRequest?, completionHandler: ((Bool, Error?) -> Void)? = nil) -> Void {
        var canUseLibrary: Bool
        switch PHPhotoLibrary.authorizationStatus() {
            case .notDetermined:
            PHPhotoLibrary.requestAuthorization { (result) in
                if result == .authorized {
                    self.initPhotoLibrary()
                    self.perfomLibraryChange(action: action, completionHandler: completionHandler)
                } else {
                    let error = NSError(domain: "Photo library access denied", code: 0, userInfo: [:])
                    completionHandler?(false, error)
                }
            }
            canUseLibrary = true
            case .authorized:
            initPhotoLibrary()
            perfomLibraryChange(action: action, completionHandler: completionHandler)
            canUseLibrary = true
        case .denied, .restricted:
            canUseLibrary = false
        default:
            canUseLibrary = false
        }
        if (!canUseLibrary) {
            let error = NSError(domain: "Photo library access denied", code: 0, userInfo: [:])
            completionHandler?(false, error)
        }
    }
    
    private func initPhotoLibrary() {
        if photoLibrary == nil {
            photoLibrary = PHPhotoLibrary.shared()
            photoLibrary?.register(self)
            allCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        }
        var collection: PHAssetCollection?
        let options = PHFetchOptions()
        if let id = Settings.sharedInstance.photoAlbumId {
            let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: options)
            if result.count > 0 {
                collection = result.firstObject
                larixCollection = result
            }
        }
        if collection == nil {
            //Search for "Larix Broadcaster" album and create it once not found
            options.predicate = NSPredicate(format: "localizedTitle == %@", larixAlbumTitle)
            options.sortDescriptors = [NSSortDescriptor(key: "endDate", ascending: false)]
            options.fetchLimit = 1
            let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular , options: options)

            if result.count > 0 {
                larixCollection = result
                Settings.sharedInstance.photoAlbumId = result.firstObject!.localIdentifier
            }
        }
        if let col = larixCollection {
            larixAssets = PHAsset.fetchAssets(in: col.firstObject!, options: nil)

        }
    }
        
    internal func photoLibraryDidChange(_ changeInstance: PHChange) {
            DDLogVerbose("photoLibraryDidChange")
       
            if let folderRequest = changeInstance.changeDetails(for: allCollections!) {
                let added = folderRequest.insertedObjects
                
                for newObject in added {
                    if let collection = newObject as? PHAssetCollection, collection.localizedTitle == larixAlbumTitle {
                        let id = collection.localIdentifier
                        Settings.sharedInstance.photoAlbumId = id
                        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
                        if result.count > 0 {
                            larixCollection = result
                            larixAssets = PHAsset.fetchAssets(in: result.firstObject!, options: nil)
                        }
                    }
                }
            }
            if let collection = larixAssets, let collectionRequest = changeInstance.changeDetails(for: collection) {
                let added = collectionRequest.insertedObjects
                for newFile in added {
                    DDLogVerbose("Added file \(newFile.localIdentifier) to Photos")
                }
            }
        }
    
        private func perfomLibraryChange(action: @escaping () -> PHAssetChangeRequest?, completionHandler: ((Bool, Error?) -> Void)? = nil) {
            photoLibrary?.performChanges({
                let collection = self.larixCollection?.firstObject
                guard let creationRequest = action() else {return}
                let newPhoto = [creationRequest.placeholderForCreatedAsset!] as NSArray
                if collection == nil {
                    //Create collection and put image at once
                    let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.larixAlbumTitle)
                    req.addAssets(newPhoto)
                } else {
                    //Put image into existing collection
                    let addAssetRequest = PHAssetCollectionChangeRequest(for: collection!)
                    addAssetRequest?.addAssets(newPhoto)
                }
            }, completionHandler: completionHandler)
        }



        
        
        private func moveToClould(url: URL) {
            let name = url.lastPathComponent
            if var cloudUrl = fileManager.url(forUbiquityContainerIdentifier: iCloudContainerId) {
                cloudUrl.appendPathComponent("Documents", isDirectory: true)
                
                cloudUrl.appendPathComponent(name)
                let remotePath = cloudUrl.absoluteString
                DDLogVerbose("iCloud URL: \(remotePath)")
                presentedItemOperationQueue.addOperation {
                    do {
                        try self.fileManager.setUbiquitous(true, itemAt: url, destinationURL: cloudUrl)
                    } catch let error as NSError {
                        DDLogVerbose("Failed to move: \(error.localizedDescription)")
                        self.delegate?.moveToCloudFailed(source: url)
                    }
                }
            } else {
                self.delegate?.moveToCloudFailed(source: url)
            }
        }
        
        internal var presentedItemURL: URL? {
            var url: URL?
            url = try! fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            return url
        }
        
        internal var presentedItemOperationQueue: OperationQueue {
            if presenterOperationQueue == nil {
                presenterOperationQueue = OperationQueue()
            }
            return presenterOperationQueue!
        }
     
        func presentedSubitem(at: URL, didMoveTo: URL) {
            DDLogVerbose("Moved \(at.lastPathComponent) to iCloud \(didMoveTo.absoluteString)")
            delegate?.movedToCloud(source: at)
        }
    
}
