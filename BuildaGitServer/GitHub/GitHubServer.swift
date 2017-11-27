//
//  GitHubSource.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 12/12/2014.
//  Copyright (c) 2014 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

class GitHubServer: GitServer {

    let endpoints: GitHubEndpoints
    var latestRateLimitInfo: GitHubRateLimit?

	let cache = InMemoryURLCache()

    init(endpoints: GitHubEndpoints, http: HTTP? = nil) {

        self.endpoints = endpoints
        super.init(service: .GitHub, http: http)
    }
}

//TODO: from each of these calls, return a "cancellable" object which can be used for cancelling

extension GitHubServer: SourceServerType {

    func getBranchesOfRepo(repo: String, completion: @escaping (_ branches: [BranchType]?, _ error: Error?) -> Void) {

        self._getBranchesOfRepo(repo: repo) { (branches, error) -> Void in
            completion(branches?.map { $0 as BranchType }, error)
        }
    }

    func getOpenPullRequests(repo: String, completion: @escaping (_ prs: [PullRequestType]?, _ error: Error?) -> Void) {

        self._getOpenPullRequests(repo: repo) { (prs, error) -> Void in
            completion(prs?.map { $0 as PullRequestType }, error)
        }
    }

    func getPullRequest(pullRequestNumber: Int, repo: String, completion: @escaping (_ pr: PullRequestType?, _ error: Error?) -> Void) {

        self._getPullRequest(pullRequestNumber: pullRequestNumber, repo: repo) { (pr, error) -> Void in
            completion(pr, error)
        }
    }

    func getRepo(repo: String, completion: @escaping (_ repo: RepoType?, _ error: Error?) -> Void) {

        self._getRepo(repo: repo) { (repo, error) -> Void in
            completion(repo, error)
        }
    }

    func getStatusOfCommit(commit: String, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> Void) {

        self._getStatusOfCommit(sha: commit, repo: repo) { (status, error) -> Void in
            completion(status, error)
        }
    }

    func postStatusOfCommit(commit: String, status: StatusType, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> Void) {

        self._postStatusOfCommit(status: status as! GitHubStatus, sha: commit, repo: repo) { (status, error) -> Void in
            completion(status, error)
        }
    }

    func getCommentsOfIssue(issueNumber: Int, repo: String, completion: @escaping (_ comments: [CommentType]?, _ error: Error?) -> Void) {

        self._getCommentsOfIssue(issueNumber: issueNumber, repo: repo) { (comments, error) -> Void in
            completion(comments?.map { $0 as CommentType }, error)
        }
    }

    func createStatusFromState(state buildState: BuildState, description: String?, targetUrl: [String: String]?) -> StatusType {

        let state = GitHubStatus.GitHubState.fromBuildState(buildState: buildState)
        let context = "Buildasaur"
        return GitHubStatus(state: state, description: description, targetUrl: targetUrl, context: context)
    }
}

extension GitHubServer: Notifier {
    func postCommentOnIssue(notification: NotifierNotification, completion: @escaping (_ comment: CommentType?, _ error: Error?) -> Void) {
        self._postCommentOnIssue(commentBody: notification.comment, issueNumber: notification.issueNumber!, repo: notification.repo) { (comment, error) -> Void in
            completion(comment, error)
        }
    }
}

extension GitHubServer {

    private func _sendRequestWithPossiblePagination(request: NSMutableURLRequest, accumulatedResponseBody: NSArray, completion: @escaping HTTP.Completion) {

        self._sendRequest(request: request) { (response, body, error) -> Void in

            if error != nil {
                completion(response, body, error)
                return
            }

            if let arrayBody = body as? [AnyObject] {

                let newBody = accumulatedResponseBody.addingObjects(from: arrayBody)

                if let links = response?.allHeaderFields["Link"] as? String {

                    //now parse page links
                    if let pageInfo = self._parsePageLinks(links: links) {

                        //here look at the links and go to the next page, accumulate the body from this response
                        //and pass it through

                        if let nextUrl = pageInfo[RelPage.Next] {

                            let newRequest = request.mutableCopy() as! NSMutableURLRequest
                            newRequest.url = nextUrl
                            self._sendRequestWithPossiblePagination(request: newRequest, accumulatedResponseBody: newBody as NSArray, completion: completion)
                            return
                        }
                    }
                }

                completion(response, newBody, error)
            } else {
                completion(response, body, error)
            }
        }
    }

