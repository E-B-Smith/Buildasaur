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
import ReactiveSwift
import Result

protocol XcodeServerViewControllerDelegate: class {
    func didCancelEditingOfXcodeServerConfig(_ config: XcodeServerConfig)
    func didSaveXcodeServerConfig(_ config: XcodeServerConfig)
}

class XcodeServerViewController: ConfigEditViewController {
    
    let serverConfig = MutableProperty<XcodeServerConfig!>(nil)
    weak var delegate: XcodeServerViewControllerDelegate?
    
    @IBOutlet weak var serverHostTextField: NSTextField!
    @IBOutlet weak var serverUserTextField: NSTextField!
    @IBOutlet weak var serverPasswordTextField: NSSecureTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupUI()
    }
    
    func setupUI() {
        
        let server = self.serverConfig
        let servProd = server.producer
        let editing = self.editing.producer
        
        //pull data in from the provided config (can be changed externally!)
        servProd.startWithValues { [weak self] config in
            self?.serverHostTextField.stringValue = config.host
            self?.serverUserTextField.stringValue = config.user ?? ""
            self?.serverPasswordTextField.stringValue = config.password ?? ""
        }
        
        //listening to changes to textfields
        let host = self.serverHostTextField.rac_text
        let user = self.serverUserTextField.rac_text
        let pass = self.serverPasswordTextField.rac_text
        let all = SignalProducer.combineLatest(host, user, pass)
        self.valid = all
            .map { try? XcodeServerConfig(host: $0, user: $1, password: $2) }
            .map { $0 != nil }
        
        //change state to .Unchecked whenever any change to a textfield has been done
        self.availabilityCheckState <~ all.map { _ in AvailabilityCheckState.unchecked }
        
        //enabled
        self.serverHostTextField.rac_enabled <~ editing
        self.serverUserTextField.rac_enabled <~ editing
        self.serverPasswordTextField.rac_enabled <~ editing
        self.trashButton.rac_hidden <~ editing
        
        let checker = self.availabilityCheckState.producer.map { state -> Bool in
            return state != .checking && state != AvailabilityCheckState.succeeded
        }
        
        //control buttons
        let nextAllowed = SignalProducer.combineLatest(self.valid, editing.producer, checker)
            .map { $0 && $1 && $2 }
        self.nextAllowed <~ nextAllowed
    }
    
    override func shouldGoNext() -> Bool {
        
        //pull the current credentials
        guard let newConfig = self.pullConfigFromUI() else { return false }
        self.serverConfig.value = newConfig
        self.delegate?.didSaveXcodeServerConfig(newConfig)
        
        //check availability of these credentials
        self.recheckForAvailability { [weak self] (state) -> () in
            
            if case .succeeded = state {
                //stop editing
                self?.editing.value = false
                
                //animated!
                delayClosure(delay: 1) {
                    self?.goNext(animated: true)
                }
            }
        }
        return false
    }
    
    fileprivate func cancel() {
        //throw away this setup, don't save anything (but don't delete either)
        self.delegate?.didCancelEditingOfXcodeServerConfig(self.serverConfig.value)
    }
    
    override func delete() {
        
        //ask if user really wants to delete
        UIUtils.showAlertAskingForRemoval("Do you really want to remove this Xcode Server configuration? This cannot be undone.", completion: { (remove) -> () in
            
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
            let oldConfigId = self.serverConfig.value.id
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
        
        let config = self.serverConfig.value
        self.storageManager.removeServer(serverConfig: config!)
        self.cancel()
    }
    
    override func checkAvailability(_ statusChanged: @escaping ((_ status: AvailabilityCheckState) -> Void)) {

        let config: XcodeServerConfig = self.serverConfig.value!
        let checkAction = AvailabilityChecker.xcodeServerAvailability()
        let _ = checkAction
            .apply(config)
            .on(starting: nil, started: nil, event: nil, failed: nil, completed: nil, interrupted: nil, terminated: nil, disposed: nil, value: statusChanged)
            .start()
    }
}

