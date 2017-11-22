//
//  SyncerLogic.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 01/10/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaGitServer
import XcodeServerSDK
import BuildaUtils

public struct StatusAndComment {
    public let status: StatusType
    public let comment: String?
    public let integration: Integration?
    public let links: [String: String]?

    public init(status: StatusType, comment: String? = nil, integration: Integration? = nil, links: [String: String]? = nil) {
        self.status = status
        self.comment = comment
        self.integration = integration
        self.links = links
    }
}

extension StandardSyncer {
    var _project: Project { return self.project }
    var _xcodeServer: XcodeServer { return self.xcodeServer }
    var _sourceServer: SourceServerType { return self.sourceServer }
    var _buildTemplate: BuildTemplate { return self.buildTemplate }
    var _waitForLttm: Bool { return self.config.waitForLttm }
    var _postStatusComments: Bool { return self.config.postStatusComments }
    var _watchingBranches: [String: Bool] { return self.config.watchingBranches }
    var _automaticallyWatchNewBranches: Bool { return self.config.automaticallyWatchNewBranches }
    var _slackWebhook: String? { return self.config.slackWebhook?.nonEmpty() }
    var _notifiers: [Notifier]? {
        var notifiers: [Notifier] = []
        if self._postStatusComments {
            notifiers.append(self.sourceNotifier)
        }
        if let slackNotifier = self.slackNotifier {
            notifiers.append(slackNotifier)
        }
        return notifiers
    }

    public typealias BotActions = (
        prsToSync: [(pr: PullRequestType, bot: Bot)],
        prBotsToCreate: [PullRequestType],
        branchesToSync: [(branch: BranchType, bot: Bot)],
        branchBotsToCreate: [BranchType],
        botsToDelete: [Bot])

    public func repoName() -> String? {
        return self._project.serviceRepoName()
    }

    internal func syncRepoWithName(repoName: String, completion: @escaping ([String: Bool]?) -> Void) {
        self._sourceServer.getRepo(repo: repoName, completion: { (repo, error) -> Void in
            if error != nil {
                //whoops, no more syncing for now
                self.notifyError(error: error, context: "Fetching Repo")
                completion(nil)
                return
            }

            if let repo = repo {

                self.syncRepoWithNameAndMetadata(repoName: repoName, repo: repo, completion: completion)
            } else {
                self.notifyErrorString(errorString: "Repo is nil and error is nil", context: "Fetching Repo")
                completion(nil)
            }
        })
    }

    private func syncRepoWithNameAndMetadata(repoName: String, repo: RepoType, completion: @escaping ([String: Bool]?) -> Void) {
        //pull PRs from source server
        self._sourceServer.getOpenPullRequests(repo: repoName, completion: { (prs, error) -> Void in

            if error != nil {
                //whoops, no more syncing for now
                self.notifyError(error: error, context: "Fetching PRs")
                completion(nil)
                return
            }

            if let prs = prs {

                self.reports["All Pull Requests"] = "\(prs.count)"
                self.syncRepoWithPRs(repoName: repoName, repo: repo, prs: prs, completion: completion)

            } else {
                self.notifyErrorString(errorString: "PRs are nil and error is nil", context: "Fetching PRs")
                completion(nil)
            }
        })
    }

    private func syncRepoWithPRs(repoName: String, repo: RepoType, prs: [PullRequestType], completion: @escaping ([String: Bool]?) -> Void) {
        //only fetch branches if there are any watched ones. there might be tens or hundreds of branches
        //so we don't want to fetch them unless user actually is watching any non-PR branches.
        if !self._watchingBranches.filter({ $0.value == true }).isEmpty || self._automaticallyWatchNewBranches {

            //we have PRs, now fetch branches
            self._sourceServer.getBranchesOfRepo(repo: repoName, completion: { (branches, error) -> Void in

                if error != nil {
                    //whoops, no more syncing for now
                    self.notifyError(error: error, context: "Fetching branches")
                    completion(nil)
                    return
                }

                if let branches = branches {

                    self.syncRepoWithPRsAndBranches(repoName: repoName, repo: repo, prs: prs, branches: branches, completion: completion)
                } else {
                    self.notifyErrorString(errorString: "Branches are nil and error is nil", context: "Fetching branches")
                    completion(nil)
                }
            })
        } else {

            //otherwise call the next step immediately with an empty array for branches
            self.syncRepoWithPRsAndBranches(repoName: repoName, repo: repo, prs: prs, branches: [], completion: completion)
        }
    }

