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
            self.onRequireUpdate?()
        }
    }
    public var xcodeServer: XcodeServer {
        didSet {
            self.onRequireUpdate?()
        }
    }
    public var project: Project {
        didSet {
            self.onRequireUpdate?()
        }
    }
    public var buildTemplate: BuildTemplate {
        didSet {
            self.onRequireUpdate?()
        }
    }
    public var triggers: [Trigger] {
        didSet {
            self.onRequireUpdate?()
        }
    }

    public override var active: Bool {
        didSet {
            self.onRequireUpdate?()
        }
    }

    public var config: SyncerConfig {
        didSet {
            self.syncInterval = self.config.syncInterval
            self.onRequireUpdate?()
        }
    }

    public var onRequireUpdate: (() -> Void)?
    public var onRequireLog: (() -> Void)?

    public var configTriplet: ConfigTriplet {
        return ConfigTriplet(syncer: self.config, server: self.xcodeServer.config, project: self.project.config, buildTemplate: self.buildTemplate, triggers: self.triggers.map { $0.config })
    }

    public init(integrationServer: XcodeServer, sourceServer: SourceServerType, project: Project, buildTemplate: BuildTemplate, triggers: [Trigger], config: SyncerConfig) {
        self.config = config

        self.sourceServer = sourceServer
        self.xcodeServer = integrationServer
        self.project = project
        self.buildTemplate = buildTemplate
        self.triggers = triggers

        super.init(syncInterval: config.syncInterval)
    }

    deinit {
        self.active = false
    }

    public override func sync(completion: @escaping () -> Void) {
        if let repoName = self.repoName() {
            self.syncRepoWithName(repoName: repoName, completion: completion)
        } else {
            self.notifyErrorString(errorString: "Nil repo name", context: "Syncing")
            completion()
        }
    }
}
