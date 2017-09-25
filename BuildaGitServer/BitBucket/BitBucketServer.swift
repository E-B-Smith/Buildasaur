//
//  BitBucketServer.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 1/27/16.
//  Copyright © 2016 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import ReactiveSwift
import Result

class BitBucketServer : GitServer {
    
    let endpoints: BitBucketEndpoints
    let cache = InMemoryURLCache()
    
    init(endpoints: BitBucketEndpoints, http: HTTP? = nil) {
        
        self.endpoints = endpoints
        super.init(service: .GitHub, http: http)
    }
    
    override func authChangedSignal() -> Signal<ProjectAuthenticator?, NoError> {
        var res: Signal<ProjectAuthenticator?, NoError>?
        self.endpoints.auth.producer.startWithSignal { (signal, disposable) in
            res = signal
        }
        return res!.observe(on: UIScheduler())
    }
}

extension BitBucketServer: SourceServerType {
    func createStatusFromState(state: BuildState, description: String?, targetUrl: String?) -> StatusType {
        
        let bbState = BitBucketStatus.BitBucketState.fromBuildState(state: state)
        let key = "Buildasaur"
        let url = targetUrl ?? "https://github.com/czechboy0/Buildasaur"
        return BitBucketStatus(state: bbState, key: key, name: key, description: description, url: url)
    }
    
    func getBranchesOfRepo(repo: String, completion: @escaping (_ branches: [BranchType]?, _ error: Error?) -> ()) {
        
        //TODO: start returning branches
        completion([], nil)
    }
    
