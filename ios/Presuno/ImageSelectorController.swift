import Foundation
import UIKit
import Eureka
import CocoaLumberjackSwift

fileprivate struct FileData {
    var url: URL
    var size: Int
    var width: Int
    var height: Int
    var image: UIImage?
}

class ImageSelectorController: UITableViewController, TypedRowControllerType {
    
    public var row: RowOf<String>!
    public var onDismissCallback: ((UIViewController) -> ())?

    private let fm = FileManager.default
    private var fileList: [FileData] = []
    private var selIdx = -1
    
    private let listUpdateBatch = 5
    private let thumbnailSize = 64
    private let queue = DispatchQueue(label: "ImageListLoader", qos: .background, attributes: .concurrent)
    private var defaultImage: UIImage?
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    convenience public init(_ callback: ((UIViewController) -> ())?){
        self.init(nibName: nil, bundle: nil)
        onDismissCallback = callback
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.allowsSelection = true
        createDefaultImage()
        updateFileList()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(doneAction(barButtonItem:)))
    }
    
    @objc func doneAction(barButtonItem: UIBarButtonItem) {
        _ = self.navigationController?.popViewController(animated: true)
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if selIdx >= 0 {
            let idxPath = IndexPath(row: selIdx, section: 0)
            tableView.selectRow(at: idxPath, animated: true, scrollPosition: .top)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    func createDefaultImage() {
        UIGraphicsBeginImageContext(CGSize(width: thumbnailSize, height: thumbnailSize))
        defaultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }
    
    func updateFileList() {
        guard let localPath = ImageLayerConfig.imageFolder else {
            return
        }
        do {
            var list = try fm.contentsOfDirectory(at: localPath, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            list.sort { return $0.lastPathComponent.caseInsensitiveCompare($1.lastPathComponent) == ComparisonResult.orderedAscending }
            let fileData = list.map { (url) -> FileData in
                let attr = try? url.resourceValues(forKeys: [.fileSizeKey])
                let size = attr?.fileSize ?? 0
                return FileData(url: url, size: size, width: 0, height: 0)
            }
            fileList = fileData.filter{ $0.size > 0 }
            selIdx = fileList.firstIndex(where: { $0.url.lastPathComponent == row.value }) ?? -1
            
            for idx in stride(from: 0, through: fileList.count, by: listUpdateBatch) {
                queue.async { [weak self] in
                    self?.loadImageDetails(idx)
                }
            }
        } catch {
            DDLogError("Get file contents failed")
        }
    }
    
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let num = fileList.count
        return num
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let i = indexPath.row
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "image")
        cell.selectionStyle = .none
        if i >= fileList.count {
            return cell
        }
        let elem = fileList[i]
        let url = elem.url
        cell.textLabel?.text = url.lastPathComponent
        var detailsStr = ""
        cell.accessoryType = i == selIdx ? .checkmark : .none

        let size = elem.size
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        detailsStr.append(sizeStr)
        if elem.width > 0 && elem.height > 0 {
            let dimensionStr = String(format: "\t\t%lldx%lld", elem.width, elem.height)
            detailsStr.append(dimensionStr)
        }
        cell.detailTextLabel?.text = detailsStr
        if let image = elem.image {
            cell.imageView?.image = image
        } else {
            cell.imageView?.image = defaultImage
        }

        return cell

    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        let i = indexPath.row
        if i < fileList.count {
            let name = fileList[i].url
            row.value = name.lastPathComponent
        }
      }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = .none
    }
    
    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteItem = UIContextualAction(style: .destructive, title: "Delete") { (action, view, postAction) in
            let i = indexPath.row
            if i < self.fileList.count {
                let item = self.fileList[i]
                let url = item.url
                do {
                    try self.fm.removeItem(at: url)
                    self.fileList.remove(at: i)
                    postAction(true)
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                } catch {
                    postAction(false)
                }
            } else {
                postAction(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [deleteItem])
    }
    
    func loadImageDetails(_ startIdx: Int) {
        var updateIdx: [IndexPath] = []
        for i in 0..<listUpdateBatch {
            let idx = startIdx + i
            if idx >= fileList.count {
                break
            }
            let elem = fileList[idx]
            let options: [CFString: AnyObject] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: kCFBooleanTrue,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailSize as CFNumber
            ]
            let cfOptions = options as CFDictionary
            let url = elem.url
            guard let source = CGImageSourceCreateWithURL(url as CFURL, cfOptions),
               let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [AnyHashable: Any] else {
                continue
            }
                
            guard let width = imageProperties[kCGImagePropertyPixelWidth] as? Int,
                  let height = imageProperties[kCGImagePropertyPixelHeight] as? Int else {
                continue
            }
            fileList[idx].width = width
            fileList[idx].height = height
            
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, cfOptions) {
                //DDLogInfo("Created image[\(idx)] \(image.width)x\(image.height)")
                fileList[idx].image = UIImage(cgImage: image)
            }
            updateIdx.append(IndexPath(row: idx, section: 0))
        }
        if !updateIdx.isEmpty {
            updateListAsync(updateIdx)
        }
    }
    
    func updateListAsync(_ updateIdx: [IndexPath]) {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadRows(at: updateIdx, with: .automatic)
        }

    }
    
}
