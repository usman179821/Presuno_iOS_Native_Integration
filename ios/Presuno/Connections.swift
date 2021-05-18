import CocoaLumberjackSwift
import Eureka
import GRDB
import SwiftMessages

fileprivate func presentError(text: String, transient: Bool = false) {
    if transient {
        Toast(text: text, theme: .warning)
    } else {
        var config = SwiftMessages.Config()
        config.duration = .forever
        let view = MessageView.viewFromNib(layout: .messageView)
        view.configureTheme(.info)
        view.titleLabel?.isHidden = true
        view.configureContent(body: text)
        view.button?.setTitle("OK", for: .normal)
        view.buttonTapHandler = { _ in SwiftMessages.hide() }
        SwiftMessages.show(config: config, view: view)
    }
}

extension BaseConnection {
    func dump() {
        DDLogVerbose(self.name)
        DDLogVerbose(self.url)
        DDLogVerbose("\(self.active)")
        let mode = ConnectionMode.init(rawValue: self.mode)
        if mode == ConnectionMode.audioOnly {
            DDLogVerbose("ConnectionMode.audioOnly")
        }
        if mode == ConnectionMode.videoOnly {
            DDLogVerbose("ConnectionMode.videoOnly")
        }
        if mode == ConnectionMode.videoAudio {
            DDLogVerbose("ConnectionMode.videoAudio")
        }
    }
}

class BaseConnectionListController<Record>: FormViewController where Record: BaseConnection {
    var activeCount = 0
    var needRefresh = false
    var idList: [Int64] = []
    
    @objc func addButtonPressed(_ sender: UIBarButtonItem) {
        let holder = DataHolder.sharedInstance
        let conn = Record()
        holder.connecion = conn
        if let editorView = createEditor() {
            self.navigationController?.pushViewController(editorView, animated: true)
        }
    }
    
    @objc func editAction(barButtonItem: UIBarButtonItem) {
        //self.performSegue(withIdentifier: "openConnectionManager", sender: self)
        if let editorView = createManager() {
            self.navigationController?.pushViewController(editorView, animated: true)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 13.0, *) {
            initForm()
        }

        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        let edit = UIBarButtonItem(title: NSLocalizedString("Manage", comment: ""), style: .plain, target: self, action: #selector(editAction(barButtonItem:)))
        toolbarItems = [flexible, edit]
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addButtonPressed(_:)))
        navigationItem.rightBarButtonItem = addButton
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.isToolbarHidden = true
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.onConnectionsUpdate = nil
        if #available(iOS 13.0, *) {
            needRefresh = true
        } else {
            //Eureka have some issues on prior iOS versions, use full remove/add instead
            form.removeAll()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 13.0, *) {
            if needRefresh {
                updateList()
                needRefresh = false
            }
        } else {
            initForm()
        }
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.onConnectionsUpdate = {[weak self] in
            self?.updateList()
        }
    }
    
    internal func updateList() {
        if #available(iOS 13.0, *) {
        } else {
            form.removeAll()
            initForm()
            return
        }
        guard var section = form.sectionBy(tag: "connections") else { return }
        tableView?.beginUpdates()
        let connectionsOpt = try? dbQueue.read { db in
            try? Record.order(Column("name").asc).fetchAll(db)
        }
        let connections = connectionsOpt ?? []
        let connCount = connections.count
        if connCount < section.count {
            let deleteRange = connCount..<section.count
            for _ in deleteRange {
                section.removeLast()
            }
        }
        let rowCount = section.count
        for i in 0..<connections.count {
            let conn = connections[i]
            if i < rowCount {
                if let row = section[i] as? CheckRow {
                    setupRecord(row, conn: conn)
                    row.updateCell()
                }
            } else {
                section <<< CheckRow() { self.setupRecord($0, conn: conn) }
                    .onChange(self.onCheck)
            }
        }
        tableView?.endUpdates()

        idList = connections.map { $0.id ?? 0 }
        self.navigationController?.isToolbarHidden = connections.isEmpty
    }
    
    
    internal func initForm() {
        let connectionsOpt = try? dbQueue.read { db in
            try? Record.order(Column("name").asc).fetchAll(db)
        }
        let connections = connectionsOpt ?? []

        let section = Section() {
            $0.tag = "connections"
        }
        for c in connections {
            //c.dump()
            section
                <<< CheckRow() { self.setupRecord($0, conn: c) }
                .onChange(self.onCheck)
        }
        
        form +++ section
        if connections.count > 0 {
            navigationController?.isToolbarHidden = false
        }
        idList = connections.map { $0.id ?? 0 }
    }
    
    internal func setupRecord(_ row: CheckRow, conn: Record) {
        let deleteAction = SwipeAction(
            style: .destructive,
            title: NSLocalizedString("Delete", comment: ""),
            handler: { (action, row, completionHandler) in
                if let i = row.indexPath?.row, i < self.idList.count {
                    let id = self.idList[i]
                    var connection: Record?
                    try? dbQueue.read { db in
                        connection = try? Record.fetchOne(db, key: id)
                    }
                    if let connection = connection {
                        _ = try! dbQueue.write { db in
                            try! connection.delete(db)
                        }
                        try? dbQueue.read { db in
                            try? self.activeCount = Record.filter(sql: "active=?", arguments: ["1"]).order(Column("name")).fetchCount(db)
                            let count = try? Record.fetchCount(db)
                            if count ?? 0 == 0 {
                                self.navigationController?.isToolbarHidden = true
                            }
                        }
                        let message = String.localizedStringWithFormat(NSLocalizedString("Deleted: \"%@\"", comment: ""), connection.name)
                        Toast(text: message, theme: .success, layout: .statusLine)
                    }
                    self.idList.remove(at: i)
                }
                completionHandler?(true)
        })
        let editAction = SwipeAction(
            style: .normal,
            title: NSLocalizedString("Edit", comment: ""),
            handler: { (action, row, completionHandler) in
                guard let i = row.indexPath?.row, i < self.idList.count else {
                    completionHandler?(false)
                    return
                }
                let id = self.idList[i]
                let holder = DataHolder.sharedInstance
                let connection = try? dbQueue.read { db in
                    try? Record.fetchOne(db, key: id)
                }
                if let conn = connection {
                    holder.connecion = conn
                    if let editorView = self.createEditor() {
                        self.navigationController?.pushViewController(editorView, animated: true)
                    }
                }
                completionHandler?(true)
        })
        

        row.title = conn.name
        row.value = conn.active
        if row.tag?.isEmpty != false {
            row.tag = UUID().uuidString
        }

        row.trailingSwipe.actions = [deleteAction, editAction]
        row.trailingSwipe.performsFirstActionWithFullSwipe = true
    }
    
    internal func onCheck(row: CheckRow) {
        
    }
    
    internal func createEditor() -> FormViewController? {
        return nil
    }

    internal func createManager() -> FormViewController? {
        return nil
    }

}

