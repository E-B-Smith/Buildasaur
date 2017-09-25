//
//  GitHubURLFactory.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 13/12/2014.
//  Copyright (c) 2014 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

class GitHubEndpoints {
    
    enum Endpoint {
        case users
        case repos
        case pullRequests
        case issues
        case branches
        case commits
        case statuses
        case issueComments
        case merges
    }
    
    enum MergeResult {
        case success(NSDictionary)
        case nothingToMerge
        case conflict
        case missing(String)
    }
    
    private let baseURL: String
    private let auth: ProjectAuthenticator?
    
    init(baseURL: String, auth: ProjectAuthenticator?) {
        self.baseURL = baseURL
        self.auth = auth
    }
    
    private func endpointURL(endpoint: Endpoint, params: [String: String]? = nil) -> String {
        
        switch endpoint {
        case .users:
            
            if let user = params?["user"] {
                return "/users/\(user)"
            } else {
                return "/user"
            }
        
            //FYI - repo must be in its full name, e.g. czechboy0/Buildasaur, not just Buildasaur
        case .repos:
            
            if let repo = params?["repo"] {
                return "/repos/\(repo)"
            } else {
                let user = self.endpointURL(endpoint: .users, params: params)
                return "\(user)/repos"
            }
            
        case .pullRequests:
            
            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let pulls = "\(repo)/pulls"
            
            if let pr = params?["pr"] {
                return "\(pulls)/\(pr)"
            } else {
                return pulls
            }
            
        case .issues:
            
            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let issues = "\(repo)/issues"
            
            if let issue = params?["issue"] {
                return "\(issues)/\(issue)"
            } else {
                return issues
            }
            
        case .branches:
            
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let branches = "\(repo)/branches"
            
            if let branch = params?["branch"] {
                return "\(branches)/\(branch)"
            } else {
                return branches
            }
            
        case .commits:
            
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let commits = "\(repo)/commits"
            
            if let commit = params?["commit"] {
                return "\(commits)/\(commit)"
            } else {
                return commits
            }
            
        case .statuses:
            
            let sha = params!["sha"]!
            let method = params?["method"]
            if let method = method {
                if method == HTTP.Method.post.rawValue {
                    //POST, we need slightly different url
                    let repo = self.endpointURL(endpoint: .repos, params: params)
                    return "\(repo)/statuses/\(sha)"
                }
            }
            
            //GET, default
            let commits = self.endpointURL(endpoint: .commits, params: params)
            return "\(commits)/\(sha)/statuses"
            
        case .issueComments:
            
            let issues = self.endpointURL(endpoint: .issues, params: params)
            let comments = "\(issues)/comments"
            
            if let comment = params?["comment"] {
                return "\(comments)/\(comment)"
            } else {
                return comments
            }
            
        case .merges:
            
            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            return "\(repo)/merges"
        }
    }
    
    func createRequest(method: HTTP.Method, endpoint: Endpoint, params: [String : String]? = nil, query: [String : String]? = nil, body:NSDictionary? = nil) throws -> NSMutableURLRequest {
        
        let endpointURL = self.endpointURL(endpoint: endpoint, params: params)
        let queryString = HTTP.stringForQuery(query)
        let wholePath = "\(self.baseURL)\(endpointURL)\(queryString)"
        
        let url = URL(string: wholePath)!
        
        let request = NSMutableURLRequest(url: url)
        
        request.httpMethod = method.rawValue
        if let auth = self.auth {
            
            switch auth.type {
            case .PersonalToken, .OAuthToken:
                request.setValue("token \(auth.secret)", forHTTPHeaderField:"Authorization")
            }
        }
        
        if let body = body {
            
            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = data
        }
        
        return request
    }
}