    enum RelPage: String {
        case First = "first"
        case Next = "next"
        case Previous = "previous"
        case Last = "last"
    }

    private func _parsePageLinks(links: String) -> [RelPage: URL]? {

        var linkDict = [RelPage: URL]()

        for i in links.split(separator: ",") {

            let link = i.split(separator: ";")
            if link.count < 2 {
                continue
            }

            //url
            var urlString = link[0].trimmingCharacters(in: CharacterSet.whitespaces)
            if urlString.hasPrefix("<") && urlString.hasSuffix(">") {
                urlString = String(urlString[urlString.index(after: urlString.startIndex) ..< urlString.index(before: urlString.endIndex)])
            }

            //rel
            let relString = link[1]
            let relComps = relString.split(separator: "=")
            if relComps.count < 2 {
                continue
            }

            var relName = relComps[1]
            if relName.hasPrefix("\"") && relName.hasSuffix("\"") {
                relName = relName[relName.index(after: relName.startIndex) ..< relName.index(before: relName.endIndex)]
            }

            if let rel = RelPage(rawValue: String(relName)),
                let url = URL(string: urlString) {
                linkDict[rel] = url
            }
        }

        return linkDict
    }

    private func _parseRateLimitInfo(headers: [AnyHashable: Any]) {
        if let resetTime = (headers["X-RateLimit-Reset"] as? NSString)?.doubleValue,
            let limit = (headers["X-RateLimit-Limit"] as? NSString)?.integerValue,
            let remaining = (headers["X-RateLimit-Remaining"] as? NSString)?.integerValue {

            self.latestRateLimitInfo = GitHubRateLimit(resetTime: resetTime, limit: limit, remaining: remaining)

        } else {
            Log.error("No X-RateLimit info provided by GitHub in headers: \(headers), we're unable to detect the remaining number of allowed requests. GitHub might fail to return data any time now :(")
        }
    }

    private func _sendRequest(request: NSMutableURLRequest, completion: @escaping HTTP.Completion) {

        let cachedInfo = self.cache.getCachedInfoForRequest(request as URLRequest)
        if let etag = cachedInfo.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        _ = self.http.sendRequest(request as URLRequest, completion: { (response, body, error) -> Void in

            if let error = error {
                completion(response, body, error)
                return
            }

            if response == nil {
                completion(nil, body, GithubServerError.with("Nil response"))
                return
            }

            if let response = response {
                self._parseRateLimitInfo(headers: response.allHeaderFields)
            }

            if
                let respDict = body as? NSDictionary,
                let message = respDict["message"] as? String, message == "Not Found" {

                    let url = request.url ?? (NSURL() as URL)
                    completion(nil, nil, GithubServerError.with("Not found: \(url)"))
                    return
            }

            //error out on special HTTP status codes
            let statusCode = response!.statusCode
            switch statusCode {
            case 200...299: //good response, cache the returned data
                let responseInfo = ResponseInfo(response: response!, body: body as AnyObject)
                cachedInfo.update(responseInfo)
            case 304: //not modified, return the cached response
                let responseInfo = cachedInfo.responseInfo!
                completion(responseInfo.response, responseInfo.body, nil)
                return
            case 400 ... 500:
                let message = (body as? NSDictionary)?["message"] as? String ?? "Unknown error"
                var resultString = "\(statusCode): \(message)"
                if let errors = (body as? NSDictionary)?["errors"] as? [[String: Any]],
                    let error = errors.first,
                    let message = error["message"] {
                    resultString += " - \(message)"
                }
                completion(response, body, GithubServerError.with(resultString))
                return
            default:
                break
            }

            completion(response, body, error)
        })
    }

