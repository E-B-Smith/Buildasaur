//
//  PersistenceMigrator.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/12/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK
import BuildaGitServer

public protocol MigratorType {
    init(persistence: Persistence)
    var persistence: Persistence { get set }
    func isMigrationRequired() -> Bool
    func attemptMigration() throws
}

extension MigratorType {

    func config() -> NSDictionary {
        let config = self.persistence.loadDictionaryFromFile(name: "Config.json") ?? [:]
        return config as NSDictionary
    }

    func persistenceVersion() -> Int? {
        let config = self.config()
        let version = config.optionalIntForKey(kPersistenceVersion)
        return version
    }
}

public class CompositeMigrator: MigratorType {

    public var persistence: Persistence {
        get {
            preconditionFailure("No persistence here")
        }
        set {
            for var i in self.childMigrators {
                i.persistence = newValue
            }
        }
    }

    internal let childMigrators: [MigratorType]
    public required init(persistence: Persistence) {
        self.childMigrators = [
            Migrator_v0_v1(persistence: persistence),
            Migrator_v1_v2(persistence: persistence),
            Migrator_v2_v3(persistence: persistence),
            Migrator_v3_v4(persistence: persistence)
        ]
    }

    public func isMigrationRequired() -> Bool {
        return !self.childMigrators.filter { $0.isMigrationRequired() }.isEmpty
    }

    public func attemptMigration() throws {

        //if we find a required migration, we need to also run all
        //the ones that come after it
        for (idx, mig) in self.childMigrators.enumerated() {
            if mig.isMigrationRequired() {
                let toRun = self.childMigrators.suffix(from: idx)
                print("Performing \(toRun.count) migrations")
                try toRun.forEach { try $0.attemptMigration() }
                break
            }
        }
    }
}

let kPersistenceVersion = "persistence_version"

/*
    - Config.json: persistence_version: null -> 1
*/
class Migrator_v0_v1: MigratorType {

    internal var persistence: Persistence
    required init(persistence: Persistence) {
        self.persistence = persistence
    }

    func isMigrationRequired() -> Bool {

        //we need to migrate if there's no persistence version, assume 1
        let version = self.persistenceVersion()
        return (version == nil)
    }

    func attemptMigration() throws {

        let pers = self.persistence
        //make sure the config file has a persistence version number
        let version = self.persistenceVersion()
        guard version == nil else {
            //all good
            return
        }

        let config = self.config()
        let mutableConfig = config.mutableCopy() as! NSMutableDictionary
        mutableConfig[kPersistenceVersion] = 1

        //save the updated config
        pers.saveDictionary(name: "Config.json", item: mutableConfig)

        //copy the rest
        pers.copyFileToWriteLocation(name: "Builda.log", isDirectory: false)
        pers.copyFileToWriteLocation(name: "Projects.json", isDirectory: false)
        pers.copyFileToWriteLocation(name: "ServerConfigs.json", isDirectory: false)
        pers.copyFileToWriteLocation(name: "Syncers.json", isDirectory: false)
        pers.copyFileToWriteLocation(name: "BuildTemplates", isDirectory: true)
    }
}

/*
    - ServerConfigs.json: each server now has an id
    - Config.json: persistence_version: 1 -> 2
*/
class Migrator_v1_v2: MigratorType {

    internal var persistence: Persistence
    required init(persistence: Persistence) {
        self.persistence = persistence
    }

    func isMigrationRequired() -> Bool {

        return self.persistenceVersion() == 1
    }

    func attemptMigration() throws {

        let serverRef = self.migrateServers()
        let (templateRef, projectRef) = self.migrateProjects()
        self.migrateSyncers(server: serverRef, project: projectRef, template: templateRef)
        self.migrateBuildTemplates()
        self.migrateConfigAndLog()
    }

    func fixPath(path: String) -> String {
        let oldUrl = NSURL(string: path)
        let newPath = oldUrl!.path!
        return newPath
    }

    func migrateBuildTemplates() {

        //first pull all triggers from all build templates and save them
        //as separate files, keeping the ids around.

        let templates = self.persistence.loadArrayOfDictionariesFromFolder(folderName: "BuildTemplates") ?? []
        guard !templates.isEmpty else { return }
        let mutableTemplates = templates.map { $0.mutableCopy() as! NSMutableDictionary }

        //go through templates and replace full triggers with just ids
        var triggers = [NSDictionary]()
        for template in mutableTemplates {

            guard let tempTriggers = template["triggers"] as? [NSDictionary] else { continue }
            let mutableTempTriggers = tempTriggers.map { $0.mutableCopy() as! NSMutableDictionary }

            //go through each trigger and each one an id
            let trigWithIds = mutableTempTriggers.map { trigger -> NSDictionary in
                trigger["id"] = Ref.new()
                return trigger.copy() as! NSDictionary
            }

            //add them to the big list of triggers that we'll save later
            triggers.append(contentsOf: trigWithIds)

            //now gather those ids
            let triggerIds = try! trigWithIds.map { try $0.stringForKey("id") }

            //and replace the "triggers" array in the build template with these ids
            template["triggers"] = triggerIds
        }

        //now save all triggers into their own folder
        self.persistence.saveArrayIntoFolder(folderName: "Triggers", items: triggers, itemFileName: {
            try! $0.stringForKey("id")
        }) {
            $0
        }

        //and save the build templates
        self.persistence.saveArrayIntoFolder(folderName: "BuildTemplates", items: mutableTemplates, itemFileName: {
            try! $0.stringForKey("id")
        }) {
            $0
        }
    }

