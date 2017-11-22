//
//  StandardSyncer.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 15/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaGitServer
import XcodeServerSDK

public class StandardSyncer: Syncer {
    public var sourceServer: SourceServerType {
        didSet {
            self.onRequireUIUpdate?()
        }
    }

    public var sourceNotifier: Notifier
    public var slackNotifier: SlackNotifier?

    public var xcodeServer: XcodeServer {
        didSet {
            if oldValue != self.xcodeServer {
                self.onRequireUIUpdate?()
            }
        }
    }
    public var project: Project {
        didSet {
            self.onRequireUIUpdate?()
        }
    }
    public var buildTemplate: BuildTemplate {
        didSet {
            self.onRequireUIUpdate?()
        }
    }
    public var triggers: [Trigger] {
        didSet {
            self.onRequireUIUpdate?()
        }
    }

    public override var active: Bool {
        didSet {
            if oldValue != self.active {
                self.onRequireUIUpdate?()
            }
        }
    }

    public var config: SyncerConfig {
        didSet {
            self.syncInterval = self.config.syncInterval
            self.onRequireUIUpdate?()
        }
    }

    public override var state: SyncerEventType {
        didSet {
            if oldValue != self.state {
                self.onRequireUIUpdate?()
            }
        }
    }

    public var onRequireUIUpdate: (() -> Void)?
    public var onRequireLog: (() -> Void)?

    public var configTriplet: ConfigTriplet {
        return ConfigTriplet(syncer: self.config, server: self.xcodeServer.config, project: self.project.config, buildTemplate: self.buildTemplate, triggers: self.triggers.map { $0.config })
    }

    public init(integrationServer: XcodeServer, sourceServer: SourceServerType & Notifier, project: Project, buildTemplate: BuildTemplate, triggers: [Trigger], config: SyncerConfig) {
        self.config = config

        self.sourceServer = sourceServer
        self.sourceNotifier = sourceServer
        self.xcodeServer = integrationServer
        self.project = project
        self.buildTemplate = buildTemplate
        self.triggers = triggers

        if let slackWebhook = self.config.slackWebhook,
            let url = URL(string: slackWebhook) {
            self.slackNotifier = SlackNotifier(webhookURL: url)
        }

        super.init(syncInterval: config.syncInterval)
    }

    deinit {
        self.active = false
    }

    public override func sync(completion: @escaping () -> Void) {
        if let repoName = self.repoName() {
            self.syncRepoWithName(repoName: repoName) { [weak self] watchingBranches in
                if let watchingBranches = watchingBranches {
                    self?.config.watchingBranches = watchingBranches
                }
                completion()
            }
        } else {
            self.notifyErrorString(errorString: "Nil repo name", context: "Syncing")
            completion()
        }
    }
}
