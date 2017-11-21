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

class ConfigEditViewController: EditableViewController {

    var availabilityCheckState: AvailabilityCheckState = .unchecked {
        didSet {
            let imageName = ConfigEditViewController.imageNameForStatus(self.availabilityCheckState)
            let image = NSImage(named: NSImage.Name(rawValue: imageName))
            self.serverStatusImageView.image = image

            if self.availabilityCheckState == .checking {
                self.progressIndicator?.startAnimation(nil)
            } else {
                self.progressIndicator?.stopAnimation(nil)
            }

            self.lastConnectionView?.stringValue = ConfigEditViewController.stringForState(self.availabilityCheckState)
        }
    }

    override var editing: Bool {
        didSet {
            self.trashButton.isEnabled = self.editing
        }
    }

    @IBOutlet weak var trashButton: NSButton!
    @IBOutlet weak var lastConnectionView: NSTextField?
    @IBOutlet weak var progressIndicator: NSProgressIndicator?
    @IBOutlet weak var serverStatusImageView: NSImageView!

    var valid: Bool = false

    //do not call directly! just override
    func checkAvailability(_ statusChanged: @escaping ((_ status: AvailabilityCheckState) -> Void)) {
        assertionFailure("Must be overriden by subclasses")
    }

    @IBAction final func trashButtonClicked(_ sender: AnyObject) {
        self.delete()
    }

    func edit() {
        self.editing = true
    }

    func delete() {
        assertionFailure("Must be overriden by subclasses")
    }

    final func recheckForAvailability(_ completion: ((_ state: AvailabilityCheckState) -> Void)?) {
        self.editingAllowed = false
        self.checkAvailability { [weak self] (status) -> Void in
            self?.availabilityCheckState = status
            if status.isDone() {
                completion?(status)
                self?.editingAllowed = true
            }
        }
    }

    private static func stringForState(_ state: AvailabilityCheckState) -> String {
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

    private static func imageNameForStatus(_ status: AvailabilityCheckState) -> String {
        switch status {
        case .unchecked:
            return NSImage.Name.statusNone.rawValue
        case .checking:
            return NSImage.Name.statusPartiallyAvailable.rawValue
        case .succeeded:
            return NSImage.Name.statusAvailable.rawValue
        case .failed:
            return NSImage.Name.statusUnavailable.rawValue
        }
    }
}