    func migrateSyncers(server: RefType?, project: RefType?, template: RefType?) {

        let syncers = self.persistence.loadArrayOfDictionariesFromFile(name: "Syncers.json") ?? []
        let mutableSyncers = syncers.map { $0.mutableCopy() as! NSMutableDictionary }

        //give each an id
        let withIds = mutableSyncers.map { syncer -> NSMutableDictionary in
            syncer["id"] = Ref.new()
            return syncer
        }

        //remove server host and project path and add new ids
        let updated = withIds.map { syncer -> NSMutableDictionary in
            syncer.removeObject(forKey: "server_host")
            syncer.removeObject(forKey: "project_path")
            syncer.optionallyAddValueForKey(server as AnyObject, key: "server_ref")
            syncer.optionallyAddValueForKey(project as AnyObject, key: "project_ref")
            syncer.optionallyAddValueForKey(template as AnyObject, key: "preferred_template_ref")
            return syncer
        }

        self.persistence.saveArray(name: "Syncers.json", items: updated as NSArray)
    }

    func migrateProjects() -> (template: RefType?, project: RefType?) {

        let projects = self.persistence.loadArrayOfDictionariesFromFile(name: "Projects.json") ?? []
        let mutableProjects = projects.map { $0.mutableCopy() as! NSMutableDictionary }

        //give each an id
        let withIds = mutableProjects.map { project -> NSMutableDictionary in
            project["id"] = Ref.new()
            return project
        }

        //fix internal urls to be normal paths instead of the file:/// paths
        let withFixedUrls = withIds.map { project -> NSMutableDictionary in
            project["url"] = self.fixPath(path: try! project.stringForKey("url"))
            project["ssh_public_key_url"] = self.fixPath(path: try! project.stringForKey("ssh_public_key_url"))
            project["ssh_private_key_url"] = self.fixPath(path: try! project.stringForKey("ssh_private_key_url"))
            return project
        }

        //remove preferred_template_id, will be moved to syncer
        let removedTemplate = withFixedUrls.map { project -> (RefType?, NSMutableDictionary) in
            let template = project["preferred_template_id"] as? RefType
            project.removeObject(forKey: "preferred_template_id")
            return (template, project)
        }

        //get just the projects
        let finalProjects = removedTemplate.map { $0.1 }

        let firstTemplate: RefType?
        if let template = removedTemplate.map({ $0.0 }).first {
            firstTemplate = template
        } else {
            firstTemplate = nil
        }
        let firstProject = finalProjects.first?["id"] as? RefType

        //save
        self.persistence.saveArray(name: "Projects.json", items: finalProjects as NSArray)

        return (template: firstTemplate, project: firstProject)
    }

    func migrateServers() -> (RefType?) {

        let servers = self.persistence.loadArrayOfDictionariesFromFile(name: "ServerConfigs.json") ?? []
        let mutableServers = servers.map { $0.mutableCopy() as! NSMutableDictionary }

        //give each an id
        let withIds = mutableServers.map { server -> NSMutableDictionary in
            server["id"] = Ref.new()
            return server
        }

        //save
        self.persistence.saveArray(name: "ServerConfigs.json", items: withIds as NSArray)

        //return the first/only one (there should be 0 or 1)
        let firstId = withIds.first?["id"] as? RefType
        return firstId
    }

    func migrateConfigAndLog() {

        //copy log
        self.persistence.copyFileToWriteLocation(name: "Builda.log", isDirectory: false)

        let config = self.config()
        let mutableConfig = config.mutableCopy() as! NSMutableDictionary
        mutableConfig[kPersistenceVersion] = 2

        //save the updated config
        self.persistence.saveDictionary(name: "Config.json", item: mutableConfig)
    }
}

/*
- ServerConfigs.json: password moved to the keychain
- Projects.json: github_token -> oauth_tokens keychain, ssh_passphrase moved to keychain
- move any .log files to a separate folder called 'Logs'
- "token1234" -> "github:username:personaltoken:token1234"
*/
class Migrator_v2_v3: MigratorType {

    internal var persistence: Persistence
    required init(persistence: Persistence) {
        self.persistence = persistence
    }

    func isMigrationRequired() -> Bool {

        return self.persistenceVersion() == 2
    }

