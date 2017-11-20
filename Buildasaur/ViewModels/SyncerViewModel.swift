//
//  SyncerViewModel.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 28/09/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaKit

struct SyncerStatePresenter {
    static func stringForState(_ state: SyncerEventType, active: Bool) -> String {

        guard active else {
            return "🚧 stopped"
        }

        let errorGen = { () -> String in
            "❗ error!"
        }

        switch state {
        case .DidStartSyncing:
            return "🔄 syncing..."
        case .DidFinishSyncing(let error):
            if error != nil {
                return errorGen()
            }
        case .DidEncounterError:
            return errorGen()
        default: break
        }
        return "✅ idle..."
    }
}

class SyncerViewModel {
    private(set) var syncer: StandardSyncer {
        didSet {
            self.updateFromSync(self.syncer)
            self.syncer.onRequireUpdate = { [weak self] in
                guard let sself = self else { return }
                sself.updateFromSync(sself.syncer)
            }
        }
    }
    private(set) var status: String {
        didSet {
            self.onStatusChanged?(self.status)
        }
    }
    var onStatusChanged: ((String) -> Void)?
    private(set) var host: String {
        didSet {
            self.onHostChanged?(self.host)
        }
    }
    var onHostChanged: ((String) -> Void)?
    private(set) var projectName: String {
        didSet {
            self.onProjectNameChanged?(self.projectName)
        }
    }
    var onProjectNameChanged: ((String) -> Void)?
    let initialProjectName: String
    private(set) var buildTemplateName: String {
        didSet {
            self.onBuildTemplateNameChanged?(self.buildTemplateName)
        }
    }
    var onBuildTemplateNameChanged: ((String) -> Void)?
    private(set) var editButtonTitle: String {
        didSet {
            self.onEditButtonTitleChanged?(self.editButtonTitle)
        }
    }
    var onEditButtonTitleChanged: ((String) -> Void)?
    private(set) var editButtonEnabled: Bool {
        didSet {
            self.onEditButtonEnabledChanged?(self.editButtonEnabled)
        }
    }
    var onEditButtonEnabledChanged: ((Bool) -> Void)?
    private(set) var controlButtonTitle: String {
        didSet {
            self.onControlButtonTitleChanged?(self.controlButtonTitle)
        }
    }
    var onControlButtonTitleChanged: ((String) -> Void)?

    typealias PresentEditViewControllerType = (ConfigTriplet) -> Void
    let presentEditViewController: PresentEditViewControllerType

    init(syncer: StandardSyncer, presentEditViewController: @escaping PresentEditViewControllerType) {
        self.presentEditViewController = presentEditViewController

        self.status = ""
        self.host = ""
        self.projectName = ""
        self.controlButtonTitle = ""
        self.syncer = syncer

        //pull initial project name for sorting
        self.initialProjectName = syncer.project.workspaceMetadata?.projectName ?? ""

        self.buildTemplateName = syncer.buildTemplate.name
        self.editButtonTitle = "View"
        self.editButtonEnabled = true

        self.updateFromSync(syncer)

        syncer.onRequireUpdate = { [weak self] in
            guard let sself = self else { return }
            sself.updateFromSync(sself.syncer)
        }
    }

    private func updateFromSync(_ syncer: StandardSyncer) {
        self.status = SyncerStatePresenter.stringForState(syncer.state, active: syncer.active)
        self.host = syncer.xcodeServer.config.host
        self.projectName = syncer.project.workspaceMetadata?.projectName ?? "[No Project]"
        self.controlButtonTitle = syncer.active ? "Stop" : "Start"
    }

    func viewButtonClicked() {
        //present the edit window
        let triplet = self.syncer.configTriplet
        self.presentEditViewController(triplet)
    }

    func startButtonClicked() {
        self.syncer.active = true
        self.updateFromSync(self.syncer)
    }

    func stopButtonClicked() {
        self.syncer.active = false
        self.updateFromSync(self.syncer)
    }

    func controlButtonClicked() {
        //TODO: run through validation first?
        self.syncer.active = !self.syncer.active
        self.updateFromSync(self.syncer)
    }

}
