import Foundation
import GRDB
import CoreImage
import CocoaLumberjackSwift
import UIKit

protocol CompositeImageLayerDelegate {
    func onImageLoadComplete()
    func onImageLoaded(name: String)
    func onLoadError(name: String, error: String)
}

class CompositeImageLayer: NSObject, URLSessionDownloadDelegate {
    let maxAllowedDowloadSize = 10_000_000
    
    var delegate: CompositeImageLayerDelegate?
    var outputImage: CIImage?
    var size: CGSize = CGSize(width: 1920, height: 1080)
    var layers: [ImageLayer] = []
    var urlSession: URLSession?
    let operationQueue = OperationQueue()
    var pendingImageLoad: Int = 0
    var downloadTasks: [Int: ImageLayer] = [:]

    override init() {
        super.init()
       let configuration = URLSessionConfiguration.default
        operationQueue.name = "imageDownloader"
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: operationQueue)
    }
    
    func loadIdList(_ list: [Int64]) {
        let layerConfigOpt = try? dbQueue.read() { db in
            try? ImageLayerConfig.fetchAll(db, keys: list)
        }
        let layerConfig = layerConfigOpt ?? []
        loadList(layerConfig)
    }
    
    var activeLayers: Set<Int64> {
        let idList = layers.filter(\.active).map(\.id)
        return Set(idList)
    }
    
    func loadActiveOnly() {
        loadConfig(predicate: Column("active") == 1)
    }

    func loadConfig(predicate: GRDB.SQLSpecificExpressible? = nil) {
        let layerConfigOpt: [ImageLayerConfig]? = try? dbQueue.read() { db in
            if let predicate = predicate {
                return try? ImageLayerConfig.filter(predicate).fetchAll(db)
            } else {
                return try? ImageLayerConfig.fetchAll(db)

            }
        }
        let layerConfig = layerConfigOpt ?? []
        loadList(layerConfig)
    }
    
    func loadList(_ layerConfig: [ImageLayerConfig]) {
        let fileManager = FileManager.default

        let existingList = layers.map(\.id)
        let existingSet = Set(existingList)
        let updatedList = layerConfig.map { $0.id ?? 0}
        let removedSet = existingSet.subtracting(Set(updatedList))
        
        for layer in layers {
            if removedSet.contains(layer.id) {
                layer.active = false
            }
        }
        
        if !removedSet.isEmpty {
            clearImages()
        }
        pendingImageLoad = layerConfig.count
        if pendingImageLoad == 0 {
            drawImages()
        }
        for config in layerConfig {
            guard let id = config.id else {
                continue
            }
            let remoteURL = URL(string: config.url) 
            if existingSet.contains(id) {
                if let layer = layers.first(where: { $0.id == id }) {
                    layer.active = true
                    markImageLoaded()
                    continue
                }
            }
            let layer = ImageLayer(id: id, name: config.name, remoteUrl: remoteURL)
            if let filePath = config.localPath {
                if fileManager.isReadableFile(atPath: filePath.path) {
                    layer.localUrl = filePath
                }
            }
            layer.zIndex = config.zIndex
            if layer.localUrl == nil {
                if let url = layer.remoteUrl {
                    let task = urlSession!.downloadTask(with: url)
                    layer.downloadTask = task
                    let taskId = task.taskIdentifier
                    downloadTasks[taskId] = layer
                    task.resume()
                } else {
                    let error = NSLocalizedString("Invalid image URL", comment: "")
                    delegate?.onLoadError(name: layer.name, error: error)
                    markImageLoaded()
                }
            } else {
                loadImageAsync(layer: layer)
            }
            let cx = CGFloat(config.displayPosX)
            let cy = CGFloat(config.displayPosY)
            layer.center = CGPoint(x: cx, y: cy)
            layer.scale = CGFloat(config.displaySize)
                
            layers.append(layer)
        }
    }
    
    func invalidate() {
        urlSession?.invalidateAndCancel()
        operationQueue.cancelAllOperations()
        layers.removeAll()
    }
    
     func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier
        guard let layer = downloadTasks[taskId] else {
            DDLogError("Something wrong been downloaded")
            return
        }
        var httpCode: Int = 200
        if let httpRes = downloadTask.response as? HTTPURLResponse {
            httpCode = httpRes.statusCode
        }
        if httpCode >= 400 {
            DDLogError("File downloading status \(httpCode)")
            let error = String.localizedStringWithFormat(NSLocalizedString("Server returned %d error", comment: ""), httpCode)
            delegate?.onLoadError(name: layer.name, error: error)
            markImageLoaded()
        } else {
            let fileName = downloadTask.response?.suggestedFilename ?? layer.remoteUrl?.lastPathComponent ?? UUID().uuidString
            if let dest = moveDownloadedImage(srcPath: location, name: fileName, recordId: layer.id) {
                layer.localUrl = dest
                loadImageAsync(layer: layer)
            } else {
                let error = NSLocalizedString("Failed to move temp file", comment: "")
                delegate?.onLoadError(name: layer.name, error: error)
                markImageLoaded()
            }
        }
        layer.downloadTask = nil
        downloadTasks.removeValue(forKey: taskId)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskId = downloadTask.taskIdentifier
        guard let layer = downloadTasks[taskId] else {
            return
        }

        let totalSize: Int64
        if totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown {
            totalSize = bytesWritten
        } else {
            totalSize = totalBytesExpectedToWrite
        }
        var errorMessage: String?

        if totalSize > maxAllowedDowloadSize {
            errorMessage = NSLocalizedString("File is too large to download", comment: "")
        } else if let mimeType = downloadTask.response?.mimeType {
            if !mimeType.starts(with: "image/") {
                errorMessage = NSLocalizedString("Unsupported MIME type", comment: "")
            }
        }
        if let message = errorMessage {
            downloadTask.cancel()
            downloadTasks.removeValue(forKey: taskId)
            layer.downloadTask = nil
            delegate?.onLoadError(name: layer.name, error: message)
            markImageLoaded()
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let taskId = task.taskIdentifier
            guard let layer = downloadTasks[taskId] else {
                return
            }
            let name = layer.name
            DDLogWarn("Request of \(name) completed with error: \(error.localizedDescription)")
            markImageLoaded()
            delegate?.onLoadError(name: name, error: error.localizedDescription)
            downloadTasks.removeValue(forKey: taskId)

        }
    }

    
    func moveDownloadedImage(srcPath: URL, name: String, recordId: Int64? = nil) -> URL? {
        let fileManager = FileManager.default
        guard let path = ImageLayerConfig.imageFolder else {
            return nil
        }
        let destPath = path.appendingPathComponent(name)

        do {
            if !fileManager.fileExists(atPath: path.path) {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            }
            let d = destPath.path
            if fileManager.fileExists(atPath: d) {
                try fileManager.removeItem(at: destPath)
            }
            try fileManager.moveItem(at: srcPath, to: destPath)
            DDLogInfo("Moved to \(destPath.absoluteString)")
            if let id = recordId {
                try dbQueue.write() { db in
                    if let rec = try ImageLayerConfig.fetchOne(db, key: id) {
                        rec.localName = name
                        try rec.update(db)
                    }
                }
            }
            
        } catch {
            DDLogError("Failed to move file: \(error.localizedDescription)")
            return nil
        }
        return destPath
    }

    func loadImageAsync(layer: ImageLayer) {
        operationQueue.addOperation {
            guard let url = layer.localUrl,
                  let image = CIImage(contentsOf: url),
                  image.extent.size != CGSize.zero else {
                DDLogError("Failed to load image from file")
                let errorMessage = NSLocalizedString("Failed to open image", comment: "")
                self.delegate?.onLoadError(name: layer.name, error: errorMessage)
                self.markImageLoaded()
                return
            }
            self.delegate?.onImageLoaded(name: layer.name)
            layer.image = image
            let imageSize = image.extent.size
            var w = imageSize.width
            var h = imageSize.height
            let canvasSize = self.size
            let canvasAspect = canvasSize.width / canvasSize.height
            if layer.scale != 0 {
                let fullW: CGFloat
                let fullH: CGFloat
                if canvasAspect > w / h {
                    fullW = canvasSize.width
                    fullH = canvasSize.width * h / w
                } else {
                    fullW = canvasSize.height * w / h
                    fullH = canvasSize.height
                }
                w = fullW * layer.scale
                h = fullH * layer.scale
            }
            let xPadding = canvasSize.width - w
            let yPadding = canvasSize.height - h
            let xPos = layer.center.x * xPadding
            let yPos = layer.center.y * yPadding
            layer.rect = CGRect(x: xPos, y: yPos, width: w, height: h)
            self.markImageLoaded()
        }

    }
    
    func markImageLoaded() {
        DDLogInfo("markImageLoaded: \(pendingImageLoad) left")
        if pendingImageLoad <= 0 {
            return
        }
        pendingImageLoad -= 1
        if pendingImageLoad == 0 {
            drawImages()
        }
    }
    
    
    func clearImages() {
        outputImage = CIImage(color: CIColor.clear)
    }
    
    func drawImages() {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        let orderedLayers = layers.sorted()
        for layer in orderedLayers where layer.active {
            if let image = layer.image {
                let uiImage = UIImage(ciImage: image)
                uiImage.draw(in: layer.rect)//(at: CGPoint.zero, blendMode: .normal, alpha: 0.7)
            }
        }
        
        if let uiImage = UIGraphicsGetImageFromCurrentImageContext(),
           let ciImage = CIImage(image: uiImage) {
            outputImage = ciImage
        }
        UIGraphicsEndImageContext()
        if let delegate = delegate {
            delegate.onImageLoadComplete()
        }
    }

    
}
