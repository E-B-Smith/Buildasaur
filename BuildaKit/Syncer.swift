//
//  Syncer.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 14/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK

public enum SyncerEventType {

    case Initial

    case DidBecomeActive
    case DidStop

    case DidStartSyncing
    case DidFinishSyncing(Error?)

    case DidEncounterError(Error)
}

class Trampoline: NSObject {

    var block: (() -> Void)?
    @objc func jump() { self.block?() }
}

public class SyncerError: Error {
    static func with(_ info: String) -> Error {
        return NSError(domain: "Syncer", code: -1, userInfo: ["info": info])
    }
}

@objc public class Syncer: NSObject {

    public private(set) var state: SyncerEventType = .Initial {
        didSet {
            self.onStateChanged?(self.state)
        }
    }
    public var onStateChanged: ((SyncerEventType) -> Void)?

    //public
    public internal(set) var reports: [String: String] = [:]
    public private(set) var lastSuccessfulSyncFinishedDate: Date?
    public private(set) var lastSyncFinishedDate: Date?
    public private(set) var lastSyncStartDate: Date?
    public private(set) var lastSyncError: Error?

    private var currentSyncError: NSError?

    /// How often, in seconds, the syncer should pull data from both sources and resolve pending actions
    public var syncInterval: TimeInterval

    private var isSyncing: Bool {
        didSet {
            if !oldValue && self.isSyncing {
                self.lastSyncStartDate = Date()
                self.state = .DidStartSyncing
            } else if oldValue && !self.isSyncing {
                self.lastSyncFinishedDate = Date()
                self.state = .DidFinishSyncing(self.lastSyncError)
            }
        }
    }

    public var active: Bool {
        didSet {
            if active && !oldValue {
                let s = #selector(Trampoline.jump)
                let timer = Timer(timeInterval: self.syncInterval, target: self.trampoline, selector: s, userInfo: nil, repeats: true)
                self.timer = timer
                RunLoop.main.add(timer, forMode: .commonModes)
                self._sync() //call for the first time, next one will be called by the timer
                self.state = .DidBecomeActive
            } else if !active && oldValue {
                self.timer?.invalidate()
                self.timer = nil
                self.state = .DidStop
            }
            self.onActiveChanged?(self.active)
        }
    }
    public var onActiveChanged: ((Bool) -> Void)?

    //private
    var timer: Timer?
    private let trampoline: Trampoline

    //---------------------------------------------------------

    public init(syncInterval: TimeInterval) {
        self.syncInterval = syncInterval
        self.active = false
        self.isSyncing = false
        self.trampoline = Trampoline()
        super.init()
        self.trampoline.block = { [weak self] () -> Void in
            self?._sync()
        }
    }

    func _sync() {

        //this shouldn't even be getting called now
        if !self.active {
            self.timer?.invalidate()
            self.timer = nil
            return
        }

        if self.isSyncing {
            //already is syncing, wait till it's finished
            Log.info("Trying to sync again even though the previous sync hasn't finished. You might want to consider making the sync interval longer. Just sayin'")
            return
        }

        Log.untouched("\n------------------------------------\n")

        self.isSyncing = true
        self.currentSyncError = nil
        self.reports.removeAll(keepingCapacity: true)

        let start = Date()
        Log.info("Sync starting at \(start)")

        self.sync { () -> Void in

            let end = Date()
            let finishState: String
            if let error = self.currentSyncError {
                finishState = "with error"
                self.lastSyncError = error
            } else {
                finishState = "successfully"
                self.lastSyncError = nil
                self.lastSuccessfulSyncFinishedDate = Date()
            }
            Log.info("Sync finished \(finishState) at \(end), took \(end.timeIntervalSince(start).clipTo(3)) seconds.")
            self.isSyncing = false
        }
    }

    func notifyErrorString(errorString: String, context: String?) {
        self.notifyError(error: SyncerError.with(errorString), context: context)
    }

    func notifyError(error: Error?, context: String?) {
        self.notifyError(error: error as NSError?, context: context)
    }

    func notifyError(error: NSError?, context: String?) {

        var message = "Syncing encountered a problem. "

        if let error = error {
            message += "Error: \(error.localizedDescription). "
        }
        if let context = context {
            message += "Context: \(context)"
        }
        Log.error(message)
        self.currentSyncError = error
        self.state = .DidEncounterError(SyncerError.with(message))
    }

    /**
    To be overriden by subclasses to do their logic in
    */
    public func sync(completion: @escaping () -> Void) {
        //sync logic here
        assertionFailure("Should be overriden by subclasses")
    }
}
