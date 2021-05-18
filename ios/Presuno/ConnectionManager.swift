import CocoaLumberjackSwift
import Eureka
import GRDB
import SwiftMessages

class BaseConnManagerViewController<Record>: FormViewController where Record: BaseConnection {
    var connections = [Record]()
    var selected = 0
    
    var mark: UIBarButtonItem?
    var edit: UIBarButtonItem?
    var trash: UIBarButtonItem?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addButtonPressed(_:)))
        navigationItem.rightBarButtonItem = addButton
        
        mark = UIBarButtonItem(title: NSLocalizedString("Mark All", comment: ""), style: .plain, target: self, action: #selector(markAction(barButtonItem:)))
        
        edit = UIBarButtonItem(title: NSLocalizedString("Edit", comment: ""), style: .plain, target: self, action: #selector(editAction(barButtonItem:)))
        
        trash = UIBarButtonItem(barButtonSystemItem: .trash , target: self, action: #selector(trashAction(barButtonItem:)))
        
        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        let flexible2 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        
        toolbarItems = [mark!, flexible, edit!, flexible2, trash!]
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.isToolbarHidden = true
        form.removeAll()
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.onConnectionsUpdate = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        initForm()
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.onConnectionsUpdate = {[weak self] in
            self?.form.removeAll()
            self?.initForm()
        }
    }
    
    func initForm() {
        let connectionsOpt = try? dbQueue.read { db in
            try? Record.order(Column("name").asc).fetchAll(db)
        }
        connections = connectionsOpt ?? []
        if connections.isEmpty {
            _ = self.navigationController?.popViewController(animated: false)
            return
        }
        let section = Section()
        section.tag = "connection_list"
        for c in connections {
            //dump(c)
            DDLogInfo("ID \(c.id ?? -1)")
            section
                <<< CheckRow() { setupRecord($0, conn: c) }
        }
        form +++ section
        
        edit?.isEnabled = false
        trash?.isEnabled = false
        mark?.isEnabled = true
        mark?.title = NSLocalizedString("Mark All", comment: "")
        navigationController?.isToolbarHidden = false
        
        selected = 0
        
    }
    
    internal func setupRecord(_ row: CheckRow, conn: Record) {
        row.title = conn.name
        row.tag = "\(conn.id!)"
        row.onChange { row in
            if let active = row.value, let _ = row.tag {
                if !active {
                    self.selected -= 1
                    self.mark?.title = NSLocalizedString("Mark All", comment: "")
                } else {
                    self.selected += 1
                    if self.selected == self.connections.count {
                        self.mark?.title = NSLocalizedString("Unmark All", comment: "")
                    }
                }
                self.edit?.isEnabled = (self.selected == 1)
                self.trash?.isEnabled = (self.selected > 0)
            }
        }
    }
    
    internal func createEditor() -> FormViewController? {
        return nil
    }

    @objc func addButtonPressed(_ sender: UIBarButtonItem) {
        let holder = DataHolder.sharedInstance
        let conn = Record()
        conn.active = true
        
        holder.connecion = conn
        if let editoriew = createEditor() {
            self.navigationController?.pushViewController(editoriew, animated: true)
        }
    }
    
    @objc func markAction(barButtonItem: UIBarButtonItem) {
        if let section = form.sectionBy(tag: "connection_list") {
            let action = (selected < connections.count) // selected == connections.count -> Unmark All
            for row in section {
                let check = row as! CheckRow
                check.value = action
                check.reload()
            }
        }
    }
    
    @objc func editAction(barButtonItem: UIBarButtonItem) {
        guard selected == 1, let section = form.sectionBy(tag: "connection_list") else { return }
        let selRow = section.first { $0.baseValue as? Bool ?? false }
        guard let tag = selRow?.tag, let id = Int64(tag) else { return }
        let holder = DataHolder.sharedInstance
        let connection = try? dbQueue.read { db in
            try? Record.fetchOne(db, key: id)
        }
        if let conn = connection {
            holder.connecion = conn
            if let editoriew = createEditor() {
                self.navigationController?.pushViewController(editoriew, animated: true)
            }
        }
    }
    
    func presentDeleteAlert() {
        let message = String.localizedStringWithFormat(NSLocalizedString("Delete selected items?", comment: ""))
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let delete = UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive, handler: { action in
            if let section = self.form.sectionBy(tag: "connection_list") {
                for row in section {
                    let check = row as! CheckRow
                    if check.value == true, let tag = row.tag {
                        let connectionOpt = try? dbQueue.read { db in
                            try? Record.fetchOne(db, key: Int64(tag))
                        }
                        if let connection = connectionOpt {
                            _ = try! dbQueue.write { db in
                                try! connection.delete(db)
                            }
                        }
                    }
                }
                self.form.removeAll()
                self.initForm()
            }
        })
        alertController.addAction(delete)
        let cancel = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        alertController.addAction(cancel)
        present(alertController, animated: true, completion: nil)
    }
    
    @objc func trashAction(barButtonItem: UIBarButtonItem) {
        if selected > 0 {
            presentDeleteAlert()
        }
    }
    
}

class ConnectionManagerViewController: BaseConnManagerViewController<Connection> {
    override func createEditor() -> FormViewController? {
        return ConnectionEditorViewController()
    }
    
}
