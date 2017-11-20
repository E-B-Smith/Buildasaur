//
//  XcodeServerViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 08/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK
import BuildaKit

protocol XcodeServerViewControllerDelegate: class {
    func didCancelEditingOfXcodeServerConfig(_ config: XcodeServerConfig)
    func didSaveXcodeServerConfig(_ config: XcodeServerConfig)
}

class XcodeServerViewController: ConfigEditViewController {

    var serverConfig: XcodeServerConfig! = nil {
        didSet {
            self.serverHostTextField.stringValue = self.serverConfig.host
            self.serverUserTextField.stringValue = self.serverConfig.user ?? ""
            self.serverPasswordTextField.stringValue = self.serverConfig.password ?? ""
        }
    }
    override var valid: Bool {
        didSet {
            self.updateNextAllowed()
        }
    }
    override var availabilityCheckState: AvailabilityCheckState {
        didSet {
            self.trashButton.isHidden = self.editing || self.availabilityCheckState == .checking
            self.updateNextAllowed()
        }
    }
    override var editing: Bool {
        didSet {
            self.serverHostTextField.isEnabled = self.editing
            self.serverUserTextField.isEnabled = self.editing
            self.serverPasswordTextField.isEnabled = self.editing
            self.trashButton.isHidden = self.editing || self.availabilityCheckState == .checking

            self.updateNextAllowed()
        }
    }
    weak var delegate: XcodeServerViewControllerDelegate?

    @IBOutlet weak var serverHostTextField: NSTextField!
    @IBOutlet weak var serverUserTextField: NSTextField!
    @IBOutlet weak var serverPasswordTextField: NSSecureTextField!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.serverHostTextField.delegate = self
        self.serverUserTextField.delegate = self
        self.serverPasswordTextField.delegate = self

        self.updateNextAllowed()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        self.updateValid()
        self.updateNextAllowed()
    }

    private func updateValid() {
        let host = self.serverHostTextField.stringValue
        let user = self.serverUserTextField.stringValue
        let pass = self.serverPasswordTextField.stringValue
        self.valid = (try? XcodeServerConfig(host: host, user: user, password: pass)) != nil
    }

    private func updateNextAllowed() {
        self.nextAllowed = self.valid
            && self.editing
            && self.availabilityCheckState != .checking
            && self.availabilityCheckState != .succeeded
    }

    override func shouldGoNext() -> Bool {
        //pull the current credentials
        guard let newConfig = self.pullConfigFromUI() else { return false }
        self.serverConfig = newConfig
        self.delegate?.didSaveXcodeServerConfig(newConfig)

        //check availability of these credentials
        self.recheckForAvailability { [weak self] (state) -> Void in

            if case .succeeded = state {
                //stop editing
                self?.editing = false

                //animated!
                delayClosure(delay: 0.2) {
                    self?.goNext(animated: true)
                }
            }
        }
        return false
    }

    private func cancel() {
        //throw away this setup, don't save anything (but don't delete either)
        self.delegate?.didCancelEditingOfXcodeServerConfig(self.serverConfig)
    }

    override func delete() {
        //ask if user really wants to delete
        UIUtils.showAlertAskingForRemoval("Do you really want to remove this Xcode Server configuration? This cannot be undone.", completion: { (remove) -> Void in
            if remove {
                self.removeCurrentConfig()
            }
        })
    }

    func pullConfigFromUI() -> XcodeServerConfig? {
        let host = self.serverHostTextField.stringValue.nonEmpty()
        let user = self.serverUserTextField.stringValue.nonEmpty()
        let password = self.serverPasswordTextField.stringValue.nonEmpty()

        if let host = host {
            let oldConfigId = self.serverConfig.id
            let config = try! XcodeServerConfig(host: host, user: user, password: password, id: oldConfigId)

            do {
                try self.storageManager.addServerConfig(config: config)
                return config
            } catch StorageManagerError.DuplicateServerConfig(let duplicate) {
                let userError = XcodeServerError.with("You already have a Xcode Server with host \"\(duplicate.host)\" and username \"\(duplicate.user ?? String())\", please go back and select it from the previous screen.")
                UIUtils.showAlertWithError(userError)
            } catch {
                UIUtils.showAlertWithError(error)
                return nil
            }
        } else {
            UIUtils.showAlertWithText("Please add a host name and IP address of your Xcode Server")
        }
        return nil
    }

    func removeCurrentConfig() {
        let config = self.serverConfig
        self.storageManager.removeServer(serverConfig: config!)
        self.cancel()
    }

    override func checkAvailability(_ statusChanged: @escaping ((_ status: AvailabilityCheckState) -> Void)) {
        AvailabilityChecker.xcodeServerAvailability(config: self.serverConfig) { state in
            statusChanged(state)
        }
    }
}

extension XcodeServerViewController: NSTextFieldDelegate {
    override func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            if textField == self.serverHostTextField || textField == self.serverHostTextField || textField == self.serverPasswordTextField {
                self.availabilityCheckState = .unchecked
                self.updateValid()
            }

        }
    }
}
