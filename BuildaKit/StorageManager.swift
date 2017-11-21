//
//  StorageManager.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 14/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK
import BuildaGitServer

public enum StorageManagerError: Error {
    case DuplicateServerConfig(XcodeServerConfig)
    case DuplicateProjectConfig(ProjectConfig)
}

public class StorageManager {

    public var syncerConfigs: [String: SyncerConfig] = [:] {
        didSet {
            self.saveSyncerConfigs(configs: self.syncerConfigs)
            self.onUpdateSyncerConfigs?()
        }
    }
    public var serverConfigs: [String: XcodeServerConfig] = [:] {
        didSet {
            self.saveServerConfigs(configs: self.serverConfigs)
            self.onUpdateServerConfigs?()
        }
    }
    public var projectConfigs: [String: ProjectConfig] = [:] {
        didSet {
            self.saveProjectConfigs(configs: self.projectConfigs)
            self.onUpdateProjectConfigs?()
        }
    }
    public var buildTemplates: [String: BuildTemplate] = [:] {
        didSet {
            self.saveBuildTemplates(templates: self.buildTemplates)
            self.onUpdateBuildTemplates?()
        }
    }
    public var triggerConfigs: [String: TriggerConfig] = [:] {
        didSet {
            self.saveTriggerConfigs(configs: self.triggerConfigs)
        }
    }
    public var config: [String: AnyObject] = [:] {
        didSet {
            self.saveConfig(config: self.config)
        }
    }

    public var onUpdateSyncerConfigs: (() -> Void)?
    public var onUpdateServerConfigs: (() -> Void)?
    public var onUpdateProjectConfigs: (() -> Void)?
    public var onUpdateBuildTemplates: (() -> Void)?

    let tokenKeychain = SecurePersistence.sourceServerTokenKeychain()
    let passphraseKeychain = SecurePersistence.sourceServerPassphraseKeychain()
    let serverConfigKeychain = SecurePersistence.xcodeServerPasswordKeychain()

    private let persistence: Persistence

    public init(persistence: Persistence) {

        self.persistence = persistence
        self.loadAllFromPersistence()
    }

    deinit {
        //
    }

    public func checkForProjectOrWorkspace(url: URL) throws {
        _ = try Project.attemptToParseFromUrl(url: url)
    }

    // MARK: adding

    public func addSyncerConfig(config: SyncerConfig) {
        self.syncerConfigs[config.id] = config
    }

    public func addTriggerConfig(triggerConfig: TriggerConfig) {
        self.triggerConfigs[triggerConfig.id] = triggerConfig
    }

    public func addBuildTemplate(buildTemplate: BuildTemplate) {
        self.buildTemplates[buildTemplate.id] = buildTemplate
    }

    public func addServerConfig(config: XcodeServerConfig) throws {

        //verify we don't have a duplicate
        let currentConfigs: [String: XcodeServerConfig] = self.serverConfigs
        let dup = currentConfigs.first(where: { $0.value.host == config.host && $0.value.user == config.user && $0.value.id != config.id })?.value
        if let duplicate = dup {
            throw StorageManagerError.DuplicateServerConfig(duplicate)
        }

        //no duplicate, save!
        self.serverConfigs[config.id] = config
    }

    public func addProjectConfig(config: ProjectConfig) throws {

        //verify we don't have a duplicate
        let currentConfigs: [String: ProjectConfig] = self.projectConfigs
        let dup = currentConfigs.first(where: { $0.value.url == config.url && $0.value.id != config.id })?.value
        if let duplicate = dup {
            throw StorageManagerError.DuplicateProjectConfig(duplicate)
        }

        //no duplicate, save!
        self.projectConfigs[config.id] = config
    }

    // MARK: removing

    public func removeTriggerConfig(triggerConfig: TriggerConfig) {
        self.triggerConfigs.removeValue(forKey: triggerConfig.id)
    }

    public func removeBuildTemplate(buildTemplate: BuildTemplate) {
        self.buildTemplates.removeValue(forKey: buildTemplate.id)
    }

    public func removeProjectConfig(projectConfig: ProjectConfig) {

        //TODO: make sure this project config is not owned by a project which
        //is running right now.
        self.projectConfigs.removeValue(forKey: projectConfig.id)
    }

    public func removeServer(serverConfig: XcodeServerConfig) {

        //TODO: make sure this server config is not owned by a server which
        //is running right now.
        self.serverConfigs.removeValue(forKey: serverConfig.id)
    }

    public func removeSyncer(syncerConfig: SyncerConfig) {

        //TODO: make sure this syncer config is not owned by a syncer which
        //is running right now.
        self.syncerConfigs.removeValue(forKey: syncerConfig.id)
    }

    // MARK: lookup

    public func triggerConfigsForIds(ids: [RefType]) -> [TriggerConfig] {
        let idsSet = Set(ids)
        return self.triggerConfigs.map { $0.1 }.filter { idsSet.contains($0.id) }
    }

    public func buildTemplatesForProjectName(projectName: String) -> [BuildTemplate] {
        //filter all build templates with the project name || with no project name (legacy reasons)
        return self.buildTemplates.values.filter { (template: BuildTemplate) -> Bool in
            if let templateProjectName = template.projectName {
                return projectName == templateProjectName
            } else {
                //if it doesn't yet have a project name associated, assume we have to show it
                return true
            }
        }
    }

    private func projectForRef(ref: RefType) -> ProjectConfig? {
        return self.projectConfigs[ref]
    }

