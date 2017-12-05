//
//  SyncerNotifierUtils.swift
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
                let e = XcodeDeviceParserError.with("Commit \(commit) failed to return status")
                completion(e)
                return
            }

            if newStatus.status.state != status?.state {

                //TODO: add logic for handling the creation of a new Issue for branch tracking
                //and the deletion of it when build succeeds etc.

                // Update commit status
                self._sourceServer.postStatusOfCommit(commit: commit, status: newStatus.status, repo: repoName) { (_, error) -> Void in

                    if let error = error as NSError? {
                        let e = XcodeDeviceParserError.with("Failed to post a status on commit \(commit) of repo \(repoName) \(error.userInfo["info"]!)")
                        completion(e)
                        return
                    }

                    completion(nil)
                }

                if let comment = newStatus.comment {
                    let notifierNotification = NotifierNotification(comment: comment,
                                                                    issueNumber: issue?.number,
                                                                    repo: repoName,
                                                                    branch: branch,
                                                                    status: newStatus.status,
                                                                    integrationResult: newStatus.integration?.result?.rawValue,
                                                                    linksToIntegration: newStatus.links,
                                                                    issues: issues)

                    self._notifiers?.forEach {
                        $0.postCommentOnIssue(notification: notifierNotification, completion: { (comment, error) -> Void in
                            if let error = error {
                                let issueNumber: String
                                if let number = issue?.number {
                                    issueNumber = "\(number)"
                                } else {
                                    issueNumber = "-"
                                }
                                let e = XcodeDeviceParserError.with("Failed to post a comment \"\(String(describing: comment))\" on Issue \(issueNumber) of repo \(repoName) \(error)")
                                completion(e)
                            } else {
                                completion(nil)
                            }
                        })
                    }
                }
            } else {
                completion(nil)
            }
        })
    }
}
