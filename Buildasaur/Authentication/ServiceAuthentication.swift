//
//  ServiceAuthentication.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 1/26/16.
//  Copyright © 2016 Honza Dvorsky. All rights reserved.
//

import Foundation
import OAuthSwift
import BuildaGitServer

class ServiceAuthenticator {

    private var oauth: OAuth2Swift?

    enum ParamKey: String {
        case ConsumerId
        case ConsumerSecret
        case AuthorizeUrl
        case AccessTokenUrl
        case ResponseType
        case CallbackUrl
        case Scope
        case State
    }

    typealias SecretFromResponseParams = ([String: String]) -> String

    init() {}

    func handleUrl(_ url: URL) {
        OAuthSwift.handle(url: url)
    }

    func getAccess(_ service: GitService, completion: @escaping (_ auth: ProjectAuthenticator?, _ error: Error?) -> Void) {

        let (params, secretFromResponseParams) = self.paramsForService(service)

        self.oauth = OAuth2Swift(
            consumerKey: params[.ConsumerId]!,
            consumerSecret: params[.ConsumerSecret]!,
            authorizeUrl: params[.AuthorizeUrl]!,
            accessTokenUrl: params[.AccessTokenUrl]!,
            responseType: params[.ResponseType]!
        )
        self.oauth?.authorize(withCallbackURL:
            URL(string: params[.CallbackUrl]!)!,
                              scope: params[.Scope]!,
                              state: params[.State]!,
                              success: { _, _, parameters in

                let secret = secretFromResponseParams(parameters as! [String : String])
                let auth = ProjectAuthenticator(service: service, username: "GIT", type: .OAuthToken, secret: secret)
                completion(auth, nil)
            },
            failure: { error in
                completion(nil, error)
            }
        )
    }

    func getAccessTokenFromRefresh(_ service: GitService, refreshToken: String, completion: (auth: ProjectAuthenticator?, error: Error?)) {
        //TODO: implement refresh token flow - to get and save a new access token
    }

    private func paramsForService(_ service: GitService) -> ([ParamKey: String], SecretFromResponseParams) {
        switch service {
        case .GitHub:
            return self.getGitHubParameters()
        }
    }

    private func getGitHubParameters() -> ([ParamKey: String], SecretFromResponseParams) {
        let service = GitService.GitHub
        let params: [ParamKey: String] = [
            .ConsumerId: service.serviceKey(),
            .ConsumerSecret: service.serviceSecret(),
            .AuthorizeUrl: service.authorizeUrl(),
            .AccessTokenUrl: service.accessTokenUrl(),
            .ResponseType: "code",
            .CallbackUrl: "buildasaur://oauth-callback/github",
            .Scope: "repo",
            .State: generateState(withLength: 20) as String
        ]
        let secret: SecretFromResponseParams = {
            //just pull out the access token, that's all we need
            return $0["access_token"]!
        }
        return (params, secret)
    }
}