    private func syncRepoWithPRsAndBranches(repoName: String, repo: RepoType, prs: [PullRequestType], branches: [BranchType], completion: @escaping ([String: Bool]?) -> Void) {
        //we have branches, now fetch bots
        self._xcodeServer.getBots({ (bots, error) -> Void in

            if let error = error {
                //whoops, no more syncing for now
                self.notifyError(error: error, context: "Fetching Bots")
                completion(nil)
                return
            }

            if let bots = bots {

                self.reports["All Bots"] = "\(bots.count)"

                //we have both PRs and Bots, resolve
                self.syncPRsAndBranchesAndBots(repo: repo, repoName: repoName, prs: prs, branches: branches, bots: bots, completion: { branches in

                    //everything is done, report the damage of the server's rate limit
                    if let rateLimitInfo = repo.latestRateLimitInfo {

                        let report = rateLimitInfo.report
                        self.reports["Rate Limit"] = report
                        Log.info("Rate Limit: \(report)")
                    }

                    completion(branches)
                })
            } else {
                self.notifyErrorString(errorString: "Nil bots even when error was nil", context: "Fetching Bots")
                completion(nil)
            }
        })
    }

    public func syncPRsAndBranchesAndBots(repo: RepoType, repoName: String, prs: [PullRequestType], branches: [BranchType], bots: [Bot], completion: @escaping ([String: Bool]?) -> Void) {
        let prsDescription = prs.map { (pr: PullRequestType) -> String in
            "    PR \(pr.number): \(pr.title) [\(pr.headName) -> \(pr.baseName)]"
            }.joined(separator: "\n")
        let branchesDescription = branches.map { (branch: BranchType) -> String in
            "    Branch [\(branch.name):\(branch.commitSHA)]" }
            .joined(separator: "\n")
        let botsDescription = bots.map { "    Bot \($0.name)" }.joined(separator: "\n")
        Log.verbose("Resolving prs:\n\(prsDescription) \nand branches:\n\(branchesDescription)\nand bots:\n\(botsDescription)")

        //create the changes necessary
        let (botActions, branchesToWatch) = self.resolvePRsAndBranchesAndBots(repoName: repoName, prs: prs, branches: branches, bots: bots)

        //create actions from changes, so called "SyncPairs"
        let syncPairs = self.createSyncPairsFrom(repo: repo, botActions: botActions)

        //start these actions
        self.applyResolvedSyncPairs(syncPairs: syncPairs) {
            completion(branchesToWatch)
        }
    }

