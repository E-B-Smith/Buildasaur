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

    // swiftlint:disable cyclomatic_complexity
    private func endpointURL(endpoint: Endpoint, params: [String: String]? = nil) -> String {
        let path: String
        switch endpoint {
        case .users:

            if let user = params?["user"] {
                path = "/users/\(user)"
            } else {
                path = "/user"
            }

            //FYI - repo must be in its full name, e.g. czechboy0/Buildasaur, not just Buildasaur
        case .repos:

            if let repo = params?["repo"] {
                path = "/repos/\(repo)"
            } else {
                let user = self.endpointURL(endpoint: .users, params: params)
                path = "\(user)/repos"
            }

        case .pullRequests:

            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let pulls = "\(repo)/pulls"

            if let pr = params?["pr"] {
                path = "\(pulls)/\(pr)"
            } else {
                path = pulls
            }

        case .issues:

            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            let issues = "\(repo)/issues"

            if let issue = params?["issue"] {
                path = "\(issues)/\(issue)"
            } else {
                path = issues
            }

        case .branches:

            let repo = self.endpointURL(endpoint: .repos, params: params)
            let branches = "\(repo)/branches"

            if let branch = params?["branch"] {
                path = "\(branches)/\(branch)"
            } else {
                path = branches
            }

        case .commits:

            let repo = self.endpointURL(endpoint: .repos, params: params)
            let commits = "\(repo)/commits"

            if let commit = params?["commit"] {
                path = "\(commits)/\(commit)"
            } else {
                path = commits
            }

        case .statuses:

            let sha = params!["sha"]!
            let method = params?["method"]
            if let method = method,
                method == HTTP.Method.post.rawValue {
                //POST, we need slightly different url
                let repo = self.endpointURL(endpoint: .repos, params: params)
                path = "\(repo)/statuses/\(sha)"
                break
            }

            //GET, default
            let commits = self.endpointURL(endpoint: .commits, params: params)
            path = "\(commits)/\(sha)/statuses"

        case .issueComments:

            let issues = self.endpointURL(endpoint: .issues, params: params)
            let comments = "\(issues)/comments"

            if let comment = params?["comment"] {
                path = "\(comments)/\(comment)"
            } else {
                path = comments
            }

        case .merges:

            assert(params?["repo"] != nil, "A repo must be specified")
            let repo = self.endpointURL(endpoint: .repos, params: params)
            path = "\(repo)/merges"
        }

        return path
    }
    // swiftlint:enable cyclomatic_complexity

    func createRequest(method: HTTP.Method, endpoint: Endpoint, params: [String: String]? = nil, query: [String: String]? = nil, body: NSDictionary? = nil) throws -> NSMutableURLRequest {

        let endpointURL = self.endpointURL(endpoint: endpoint, params: params)
        let queryString = HTTP.stringForQuery(query)
        let wholePath = "\(self.baseURL)\(endpointURL)\(queryString)"

        let url = URL(string: wholePath)!

        let request = NSMutableURLRequest(url: url)

        request.httpMethod = method.rawValue
        if let auth = self.auth {

            switch auth.type {
            case .PersonalToken, .OAuthToken:
                request.setValue("token \(auth.secret)", forHTTPHeaderField: "Authorization")
            }
        }

        if let body = body {

            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = data
        }

        return request
    }
}