    private func _sendRequestWithMethod(method: HTTP.Method, endpoint: GitHubEndpoints.Endpoint, params: [String: String]?, query: [String: String]?, body: NSDictionary?, completion: @escaping HTTP.Completion) {

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

    /**
    *   GET all open pull requests of a repo (full name).
    */
    private func _getOpenPullRequests(repo: String, completion: @escaping (_ prs: [GitHubPullRequest]?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo
        ]
        self._sendRequestWithMethod(method: .get, endpoint: .pullRequests, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSArray,
                let prs: [GitHubPullRequest] = try? GitHubArray(jsonArray: body) {
                completion(prs, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   GET a pull requests of a repo (full name) by its number.
    */
    private func _getPullRequest(pullRequestNumber: Int, repo: String, completion: @escaping (_ pr: GitHubPullRequest?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "pr": pullRequestNumber.description
        ]

        self._sendRequestWithMethod(method: .get, endpoint: .pullRequests, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let pr = try? GitHubPullRequest(json: body)
            {
                completion(pr, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   GET all open issues of a repo (full name).
    */
    private func _getOpenIssues(repo: String, completion: @escaping (_ issues: [GitHubIssue]?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo
        ]
        self._sendRequestWithMethod(method: .get, endpoint: .issues, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSArray,
                let issues: [GitHubIssue] = try? GitHubArray(jsonArray: body) {
                completion(issues, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   GET an issue of a repo (full name) by its number.
    */
    private func _getIssue(issueNumber: Int, repo: String, completion: @escaping (_ issue: GitHubIssue?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "issue": issueNumber.description
        ]

        self._sendRequestWithMethod(method: .get, endpoint: .issues, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let issue = try? GitHubIssue(json: body)
            {
                completion(issue, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   POST a new Issue
    */
    private func _postNewIssue(issueTitle: String, issueBody: String?, repo: String, completion: @escaping (_ issue: GitHubIssue?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo
        ]

        let body = [
            "title": issueTitle,
            "body": issueBody ?? ""
        ]

        self._sendRequestWithMethod(method: .post, endpoint: .issues, params: params, query: nil, body: body as NSDictionary) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let issue = try? GitHubIssue(json: body)
            {
                completion(issue, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   Close an Issue by its number and repo (full name).
    */
    private func _closeIssue(issueNumber: Int, repo: String, completion: @escaping (_ issue: GitHubIssue?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "issue": issueNumber.description
        ]

        let body = [
            "state": "closed"
        ]

        self._sendRequestWithMethod(method: .patch, endpoint: .issues, params: params, query: nil, body: body as NSDictionary) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let issue = try? GitHubIssue(json: body)
            {
                completion(issue, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   GET the status of a commit (sha) from a repo.
    */
    private func _getStatusOfCommit(sha: String, repo: String, completion: @escaping (_ status: GitHubStatus?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "sha": sha
        ]

        self._sendRequestWithMethod(method: .get, endpoint: .statuses, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSArray,
                let statuses: [GitHubStatus] = try? GitHubArray(jsonArray: body)
            {
                //sort them by creation date
                let mostRecentStatus = statuses.sorted(by: { return $0.created! > $1.created! }).first
                completion(mostRecentStatus, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   POST a new status on a commit.
    */
    private func _postStatusOfCommit(status: GitHubStatus, sha: String, repo: String, completion: @escaping (_ status: GitHubStatus?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "sha": sha
        ]

        let body = status.dictionarify()
        self._sendRequestWithMethod(method: .post, endpoint: .statuses, params: params, query: nil, body: body) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let status = try? GitHubStatus(json: body)
            {
                completion(status, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   GET comments of an issue - WARNING - there is a difference between review comments (on a PR, tied to code)
    *   and general issue comments - which appear in both Issues and Pull Requests (bc a PR is an Issue + code)
    *   This API only fetches the general issue comments, NOT comments on code.
    */
    private func _getCommentsOfIssue(issueNumber: Int, repo: String, completion: @escaping (_ comments: [GitHubComment]?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "issue": issueNumber.description
        ]

        self._sendRequestWithMethod(method: .get, endpoint: .issueComments, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSArray,
                let comments: [GitHubComment] = try? GitHubArray(jsonArray: body)
            {
                completion(comments, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   POST a comment on an issue.
    */
    private func _postCommentOnIssue(commentBody: String, issueNumber: Int, repo: String, completion: @escaping (_ comment: GitHubComment?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "issue": issueNumber.description
        ]

        let body = [
            "body": commentBody
        ]

        self._sendRequestWithMethod(method: .post, endpoint: .issueComments, params: params, query: nil, body: body as NSDictionary) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let comment = try? GitHubComment(json: body)
            {
                completion(comment, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   PATCH edit a comment with id
    */
    private func _editCommentOnIssue(commentId: Int, newCommentBody: String, repo: String, completion: @escaping (_ comment: GitHubComment?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo,
            "comment": commentId.description
        ]

        let body = [
            "body": newCommentBody
        ]

        self._sendRequestWithMethod(method: .patch, endpoint: .issueComments, params: params, query: nil, body: body as NSDictionary) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let comment = try? GitHubComment(json: body)
            {
                completion(comment, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   POST merge a head branch/commit into a base branch.
    *   has a couple of different responses, a bit tricky
    */
    private func _mergeHeadIntoBase(head: String, base: String, commitMessage: String, repo: String, completion: @escaping (_ result: GitHubEndpoints.MergeResult?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo
        ]

        let body = [
            "head": head,
            "base": base,
            "commit_message": commitMessage
        ]

        self._sendRequestWithMethod(method: .post, endpoint: .merges, params: params, query: nil, body: body as NSDictionary) { (response, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if let response = response {
                let code = response.statusCode
                switch code {
                case 201:
                    //success
                    completion(GitHubEndpoints.MergeResult.success(body as! NSDictionary), error)

                case 204:
                    //no-op
                    completion(GitHubEndpoints.MergeResult.nothingToMerge, error)

                case 409:
                    //conflict
                    completion(GitHubEndpoints.MergeResult.conflict, error)

                case 404:
                    //missing
                    let bodyDict = body as! NSDictionary
                    let message = bodyDict["message"] as! String
                    completion(GitHubEndpoints.MergeResult.missing(message), error)
                default:
                    completion(nil, error)
                }
            } else {
                completion(nil, GithubServerError.with("Nil response"))
            }
        }
    }

    /**
    *   GET branches of a repo
    */
    private func _getBranchesOfRepo(repo: String, completion: @escaping (_ branches: [GitHubBranch]?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo
        ]

        self._sendRequestWithMethod(method: .get, endpoint: .branches, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSArray,
                let branches: [GitHubBranch] = try? GitHubArray(jsonArray: body)
            {
                completion(branches, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

    /**
    *   GET repo metadata
    */
    private func _getRepo(repo: String, completion: @escaping (_ repo: GitHubRepo?, _ error: Error?) -> Void) {

        let params = [
            "repo": repo
        ]

        self._sendRequestWithMethod(method: .get, endpoint: .repos, params: params, query: nil, body: nil) { (_, body, error) -> Void in

            if error != nil {
                completion(nil, error)
                return
            }

            if
                let body = body as? NSDictionary,
                let repository: GitHubRepo = try? GitHubRepo(json: body)
            {
                completion(repository, nil)
            } else {
                completion(nil, GithubServerError.with("Wrong body \(String(describing: body))"))
            }
        }
    }

}
