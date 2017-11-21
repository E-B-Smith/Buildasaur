//
//  BlueprintFileParser.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/21/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

class BlueprintFileParser: SourceControlFileParser {

    func supportedFileExtensions() -> [String] {
        return ["xcscmblueprint"]
    }

    func parseFileAtUrl(url: URL) throws -> WorkspaceMetadata {

        //JSON -> NSDictionary
        let data = try Data(contentsOf: url, options: NSData.ReadingOptions())
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? NSDictionary else { throw XcodeDeviceParserError.with("Failed to parse \(url)") }

        //parse our required keys
        let projectName = dictionary.optionalStringForKey("DVTSourceControlWorkspaceBlueprintNameKey")
        let projectPath = dictionary.optionalStringForKey("DVTSourceControlWorkspaceBlueprintRelativePathToProjectKey")
        let projectWCCIdentifier = dictionary.optionalStringForKey("DVTSourceControlWorkspaceBlueprintPrimaryRemoteRepositoryKey")

        var primaryRemoteRepositoryDictionary: NSDictionary?
        if let wccId = projectWCCIdentifier {
            if let wcConfigs = dictionary["DVTSourceControlWorkspaceBlueprintRemoteRepositoriesKey"] as? [NSDictionary] {
                primaryRemoteRepositoryDictionary = wcConfigs.filter({
                    if let loopWccId = $0.optionalStringForKey("DVTSourceControlWorkspaceBlueprintRemoteRepositoryIdentifierKey") {
                        return loopWccId == wccId
                    }
                    return false
                }).first
            }
        }

        let projectURLString = primaryRemoteRepositoryDictionary?.optionalStringForKey("DVTSourceControlWorkspaceBlueprintRemoteRepositoryURLKey")

        var projectWCCName: String?
        if
            let copyPaths = dictionary["DVTSourceControlWorkspaceBlueprintWorkingCopyPathsKey"] as? [String: String],
            let primaryRemoteRepoId = projectWCCIdentifier
        {
            projectWCCName = copyPaths[primaryRemoteRepoId]
        }

        return try WorkspaceMetadata(projectName: projectName, projectPath: projectPath, projectWCCIdentifier: projectWCCIdentifier, projectWCCName: projectWCCName, projectURLString: projectURLString)
    }
}
