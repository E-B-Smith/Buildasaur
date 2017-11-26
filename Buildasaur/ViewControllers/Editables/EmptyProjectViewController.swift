//
//  EmptyProjectViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 30/09/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit
import BuildaUtils

protocol EmptyProjectViewControllerDelegate: class {
    func didSelectProjectConfig(_ config: ProjectConfig)
}

extension ProjectConfig {
    var name: String {
        let fileWithExtension = (self.url as NSString).lastPathComponent
        let file = (fileWithExtension as NSString).deletingPathExtension
        return file
    }
}

class EmptyProjectViewController: EditableViewController {
    //for cases when we're editing an existing syncer - show the
    //right preference.
    var existingConfigId: RefType?

    weak var emptyProjectDelegate: EmptyProjectViewControllerDelegate?

    @IBOutlet weak var existingProjectsPopup: NSPopUpButton!

    private var projectConfigs: [ProjectConfig] = []
    private var selectedConfig: ProjectConfig? = nil {
        didSet {
            self.nextAllowed = self.selectedConfig != nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupDataSource()
        self.setupPopupAction()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        //select if existing config is being edited
        let index: Int
        if let id = self.selectedConfig?.id {
            let ids = self.projectConfigs.map { $0.id }
            index = ids.index(of: id) ?? 0
        } else if let configId = self.existingConfigId {
            let ids = self.projectConfigs.map { $0.id }
            index = ids.index(of: configId) ?? 0
        } else {
            index = 0
        }
        self.selectItemAtIndex(index)
        self.existingProjectsPopup.selectItem(at: index)
        self.nextAllowed = self.selectedConfig != nil
    }

    private var addNewString: String {
        return "Add new Xcode Project..."
    }

    private func newConfig() -> ProjectConfig {
        return ProjectConfig()
    }

    override func shouldGoNext() -> Bool {
        var current = self.selectedConfig!
        if current.url.isEmpty {
            //just new config, needs to be picked
            guard let picked = self.pickNewProject() else { return false }
            current = picked
        }

        self.didSelectProjectConfig(current)
        return super.shouldGoNext()
    }

    private func selectItemAtIndex(_ index: Int) {
        let configs = self.projectConfigs
        // last item is "add new"
        let config = (index == configs.count) ? self.newConfig() : configs[index]
        self.selectedConfig = config
    }

    private func setupPopupAction() {
        self.existingProjectsPopup.onClick = { [weak self] _ in
            guard let sself = self else { return }
            let index = sself.existingProjectsPopup.indexOfSelectedItem
            sself.selectItemAtIndex(index)
        }
    }

    private func setupDataSource() {
        let update = { [weak self] in
            guard let sself = self else { return }

            sself.projectConfigs = sself.storageManager.projectConfigs.values.filter {
                (try? Project(config: $0)) != nil
            }.sorted {
                $0.name < $1.name
            }

            let popup = sself.existingProjectsPopup
            popup?.removeAllItems()
            var configDisplayNames = sself.projectConfigs.map { $0.name }
            configDisplayNames.append(sself.addNewString)
            popup?.addItems(withTitles: configDisplayNames)
        }
        self.storageManager.onUpdateProjectConfigs = update
        update()
    }

    private func didSelectProjectConfig(_ config: ProjectConfig) {
        Log.verbose("Selected \(config.url)")
        self.emptyProjectDelegate?.didSelectProjectConfig(config)
    }

    private func pickNewProject() -> ProjectConfig? {
        if let url = StorageUtils.openWorkspaceOrProject() {

            do {
                try self.storageManager.checkForProjectOrWorkspace(url: url)
                var config = ProjectConfig()
                config.url = url.path
                return config
            } catch {
                //local source is malformed, something terrible must have happened, inform the user this can't be used (log should tell why exactly)
                let buttons = ["See workaround", "OK"]

                UIUtils.showAlertWithButtons("Couldn't add Xcode project at path \(url.absoluteString), error: \((error as NSError).userInfo["info"] ?? "Unknown").", buttons: buttons, style: .critical, completion: { (tappedButton) -> Void in

                    if tappedButton == "See workaround" {
                        openLink("https://github.com/czechboy0/Buildasaur/issues/165#issuecomment-148220340")
                    }
                })
            }
        } else {
            //user cancelled
        }
        return nil
    }
}