    func getOpenPullRequests(repo: String, completion: @escaping ([PullRequestType]?, Error?) -> ()) {
        
        let params = [
            "repo": repo
        ]
        self._sendRequestWithMethod(method: .get, endpoint: .pullRequests, params: params, query: nil, body: nil) { (response, body, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? [NSDictionary] {
                let (result, error): ([BitBucketPullRequest]?, NSError?) = unthrow {
                    return try BitBucketArray(jsonArray: body)
                }
                completion(result?.map { $0 as PullRequestType }, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
    
    func getPullRequest(pullRequestNumber: Int, repo: String, completion: @escaping (_ pr: PullRequestType?, _ error: Error?) -> ()) {
        
        let params = [
            "repo": repo,
            "pr": pullRequestNumber.description
        ]
        
        self._sendRequestWithMethod(method: .get, endpoint: .pullRequests, params: params, query: nil, body: nil) { (response, body, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? NSDictionary {
                let (result, error): (BitBucketPullRequest?, NSError?) = unthrow {
                    return try BitBucketPullRequest(json: body)
                }
                completion(result, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
    
    func getRepo(repo: String, completion: @escaping (_ repo: RepoType?, _ error: Error?) -> ()) {
        
        let params = [
            "repo": repo
        ]
        
        self._sendRequestWithMethod(method: .get, endpoint: .repos, params: params, query: nil, body: nil) {
            (response, body, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? NSDictionary {
                let (result, error): (BitBucketRepo?, NSError?) = unthrow {
                    return try BitBucketRepo(json: body)
                }
                completion(result, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
    
    func getStatusOfCommit(commit: String, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> ()) {
        
        let params = [
            "repo": repo,
            "sha": commit,
            "status_key": "Buildasaur"
        ]
        
        self._sendRequestWithMethod(method: .get, endpoint: .commitStatuses, params: params, query: nil, body: nil) { (response, body, error) -> () in
            
            if response?.statusCode == 404 {
                //no status yet, just pass nil but OK
                completion(nil, nil)
                return
            }
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? NSDictionary {
                let (result, error): (BitBucketStatus?, NSError?) = unthrow {
                    return try BitBucketStatus(json: body)
                }
                completion(result, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
    
    func postStatusOfCommit(commit: String, status: StatusType, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> ()) {
        
        let params = [
            "repo": repo,
            "sha": commit
        ]
        
        let body = (status as! BitBucketStatus).dictionarify()
        self._sendRequestWithMethod(method: .post, endpoint: .commitStatuses, params: params, query: nil, body: body) { (response, body, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? NSDictionary {
                let (result, error): (BitBucketStatus?, NSError?) = unthrow {
                    return try BitBucketStatus(json: body)
                }
                completion(result, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
    
    func postCommentOnIssue(comment: String, issueNumber: Int, repo: String, completion: @escaping (_ comment: CommentType?, _ error: Error?) -> ()) {
        
        let params = [
            "repo": repo,
            "pr": issueNumber.description
        ]
        
        let body = [
            "content": comment
        ]
        
        self._sendRequestWithMethod(method: .post, endpoint: .pullRequestComments, params: params, query: nil, body: body as NSDictionary) { (response, body, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? NSDictionary {
                let (result, error): (BitBucketComment?, NSError?) = unthrow {
                    return try BitBucketComment(json: body)
                }
                completion(result, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
    
    func getCommentsOfIssue(issueNumber: Int, repo: String, completion: @escaping (_ comments: [CommentType]?, _ error: Error?) -> ()) {
        
        let params = [
            "repo": repo,
            "pr": issueNumber.description
        ]
        
        self._sendRequestWithMethod(method: .get, endpoint: .pullRequestComments, params: params, query: nil, body: nil) { (response, body, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let body = body as? [NSDictionary] {
                let (result, error): ([BitBucketComment]?, NSError?) = unthrow {
                    return try BitBucketArray(jsonArray: body)
                }
                completion(result?.map { $0 as CommentType }, error)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }
}

extension BitBucketServer {
    
    private func _sendRequest(request: NSMutableURLRequest, isRetry: Bool = false, completion: @escaping HTTP.Completion) {
        
        let _ = self.http.sendRequest(request as URLRequest) { (response, body, error) -> () in
            
            if let error = error {
                completion(response, body, error)
                return
            }
            
            //error out on special HTTP status codes
            let statusCode = response!.statusCode
            switch statusCode {
            case 401: //unauthorized, use refresh token to get a new access token
                      //only try to refresh token once
                if !isRetry {
                    self._handle401(request: request, completion: completion)
                }
                return
            case 400, 402 ... 500:
                
                let message = ((body as? NSDictionary)?["error"] as? NSDictionary)?["message"] as? String ?? (body as? String ?? "Unknown error")
                let resultString = "\(statusCode): \(message)"
                completion(response, body, GithubServerError.with(resultString/*, internalError: error*/))
                return
            default:
                break
            }
            
            completion(response, body, error)
        }
    }
    
    private func _handle401(request: NSMutableURLRequest, completion: @escaping HTTP.Completion) {
        
        //we need to use the refresh token to request a new access token
        //then we need to notify that we updated the secret, so that it can
        //be saved by buildasaur
        //then we need to set the new access token to this waiting request and
        //run it again. if that fails too, we fail for real.
        
        Log.verbose("Got 401, starting a BitBucket refresh token flow...")
        
        //get a new access token
        self._refreshAccessToken(request: request) { error in
            
            if let error = error {
                Log.verbose("Failed to get a new access token")
                completion(nil, nil, error)
                return
            }

            //we have a new access token, force set the new cred on the original
            //request
            self.endpoints.setAuthOnRequest(request: request)
            
            Log.verbose("Successfully refreshed a BitBucket access token")
            
            //retrying the original request
            self._sendRequest(request: request, isRetry: true, completion: completion)
        }
    }
    
    private func _refreshAccessToken(request: NSMutableURLRequest, completion: @escaping (Error?) -> ()) {
        
        let refreshRequest = self.endpoints.createRefreshTokenRequest()
        let _ = self.http.sendRequest(refreshRequest as URLRequest) { (response, body, error) -> () in
            
            if let error = error {
                completion(error)
                return
            }
            
            guard response?.statusCode == 200 else {
                completion(GithubServerError.with("Wrong status code returned, refreshing access token failed"))
                return
            }
            
            do {
                let payload = body as! NSDictionary
                let accessToken = try payload.stringForKey("access_token")
                let refreshToken = try payload.stringForKey("refresh_token")
                let secret = [refreshToken, accessToken].joined(separator: ":")
                
                let newAuth = ProjectAuthenticator(service: .BitBucket, username: "GIT", type: .OAuthToken, secret: secret)
                self.endpoints.auth.value = newAuth
                completion(nil)
            } catch {
                completion(error as NSError)
            }
        }
    }
    
    private func _sendRequestWithMethod(method: HTTP.Method, endpoint: BitBucketEndpoints.Endpoint, params: [String: String]?, query: [String: String]?, body: NSDictionary?, completion: @escaping HTTP.Completion) {
        
        var allParams = [
            "method": method.rawValue
        ]
        
        //merge the two params
        if let params = params {
            for (key, value) in params {
                allParams[key] = value
            }
        }
        
        do {
            let request = try self.endpoints.createRequest(method: method, endpoint: endpoint, params: allParams, query: query, body: body)
            self._sendRequestWithPossiblePagination(request: request, accumulatedResponseBody: NSArray(), completion: completion)
        } catch {
            completion(nil, nil, GithubServerError.with("Couldn't create Request, error \(error)"))
        }
    }
    
    private func _sendRequestWithPossiblePagination(request: NSMutableURLRequest, accumulatedResponseBody: NSArray, completion: @escaping HTTP.Completion) {
        
        self._sendRequest(request: request) {
            (response, body, error) -> () in
            
            if error != nil {
                completion(response, body, error)
                return
            }
            
            guard let dictBody = body as? NSDictionary else {
                completion(response, body, error)
                return
            }
            
            //pull out the values
            guard let arrayBody = dictBody["values"] as? [AnyObject] else {
                completion(response, dictBody, error)
                return
            }
            
            //we do have more, let's fetch it
            let newBody = accumulatedResponseBody.addingObjects(from: arrayBody)

            guard let nextLink = dictBody.optionalStringForKey("next") else {
                
                //is array, but we don't have any more data
                completion(response, newBody, error)
                return
            }
            
            let newRequest = request.mutableCopy() as! NSMutableURLRequest
            newRequest.url = URL(string: nextLink)!
            self._sendRequestWithPossiblePagination(request: newRequest, accumulatedResponseBody: newBody as NSArray, completion: completion)
            return
        }
    }

}
