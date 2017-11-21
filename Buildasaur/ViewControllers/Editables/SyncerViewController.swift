//
//  SyncerViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 08/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import BuildaUtils
import XcodeServerSDK
import BuildaKit

protocol SyncerViewControllerDelegate: class {

    func didCancelEditingOfSyncerConfig(_ config: SyncerConfig)
    func didSaveSyncerConfig(_ config: SyncerConfig)
    func didRequestEditing()
}

class SyncerViewController: ConfigEditViewController {
    var syncerConfig: SyncerConfig! = nil {
        didSet {
            if let syncer = self.syncerManager.syncerWithRef(ref: self.syncerConfig.id) {
                self.syncer = syncer
            }

            self.syncIntervalStepper.doubleValue = self.syncerConfig.syncInterval
            self.syncInterval = self.syncerConfig.syncInterval
            self.lttmToggle.on = self.syncerConfig.waitForLttm
            self.postStatusCommentsToggle.on = self.syncerConfig.postStatusComments
            self.watchedBranches = self.syncerConfig.watchedBranchNames

            self.generateConfig()
        }
    }

    var xcodeServerConfig: XcodeServerConfig! = nil {
        didSet {
            self.xcodeServerNameLabel.stringValue = self.xcodeServerConfig.host
        }
    }
    var projectConfig: ProjectConfig! = nil {
        didSet {
            self.projectNameLabel.stringValue = self.projectConfig.name
        }
    }
    var buildTemplate: BuildTemplate! = nil {
        didSet {
            self.buildTemplateNameLabel.stringValue = self.buildTemplate.name
        }
    }

    weak var delegate: SyncerViewControllerDelegate?

    private var syncer: StandardSyncer? {
        didSet {
            self.update(forSyncer: self.syncer)
        }
    }

    @IBOutlet weak var editButton: NSButton!
    @IBOutlet weak var statusTextField: NSTextField!
    @IBOutlet weak var startStopButton: NSButton!
    @IBOutlet weak var statusActivityIndicator: NSProgressIndicator!
    @IBOutlet weak var stateLabel: NSTextField!

    @IBOutlet weak var xcodeServerNameLabel: NSTextField!
    @IBOutlet weak var projectNameLabel: NSTextField!
    @IBOutlet weak var buildTemplateNameLabel: NSTextField!

    @IBOutlet weak var syncIntervalStepper: NSStepper!
    @IBOutlet weak var syncIntervalTextField: NSTextField!
    @IBOutlet weak var lttmToggle: NSButton!
    @IBOutlet weak var postStatusCommentsToggle: NSButton!

    @IBOutlet weak var manualBotManagementButton: NSButton!
    @IBOutlet weak var branchWatchingButton: NSButton!

    private var isSyncing: Bool = false {
        didSet {
            self.editing = !self.isSyncing

            self.startStopButton.title = self.isSyncing ? "Stop" : "Start"
            if self.isSyncing {
                self.statusActivityIndicator.startAnimation(nil)
            } else {
                self.statusActivityIndicator.stopAnimation(nil)
            }
            self.manualBotManagementButton.isEnabled = !self.isSyncing
            self.branchWatchingButton.isEnabled = !self.isSyncing

            self.trashButton.isHidden = self.isSyncing

            //TODO: actually look into whether we've errored on the last sync
            //etc. to be more informative with this status (green should
            //only mean "Everything is OK, AFAIK", not "We're syncing")
            self.availabilityCheckState = self.isSyncing ? .succeeded : .unchecked
        }
    }

    private var syncInterval: Double = 15 {
        didSet {
            self.syncIntervalTextField.doubleValue = self.syncInterval
            self.generateConfig()
        }
    }
    private var watchedBranches: [String] = [] {
        didSet {
            self.generateConfig()
        }
    }

    override var editing: Bool {
        didSet {
            self.editButton.isEnabled = self.editing
            self.syncIntervalStepper.isEnabled = self.editing
            self.lttmToggle.isEnabled = self.editing
            self.postStatusCommentsToggle.isEnabled = self.editing
        }
    }