    func attemptMigration() throws {

        let pers = self.persistence

        //migrate
        self.migrateProjectAuthentication()
        self.migrateServerAuthentication()
        self.migrateLogs()

        //copy the rest
        pers.copyFileToWriteLocation(name: "Syncers.json", isDirectory: false)
        pers.copyFileToWriteLocation(name: "BuildTemplates", isDirectory: true)
        pers.copyFileToWriteLocation(name: "Triggers", isDirectory: true)

        let config = self.config()
        let mutableConfig = config.mutableCopy() as! NSMutableDictionary
        mutableConfig[kPersistenceVersion] = 3

        //save the updated config
        pers.saveDictionary(name: "Config.json", item: mutableConfig)
    }

    func migrateProjectAuthentication() {

        let pers = self.persistence
        let projects = pers.loadArrayOfDictionariesFromFile(name: "Projects.json") ?? []
        let mutableProjects = projects.map { $0.mutableCopy() as! NSMutableDictionary }

        let renamedAuth = mutableProjects.map { (d: NSMutableDictionary) -> NSDictionary in

            let id = try! d.stringForKey("id")
            let token = try! d.stringForKey("github_token")
            let auth = ProjectAuthenticator(service: .GitHub, username: "GIT", type: .PersonalToken, secret: token)
            let formattedToken = auth.toString()

            let passphrase = d.optionalStringForKey("ssh_passphrase")
            d.removeObject(forKey: "github_token")
            d.removeObject(forKey: "ssh_passphrase")

            let tokenKeychain = SecurePersistence.sourceServerTokenKeychain()
            tokenKeychain.writeIfNeeded(key: id, value: formattedToken)

            let passphraseKeychain = SecurePersistence.sourceServerPassphraseKeychain()
            passphraseKeychain.writeIfNeeded(key: id, value: passphrase)

            precondition(tokenKeychain.read(key: id) == formattedToken, "Saved token must match")
            precondition(passphraseKeychain.read(key: id) == passphrase, "Saved passphrase must match")

            return d
        }

        pers.saveArray(name: "Projects.json", items: renamedAuth as NSArray)
    }

    func migrateServerAuthentication() {

        let pers = self.persistence
        let servers = pers.loadArrayOfDictionariesFromFile(name: "ServerConfigs.json") ?? []
        let mutableServers = servers.map { $0.mutableCopy() as! NSMutableDictionary }

        let withoutPasswords = mutableServers.map { (d: NSMutableDictionary) -> NSDictionary in

            let password = try! d.stringForKey("password")
            let key = (try! XcodeServerConfig(json: d as! [String: Any])).keychainKey()

            let keychain = SecurePersistence.xcodeServerPasswordKeychain()
            keychain.writeIfNeeded(key: key, value: password)

            d.removeObject(forKey: "password")

            precondition(keychain.read(key: key) == password, "Saved password must match")

            return d
        }

        pers.saveArray(name: "ServerConfigs.json", items: withoutPasswords as NSArray)
    }

    func migrateLogs() {

        let pers = self.persistence
        (pers.filesInFolder(folderUrl: pers.folderForIntention(intention: .Reading)) ?? [])
            .map { $0.lastPathComponent }
            .filter { $0.hasSuffix("log") }
            .forEach {
                pers.copyFileToFolder(fileName: $0, folder: "Logs")
                pers.deleteFile(name: $0)
        }
    }
}

/*
 - Syncers.json: watched branched moved to dictionary [String: Bool] instead of list of currently watching branches
                 add automatically watching new branches option
 */
class Migrator_v3_v4: MigratorType {
    internal var persistence: Persistence
    required init(persistence: Persistence) {
        self.persistence = persistence
    }

    func isMigrationRequired() -> Bool {

        return self.persistenceVersion() == 3
    }

    func attemptMigration() throws {
        self.migrateSyncers()

        let config = self.config()
        let mutableConfig = config.mutableCopy() as! NSMutableDictionary
        mutableConfig[kPersistenceVersion] = 4

        //save the updated config
        self.persistence.saveDictionary(name: "Config.json", item: mutableConfig)

        //copy the rest
        self.persistence.copyFileToWriteLocation(name: "Projects.json", isDirectory: false)
        self.persistence.copyFileToWriteLocation(name: "ServerConfigs.json", isDirectory: false)
        self.persistence.copyFileToWriteLocation(name: "BuildTemplates", isDirectory: true)
        self.persistence.copyFileToWriteLocation(name: "Logs", isDirectory: true)
        self.persistence.copyFileToWriteLocation(name: "Triggers", isDirectory: true)
    }

    func migrateSyncers() {
        let syncers = self.persistence.loadArrayOfDictionariesFromFile(name: "Syncers.json") ?? []
        let mutableSyncers = syncers.map { $0.mutableCopy() as! NSMutableDictionary }

        for syncer in mutableSyncers {
            syncer.optionallyAddValueForKey((syncer["watched_branches"] as? [String] ?? []).reduce(NSMutableDictionary()) { (result, branch) -> NSMutableDictionary in
                result[branch] = true
                return result
            }, key: "watching_branches")
            syncer.optionallyAddValueForKey(false as AnyObject, key: "automatically_watch_new_branches")
            syncer.removeObject(forKey: "watched_branches")
        }

        self.persistence.saveArray(name: "Syncers.json", items: mutableSyncers as NSArray)
    }
}
