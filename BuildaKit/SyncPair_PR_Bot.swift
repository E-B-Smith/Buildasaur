//
//  SyncPair_PR_Bot.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 16/05/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaGitServer
import BuildaUtils

public class SyncPair_PR_Bot: SyncPair {

    let pr: PullRequestType
    let bot: Bot
    public let resolver: SyncPairPRResolver

    public init(pr: PullRequestType, bot: Bot, resolver: SyncPairPRResolver) {
        self.pr = pr
        self.bot = bot
        self.resolver = resolver
        super.init()
    }

    override func sync(completion: @escaping Completion) {

        //sync the PR with the Bot
        self.syncPRWithBot(completion: completion)
    }

    override func syncPairName() -> String {
        return "PR (\(self.pr.number):\(self.pr.headName)) + Bot (\(self.bot.name))"
    }

    // MARK: Internal

    private func syncPRWithBot(completion: @escaping Completion) {

        let syncer = self.syncer
        let bot = self.bot
        let pr = self.pr
        let headCommit = pr.headCommitSHA
        let issue = pr

        self.getIntegrations(bot: bot, completion: { (integrations, error) -> Void in

            if let error = error {
                completion(error)
                return
            }

            //first check whether the bot is even enabled
            self.isBotEnabled(integrations: integrations, completion: { (isEnabled, error) -> Void in

                if let error = error {
                    completion(error)
                    return
                }

                if isEnabled {

                    self.syncer.xcodeServer.getHostname { (hostname, error) -> Void in

                        if let error = error {
                            completion(error)
                            return
                        }

                        let actions = self.resolver.resolveActionsForCommitAndIssueWithBotIntegrations(
                            commit: headCommit,
                            issue: issue,
                            bot: bot,
                            hostname: hostname!,
                            buildStatusCreator: self.syncer,
                            integrations: integrations)
                        self.performActions(actions: actions, completion: completion)
                    }

                } else {

                    //not enabled, make sure the PR reflects that and the instructions are clear
                    Log.verbose("Bot \(bot.name) is not yet enabled, ignoring...")

                    let status = self.syncer.createStatusFromState(state: BuildState.Pending, description: "Waiting for \"lttm\" to start testing", targetUrl: nil)
                    let notYetEnabled = StatusAndComment(status: status)
                    syncer?.updateCommitStatusIfNecessary(newStatus: notYetEnabled, commit: headCommit, issue: pr, completion: completion)
                }
            })
        })
    }

    private func isBotEnabled(integrations: [Integration], completion: @escaping (_ isEnabled: Bool, _ error: Error?) -> Void) {

        //bot is enabled if (there are any integrations) OR (there is a recent comment with a keyword to enable the bot in the pull request's conversation)
        //which means that there are two ways of enabling a bot.
        //a) manually start an integration through Xcode, API call or in Builda's GUI (TBB)
        //b) (optional) comment an agreed keyword in the Pull Request, e.g. "lttm" - 'looks testable to me' is a frequent one

        if !integrations.isEmpty || !self.syncer._waitForLttm {
            completion(true, nil)
            return
        }

        let keyword = ["lttm"]

        if let repoName = syncer.repoName() {

            self.syncer.sourceServer.findMatchingCommentInIssue(commentsToMatch: keyword, issue: self.pr.number, repo: repoName) { (foundComments, error) -> Void in

                if error != nil {
                    let e = SyncerError.with("Fetching comments"/*, internalError: error as? NSError*/)
                    completion(false, e)
                    return
                }

                if let foundComments = foundComments {
                    completion(!foundComments.isEmpty, nil)
                } else {
                    completion(false, nil)
                }
            }

        } else {
            completion(false, SyncerError.with("No repo name, cannot find the GitHub repo!"))
        }
    }
}
