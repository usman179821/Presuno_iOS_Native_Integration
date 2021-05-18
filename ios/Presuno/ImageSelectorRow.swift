import Foundation
import Eureka
import UIKit

final class ImageSelectorRow: OptionsRow<PushSelectorCell<String>>, PresenterRowType, RowType {
    
    typealias PresenterRow = ImageSelectorController
    
    /// Defines how the view controller will be presented, pushed, etc.
    public var presentationMode: PresentationMode<PresenterRow>?
    
    /// Will be called before the presentation occurs.
    public var onPresentCallback: ((FormViewController, PresenterRow) -> Void)?

    public required init(tag: String?) {
        super.init(tag: tag)
        presentationMode = .show(controllerProvider: ControllerProvider.callback { return ImageSelectorController(){ _ in } }, onDismiss: { vc in _ = vc.navigationController?.popViewController(animated: true) })
    }
    
    /**
     Extends `didSelect` method
     */
    public override func customDidSelect() {
        super.customDidSelect()
        guard let presentationMode = presentationMode, !isDisabled else { return }
        if let controller = presentationMode.makeController() {
            controller.row = self
            controller.title = selectorTitle ?? controller.title
            onPresentCallback?(cell.formViewController()!, controller)
            presentationMode.present(controller, row: self, presentingController: self.cell.formViewController()!)
        } else {
            presentationMode.present(nil, row: self, presentingController: self.cell.formViewController()!)
        }
    }
    
    /**
     Prepares the pushed row setting its title and completion callback.
     */
//    public override func prepare(for segue: UIStoryboardSegue) {
//        super.prepare(for: segue)
//        guard let rowVC = segue.destination as? PresenterRow else { return }
//        rowVC.title = selectorTitle ?? rowVC.title
//        rowVC.onDismissCallback = presentationMode?.onDismissCallback ?? rowVC.onDismissCallback
//        onPresentCallback?(cell.formViewController()!, rowVC)
//        rowVC.row = self
//    }

    
}
