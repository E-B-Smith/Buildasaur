//
//  SyncerManager.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/3/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaHeartbeatKit
import BuildaUtils

//owns running syncers and their children, manages starting/stopping them,
//creating them from configurations

public class SyncerManager {

    public let storageManager: StorageManager
    public let factory: SyncerFactoryType
    public let loginItem: LoginItem

    public var syncers: [StandardSyncer] {
        didSet {
            self.onSyncersChange?(self.syncers)
        }
    }
    public var onSyncersChange: (([StandardSyncer]) -> Void)?
    public var configTriplets: [ConfigTriplet] = []
    public var heartbeatManager: HeartbeatManager?

    public init(storageManager: StorageManager, factory: SyncerFactoryType, loginItem: LoginItem) {

        self.storageManager = storageManager
        self.loginItem = loginItem

        self.factory = factory
        self.syncers = []

        self.storageManager.onUpdateSyncerConfigs = { [weak self] in
            self?.reloadSyncers()
        }
        self.reloadSyncers()
        self.checkForAutostart()
        self.setupHeartbeatManager()
    }

    private func reloadSyncers() {
        typealias OptionalTuple = (SyncerConfig, XcodeServerConfig?, ProjectConfig?, BuildTemplate?, [TriggerConfig]?)
        typealias OptionalTuples = [OptionalTuple]

        let latestTuples: OptionalTuples = self.storageManager.syncerConfigs.values.map { (syncerConfig: SyncerConfig) -> OptionalTuple in
            let buildTemplates = self.storageManager.buildTemplates[syncerConfig.preferredTemplateRef]
            let triggerIds = Set(buildTemplates?.triggers ?? [])
            let triggers = self.storageManager.triggerConfigs.filter { triggerIds.contains($0.0) }.map { $0.1 }
            return (
                syncerConfig,
                self.storageManager.serverConfigs[syncerConfig.xcodeServerRef],
                self.storageManager.projectConfigs[syncerConfig.projectRef],
                buildTemplates,
                triggers
            )
        }
        let nonNilTuples = latestTuples.filter { (tuple: OptionalTuple) -> Bool in
            tuple.1 != nil && tuple.2 != nil && tuple.3 != nil && tuple.4 != nil
        }
        let unwrapped = nonNilTuples.map { ($0.0, $0.1!, $0.2!, $0.3!, $0.4!) }

        let triplets = unwrapped.map {
            return ConfigTriplet(
                syncer: $0.0,
                server: $0.1,
                project: $0.2,
                buildTemplate: $0.3,
                triggers: $0.4)
        }
        self.configTriplets = triplets
        self.syncers = self.factory.createSyncers(configs: self.configTriplets)
    }
    private func setupHeartbeatManager() {
        if let heartbeatOptOut = self.storageManager.config["heartbeat_opt_out"] as? Bool, heartbeatOptOut {
            Log.info("User opted out of anonymous heartbeat")
        } else {
            Log.info("Will send anonymous heartbeat. To opt out add `\"heartbeat_opt_out\" = true` to ~/Library/Application Support/Buildasaur/Config.json")
            self.heartbeatManager = HeartbeatManager(server: "https://builda-ekg.herokuapp.com")
            self.heartbeatManager!.delegate = self
            self.heartbeatManager!.start()
        }
    }

    private func checkForAutostart() {
        guard let autostart = self.storageManager.config["autostart"] as? Bool, autostart else { return }
        self.syncers.forEach { $0.active = true }
    }

    public func xcodeServerWithRef(ref: RefType) -> XcodeServer? {
        guard let xcodeServerConfig = self.storageManager.serverConfigs.first(where: { $0.value.id == ref })?.value else { return nil }
        return self.factory.createXcodeServer(config: xcodeServerConfig)
    }

    public func projectWithRef(ref: RefType) -> Project? {
        guard let projectConfig = self.storageManager.projectConfigs.first(where: { $0.value.id == ref })?.value else { return nil }
        return self.factory.createProject(config: projectConfig)
    }

    public func syncerWithRef(ref: RefType) -> StandardSyncer? {
        guard let syncer = self.factory.createSyncers(configs: self.configTriplets).first(where: { $0.config.id == ref }) else { return nil }
        return syncer
    }

    deinit {
        self.stopSyncers()
    }

    public func startSyncers() {
        self.syncers.forEach { $0.active = true }
    }

    public func stopSyncers() {
        self.syncers.forEach { $0.active = false }
    }
}

extension SyncerManager: HeartbeatManagerDelegate {

    public func typesOfRunningSyncers() -> [String: Int] {
        return self.syncers.filter { $0.active }.reduce([:]) { (all, syncer) -> [String: Int] in
            var stats = all
            let syncerType = syncer._project.workspaceMetadata!.service.rawValue
            stats[syncerType] = (stats[syncerType] ?? 0) + 1
            return stats
        }
    }
}
