import Foundation
import GRDB
import CocoaLumberjackSwift

class ImageLayerConfigImport {
    typealias CompletionFunction =  (Int) -> Void
    
    private let importedItemsFile = "import_list.txt"
    private var maxZOrder: Int32 = 0
    
    func run(onComplete: @escaping CompletionFunction) {
        OperationQueue.main.addOperation {
            self.addImported(onComplete)
        }
    }
    
    private func addImported(_ onComplete: CompletionFunction) {
        let fm = FileManager.default
        guard var dest = fm.containerURL(forSecurityApplicationGroupIdentifier: SK.overlaysContainerName) else {
            return
        }
        dest.appendPathComponent(importedItemsFile)
        do {
            if fm.fileExists(atPath: dest.path) {
                let contents = try String(contentsOf: dest, encoding: .utf8)
                let list = contents.split(separator: "\n")
                importFromList(list, onComplete: onComplete)
                try fm.removeItem(at: dest)
                
            }
        } catch {
            DDLogError("Failed to update import list: \(error.localizedDescription)")
        }
    }
    
    private func importFromList(_ list: [Substring], onComplete: CompletionFunction) {
        let fm = FileManager.default
        guard let dest: URL = fm.containerURL(forSecurityApplicationGroupIdentifier: SK.overlaysContainerName) else {
            return
        }

        let layersOpt = try? dbQueue.read { db in
            try? ImageLayerConfig.order(Column("z_index").asc).fetchAll(db)
        }
        let layers = layersOpt ?? []
        if let lastLayer = layers.last {
            maxZOrder = lastLayer.zIndex
        }
        var importCount = 0

        for name in list {
            let nameStr = String(name)
            let fileUrl: URL = dest.appendingPathComponent(nameStr)
            if !fm.fileExists(atPath: fileUrl.path) {
                continue
            }
            if layers.contains(where: { ($0.localName ?? "") == name }) { continue}

            if let _ = addRecordByLocalName(name: String(name)) {
                importCount += 1
            }
        }
        if importCount > 0 {
            onComplete(importCount)
        }
    }
    
    func addRecordByLocalName(name: String) -> ImageLayerConfig? {
        var title = name
        if let extPos = name.lastIndex(of: ".") {
            let namePos = name.index(before: extPos)
            title = String(name.prefix(through: namePos))
        }
        let layer = ImageLayerConfig()
        if maxZOrder < Int32.max {
            maxZOrder += 1
        }
        layer.active = false
        layer.name = title
        layer.localName = name
        layer.zIndex = maxZOrder
        
        do {
            try dbQueue.write { db in
                try layer.insert(db)
                layer.id = db.lastInsertedRowID
            }
        } catch {
            DDLogError("Add record failed: \(error.localizedDescription)")
            return nil
        }
        return layer
    }
    
}