    public func resolvePRsAndBranchesAndBots(
        repoName: String,
        prs: [PullRequestType],
        branches: [BranchType],
        bots: [Bot])
        -> (BotActions, [String: Bool]?) {

            //first filter only builda's bots, don't manipulate manually created bots
            //also filter only bots that belong to this project
            let buildaBots = bots.filter { BotNaming.isBuildaBotBelongingToRepoWithName(bot: $0, repoName: repoName) }

            //create a map of name -> bot for fast manipulation
            var mappedBots = buildaBots.toDictionary(key: { $0.name })

            //PRs that also have a bot, prsToSync
            var prsToSync: [(pr: PullRequestType, bot: Bot)] = []

            //branches that also have a bot, branchesToSync
            var branchesToSync: [(branch: BranchType, bot: Bot)] = []

            //PRs that don't have a bot yet, to create
            var prBotsToCreate: [PullRequestType] = []

            //branches that don't have a bot yet, to create
            var branchBotsToCreate: [BranchType] = []

            //make sure every PR has a bot
            for pr in prs {

                let botName = BotNaming.nameForBotWithPR(pr: pr, repoName: repoName)

                if let bot = mappedBots[botName] {
                    //we found a corresponding bot to this PR, add to toSync
                    prsToSync.append((pr: pr, bot: bot))

                    //and remove from bots mappedBots, because we handled it
                    _ = mappedBots.removeValue(forKey: botName)
                } else {
                    //no bot found for this PR, we'll have to create one
                    prBotsToCreate.append(pr)
                }
            }

            //first try to find Branch objects for our watched branches

            //create a map of branch names to branch objects for fast lookup
            let branchesDictionary = branches.toDictionary { $0.name }

            //filter just the ones we want
            var newBranchesSet = Set(branchesDictionary.keys)
            let watchedBranchesSet = Set(self._watchingBranches.keys)

            //Get new branches to watch
            newBranchesSet.subtract(watchedBranchesSet)
            //Add existing branches
            newBranchesSet = newBranchesSet.union(watchedBranchesSet.filter { branch -> Bool in
                return self._watchingBranches[branch] == true && branchesDictionary.keys.contains(branch)
            })
            //Remove branches attached to a PR
            newBranchesSet.subtract(prs.map { $0.headName })
            let branchesToWatch = newBranchesSet.map { branchesDictionary[$0]! }

            //go through the branches to track
            for branch in branchesToWatch {

                let botName = BotNaming.nameForBotWithBranch(branch: branch, repoName: repoName)

                if let bot = mappedBots[botName] {

                    //we found a corresponding bot to this watched Branch, add to toSync
                    branchesToSync.append((branch: branch, bot: bot))

                    //and remove from bots mappedBots, because we handled it
                    _ = mappedBots.removeValue(forKey: botName)
                } else {

                    //no bot found for this Branch, create one
                    branchBotsToCreate.append(branch)
                }
            }

            //bots that don't have a PR or a branch, to delete
            let botsToDelete = Array(mappedBots.values)

            let watchingBranches: [String: Bool]?
            if !self._watchingBranches.filter({ $0.value == true }).isEmpty || self._automaticallyWatchNewBranches {
                watchingBranches = branches.reduce([String: Bool]()) { (result, branch) -> [String: Bool] in
                    var result = result
                    result[branch.name] = branchesToWatch.contains(where: { $0.name == branch.name })
                    return result
                }
            } else {
                watchingBranches = nil
            }

            return ((prsToSync, prBotsToCreate, branchesToSync, branchBotsToCreate, botsToDelete), watchingBranches)
    }

    public func createSyncPairsFrom(repo: RepoType, botActions: BotActions) -> [SyncPair] {
        //create sync pairs for each action needed
        let syncPRBotSyncPairs = botActions.prsToSync.map({
            SyncPair_PR_Bot(pr: $0.pr, bot: $0.bot, resolver: SyncPairPRResolver()) as SyncPair
        })
        let createBotFromPRSyncPairs = botActions.prBotsToCreate.map({ SyncPair_PR_NoBot(pr: $0) as SyncPair })
        let syncBranchBotSyncPairs = botActions.branchesToSync.map({
            SyncPair_Branch_Bot(branch: $0.branch, bot: $0.bot, resolver: SyncPairBranchResolver()) as SyncPair
        })
        let createBotFromBranchSyncPairs = botActions.branchBotsToCreate.map({ SyncPair_Branch_NoBot(branch: $0, repo: repo) as SyncPair })
        let deleteBotSyncPairs = botActions.botsToDelete.map({ SyncPair_Deletable_Bot(bot: $0) as SyncPair })

        //here feel free to inject more things to be done during a sync

        //put them all into one array
        let toCreate: [SyncPair] = createBotFromPRSyncPairs + createBotFromBranchSyncPairs
        let toSync: [SyncPair] = syncPRBotSyncPairs + syncBranchBotSyncPairs
        let toDelete: [SyncPair] = deleteBotSyncPairs

        let syncPairsRaw: [SyncPair] = toCreate + toSync + toDelete

        //prepared sync pair
        let syncPairs = syncPairsRaw.map { (syncPair: SyncPair) -> SyncPair in
            syncPair.syncer = self
            return syncPair
        }

        if !toCreate.isEmpty {
            self.reports["Created bots"] = "\(toCreate.count)"
        }
        if !toDelete.isEmpty {
            self.reports["Deleted bots"] = "\(toDelete.count)"
        }
        if !toSync.isEmpty {
            self.reports["Synced bots"] = "\(toSync.count)"
        }

        return syncPairs
    }

    private func applyResolvedSyncPairs(syncPairs: [SyncPair], completion: @escaping () -> Void) {
        //actually kick the sync pairs off
        let group = DispatchGroup()
        for i in syncPairs {
            group.enter()
            i.start(completion: { (error) -> Void in
                if let error = error {
                    self.notifyError(error: error, context: "SyncPair: \(i.syncPairName())")
                }
                group.leave()
            })
        }

        group.notify(queue: DispatchQueue.main, execute: completion)
    }
}
