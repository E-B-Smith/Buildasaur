//
//  EditableViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/5/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaUtils
import BuildaKit

class EditableViewController: NSViewController {

    var storageManager: StorageManager {
        return self.syncerManager.storageManager
    }
    var syncerManager: SyncerManager!
    var editingAllowed: Bool = true
    var editing: Bool = true

    var nextAllowed: Bool = true {
        didSet {
            self.onNextAllowedChanged?(self.nextAllowed)
        }
    }
    var previousAllowed: Bool = true {
        didSet {
            self.onPreviousAllowedChanged?(self.previousAllowed)
        }
    }
    var cancelAllowed: Bool = true

    var nextTitle: String = "Next" {
        didSet {
            self.onNextTitleChanged?(self.nextTitle)
        }
    }

    var onNextAllowedChanged: ((Bool) -> Void)?
    var onPreviousAllowedChanged: ((Bool) -> Void)?
    var onCancelAllowedChanged: ((Bool) -> Void)?
    var onNextTitleChanged: ((String) -> Void)?

    var onWantsNext: ((Bool) -> Void)?
    var onWantsPrevious: ((Bool) -> Void)?

    //TODO ???
    /*typealias ActionSignal = Signal<Void, NoError>
    typealias AnimatableSignal = Signal<Bool, NoError>
    private typealias ActionObserver = ActionSignal.Observer
    private typealias AnimatableObserver = AnimatableSignal.Observer

    var wantsNext: AnimatableSignal!
    var wantsPrevious: ActionSignal!

    private var sinkNext: AnimatableObserver!
    private var sinkPrevious: ActionObserver!*/

    override func viewDidLoad() {
        super.viewDidLoad()

        //TODO ???
        /*let (wn, sn) = AnimatableSignal.pipe()
        self.wantsNext = wn
        self.sinkNext = sn
        let (wp, sp) = ActionSignal.pipe()
        self.wantsPrevious = wp
        self.sinkPrevious = sp*/
    }

    //call from inside of controllers, e.g.
    //when shouldGoNext starts validating and it succeeds some time later,
    //call goNext to finish going next. otherwise don't call
    //and force user to fix the problem.

    final func goNext(animated: Bool = false) {
        self.onWantsNext?(animated)
    }

    final func goPrevious() {
        self.onWantsPrevious?(false)
    }

    //for overriding

    func shouldGoNext() -> Bool {
        return true
    }

    func shouldGoPrevious() -> Bool {
        return true
    }

    func shouldCancel() -> Bool {
        return true
    }
}
