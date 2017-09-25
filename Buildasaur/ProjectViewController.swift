//
//  ProjectViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 07/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import BuildaUtils
import XcodeServerSDK
import BuildaKit
import BuildaGitServer
import ReactiveSwift

protocol ProjectViewControllerDelegate: class {
    func didCancelEditingOfProjectConfig(_ config: ProjectConfig)
    func didSaveProjectConfig(_ config: ProjectConfig)
}

class ProjectViewController: ConfigEditViewController {
    
    let projectConfig = MutableProperty<ProjectConfig!>(nil)
    weak var delegate: ProjectViewControllerDelegate?
    
    var serviceAuthenticator: ServiceAuthenticator!
    
    fileprivate var project: Project!
    
    fileprivate let privateKeyUrl = MutableProperty<URL?>(nil)
    fileprivate let publicKeyUrl = MutableProperty<URL?>(nil)
    
    fileprivate let authenticator = MutableProperty<ProjectAuthenticator?>(nil)
    fileprivate let userWantsTokenAuth = MutableProperty<Bool>(false)

    //we have a project
    @IBOutlet weak var projectNameLabel: NSTextField!
    @IBOutlet weak var projectPathLabel: NSTextField!
    @IBOutlet weak var projectURLLabel: NSTextField!
    
    @IBOutlet weak var selectSSHPrivateKeyButton: NSButton!
    @IBOutlet weak var selectSSHPublicKeyButton: NSButton!
    @IBOutlet weak var sshPassphraseTextField: NSSecureTextField!
    
