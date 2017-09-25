//
//  SelectTriggerViewController.swift
//  Buildasaur
//
//  Created by Anton Domashnev on 23/06/16.
//  Copyright © 2016 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import XcodeServerSDK
import ReactiveSwift
import BuildaKit


protocol SelectTriggerViewControllerDelegate: class {
    func selectTriggerViewController(_ viewController: SelectTriggerViewController, didSelectTriggers selectedTriggers: [TriggerConfig])
}

class SelectTriggerViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    
    weak var delegate: SelectTriggerViewControllerDelegate?
    
    @IBOutlet weak var triggersListContainerViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var triggersListContainerView: NSView!
    @IBOutlet weak var triggersTableView: NSTableView!
    @IBOutlet weak var doneButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    
    var storageManager: StorageManager!
    
    fileprivate let triggers = MutableProperty<[TriggerConfig]>([])
    fileprivate let selectedTriggerIDs = MutableProperty<[String]>([])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupBindings()
        self.fetchTriggers()
        self.selectedTriggerIDs.value = []
        
    }
    
    fileprivate func setupBindings() {
        self.triggers.producer.startWithValues { [weak self] _ in
            self?.triggersTableView.reloadData()
        }
        self.selectedTriggerIDs.producer.startWithValues { [weak self] _ in
            self?.doneButton.isEnabled = self?.selectedTriggerIDs.value.count ?? 0 > 0
        }
    }
    
    //MARK: triggers table view
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.triggers.value.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let triggers = self.triggers.value
        let trigger = triggers[row]
        switch tableColumn!.identifier.rawValue {
        case "name":
            return trigger.name
        case "selected":
            let index = self.selectedTriggerIDs.value
                .indexOfFirstObjectPassingTest { $0 == trigger.id }
            let enabled = index ?? -1 > -1
            return enabled
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: NSTableView, shouldSelect tableColumn: NSTableColumn?) -> Bool {
        return false
    }
    
    @IBAction func triggersTableViewRowCheckboxTapped(_ sender: AnyObject) {
        let trigger = self.triggers.value[self.triggersTableView.selectedRow]
        let foundIndex = self.selectedTriggerIDs.value.indexOfFirstObjectPassingTest(test: { $0 == trigger.id })
        
        if let foundIndex = foundIndex {
            let _ = self.selectedTriggerIDs.value.remove(at: foundIndex)
        } else {
            self.selectedTriggerIDs.value.append(trigger.id)
        }
    }
    
    @IBAction func triggerTableViewEditTapped(_ sender: AnyObject) {
        let index = self.triggersTableView.selectedRow
        let trigger = self.triggers.value[index]
        self.editTrigger(trigger)
    }
    
    @IBAction func triggerTableViewDeleteTapped(_ sender: AnyObject) {
        let index = self.triggersTableView.selectedRow
        let trigger = self.triggers.value[index]
        self.storageManager.removeTriggerConfig(triggerConfig: trigger)
        let _ = self.triggers.value.remove(at: index)
    }
 
    //MARK: helpers
    
    func editTrigger(_ trigger: TriggerConfig?) {
        let triggerViewController = NSStoryboard.mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: TriggerViewController.storyboardID)) as! TriggerViewController
        triggerViewController.triggerConfig.value = trigger
        triggerViewController.storageManager = self.storageManager
        triggerViewController.delegate = self
        self.pushTriggerViewController(triggerViewController)
    }
    
    func fetchTriggers() {
        self.triggers.value = self.storageManager.triggerConfigs.value.map { $0.1 }
    }
    
    func pushTriggerViewController(_ viewController: TriggerViewController) {
        self.addChildViewController(viewController)
        self.view.addSubview(viewController.view)
        
        let pushingView = viewController.view
        let mainLeadingConstraint = self.triggersListContainerViewLeadingConstraint
        let endPushingViewFrame = pushingView.frame
        pushingView.frame = pushingView.frame.offsetBy(dx: pushingView.frame.width, dy: 0)
        
        NSAnimationContext.runAnimationGroup({ (context: NSAnimationContext) -> Void in
            
            context.duration = 0.3
            pushingView.animator().frame = endPushingViewFrame
            mainLeadingConstraint?.animator().constant = -pushingView.frame.width
            
        }) { /* do nothing */ }
    }
    
    func popTriggerViewController(_ viewController: TriggerViewController) {
        let poppingView = viewController.view
        let mainLeadingConstraint = self.triggersListContainerViewLeadingConstraint
        let endPoppingViewFrame = poppingView.frame.offsetBy(dx: poppingView.frame.width, dy: 0)
        
        NSAnimationContext.runAnimationGroup({ (context: NSAnimationContext) -> Void in
            
            context.duration = 0.3
            poppingView.animator().frame = endPoppingViewFrame
            mainLeadingConstraint?.animator().constant = 0
            
        }) {
            
            poppingView.removeFromSuperview()
            viewController.removeFromParentViewController()
        }
    }
    
    //MARK: actions
    
    @IBAction func doneButtonClicked(_ sender: NSButton) {
        
        let dictionarifyAvailableTriggers: [String: TriggerConfig] = self.triggers.value.dictionarifyWithKey {$0.id}
        let selectedTriggers: [TriggerConfig] = self.selectedTriggerIDs.value.map { dictionarifyAvailableTriggers[$0]! }
        self.delegate?.selectTriggerViewController(self, didSelectTriggers: selectedTriggers)
        self.dismiss(nil)
    }
    
    @IBAction func cancelButtonClicked(_ sender: NSButton) {
        
        self.dismiss(nil)
    }
    
}

extension SelectTriggerViewController: TriggerViewControllerDelegate {
    
    func triggerViewController(_ triggerViewController: NSViewController, didCancelEditingTrigger trigger: TriggerConfig) {
        self.popTriggerViewController(triggerViewController as! TriggerViewController)
    }
    
    func triggerViewController(_ triggerViewController: NSViewController, didSaveTrigger trigger: TriggerConfig) {
        var mapped = self.triggers.value.dictionarifyWithKey { $0.id }
        mapped[trigger.id] = trigger
        self.triggers.value = Array(mapped.values)
        self.popTriggerViewController(triggerViewController as! TriggerViewController)
    }

}
