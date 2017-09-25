//
//  BitBucketEndpoints.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 1/27/16.
//  Copyright © 2016 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import ReactiveSwift

class BitBucketEndpoints {
    
    enum Endpoint {
        case repos
        case pullRequests
        case pullRequestComments
        case commitStatuses
    }
    
    private let baseURL: String
    internal let auth = MutableProperty<ProjectAuthenticator?>(nil)
    
    init(baseURL: String, auth: ProjectAuthenticator?) {
        self.baseURL = baseURL
        self.auth.value = auth
    }
    
    private func endpointURL(endpoint: Endpoint, params: [String: String]? = nil) -> String {
        
        switch endpoint {
            
        case .repos:
            
            if let repo = params?["repo"] {
                return "/2.0/repositories/\(repo)"
            } else {
                return "/2.0/repositories"
            }
            
        case .pullRequests:
            
            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            
            if let pr = params?["pr"] {
                return "\(repo)/pullrequests/\(pr)"
            } else {
                return "\(repo)/pullrequests"
            }
        
        case .pullRequestComments:
            
            assert(params?["repo"] != nil, "A repo must be specified")
            assert(params?["pr"] != nil, "A PR must be specified")
            let pr = self.endpointURL(endpoint: .pullRequests, params: params)
            
            if params?["method"] == "POST" {
                let repo = params!["repo"]!
                let pr = params!["pr"]!
                return "/1.0/repositories/\(repo)/pullrequests/\(pr)/comments"
            } else {
                return "\(pr)/comments"
            }
            
        case .commitStatuses:
            
            assert(params?["repo"] != nil, "A repo must be specified")
            assert(params?["sha"] != nil, "A commit sha must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let sha = params!["sha"]!
            
            let build = "\(repo)/commit/\(sha)/statuses/build"
            
            if let key = params?["status_key"] {
                return "\(build)/\(key)"
            }
            
            return build
            
        }
        
    }
    
    func setAuthOnRequest(request: NSMutableURLRequest) {
        
        guard let auth = self.auth.value else { return }
            
        switch auth.type {
        case .OAuthToken:
            let tokens = auth.secret.components(separatedBy: ":")
            //first is refresh token, second access token
            request.setValue("Bearer \(tokens[1])", forHTTPHeaderField:"Authorization")
        default:
            fatalError("This kind of authentication is not supported for BitBucket")
        }
    }
    
    func createRefreshTokenRequest() -> NSMutableURLRequest {
        
        guard let auth = self.auth.value else { fatalError("No auth") }
        let refreshUrl = auth.service.accessTokenUrl()
        let refreshToken = auth.secret.components(separatedBy: ":")[0]
        let body = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken)
            ].map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        
        let request = NSMutableURLRequest(url: URL(string: refreshUrl)!)
        
        let service = auth.service
        let servicePublicKey = service.serviceKey()
        let servicePrivateKey = service.serviceSecret()
        let credentials = "\(servicePublicKey):\(servicePrivateKey)".base64String()
        request.setValue("Basic \(credentials)", forHTTPHeaderField:"Authorization")
        
        request.httpMethod = "POST"
        self.setStringBody(request: request, body: body)
        return request
    }
    
    func createRequest(method: HTTP.Method, endpoint: Endpoint, params: [String : String]? = nil, query: [String : String]? = nil, body: NSDictionary? = nil) throws -> NSMutableURLRequest {
        
        let endpointURL = self.endpointURL(endpoint: endpoint, params: params)
        let queryString = HTTP.stringForQuery(query)
        let wholePath = "\(self.baseURL)\(endpointURL)\(queryString)"
        
        let url = URL(string: wholePath)!
        
        let request = NSMutableURLRequest(url: url)
        
        request.httpMethod = method.rawValue
        self.setAuthOnRequest(request: request)
        
        if let body = body {
            try self.setJSONBody(request: request, body: body)
        }
        
        return request
    }
    
    func setStringBody(request: NSMutableURLRequest, body: String) {
        let data = body.data(using: String.Encoding.utf8)
        request.httpBody = data
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }

    func setJSONBody(request: NSMutableURLRequest, body: NSDictionary) throws {
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        request.httpBody = data
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }
}
