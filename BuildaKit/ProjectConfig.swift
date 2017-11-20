//
//  ProjectConfig.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/3/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import BuildaGitServer

public struct ProjectConfig {
    public let id: RefType
    public var url: String
    public var privateSSHKeyPath: String
    public var publicSSHKeyPath: String

    public var sshPassphrase: String? //loaded from the keychain
    public var serverAuthentication: ProjectAuthenticator? //loaded from the keychain

    //creates a new default ProjectConfig
    public init() {
        self.id = Ref.new()
        self.url = ""
        self.serverAuthentication = nil
        self.privateSSHKeyPath = ""
        self.publicSSHKeyPath = ""
        self.sshPassphrase = nil
    }

    public func validate() throws {
        //TODO: throw of required keys are not valid
    }
}

private struct Keys {

    static let URL = "url"
    static let PrivateSSHKeyPath = "ssh_private_key_url"
    static let PublicSSHKeyPath = "ssh_public_key_url"
    static let Id = "id"
}

extension ProjectConfig: JSONSerializable {

    public func jsonify() -> [String: Any] {
        var json: [String: Any] = [:]
        json[Keys.URL] = self.url
        json[Keys.PrivateSSHKeyPath] = self.privateSSHKeyPath
        json[Keys.PublicSSHKeyPath] = self.publicSSHKeyPath
        json[Keys.Id] = self.id
        return json
    }

    public init(json: [String: Any]) throws {
        self.url = json[Keys.URL] as! String
        self.privateSSHKeyPath = json[Keys.PrivateSSHKeyPath] as! String
        self.publicSSHKeyPath = json[Keys.PublicSSHKeyPath] as! String
        self.id = json[Keys.Id] as! String
    }
}
