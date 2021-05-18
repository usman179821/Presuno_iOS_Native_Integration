import Foundation
import UIKit


class ImageLayerPreview: UIViewController, CompositeImageLayerDelegate {
    
    let testLayer = CompositeImageLayer()

    @IBOutlet weak var imageView: UIImageView!
    override func viewDidLoad() {
        testLayer.delegate = self
        let res = Settings.sharedInstance.resolution
        var multiplier = CGFloat(res.width) / CGFloat(res.height)
        let viewSize: CGSize
        
        if Settings.sharedInstance.portrait {
            multiplier = 1.0 / multiplier
            viewSize = CGSize(width: CGFloat(res.height), height: CGFloat(res.width))
        } else {
           viewSize = CGSize(width: CGFloat(res.width), height: CGFloat(res.height))
        }
        testLayer.size = viewSize
        if let constr = imageView.constraints.first(where: { $0.identifier == "ImageAspectRatio" }) {
            let newConstaint = NSLayoutConstraint(item: constr.firstItem!, attribute: constr.firstAttribute, relatedBy: constr.relation, toItem: constr.secondItem, attribute: constr.secondAttribute, multiplier: multiplier, constant: constr.constant)
            imageView.removeConstraint(constr)
            imageView.addConstraint(newConstaint)
        }
        testLayer.loadActiveOnly()
    }
    
    
    func onImageLoadComplete() {
        DispatchQueue.main.async {
            if let ciImage = self.testLayer.outputImage {
                self.imageView.image = UIImage(ciImage: ciImage)
            }
        }
    }
    
    func onImageLoaded(name: String) {
        
    }
    
    func onLoadError(name: String, error: String) {
        let message = String(format: "“%@” loading failed: %@", name, error)
        Toast(text: message, theme: .error)
    }

}
