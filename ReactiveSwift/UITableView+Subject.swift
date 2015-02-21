// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

private var selectionSubjectKey = "selectionSubjectKey"

public extension UITableView {
    
    public var selectionSubject: SetCollection<NSIndexPath> {
        return getAdditionalFieldOrUpdate(&selectionSubjectKey) { TableViewSelectionSubject<()>(self) }
    }

    public func setDataSource<T, C: UITableViewCell>(model: SeqCollection<T>, prototypeCell: String, _ f: (T, C) -> ()) -> Stream<()> {
        return setDataSource(model) { [weak self] (e, i) in
            let (cell) = self!.dequeueReusableCellWithIdentifier(prototypeCell) as! C
            f(e, cell)
            return cell
        }
    }
    
    public func setDataSource<T, C: UITableViewCell>(model: SeqView<T>, prototypeCell: String, _ f: (T, C) -> ()) -> Stream<()> {
        return setDataSource(model) { [weak self] (e, i) in
            let (cell) = self!.dequeueReusableCellWithIdentifier(prototypeCell) as! C
            f(e, cell)
            return cell
        }
    }
    
    public func setDataSource<T>(model: SeqCollection<T>, _ f: (T, Int) -> UITableViewCell) -> Stream<()> {
        return setDataSource(MutableTableViewDataSource(SeqViewErasure(model, f)), model)
    }
    
    public func setDataSource<T>(model: SeqView<T>, _ f: (T, Int) -> UITableViewCell) -> Stream<()> {
        return setDataSource(TableViewDataSource(SeqViewErasure(model, f)), model)
    }
    
    private func setDataSource<X>(source: TableViewDataSource, _ model: SeqView<X>) -> Stream<()> {
        dataSource = source
        reloadData()
        return mix([Streams.pure(())
            , model.skip(1)
                .foreach { [weak self] e -> () in self?.update(e, source.model); () }
                .onClose { [weak self] _ -> () in
                    self?.dataSource = nil
                    self?.reloadData()
                }
                .nullify()])
        
    }
    
    private func update<E>(update: SeqView<E>.UpdateType, _ guard: AnyObject) {
        if update.sender === guard {
            return
        }
        beginUpdates()
        for e in update.detail {
            deleteRowsAtIndexPaths(e.deletes, withRowAnimation: .None)
            insertRowsAtIndexPaths(e.inserts, withRowAnimation: .None)
        }
        endUpdates()
    }

}

private class TableViewSelectionSubject<T>: SetCollection<NSIndexPath> {
    
    private weak var table: UITableView!
    
    private var observer: NotificationObserver? = nil
    
    init(_ table: UITableView) {
        self.table = table
        super.init()
        
        observer = NotificationObserver(nil, UITableViewSelectionDidChangeNotification)
        { [weak self] e in
            if (e.object === self?.table) {
                self!.assign((self!.table.indexPathsForSelectedRows() as? [NSIndexPath]) ?? [], sender: table)
            }
        }
    }

    override func commit(update: UpdateType) {
        if update.sender !== table {
            for e in update.detail.insert {
                table.selectRowAtIndexPath(e, animated: false, scrollPosition: .None)
            }
            for e in update.detail.delete {
                table.deselectRowAtIndexPath(e, animated: false)
            }
        }
        super.commit(update)
    }

}

internal protocol SeqViewBridge: NSObjectProtocol {
    
    var count: Int { get }
    
    func viewForIndex(path: NSIndexPath) -> UIView

    func removeAt(index: NSIndexPath)
    
    func move(from: NSIndexPath, to: NSIndexPath)

}

internal class SeqViewErasure<T, V: UIView>: NSObject, SeqViewBridge {
    
    private let a: SeqView<T>
    private let f: (T, Int) -> V

    init(_ a: SeqView<T>, _ f: (T, Int) -> V) {
        self.a = a
        self.f = f
    }
    
    var count: Int { return Int(a.count) }
    
    var mutable: SeqCollection<T> { return a as! SeqCollection<T> }
    
    func viewForIndex(path: NSIndexPath) -> UIView {
        return f(a[path.row]!, path.row)
    }
    
    func removeAt(index: NSIndexPath) {
        mutable.removeAt(index.row)
    }
    
    func move(from: NSIndexPath, to: NSIndexPath) {
        mutable.move(from.row, to: to.row, sender: self)
    }

}

private class TableViewDataSource: NSObject, UITableViewDataSource {
    
    let model: SeqViewBridge
    
    required init (_ model: SeqViewBridge) {
        self.model = model
    }
    
    @objc func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return model.count
    }
    
    @objc func tableView(_: UITableView, cellForRowAtIndexPath path: NSIndexPath) -> UITableViewCell {
        return model.viewForIndex(path) as! UITableViewCell
    }
    
}

private class MutableTableViewDataSource: TableViewDataSource {
    
    @objc func tableView(_: UITableView, canEditRowAtIndexPath _: NSIndexPath) -> Bool {
        return true
    }
    
    @objc func tableView(_: UITableView, commitEditingStyle style: UITableViewCellEditingStyle, forRowAtIndexPath path: NSIndexPath) {
        if style == .Delete {
            model.removeAt(path)
        }
    }
    
    @objc func tableView(_: UITableView, canMoveRowAtIndexPath _: NSIndexPath) -> Bool {
        return true
    }
    
    @objc func tableView(_: UITableView, moveRowAtIndexPath src: NSIndexPath, toIndexPath dest: NSIndexPath) {
        model.move(src, to: dest)
    }

}

internal extension SeqDiff {
    var deletes: [NSIndexPath] { return indexPathsInRange(offset ..< (offset+delete)) }
    var inserts: [NSIndexPath] { return indexPathsInRange(offset ..< (offset+UInt(insert.count))) }
}

private func indexPathsInRange(range: Range<UInt>) -> [NSIndexPath] {
    var a = [NSIndexPath]()
    for i in range {
        a.append(NSIndexPath(forRow: Int(i), inSection: 0))
    }
    return a
}
