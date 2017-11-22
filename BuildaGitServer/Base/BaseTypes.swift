//
//  BaseTypes.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/16/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation

public protocol BuildStatusCreator {
    func createStatusFromState(state: BuildState, description: String?, targetUrl: [String: String]?) -> StatusType
}

public protocol SourceServerType: BuildStatusCreator {
    func getBranchesOfRepo(repo: String, completion: @escaping (_ branches: [BranchType]?, _ error: Error?) -> Void)
    func getOpenPullRequests(repo: String, completion: @escaping (_ prs: [PullRequestType]?, _ error: Error?) -> Void)
    func getPullRequest(pullRequestNumber: Int, repo: String, completion: @escaping (_ pr: PullRequestType?, _ error: Error?) -> Void)
    func getRepo(repo: String, completion: @escaping (_ repo: RepoType?, _ error: Error?) -> Void)
    func getStatusOfCommit(commit: String, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> Void)
    func postStatusOfCommit(commit: String, status: StatusType, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> Void)
    func getCommentsOfIssue(issueNumber: Int, repo: String, completion: @escaping (_ comments: [CommentType]?, _ error: Error?) -> Void)
}

public struct NotifierNotification {
    public let comment: String
    public let issueNumber: Int?
    public let repo: String
    public let branch: String
    public let status: StatusType
    public let integrationResult: String?
    public let linksToIntegration: [String: String]?
    public let issues: String?

    public init(comment: String, issueNumber: Int?, repo: String, branch: String, status: StatusType, integrationResult: String?, linksToIntegration: [String: String]?, issues: String?) {
        self.comment = comment
        self.issueNumber = issueNumber
        self.repo = repo
        self.branch = branch
        self.status = status
        self.integrationResult = integrationResult
        self.linksToIntegration = linksToIntegration
        self.issues = issues
    }
}

public protocol Notifier {
    func postCommentOnIssue(notification: NotifierNotification, completion: @escaping (_ comment: CommentType?, _ error: Error?) -> Void)
}

public class SourceServerFactory {

    public init() { }

    public func createServer(service: GitService, auth: ProjectAuthenticator?) -> SourceServerType & Notifier {

        if let auth = auth {
            precondition(service == auth.service)
        }

        return GitServerFactory.server(service: service, auth: auth)
    }
}

public struct RepoPermissions {
    public let read: Bool
    public let write: Bool
    public init(read: Bool, write: Bool) {
        self.read = read
        self.write = write
    }
}

public protocol RateLimitType {

    var report: String { get }
}

public protocol RepoType {

    var permissions: RepoPermissions { get }
    var originUrlSSH: String { get }
    var latestRateLimitInfo: RateLimitType? { get }
}

public protocol BranchType {

    var name: String { get }
    var commitSHA: String { get }
}

public protocol IssueType {

    var number: Int { get }
}

public protocol PullRequestType: IssueType {
    var headName: String { get }
    var headCommitSHA: String { get }
    var headRepo: RepoType { get }

    var baseName: String { get }

    var title: String { get }
}

public enum BuildState: String {
    case NoState
    case Pending
    case Success
    case Error
    case Failure
}

public protocol StatusType {
    var state: BuildState { get }
    var description: String? { get }
    var targetUrl: String? { get }
}

extension StatusType {

    public func isEqual(rhs: StatusType) -> Bool {
        let lhs = self
        return lhs.state == rhs.state && lhs.description == rhs.description
    }
}

public protocol CommentType {

    var body: String { get }
}
