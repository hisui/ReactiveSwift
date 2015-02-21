// Copyright (c) 2014 segfault.jp. All rights reserved.

import UIKit

public extension UICollectionView {
    
    private func dequeueCell<C: UICollectionViewCell>(id: String) -> C {
        return dequeueReusableCellWithReuseIdentifier(id, forIndexPath: NSIndexPath(forRow: 0, inSection: 0)) as! C
    }

    public func setDataSource<T, C: UICollectionViewCell>(model: SeqView<T>, prototypeCell: String, _ f: (T, C) -> ()) -> Stream<()> {
        return setDataSource(model) { [weak self] (e, i) in
            let (cell) = self!.dequeueCell(prototypeCell) as C
            f(e, cell)
            return cell
        }
    }

    public func setDataSource<T>(model: SeqView<T>, _ f: (T, Int) -> UICollectionViewCell) -> Stream<()> {
        return setDataSource(CollectionViewDataSource(SeqViewErasure(model, f)), model)
    }

    private func setDataSource<X>(source: CollectionViewDataSource, _ model: SeqView<X>) -> Stream<()> {
        dataSource = source
        reloadData()
        return model.skip(1)
            .foreach { [weak self] e -> () in self?.update(e, source.model); () }
            .onClose { [weak self] _ -> () in
                self?.dataSource = nil
                self?.reloadData()
            }
            .nullify()
    }
    
    private func update<E>(update: SeqView<E>.UpdateType, _ guard: AnyObject) {
        performBatchUpdates({
            for e in update.detail {
                self.deleteItemsAtIndexPaths(e.deletes)
                self.insertItemsAtIndexPaths(e.inserts)
            }
        }, completion: nil)
    }
    
}

class CollectionViewDataSource: NSObject, UICollectionViewDataSource {
    
    private let model: SeqViewBridge

    required init (_ model: SeqViewBridge) {
        self.model = model
    }
    
    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return model.count
    }
    
    func collectionView(_: UICollectionView, cellForItemAtIndexPath path: NSIndexPath) -> UICollectionViewCell {
        return model.viewForIndex(path) as! UICollectionViewCell
    }

}
