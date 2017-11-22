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
        public let statusToSet: (status: StatusAndComment, commit: String, branch: String, issue: IssueType?)?
        public let startNewIntegrationBot: Bot? //if non-nil, starts a new integration on this bot
        public let lastIntegration: Integration?
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
            let branch = newStatus.branch
            let issue = newStatus.issue

            group.enter()

            let updateCommitStatusIfNecessary: ((IntegrationIssues?) -> Void) = { [weak self] integrationIssues in
                let issues = self?.buildIssues(integrationIssues: integrationIssues)
                self?.syncer.updateCommitStatusIfNecessary(newStatus: status, commit: commit, branch: branch, issue: issue, issues: issues, completion: { (error) -> Void in
                    if let error = error {
                        lastGroupError = error
                    }
                    group.leave()
                })
            }

            switch status.status.state {
            case .NoState, .Pending, .Success:
                updateCommitStatusIfNecessary(nil)
            case .Failure, .Error:
                if let lastIntegration = actions.lastIntegration {
                    self.getIntegrationIssues(integration: lastIntegration, completion: { (integrationIssues, error) in
                        if error != nil {
                            lastGroupError = SyncerError.with("Integration \(lastIntegration.id!) failed to retrieve an integration issues")
                        }
                        updateCommitStatusIfNecessary(integrationIssues)
                    })
                } else {
                    updateCommitStatusIfNecessary(nil)
                }
            }

        }

        if let startNewIntegrationBot = actions.startNewIntegrationBot {
            let bot = startNewIntegrationBot

            group.enter()
            self.syncer._xcodeServer.postIntegration(bot.id, completion: { (integration, error) -> Void in
                if let integration = integration, error == nil {
                    Log.info("Bot \(bot.name) successfully enqueued Integration #\(integration.number)")
                } else {
                    lastGroupError = SyncerError.with("Bot \(bot.name) failed to enqueue an integration"/*, internalError: error*/)
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

    private func getIntegrationIssues(integration: Integration, completion: @escaping (_ integrationIssues: IntegrationIssues?, _ error: Error?) -> Void) {
        self.syncer?._xcodeServer.getIntegrationIssues(integration.id, completion: { (integrationIssues, error) in
            if error != nil {
                let e = SyncerError.with("Integration \(integration.id) failed return integration issues")
                completion(nil, e)
                return
            }

            if let integrationIssues = integrationIssues {
                completion(integrationIssues, nil)

            } else {
                let e = SyncerError.with("Getting integration issues")
                completion(nil, e)
            }
        })
    }
}

extension SyncPair {
    private  func buildIssues(integrationIssues: IntegrationIssues?) -> String? {
        guard let integrationIssues = integrationIssues else { return nil }

        var str = ""
        if !integrationIssues.buildServiceErrors.isEmpty {
            str += "*Service errors*\n"
            str += self.issues(integrationIssues.buildServiceErrors)
        }
        if !integrationIssues.triggerErrors.isEmpty {
            str += "*Triggers Errors*\n"
            str += self.issues(integrationIssues.triggerErrors)
        }
        if !integrationIssues.errors.isEmpty {
            str += "*Errors*\n"
            str += self.issues(integrationIssues.errors)
        }
        if !integrationIssues.testFailures.isEmpty {
            str += "*Test failures*\n"
            str += self.issues(integrationIssues.testFailures)
        }

        if !integrationIssues.buildServiceWarnings.isEmpty {
            str += "*Service warnings*\n"
            str += self.issues(integrationIssues.buildServiceWarnings)
        }
        if !integrationIssues.analyzerWarnings.isEmpty {
            str += "*Analyzer warnings*\n"
            str += self.issues(integrationIssues.analyzerWarnings)
        }
        if !integrationIssues.warnings.isEmpty {
            str += "*Warnings*\n"
            str += self.issues(integrationIssues.warnings)
        }

        return str
    }

    private func issues(_ issues: [IntegrationIssue]) -> String {
        return issues.reduce("", { (str, issue) -> String in
            var str = str
            str += self.string(for: issue) + "\n"
            return str
        })
    }

    private func emoji(for issue: IntegrationIssue) -> String {
        if case .resolved = issue.status {
            return "✅"
        } else if case .silenced = issue.status {
            return "🙊"
        }
        let emoji: String
        switch issue.type {
        case .BuildServiceError, .TriggerError, .Error, .TestFailure: emoji = "🛑"
        case .BuildServiceWarning, .Warning, .AnalyzerWarning: emoji = "⚠️"
        }
        return emoji
    }

    private func string(for issue: IntegrationIssue) -> String {
        var str = "\n" + self.emoji(for: issue) + "  "
        if let message = issue.message {
            str += message
        }
        if let lineNumber = issue.lineNumber,
            let file = issue.documentFilePath {
            str += "\n\tIn \(file):\(lineNumber)"
        }
        return str
    }
}
