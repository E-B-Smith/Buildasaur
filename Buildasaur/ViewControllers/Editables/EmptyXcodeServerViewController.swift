//
//  EmptyXcodeServerViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/3/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaKit
import BuildaUtils
import XcodeServerSDK

protocol EmptyXcodeServerViewControllerDelegate: class {
    func didSelectXcodeServerConfig(_ config: XcodeServerConfig)
}

class EmptyXcodeServerViewController: EditableViewController {

    //for cases when we're editing an existing syncer - show the
    //right preference.
    var existingConfigId: RefType?

    weak var emptyServerDelegate: EmptyXcodeServerViewControllerDelegate?

    @IBOutlet weak var existingXcodeServersPopup: NSPopUpButton!

    private var xcodeServerConfigs: [XcodeServerConfig] = []
    private var selectedConfig: XcodeServerConfig? {
        didSet {
            self.nextAllowed = self.selectedConfig != nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupDataSource()
        self.setupPopupAction()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.nextTitle = "Next"
        self.previousAllowed = self.existingConfigId != nil
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        //select if existing config is being edited
        let index: Int
        if let id = self.selectedConfig?.id {
            let ids = self.xcodeServerConfigs.map { $0.id }
            index = ids.index(of: id) ?? 0
        } else if let configId = self.existingConfigId {
            let ids = self.xcodeServerConfigs.map { $0.id }
            index = ids.index(of: configId) ?? 0
        } else {
            index = 0
        }
        self.selectItemAtIndex(index)
        self.existingXcodeServersPopup.selectItem(at: index)
        self.nextAllowed = self.selectedConfig != nil
    }

    private var addNewString: String {
        return "Add new Xcode Server..."
    }

    private func newConfig() -> XcodeServerConfig {
        return XcodeServerConfig()
    }

    override func shouldGoNext() -> Bool {
        self.didSelectXcodeServer(self.selectedConfig!)
        return super.shouldGoNext()
    }

    private func selectItemAtIndex(_ index: Int) {
        let configs = self.xcodeServerConfigs
        // last item is "add new"
        let config = (index == configs.count) ? self.newConfig() : configs[index]
        self.selectedConfig = config
    }

    private func setupPopupAction() {
        self.existingXcodeServersPopup.onClick = { [weak self] _ in
            if let index = self?.existingXcodeServersPopup.indexOfSelectedItem {
                self?.selectItemAtIndex(index)
            }
        }
    }

    private func setupDataSource() {
        let update = { [weak self] in
            guard let sself = self else { return }

            sself.xcodeServerConfigs = sself.storageManager.serverConfigs.values.sorted {
                $0.host < $1.host
            }

            let popup = sself.existingXcodeServersPopup
            popup?.removeAllItems()
            var configDisplayNames = sself.xcodeServerConfigs.map { "\($0.host) (\($0.user ?? String()))" }
            configDisplayNames.append(sself.addNewString)
            popup?.addItems(withTitles: configDisplayNames)
        }
        self.storageManager.onUpdateServerConfigs = update
        update()
    }

    private func didSelectXcodeServer(_ config: XcodeServerConfig) {
        Log.verbose("Selected \(config.host)")
        self.emptyServerDelegate?.didSelectXcodeServerConfig(config)
    }
}
