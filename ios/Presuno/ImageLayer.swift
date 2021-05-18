import Foundation
import CoreImage

class ImageLayer: Comparable {
    var id: Int64
    var active: Bool
    var name: String
    var remoteUrl: URL?
    var localUrl: URL?
    var rect: CGRect = CGRect()
    var center: CGPoint = CGPoint()
    var size: CGSize = CGSize()
    var scale: CGFloat = 0.0
    var zIndex: Int32 = 0
    var image: CIImage?
    var downloadTask: URLSessionDownloadTask?
    
    init(id: Int64, name: String, remoteUrl: URL?) {
        self.id = id
        self.name = name
        self.remoteUrl = remoteUrl
        self.active = true
    }
    
    static func < (a: ImageLayer, b: ImageLayer) -> Bool {
        return a.zIndex < b.zIndex
    }

    static func == (a: ImageLayer, b: ImageLayer) -> Bool {
        return a.zIndex == b.zIndex
    }

}
