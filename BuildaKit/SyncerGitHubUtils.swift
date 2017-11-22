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

    public func createStatusFromState(state: BuildState, description: String?, targetUrl: [String: String]?) -> StatusType {

        return self._sourceServer.createStatusFromState(state: state, description: description, targetUrl: targetUrl)
    }
}

extension StandardSyncer {
    func updateCommitStatusIfNecessary(
        newStatus: StatusAndComment,
        commit: String,
        branch: String,
        issue: IssueType?,
        issues: String? = nil,
        completion: @escaping SyncPair.Completion) {
        let repoName = self.repoName()!
        self._sourceServer.getStatusOfCommit(commit: commit, repo: repoName, completion: { (status, error) -> Void in

            if error != nil {
                let e = XcodeDeviceParserError.with("Commit \(commit) failed to return status"/*, internalError: error as? Error*/)
                completion(e)
                return
            }

            if status == nil || !newStatus.status.isEqual(rhs: status!) {

                //TODO: add logic for handling the creation of a new Issue for branch tracking
                //and the deletion of it when build succeeds etc.

                self.postStatusWithComment(statusWithComment: newStatus, commit: commit, repo: repoName, branch: branch, issue: issue, issues: issues, completion: completion)

            } else {
                completion(nil)
            }
        })
    }

    func postMessageOnSlackIfPossible(statusWithComment: StatusAndComment, commit: String, repo: String, branch: String, issue: IssueType?, issues: String?) {
        // We prioritise Slack over Github comments
        if let slackWebhook = self._slackWebhook,
            statusWithComment.comment != nil {
            SlackIntegration(webhook: slackWebhook)
                .postCommentOnIssue(statusWithComment: statusWithComment, repo: repo, branch: branch, prNumber: issue?.number, issues: issues)
        }
    }

    func postStatusWithComment(statusWithComment: StatusAndComment, commit: String, repo: String, branch: String, issue: IssueType?, issues: String?, completion: @escaping SyncPair.Completion) {

        self.postMessageOnSlackIfPossible(statusWithComment: statusWithComment, commit: commit, repo: repo, branch: branch, issue: issue, issues: issues)

        self._sourceServer.postStatusOfCommit(commit: commit, status: statusWithComment.status, repo: repo) { (_, error) -> Void in

            if let error = error as NSError? {
                let e = XcodeDeviceParserError.with("Failed to post a status on commit \(commit) of repo \(repo) \(error.userInfo["info"]!)")
                completion(e)
                return
            }

            //have a chance to NOT post a status comment...
            let postStatusComments = self._postStatusComments

            //optional there can be a comment to be posted and there's an issue to be posted on
            if
                let issue = issue,
                let comment = statusWithComment.comment, postStatusComments {

                //we have a comment, post it to the right place
                self._sourceServer.postCommentOnIssue(comment: comment, issueNumber: issue.number, repo: repo, completion: { (comment, error) -> Void in
                    if let error = error {
                        let e = XcodeDeviceParserError.with("Failed to post a comment \"\(String(describing: comment))\" on Issue \(issue.number) of repo \(repo) \(error)")
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