    //authentication stuff
    @IBOutlet weak var tokenTextField: NSTextField!
    @IBOutlet weak var tokenStackView: NSStackView!
    @IBOutlet weak var serviceName: NSTextField!
    @IBOutlet weak var serviceLogo: NSImageView!
    @IBOutlet weak var loginButton: NSButton!
    @IBOutlet weak var useTokenButton: NSButton!
    @IBOutlet weak var logoutButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupUI()
    }
    
    func setupUI() {
        
        let projConf = self.projectConfig
        let prod = projConf.producer
        let editing = self.editing
        let proj = prod.map { newConfig in
            //this config already went through validation like a second ago.
            return try! Project(config: newConfig)
        }
        
        let projectAuth = self.projectConfig.value.serverAuthentication
        self.authenticator.value = projectAuth
        self.userWantsTokenAuth.value = projectAuth?.type == .PersonalToken
        
        //project
        proj.startWithValues { [weak self] in self?.project = $0 }
        
        //enabled
        self.selectSSHPrivateKeyButton.rac_enabled <~ editing
        self.selectSSHPublicKeyButton.rac_enabled <~ editing
        self.sshPassphraseTextField.rac_enabled <~ editing
        self.tokenTextField.rac_enabled <~ editing
        
        //editable data
        let privateKey = self.privateKeyUrl.producer
        let publicKey = self.publicKeyUrl.producer
        
        let privateKeyPath = privateKey.map { $0?.path }
        let publicKeyPath = publicKey.map { $0?.path }
        
        self.selectSSHPrivateKeyButton.rac_title <~ privateKeyPath.map {
            $0 ?? "Select SSH Private Key"
        }
        self.selectSSHPublicKeyButton.rac_title <~ publicKeyPath.map {
            $0 ?? "Select SSH Public Key"
        }
        
        //dump whenever config changes
        prod.startWithValues { [weak self] in
            
            let priv = $0.privateSSHKeyPath
            self?.privateKeyUrl.value = priv.isEmpty ? nil : URL(fileURLWithPath: priv)
            let pub = $0.publicSSHKeyPath
            self?.publicKeyUrl.value = pub.isEmpty ? nil : URL(fileURLWithPath: pub)
            self?.sshPassphraseTextField.stringValue = $0.sshPassphrase ?? ""
        }
        
        let meta = proj.map { $0.workspaceMetadata! }
        
        SignalProducer.combineLatest(
            proj,
            self.authenticator.producer,
            self.userWantsTokenAuth.producer
            )
            .startWithValues { [weak self] (proj, auth, forceUseToken) in
                self?.updateServiceMeta(proj, auth: auth, userWantsTokenAuth: forceUseToken)
        }
        SignalProducer.combineLatest(self.tokenTextField.rac_text, self.userWantsTokenAuth.producer)
            .startWithValues { [weak self] token, forceToken in
                if forceToken {
                    if token.isEmpty {
                        self?.authenticator.value = nil
                    } else {
                        self?.authenticator.value = ProjectAuthenticator(service: .GitHub, username: "GIT", type: .PersonalToken, secret: token)
                    }
                }
        }
        
        //fill data in
        self.projectNameLabel.rac_stringValue <~ meta.map { $0.projectName }
        self.projectURLLabel.rac_stringValue <~ meta.map { $0.projectURL.absoluteString ?? "" }
        self.projectPathLabel.rac_stringValue <~ meta.map { $0.projectPath }
        
        //invalidate availability on change of any input
        let privateKeyVoid = privateKey.map { _ in }
        let publicKeyVoid = publicKey.map { _ in }
        let githubTokenVoid = self.tokenTextField.rac_text.map { _ in }
        let sshPassphraseVoid = self.sshPassphraseTextField.rac_text.map { _ in }
        let all = SignalProducer.combineLatest(privateKeyVoid, publicKeyVoid, githubTokenVoid, sshPassphraseVoid)
        all.startWithValues { [weak self] _ in self?.availabilityCheckState.value = .unchecked }
        
        //listen for changes
        let privateKeyValid = privateKey.map { $0 != nil }
        let publicKeyValid = publicKey.map { $0 != nil }
        let githubTokenValid = self.authenticator.producer.map { $0 != nil }
        
        let allInputs = SignalProducer.combineLatest(privateKeyValid, publicKeyValid, githubTokenValid)
        let valid = allInputs.map { $0.0 && $0.1 && $0.2 }
        self.valid = valid
        
        let checker = self.availabilityCheckState.producer.map { state -> Bool in
            return state != .checking && state != AvailabilityCheckState.succeeded
        }
        
        //control buttons
        let nextAllowed = SignalProducer.combineLatest(self.valid, editing.producer, checker)
            .map { $0 && $1 && $2 }
        self.nextAllowed <~ nextAllowed
        self.trashButton.rac_hidden <~ editing
    }
    
    func updateServiceMeta(_ proj: Project, auth: ProjectAuthenticator?, userWantsTokenAuth: Bool) {
        
        let meta = proj.workspaceMetadata!
        let service = meta.service
        
        let name = "\(service.prettyName())"
        self.serviceName.stringValue = name
        self.serviceLogo.image = NSImage(named: NSImage.Name(rawValue: service.logoName()))
        
        let alreadyHasAuth = auth != nil

        switch service {
        case .GitHub:
            if let auth = auth, auth.type == .PersonalToken && !auth.secret.isEmpty {
                self.tokenTextField.stringValue = auth.secret
            } else {
                self.tokenTextField.stringValue = ""
            }
            self.useTokenButton.isHidden = alreadyHasAuth
        case .BitBucket:
            self.useTokenButton.isHidden = true
        }
        
        self.loginButton.isHidden = alreadyHasAuth
        self.logoutButton.isHidden = !alreadyHasAuth
        
        let showTokenField = userWantsTokenAuth && service == .GitHub && (auth?.type == .PersonalToken || auth == nil)
        self.tokenStackView.isHidden = !showTokenField
    }
    
    override func shouldGoNext() -> Bool {
        
        //pull data from UI, create config, save it and try to validate
        guard let newConfig = self.pullConfigFromUI() else { return false }
        self.projectConfig.value = newConfig
        self.delegate?.didSaveProjectConfig(newConfig)
        
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
    
    func previous() {
        self.goBack()
    }
    
    fileprivate func goBack() {
        let config = self.projectConfig.value
        self.delegate?.didCancelEditingOfProjectConfig(config!)
    }
    
    override func delete() {
        
        //ask if user really wants to delete
        UIUtils.showAlertAskingForRemoval("Do you really want to remove this Xcode Project configuration? This cannot be undone.", completion: { (remove) -> () in
            
            if remove {
                self.removeCurrentConfig()
            }
        })
    }
    
    override func checkAvailability(_ statusChanged: @escaping ((_ status: AvailabilityCheckState) -> ())) {
        
        let _ = AvailabilityChecker
                .projectAvailability()
                .apply(self.projectConfig.value)
                .on(starting: nil, started: nil, event: nil, failed: nil, completed: nil, interrupted: nil, terminated: nil, disposed: nil, value: statusChanged)
                .start()
    }
    
    func pullConfigFromUI() -> ProjectConfig? {
        
        let sshPassphrase = self.sshPassphraseTextField.stringValue.nonEmpty()
        guard
            let privateKeyPath = self.privateKeyUrl.value?.path,
            let publicKeyPath = self.publicKeyUrl.value?.path,
            let auth = self.authenticator.value else {
            return nil
        }
        
        var config = self.projectConfig.value!
        config.serverAuthentication = auth
        config.sshPassphrase = sshPassphrase
        config.privateSSHKeyPath = privateKeyPath
        config.publicSSHKeyPath = publicKeyPath
        
        do {
            try self.storageManager.addProjectConfig(config: config)
            return config
        } catch StorageManagerError.DuplicateProjectConfig(let duplicate) {
            let userError = XcodeServerError.with("You already have a Project at \"\(duplicate.url)\", please go back and select it from the previous screen.")
            UIUtils.showAlertWithError(userError)
        } catch {
            UIUtils.showAlertWithError(error)
        }
        return nil
    }
    
    func removeCurrentConfig() {
    
        let config = self.projectConfig.value!
        self.storageManager.removeProjectConfig(projectConfig: config)
        self.goBack()
    }
    
    func selectKey(_ type: String) {
        
        if let url = StorageUtils.openSSHKey(publicOrPrivate: type) {
            do {
                _ = try String(contentsOf: url, encoding: String.Encoding.ascii)
                if type == "public" {
                    self.publicKeyUrl.value = url
                } else {
                    self.privateKeyUrl.value = url
                }
            } catch {
                UIUtils.showAlertWithError(error as NSError)
            }
        }
    }
    
    @IBAction func selectPublicKeyTapped(_ sender: AnyObject) {
        self.selectKey("public")
    }
    
    @IBAction func selectPrivateKeyTapped(_ sender: AnyObject) {
        self.selectKey("private")
    }
    
    @IBAction func loginButtonClicked(_ sender: AnyObject) {
        
        self.userWantsTokenAuth.value = false
        
        let service = self.project.workspaceMetadata!.service
        self.serviceAuthenticator.getAccess(service) { (auth, error) -> () in
            
            guard let auth = auth else {
                //TODO: show UI error that login failed
                UIUtils.showAlertWithError(XcodeServerError.with("Failed to log in, please try again"/*, internalError: (error as! NSError), userInfo: nil*/))
                self.authenticator.value = nil
                return
            }
            
            //we have been authenticated, hooray!
            self.authenticator.value = auth
        }
    }
    
    @IBAction func useTokenClicked(_ sender: AnyObject) {
        
        self.userWantsTokenAuth.value = true
    }
    
    @IBAction func logoutButtonClicked(_ sender: AnyObject) {
        
        self.authenticator.value = nil
        self.userWantsTokenAuth.value = false
        self.tokenTextField.rac_stringValue.value = ""
    }
    
}
