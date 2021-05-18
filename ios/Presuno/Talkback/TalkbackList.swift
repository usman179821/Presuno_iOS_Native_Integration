import Foundation
import Eureka
import UIKit

class TalkbackListControler: BaseConnectionListController<IncomingConnection> {
    var activeId: Int64?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = NSLocalizedString("Talkback", comment: "")
    }

    
    override func initForm() {
        super.initForm()
        
        let active = try? dbQueue.read { db in
            try? IncomingConnection.filter(sql: "active=?", arguments: ["1"]).fetchOne(db)
        }
        activeId = active?.id
        
        form +++ Section()
            <<< ButtonRow() {
                $0.title = NSLocalizedString("Talkback documentation", comment: "")
                $0.onCellSelection { (_, _) in
                    if let url = URL(string: "https://softvelum.com/larix/talkback/") {
                        UIApplication.shared.open(url, options: [:])
                    }
                }
            }
    }
    
    override func setupRecord(_ row: CheckRow, conn: IncomingConnection) {
        super.setupRecord(row, conn: conn)

        let shareAction = SwipeAction(
            style: .normal,
            title: NSLocalizedString("Grove", comment: ""),
            handler: { (action, row, completionHandler) in
                if let i = row.indexPath?.row, i < self.idList.count {
                    let id =  self.idList[i]
                    let record = try? dbQueue.read { db in
                        try? IncomingConnection.filter(key: id).fetchOne(db)
                    }
                    if let conn = record {
                        let storyboard = UIStoryboard.init(name: "Main", bundle: Bundle.main)
                        if let exportView = storyboard.instantiateViewController(withIdentifier: "exportGrove") as? ExportGroveController {
                            exportView.enableSelection = false
                            exportView.talkback = [conn]
                            exportView.selectedTalkback = [0]
                            self.navigationController?.pushViewController(exportView, animated: true)
                        }
                    }
                }
                completionHandler?(true)
        })
        row.leadingSwipe.actions = [shareAction]
    }
    
    
    
    override func updateList() {
        super.updateList()
        let active = try? dbQueue.read { db in
            try? IncomingConnection.filter(sql: "active=?", arguments: ["1"]).fetchOne(db)
        }
        activeId = active?.id
    }

    
    override func onCheck(row: CheckRow) {
        guard let active = row.value, let idx = row.indexPath?.row, idx < idList.count else { return }
        if activeId != nil {
            try! dbQueue.write { db in
                try db.execute(sql: "UPDATE incoming_connection SET active = 0 WHERE id = ?", arguments: [activeId])
            }
            
            if let activeIdx = idList.firstIndex(of: activeId!),
               let activeRow = form.sectionBy(tag: "connections")?.allRows[activeIdx] as? CheckRow {
                activeRow.value = false
                activeRow.updateCell()
            }
            activeId = nil
        }
        let id = idList[idx]
        if active && id != activeId {
            try! dbQueue.write { db in
                try db.execute(sql: "UPDATE incoming_connection SET active = 1 WHERE id = ?", arguments: [id])
            }
            activeId = id
        }
    }
    
    override func createEditor() -> FormViewController? {
        return TalkbackEditorViewController()
    }
    
    override func createManager() -> FormViewController? {
        return TalkbackManagerViewController()
    }

}
