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
import ReactiveCocoa
import ReactiveSwift
import Result

protocol EmptyXcodeServerViewControllerDelegate: class {
    func didSelectXcodeServerConfig(_ config: XcodeServerConfig)
}

class EmptyXcodeServerViewController: EditableViewController {
    
    //for cases when we're editing an existing syncer - show the
    //right preference.
    var existingConfigId: RefType?
    
    weak var emptyServerDelegate: EmptyXcodeServerViewControllerDelegate?
    
    @IBOutlet weak var existingXcodeServersPopup: NSPopUpButton!

    fileprivate var xcodeServerConfigs: [XcodeServerConfig] = []
    fileprivate var selectedConfig = MutableProperty<XcodeServerConfig?>(nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupDataSource()
        self.setupPopupAction()
        self.setupEditableStates()
        
        //select if existing config is being edited
        let index: Int
        if let configId = self.existingConfigId {
            let ids = self.xcodeServerConfigs.map { $0.id }
            index = ids.index(of: configId) ?? 0
        } else {
            index = 0
        }
        self.selectItemAtIndex(index)
        self.existingXcodeServersPopup.selectItem(at: index)
    }
    
    func addNewString() -> String {
        return "Add new Xcode Server..."
    }
    
    func newConfig() -> XcodeServerConfig {
        return XcodeServerConfig()
    }
    
    override func shouldGoNext() -> Bool {
        self.didSelectXcodeServer(self.selectedConfig.value!)
        return super.shouldGoNext()
    }
    
    fileprivate func setupEditableStates() {
        
        self.nextAllowed <~ self.selectedConfig.producer.map { $0 != nil }
    }
    
    fileprivate func selectItemAtIndex(_ index: Int) {
        
        let configs = self.xcodeServerConfigs
        
        //                                      last item is "add new"
        let config = (index == configs.count) ? self.newConfig() : configs[index]
        self.selectedConfig.value = config
    }
    
    fileprivate func setupPopupAction() {
        
        let handler = SignalProducer<AnyObject, NoError> { [weak self] sink, _ in
            if let sself = self {
                let index = sself.existingXcodeServersPopup.indexOfSelectedItem
                sself.selectItemAtIndex(index)
            }
            sink.sendCompleted()
        }
        let action = Action { (_: ()) in handler }
        self.existingXcodeServersPopup.reactive.pressed = CocoaAction(action)
    }
    
    fileprivate func setupDataSource() {

        let configsProducer = self.storageManager.serverConfigs.producer
        let allConfigsProducer = configsProducer
            .map { Array($0.values) }
            .map { configs in configs.sorted { $0.host < $1.host } }
        allConfigsProducer.startWithValues { [weak self] newConfigs in
            guard let sself = self else { return }
            
            sself.xcodeServerConfigs = newConfigs
            let popup = sself.existingXcodeServersPopup
            popup?.removeAllItems()
            var configDisplayNames = newConfigs.map { "\($0.host) (\($0.user ?? String()))" }
            configDisplayNames.append(self?.addNewString() ?? ":(")
            popup?.addItems(withTitles: configDisplayNames)
        }
    }
    
    fileprivate func didSelectXcodeServer(_ config: XcodeServerConfig) {
        Log.verbose("Selected \(config.host)")
        self.emptyServerDelegate?.didSelectXcodeServerConfig(config)
    }
}