    private var generatedConfig: SyncerConfig! = nil

    //----

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupBindings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.nextTitle = "Done"
        self.nextAllowed = true
        self.previousAllowed = false

        self.update(forSyncer: self.syncer)
    }

    private func update(forSyncer syncer: StandardSyncer?) {
        let stringState: String
        if let syncer = self.syncer {
            stringState = SyncerViewController.stringForEvent(syncer.state, syncer: syncer)
        } else {
            stringState = ""
        }
        self.statusTextField.stringValue = stringState

        if let syncer = self.syncer {
            let checkSyncer = { [weak self] in
                self?.stateLabel.stringValue = SyncerStatePresenter.stringForState(syncer.state, active: syncer.active)
                self?.statusTextField.stringValue = SyncerViewController.stringForEvent(syncer.state, syncer: syncer)

            }
            syncer.onActiveChanged = { [weak self] active in
                self?.isSyncing = active
                checkSyncer()
            }
            syncer.onStateChanged = { _ in
                checkSyncer()
            }
            checkSyncer()
            self.isSyncing = syncer.active
        } else {
            self.isSyncing = false
        }
    }

    func setupBindings() {
        self.lttmToggle.onClick = { [weak self] _ in
            self?.generateConfig()
        }
        self.postStatusCommentsToggle.onClick = { [weak self] _ in
            self?.generateConfig()
        }
        self.setupSyncInterval()
    }

    func generateConfig() {
        let original = self.syncerConfig
        let waitForLttm = self.lttmToggle.on
        let postStatusComments = self.postStatusCommentsToggle.on
        let syncInterval = self.syncInterval
        let watchedBranches = self.watchedBranches

        var config = original!
        config.waitForLttm = waitForLttm
        config.postStatusComments = postStatusComments
        config.syncInterval = syncInterval
        config.watchedBranchNames = watchedBranches

        self.generatedConfig = config

        //hmm... we technically aren't saving do disk yet
        //but at least if you edit sth else and come back you'll see
        //your latest setup.
        self.delegate?.didSaveSyncerConfig(config)
    }

    func setupSyncInterval() {
        self.syncIntervalStepper.onValueChanged = { [weak self] _ in
            guard let sself = self else { return }
            let value = sself.syncIntervalStepper.doubleValue

            if value < 1 {
                UIUtils.showAlertWithText("Sync interval cannot be less than 1 second.")
                sself.syncIntervalStepper.doubleValue = 1
            } else {
                sself.syncInterval = value
            }
        }
    }

    override func delete() {

        //ask if user really wants to delete
        UIUtils.showAlertAskingForRemoval("Do you really want to remove this Syncer? This cannot be undone.", completion: { (remove) -> Void in

            if remove {
                let currentConfig = self.generatedConfig
                self.storageManager.removeSyncer(syncerConfig: currentConfig!)
                self.delegate?.didCancelEditingOfSyncerConfig(currentConfig!)
            }
        })
    }

    @IBAction func startStopButtonTapped(_ sender: AnyObject) {
        self.toggleActive()
    }

    @IBAction func editButtonClicked(_ sender: AnyObject) {
        self.editClicked()
    }

    private func editClicked() {
        self.delegate?.didRequestEditing()
    }

    override func shouldGoNext() -> Bool {
        self.save()
        return true
    }

    private func toggleActive() {

        let isSyncing = self.isSyncing

        if isSyncing {

            //syncing, just stop

            self.syncer!.active = false

        } else {

            //not syncing

            //save config to disk, which will result in us having a proper
            //syncer coming from the SyncerManager
            self.save()

            //TODO: verify syncer before starting

            //start syncing (now there must be a syncer)
            self.syncer!.active = true
        }
    }

    private func save() {
        let newConfig = self.generatedConfig
        self.storageManager.addSyncerConfig(config: newConfig!)
        self.delegate?.didSaveSyncerConfig(newConfig!)
    }
}

extension SyncerViewController {

