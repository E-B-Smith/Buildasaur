//
//  BuildTemplate.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 09/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK

private let kKeyId = "id"
private let kKeyProjectName = "project_name"
private let kKeyName = "name"
private let kKeyScheme = "scheme"
private let kKeySchedule = "schedule"
private let kKeyCleaningPolicy = "cleaning_policy"
private let kKeyTriggers = "triggers"
private let kKeyTestingDevices = "testing_devices"
private let kKeyDeviceFilter = "device_filter"
private let kKeyPlatformType = "platform_type"
private let kKeyShouldAnalyze = "should_analyze"
private let kKeyShouldTest = "should_test"
private let kKeyShouldArchive = "should_archive"
private let kKeyManageCertsAndProfiles = "manage_certs_and_profiles"
private let kKeyAddMissingDevicesToTeams = "add_missing_devices_to_teams"

public struct BuildTemplate: JSONSerializable {

    public let id: RefType

    public var projectName: String?
    public var name: String
    public var scheme: String
    public var schedule: BotSchedule
    public var cleaningPolicy: BotConfiguration.CleaningPolicy
    public var triggers: [RefType]
    public var shouldAnalyze: Bool
    public var shouldTest: Bool
    public var shouldArchive: Bool
    public var addMissingDevicesToTeams: Bool
    public var manageCertsAndProfiles: Bool
    public var testingDeviceIds: [String]
    public var deviceFilter: DeviceFilter.FilterType
    public var platformType: DevicePlatform.PlatformType?

    func validate() -> Bool {

        if self.id.isEmpty { return false }
        //TODO: add all the other required values! this will be called on saving from the UI to make sure we have all the required fields.
        return true
    }

    public init(projectName: String? = nil) {
        self.id = Ref.new()
        self.projectName = projectName
        self.name = ""
        self.scheme = ""
        self.schedule = BotSchedule.manualBotSchedule()
        self.cleaningPolicy = BotConfiguration.CleaningPolicy.never
        self.triggers = []
        self.shouldAnalyze = true
        self.shouldTest = true
        self.shouldArchive = false
        self.manageCertsAndProfiles = false
        self.addMissingDevicesToTeams = false
        self.testingDeviceIds = []
        self.deviceFilter = .allAvailableDevicesAndSimulators
        self.platformType = nil
    }

    public init(json: [String: Any]) throws {
        self.id = json[kKeyId] as? RefType ?? Ref.new()
        self.projectName = json[kKeyProjectName] as? String
        self.name = json[kKeyName] as! String
        self.scheme = json[kKeyScheme] as! String
        if let scheduleDict = json[kKeySchedule]  as? NSDictionary {
            self.schedule = try BotSchedule(json: scheduleDict)
        } else {
            self.schedule = BotSchedule.manualBotSchedule()
        }
        if
            let cleaningPolicy = json[kKeyCleaningPolicy] as? Int,
            let policy = BotConfiguration.CleaningPolicy(rawValue: cleaningPolicy) {
                self.cleaningPolicy = policy
        } else {
            self.cleaningPolicy = BotConfiguration.CleaningPolicy.never
        }
        if let array = json[kKeyTriggers] as? [RefType] {
            self.triggers = array
        } else {
            self.triggers = []
        }

        self.shouldAnalyze = json[kKeyShouldAnalyze] as! Bool
        self.shouldTest = json[kKeyShouldTest] as! Bool
        self.shouldArchive = json[kKeyShouldArchive] as! Bool

        self.manageCertsAndProfiles = json[kKeyManageCertsAndProfiles] as? Bool ?? false
        self.addMissingDevicesToTeams = json[kKeyAddMissingDevicesToTeams] as? Bool ?? false

        self.testingDeviceIds = json[kKeyTestingDevices] as? [String] ?? []

        if
            let deviceFilterInt = json[kKeyDeviceFilter] as? Int,
            let deviceFilter = DeviceFilter.FilterType(rawValue: deviceFilterInt)
        {
            self.deviceFilter = deviceFilter
        } else {
            self.deviceFilter = .allAvailableDevicesAndSimulators
        }

        if
            let platformTypeString = json[kKeyPlatformType] as? String,
            let platformType = DevicePlatform.PlatformType(rawValue: platformTypeString) {
                self.platformType = platformType
        } else {
            self.platformType = nil
        }

        if !self.validate() {
            throw XcodeServerError.with("Invalid input into Build Template")
        }
    }

    public func jsonify() -> [String: Any] {
        var dict: [String: Any] = [:]

        dict[kKeyId] = self.id
        dict[kKeyTriggers] = self.triggers
        dict[kKeyDeviceFilter] = self.deviceFilter.rawValue
        dict[kKeyTestingDevices] = self.testingDeviceIds
        dict[kKeyCleaningPolicy] = self.cleaningPolicy.rawValue
        dict[kKeyName] = self.name
        dict[kKeyScheme] = self.scheme
        dict[kKeyShouldAnalyze] = self.shouldAnalyze
        dict[kKeyShouldTest] = self.shouldTest
        dict[kKeyShouldArchive] = self.shouldArchive
        dict[kKeyManageCertsAndProfiles] = self.manageCertsAndProfiles
        if self.manageCertsAndProfiles {
            dict[kKeyAddMissingDevicesToTeams] = self.addMissingDevicesToTeams
        }
        dict[kKeySchedule] = self.schedule.dictionarify()
        if let projectName = self.projectName {
            dict[kKeyProjectName] = projectName
        }
        if let platformType = self.platformType {
            dict[kKeyPlatformType] = platformType.rawValue
        }

        return dict
    }
}
