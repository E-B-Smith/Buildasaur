//
//  EmptyProjectViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 30/09/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit
import ReactiveCocoa
import ReactiveSwift
import Result
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
    
    fileprivate var projectConfigs: [ProjectConfig] = []
    fileprivate var selectedConfig = MutableProperty<ProjectConfig?>(nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupDataSource()
        self.setupPopupAction()
        self.setupEditableStates()
        
        //select if existing config is being edited
        let index: Int
        if let configId = self.existingConfigId {
            let ids = self.projectConfigs.map { $0.id }
            index = ids.index(of: configId) ?? 0
        } else {
            index = 0
        }
        self.selectItemAtIndex(index)
        self.existingProjectsPopup.selectItem(at: index)
    }
    
    func addNewString() -> String {
        return "Add new Xcode Project..."
    }
    
    func newConfig() -> ProjectConfig {
        return ProjectConfig()
    }
    
    override func shouldGoNext() -> Bool {
        
        var current = self.selectedConfig.value!
        if current.url.isEmpty {
            //just new config, needs to be picked
            guard let picked = self.pickNewProject() else { return false }
            current = picked
        }
        
        self.didSelectProjectConfig(current)
        return super.shouldGoNext()
    }
    
    fileprivate func setupEditableStates() {
        
        self.nextAllowed <~ self.selectedConfig.producer.map { $0 != nil }
    }
    
    fileprivate func selectItemAtIndex(_ index: Int) {
        
        let configs = self.projectConfigs
        
        //                                      last item is "add new"
        let config = (index == configs.count) ? self.newConfig() : configs[index]
        self.selectedConfig.value = config
    }
    
    fileprivate func setupPopupAction() {
        
        let handler = SignalProducer<AnyObject, NoError> { [weak self] sink, _ in
            if let sself = self {
                let index = sself.existingProjectsPopup.indexOfSelectedItem
                sself.selectItemAtIndex(index)
            }
            sink.sendCompleted()
        }
        let action = Action { (_: ()) in handler }
        self.existingProjectsPopup.reactive.pressed = CocoaAction(action)
    }
    
    fileprivate func setupDataSource() {
        
        let configsProducer = self.storageManager.projectConfigs.producer
        let allConfigsProducer = configsProducer
            .map { Array($0.values) }
            .map { configs in configs.filter { (try? Project(config: $0)) != nil } }
            .map { configs in configs.sorted { $0.name < $1.name } }
        allConfigsProducer.startWithValues { [weak self] newConfigs in
            guard let sself = self else { return }
            
            sself.projectConfigs = newConfigs
            let popup = sself.existingProjectsPopup
            popup?.removeAllItems()
            var configDisplayNames = newConfigs.map { $0.name }
            configDisplayNames.append(self?.addNewString() ?? ":(")
            popup?.addItems(withTitles: configDisplayNames)
        }
    }
    
    fileprivate func didSelectProjectConfig(_ config: ProjectConfig) {
        Log.verbose("Selected \(config.url)")
        self.emptyProjectDelegate?.didSelectProjectConfig(config)
    }
    
    fileprivate func pickNewProject() -> ProjectConfig? {
        
        if let url = StorageUtils.openWorkspaceOrProject() {
            
            do {
                try self.storageManager.checkForProjectOrWorkspace(url: url)
                var config = ProjectConfig()
                config.url = url.path
                return config
            } catch {
                //local source is malformed, something terrible must have happened, inform the user this can't be used (log should tell why exactly)
                let buttons = ["See workaround", "OK"]

                UIUtils.showAlertWithButtons("Couldn't add Xcode project at path \(url.absoluteString), error: \((error as NSError).localizedDescription).", buttons: buttons, style: .critical, completion: { (tappedButton) -> () in
                    
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