    // MARK: handling branch watching, manual bot management and link opening

    @IBAction func branchWatchingTapped(_ sender: AnyObject) {
        precondition(self.syncer != nil)
        self.performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "showBranchWatching"), sender: self)
    }

    @IBAction func manualBotManagementTapped(_ sender: AnyObject) {
        precondition(self.syncer != nil)
        self.performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "showManual"), sender: self)
    }

    @IBAction func helpLttmButtonTapped(_ sender: AnyObject) {
        openLink("https://github.com/czechboy0/Buildasaur/blob/master/README.md#unlock-the-lttm-barrier")
    }

    @IBAction func helpPostStatusCommentsButtonTapped(_ sender: AnyObject) {
        openLink("https://github.com/czechboy0/Buildasaur/blob/master/README.md#envelope-posting-status-comments")
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {

        if let manual = segue.destinationController as? ManualBotManagementViewController {
            manual.syncer = self.syncer
            manual.storageManager = self.storageManager
        }

        if let branchWatching = segue.destinationController as? BranchWatchingViewController {
            branchWatching.syncer = self.syncer
            branchWatching.delegate = self
        }
    }
}

extension SyncerViewController: BranchWatchingViewControllerDelegate {

    func didUpdateWatchedBranches(_ branches: [String]) {
        self.watchedBranches = branches
        self.save()
    }
}

extension SyncerViewController {

    // MARK: status changes

    static func stringForEvent(_ event: SyncerEventType, syncer: Syncer) -> String {
        switch event {
        case .DidBecomeActive:
            return self.syncerBecameActive(syncer)
        case .DidEncounterError(let error):
            return self.syncerEncounteredError(syncer, error: error)
        case .DidFinishSyncing:
            return self.syncerDidFinishSyncing(syncer)
        case .DidStartSyncing:
            return self.syncerDidStartSyncing(syncer)
        case .DidStop:
            return self.syncerStopped(syncer)
        case .Initial:
            return "Click Start to start syncing your project..."
        }
    }

    static func syncerBecameActive(_ syncer: Syncer) -> String {
        return self.report("Syncer is now active...", syncer: syncer)
    }

    static func syncerStopped(_ syncer: Syncer) -> String {
        return self.report("Syncer is stopped", syncer: syncer)
    }

    static func syncerDidStartSyncing(_ syncer: Syncer) -> String {
        var messages = [
            "Syncing in progress..."
        ]

        if let lastStartedSync = syncer.lastSyncStartDate {
            let lastSyncString = "Started sync at \(lastStartedSync)"
            messages.append(lastSyncString)
        }

        return self.reportMultiple(messages, syncer: syncer)
    }

    static func syncerDidFinishSyncing(_ syncer: Syncer) -> String {
        var messages = [
            "Syncer is Idle... Waiting for the next sync..."
        ]

        if let ourSyncer = syncer as? StandardSyncer {

            //error?
            if let error = ourSyncer.lastSyncError {
                messages.insert("Last sync failed with error \(error.localizedDescription)", at: 0)
            }

            //info reports
            let reports = ourSyncer.reports
            let reportsArray = reports.keys.map({ "\($0): \(reports[$0]!)" })
            messages += reportsArray
        }

        return self.reportMultiple(messages, syncer: syncer)
    }

    static func syncerEncounteredError(_ syncer: Syncer, error: Error) -> String {
        return self.report("Error: \((error as NSError).localizedDescription)", syncer: syncer)
    }

    static func report(_ string: String, syncer: Syncer) -> String {
        return self.reportMultiple([string], syncer: syncer)
    }

    static func reportMultiple(_ strings: [String], syncer: Syncer) -> String {
        var itemsToReport = [String]()

        if let lastFinishedSync = syncer.lastSuccessfulSyncFinishedDate {
            let lastSyncString = "Last successful sync at \(lastFinishedSync)"
            itemsToReport.append(lastSyncString)
        }

        strings.forEach { itemsToReport.append($0) }
        return itemsToReport.joined(separator: "\n")
    }
}
