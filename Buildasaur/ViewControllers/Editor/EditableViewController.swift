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
