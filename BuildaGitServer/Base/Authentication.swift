//
//  Authentication.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 1/26/16.
//  Copyright © 2016 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

public struct ProjectAuthenticator {
    public enum AuthType: String {
        case PersonalToken
        case OAuthToken
    }

    public let service: GitService
    public let username: String
    public let type: AuthType
    public let secret: String

    public init(service: GitService, username: String, type: AuthType, secret: String) {
        self.service = service
        self.username = username
        self.type = type
        self.secret = secret
    }
}

public protocol KeychainStringSerializable {
    static func fromString(value: String) throws -> Self
    func toString() -> String
}

extension ProjectAuthenticator: KeychainStringSerializable {
    public static func fromString(value: String) throws -> ProjectAuthenticator {
        let comps = value.components(separatedBy: ":")
        guard comps.count >= 4 else { throw GithubServerError.with("Corrupted keychain string") }
        guard let service = GitService(rawValue: comps[0]) else {
            throw GithubServerError.with("Unsupported service: \(comps[0])")
        }
        guard let type = ProjectAuthenticator.AuthType(rawValue: comps[2]) else {
            throw GithubServerError.with("Unsupported auth type: \(comps[2])")
        }
        //join the rest back in case we have ":" in the token
        let remaining = comps.dropFirst(3).joined(separator: ":")
        let auth = ProjectAuthenticator(service: service, username: comps[1], type: type, secret: remaining)
        return auth
    }

    public func toString() -> String {
        return [
            self.service.rawValue,
            self.username,
            self.type.rawValue,
            self.secret
        ].joined(separator: ":")
    }
}
