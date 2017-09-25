//
//  ConfigEditViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 08/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaUtils
import XcodeServerSDK
import BuildaKit
import ReactiveSwift
import Result

class ConfigEditViewController: EditableViewController {
    
    let availabilityCheckState = MutableProperty<AvailabilityCheckState>(.unchecked)
    
    @IBOutlet weak var trashButton: NSButton!
    @IBOutlet weak var lastConnectionView: NSTextField?
    @IBOutlet weak var progressIndicator: NSProgressIndicator?
    @IBOutlet weak var serverStatusImageView: NSImageView!

    var valid: SignalProducer<Bool, NoError>!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupUI()
        self.setupAvailability()
    }
    
    fileprivate func setupUI() {
        
        if self.serverStatusImageView != nil {
            //status image
            let statusImage = self
                .availabilityCheckState
                .producer
                .map { ConfigEditViewController.imageNameForStatus($0) }
                .map { NSImage(named: NSImage.Name(rawValue: $0)) }
            self.serverStatusImageView.rac_image <~ statusImage
        }
        
        if self.trashButton != nil {
            //only enable the delete button in editing mode
            self.trashButton.rac_enabled <~ self.editing
        }
    }
    
    //do not call directly! just override
    func checkAvailability(_ statusChanged: @escaping ((_ status: AvailabilityCheckState) -> ())) {
        assertionFailure("Must be overriden by subclasses")
    }
        
    @IBAction final func trashButtonClicked(_ sender: AnyObject) {
        self.delete()
    }
    
    func edit() {
        self.editing.value = true
    }
    
    func delete() {
        assertionFailure("Must be overriden by subclasses")
    }
    
    final func recheckForAvailability(_ completion: ((_ state: AvailabilityCheckState) -> ())?) {
        self.editingAllowed.value = false
        self.checkAvailability { [weak self] (status) -> () in
            self?.availabilityCheckState.value = status
            if status.isDone() {
                completion?(status)
                self?.editingAllowed.value = true
            }
        }
    }
    
    fileprivate func setupAvailability() {
        
        let state = self.availabilityCheckState.producer
        if let progress = self.progressIndicator {
            progress.rac_animating <~ state.map { $0 == .checking }
        }
        if let lastConnection = self.lastConnectionView {
            lastConnection.rac_stringValue <~ state.map { ConfigEditViewController.stringForState($0) }
        }
    }
    
    fileprivate static func stringForState(_ state: AvailabilityCheckState) -> String {
        
        //TODO: add some emoji!
        switch state {
        case .checking:
            return "Checking access to server..."
        case .failed(let error):
            let desc = (error as NSError?)?.localizedDescription ?? "\(String(describing: error))"
            return "Failed to access server, error: \n\(desc)"
        case .succeeded:
            return "Verified access, all is well!"
        case .unchecked:
            return ""
        }
    }
    
    fileprivate static func imageNameForStatus(_ status: AvailabilityCheckState) -> String {
        
        switch status {
        case .unchecked:
            return NSImage.Name.statusNone.rawValue
        case .checking:
            return NSImage.Name.statusPartiallyAvailable.rawValue
        case .succeeded:
            return NSImage.Name.statusAvailable.rawValue
        case .failed(_):
            return NSImage.Name.statusUnavailable.rawValue
        }
    }
}
