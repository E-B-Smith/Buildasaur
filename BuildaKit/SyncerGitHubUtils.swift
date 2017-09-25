//
//  SyncerGitHubUtils.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 16/05/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaGitServer
import BuildaUtils

extension StandardSyncer: BuildStatusCreator {
    
    public func createStatusFromState(state: BuildState, description: String?, targetUrl: String?) -> StatusType {
        
        return self._sourceServer.createStatusFromState(state: state, description: description, targetUrl: targetUrl)
    }
}

extension StandardSyncer {
    
    func updateCommitStatusIfNecessary(
        newStatus: StatusAndComment,
        commit: String,
        issue: IssueType?,
        completion: @escaping SyncPair.Completion) {
        
        let repoName = self.repoName()!
        self._sourceServer.getStatusOfCommit(commit: commit, repo: repoName, completion: { (status, error) -> () in
            
            if error != nil {
                let e = XcodeDeviceParserError.with("Commit \(commit) failed to return status"/*, internalError: error as? Error*/)
                completion(e)
                return
            }
            
            if status == nil || !newStatus.status.isEqual(rhs: status!) {
                
                //TODO: add logic for handling the creation of a new Issue for branch tracking
                //and the deletion of it when build succeeds etc.
                
                self.postStatusWithComment(statusWithComment: newStatus, commit: commit, repo: repoName, issue: issue, completion: completion)
                
            } else {
                completion(nil)
            }
        })
    }

    func postStatusWithComment(statusWithComment: StatusAndComment, commit: String, repo: String, issue: IssueType?, completion: @escaping SyncPair.Completion) {
        
        self._sourceServer.postStatusOfCommit(commit: commit, status: statusWithComment.status, repo: repo) { (status, error) -> () in
            
            if error != nil {
                let e = XcodeDeviceParserError.with("Failed to post a status on commit \(commit) of repo \(repo)"/*, internalError: error as? NSError*/)
                completion(e)
                return
            }
            
            //have a chance to NOT post a status comment...
            let postStatusComments = self._postStatusComments
            
            //optional there can be a comment to be posted and there's an issue to be posted on
            if
                let issue = issue,
                let comment = statusWithComment.comment, postStatusComments {
                
                //we have a comment, post it
                self._sourceServer.postCommentOnIssue(comment: comment, issueNumber: issue.number, repo: repo, completion: { (comment, error) -> () in
                    
                    if error != nil {
                        let e = XcodeDeviceParserError.with("Failed to post a comment \"\(String(describing: comment))\" on Issue \(issue.number) of repo \(repo)"/*, internalError: error as? NSError*/)
                        completion(e)
                    } else {
                        completion(nil)
                    }
                })
                
            } else {
                completion(nil)
            }
        }
    }
}