    private func serverForHost(host: String) -> XcodeServer? {
        guard let config = self.serverConfigs[host] else { return nil }
        let server = XcodeServerFactory.server(config)
        return server
    }

    // MARK: loading

    private func loadAllFromPersistence() {

        self.config = self.persistence.loadDictionaryFromFile(name: "Config.json") ?? [:]

        let allProjects: [ProjectConfig] = self.persistence.loadArrayFromFile(name: "Projects.json") ?? []
        //load server token & ssh passphrase from keychain
        let tokenKeychain = self.tokenKeychain
        let passphraseKeychain = self.passphraseKeychain
        self.projectConfigs = allProjects
            .map { (_p: ProjectConfig) -> ProjectConfig in
                var p = _p
                var auth: ProjectAuthenticator?
                if let val = tokenKeychain.read(key: p.keychainKey()) {
                    auth = try? ProjectAuthenticator.fromString(value: val)
                }
                p.serverAuthentication = auth
                p.sshPassphrase = passphraseKeychain.read(key: p.keychainKey())
                return p
            }.dictionarifyWithKey { $0.id }

        let allServerConfigs: [XcodeServerConfig] = self.persistence.loadArrayFromFile(name: "ServerConfigs.json") ?? []
        //load xcs passwords from keychain
        let xcsConfigKeychain = self.serverConfigKeychain
        self.serverConfigs = allServerConfigs
            .map { (_x: XcodeServerConfig) -> XcodeServerConfig in
                var x = _x
                x.password = xcsConfigKeychain.read(key: x.keychainKey())
                return x
            }.dictionarifyWithKey { $0.id }

        let allTemplates: [BuildTemplate] = self.persistence.loadArrayFromFolder(folderName: "BuildTemplates") ?? []
        self.buildTemplates = allTemplates.dictionarifyWithKey { $0.id }
        let allTriggers: [TriggerConfig] = self.persistence.loadArrayFromFolder(folderName: "Triggers") ?? []
        self.triggerConfigs = allTriggers.dictionarifyWithKey { $0.id }
        let allSyncers: [SyncerConfig] = self.persistence.loadArrayFromFile(name: "Syncers.json") { self.createSyncerConfigFromJSON(json: $0) } ?? []
        self.syncerConfigs = allSyncers.dictionarifyWithKey { $0.id }
    }

    // MARK: Saving

    private func saveConfig(config: [String: AnyObject]) {
        self.persistence.saveDictionary(name: "Config.json", item: config as NSDictionary)
    }

    private func saveProjectConfigs(configs: [String: ProjectConfig]) {
        let projectConfigs: NSArray = Array(configs.values).map { $0.jsonify() } as NSArray
        let tokenKeychain = SecurePersistence.sourceServerTokenKeychain()
        let passphraseKeychain = SecurePersistence.sourceServerPassphraseKeychain()
        configs.values.forEach {
            if let auth = $0.serverAuthentication {
                tokenKeychain.writeIfNeeded(key: $0.keychainKey(), value: auth.toString())
            }
            passphraseKeychain.writeIfNeeded(key: $0.keychainKey(), value: $0.sshPassphrase)
        }
        self.persistence.saveArray(name: "Projects.json", items: projectConfigs)
    }

    private func saveServerConfigs(configs: [String: XcodeServerConfig]) {
        let serverConfigs = Array(configs.values).map { $0.jsonify() }
        let serverConfigKeychain = SecurePersistence.xcodeServerPasswordKeychain()
        configs.values.forEach {
            serverConfigKeychain.writeIfNeeded(key: $0.keychainKey(), value: $0.password)
        }
        self.persistence.saveArray(name: "ServerConfigs.json", items: serverConfigs as NSArray)
    }

    private func saveSyncerConfigs(configs: [String: SyncerConfig]) {
        let syncerConfigs = Array(configs.values).map { $0.jsonify() }
        self.persistence.saveArray(name: "Syncers.json", items: syncerConfigs as NSArray)
    }

    private func saveBuildTemplates(templates: [String: BuildTemplate]) {

        //but first we have to *delete* the directory first.
        //think of a nicer way to do this, but this at least will always
        //be consistent.
        let folderName = "BuildTemplates"
        self.persistence.deleteFolder(name: folderName)
        let items = Array(templates.values)
        self.persistence.saveArrayIntoFolder(folderName: folderName, items: items) { $0.id }
    }

    private func saveTriggerConfigs(configs: [String: TriggerConfig]) {

        //but first we have to *delete* the directory first.
        //think of a nicer way to do this, but this at least will always
        //be consistent.
        let folderName = "Triggers"
        self.persistence.deleteFolder(name: folderName)
        let items = Array(configs.values)
        self.persistence.saveArrayIntoFolder(folderName: folderName, items: items) { $0.id }
    }
}

extension StorageManager: SyncerLifetimeChangeObserver {

    public func authChanged(projectConfigId: String, auth: ProjectAuthenticator) {

        //and modify in the owner's config
        var config = self.projectConfigs[projectConfigId]!

        //auth info changed, re-save it into the keychain
        self.tokenKeychain.writeIfNeeded(key: config.keychainKey(), value: auth.toString())

        config.serverAuthentication = auth
        self.projectConfigs[projectConfigId] = config
    }
}

//Syncer Parsing
extension StorageManager {

    private func createSyncerConfigFromJSON(json: NSDictionary) -> SyncerConfig? {

        do {
            return try SyncerConfig(json: json as! [String: Any])
        } catch {
            Log.error(error)
        }
        return nil
    }
}