class ConnectionsViewController: BaseConnectionListController<Connection> {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = NSLocalizedString("Connections", comment: "")
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func setupRecord(_ row: CheckRow, conn: Connection) {
        super.setupRecord(row, conn: conn)
        let shareAction = SwipeAction(
            style: .normal,
            title: NSLocalizedString("Grove", comment: ""),
            handler: { (action, row, completionHandler) in
                if let i = row.indexPath?.row, i < self.idList.count {
                    let id =  self.idList[i]
                    let record = try? dbQueue.read { db in
                        try? Connection.filter(key: id).fetchOne(db)
                    }
                    if let conn = record {
                        let storyboard = UIStoryboard.init(name: "Main", bundle: Bundle.main)
                        if let exportView = storyboard.instantiateViewController(withIdentifier: "exportGrove") as? ExportGroveController {
                            exportView.enableSelection = false
                            exportView.connections = [conn]
                            exportView.selectedConnections = [0]
                            self.navigationController?.pushViewController(exportView, animated: true)
                        }
                    }
                }
                completionHandler?(true)
        })
        row.leadingSwipe.actions = [shareAction]
    }
    
    override func onCheck(row: CheckRow) {
        if let active = row.value, let i = row.indexPath?.row {
            if !active {
                // deselection
                if i >= idList.count { return }
                let id = idList[i]
                try! dbQueue.write { db in
                    let connection = try! Connection.fetchOne(db, key: id)
                    connection?.active = false
                    try! connection?.update(db)
                }
            } else {
                if self.activeCount < 3 {
                    if i >= idList.count { return }
                    let id = idList[i]
                    try! dbQueue.write { db in
                        let connection = try! Connection.fetchOne(db, key: id)
                        connection?.active = true
                        try! connection?.update(db)
                    }
                } else {
                    row.value = false
                    let message = NSLocalizedString("Maximum count of simultaneous connections is 3.", comment: "")
                    Toast(text: message, theme: .info)
                }
            }
        }
        try? dbQueue.read { db in
            try? self.activeCount = Connection.filter(sql: "active=?", arguments: ["1"]).fetchCount(db)
        }
    }
    
    override func createEditor() -> FormViewController? {
        return ConnectionEditorViewController()
    }

    override func createManager() -> FormViewController? {
        return ConnectionManagerViewController()
    }

}

