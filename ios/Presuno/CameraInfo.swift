import AVFoundation

struct CameraInfo {
    var id: String
    var name: String
    var position: AVCaptureDevice.Position
    var videoSizes: Array<CMVideoDimensions>
    
    init (id: String, name: String, position: AVCaptureDevice.Position, sizes: Array<CMVideoDimensions>) {
        self.id = id
        self.name = name
        self.position = position
        self.videoSizes = sizes
    }
}

func getCameraList() -> Array<CameraInfo> {
    var out: [CameraInfo] = []
    let discovery = AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
    for camera in discovery.devices {
        var sizes: [CMVideoDimensions] = []
        for format in camera.formats {
            if kCMMediaType_Video != CMFormatDescriptionGetMediaType(format.formatDescription) {
                continue
            }
            if kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange != CMFormatDescriptionGetMediaSubType(format.formatDescription) {
                continue
            }
            sizes.append(CMVideoFormatDescriptionGetDimensions(format.formatDescription))
        }
        out.append(CameraInfo(id: camera.uniqueID, name: camera.localizedName, position: camera.position, sizes: sizes))
    }
    return out
}
