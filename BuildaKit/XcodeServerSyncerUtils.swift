//
//  XcodeServerSyncerUtils.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 15/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaGitServer
import BuildaUtils

public class XcodeServerSyncerUtils {

    public class func createBotFromBuildTemplate(botName: String, syncer: StandardSyncer, template: BuildTemplate, project: Project, branch: String, scheduleOverride: BotSchedule?, xcodeServer: XcodeServer, completion: @escaping (_ bot: Bot?, _ error: Error?) -> Void) {

        //pull info from template
        let schemeName = template.scheme

        //optionally override the schedule, if nil, takes it from the template
        let schedule = scheduleOverride ?? template.schedule
        let cleaningPolicy = template.cleaningPolicy
        let triggers = syncer.triggers
        let analyze = template.shouldAnalyze
        let test = template.shouldTest
        let archive = template.shouldArchive

        //TODO: create a device spec from testing devices and filter type (and scheme target type?)
        let testingDeviceIds = template.testingDeviceIds
        let filterType = template.deviceFilter
        let platformType = template.platformType ?? .iOS //default to iOS for no reason
        let architectureType = DeviceFilter.ArchitectureType.architectureFromPlatformType(platformType)

        let devicePlatform = DevicePlatform(type: platformType)
        let deviceFilter = DeviceFilter(platform: devicePlatform, filterType: filterType, architectureType: architectureType)

        let deviceSpecification = DeviceSpecification(filters: [deviceFilter], deviceIdentifiers: testingDeviceIds)

        let blueprint = project.createSourceControlBlueprint(branch: branch)

        //create bot config
        let botConfiguration = BotConfiguration(
            builtFromClean: cleaningPolicy,
            analyze: analyze,
            test: test,
            archive: archive,
            schemeName: schemeName,
            schedule: schedule,
            triggers: triggers,
            deviceSpecification: deviceSpecification,
            sourceControlBlueprint: blueprint)

        //create the bot finally
        let newBot = Bot(name: botName, configuration: botConfiguration)

        xcodeServer.createBot(newBot, completion: { (response) -> Void in

            var outBot: Bot?
            var outError: Error?
            switch response {
            case .success(let bot):
                //we good
                Log.info("Successfully created bot \(bot.name)")
                outBot = bot
            case .error(let error):
                outError = error
            default:
                outError = XcodeServerError.with("Failed to return bot after creation even after error was nil!")
            }

            //print success/failure etc
            if let error = outError {
                Log.error("Failed to create bot with name \(botName) and json \(newBot.dictionarify()), error \(error)")
            }

            OperationQueue.main.addOperation {
                completion(outBot, outError)
            }
        })
    }

}
