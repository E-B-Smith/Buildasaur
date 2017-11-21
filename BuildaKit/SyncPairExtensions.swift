//
//  SyncPairExtensions.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 19/05/15.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaGitServer
import BuildaUtils

extension SyncPair {

    public struct Actions {
        public let integrationsToCancel: [Integration]?
        public let statusToSet: (status: StatusAndComment, commit: String, issue: IssueType?)?
        public let startNewIntegrationBot: Bot? //if non-nil, starts a new integration on this bot
    }

    func performActions(actions: Actions, completion: @escaping Completion) {
        let group = DispatchGroup()
        var lastGroupError: Error?

        if let integrationsToCancel = actions.integrationsToCancel {
            group.enter()
            self.syncer.cancelIntegrations(integrations: integrationsToCancel, completion: { () -> Void in
                group.leave()
            })
        }

        if let newStatus = actions.statusToSet {
            let status = newStatus.status
            let commit = newStatus.commit
            let issue = newStatus.issue

            group.enter()
            self.syncer.updateCommitStatusIfNecessary(newStatus: status, commit: commit, issue: issue, completion: { (error) -> Void in
                if let error = error {
                    lastGroupError = error
                }
                group.leave()
            })
        }

        if let startNewIntegrationBot = actions.startNewIntegrationBot {
            let bot = startNewIntegrationBot

            group.enter()
            self.syncer._xcodeServer.postIntegration(bot.id, completion: { (integration, error) -> Void in
                if let integration = integration, error == nil {
                    Log.info("Bot \(bot.name) successfully enqueued Integration #\(integration.number)")
                } else {
                    let e = SyncerError.with("Bot \(bot.name) failed to enqueue an integration"/*, internalError: error*/)
                    lastGroupError = e
                }

                group.leave()
            })
        }

        group.notify(queue: DispatchQueue.main) {
            completion(lastGroupError)
        }
    }

    // MARK: Utility functions

    func getIntegrations(bot: Bot, completion: @escaping (_ integrations: [Integration], _ error: Error?) -> Void) {
        let syncer = self.syncer

        /*
        TODO: we should establish some reliable and reasonable plan for how many integrations to fetch.
        currently it's always 20, but some setups might have a crazy workflow with very frequent commits
        on active bots etc.
        */
        let query = [
            "last": "20"
        ]
        syncer?._xcodeServer.getBotIntegrations(bot.id, query: query, completion: { (integrations, error) -> Void in
            if error != nil {
                let e = SyncerError.with("Bot \(bot.name) failed return integrations"/*, internalError: error*/)
                completion([], e)
                return
            }

            if let integrations = integrations {
                completion(integrations, nil)

            } else {
                let e = SyncerError.with("Getting integrations"/*, internalError: SyncerError.with("Nil integrations even after returning nil error!")*/)
                completion([], e)
            }
        })
    }

}
