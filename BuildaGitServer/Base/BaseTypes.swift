//
//  BaseTypes.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/16/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result

public protocol BuildStatusCreator {
    func createStatusFromState(state: BuildState, description: String?, targetUrl: String?) -> StatusType
}

public protocol SourceServerType: BuildStatusCreator {
    
    func getBranchesOfRepo(repo: String, completion: @escaping (_ branches: [BranchType]?, _ error: Error?) -> ())
    func getOpenPullRequests(repo: String, completion: @escaping (_ prs: [PullRequestType]?, _ error: Error?) -> ())
    func getPullRequest(pullRequestNumber: Int, repo: String, completion: @escaping (_ pr: PullRequestType?, _ error: Error?) -> ())
    func getRepo(repo: String, completion: @escaping (_ repo: RepoType?, _ error: Error?) -> ())
    func getStatusOfCommit(commit: String, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> ())
    func postStatusOfCommit(commit: String, status: StatusType, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> ())
    func postCommentOnIssue(comment: String, issueNumber: Int, repo: String, completion: @escaping (_ comment: CommentType?, _ error: Error?) -> ())
    func getCommentsOfIssue(issueNumber: Int, repo: String, completion: @escaping (_ comments: [CommentType]?, _ error: Error?) -> ())

    func authChangedSignal() -> Signal<ProjectAuthenticator?, NoError>
}

public class SourceServerFactory {
    
    public init() { }
    
    public func createServer(service: GitService, auth: ProjectAuthenticator?) -> SourceServerType {
        
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

public enum BuildState {
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

