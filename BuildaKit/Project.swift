//
//  Project.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 14/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK

open class Project {
    public var url: URL {
        return URL(fileURLWithPath: self.config.url, isDirectory: true)
    }

    public var config: ProjectConfig {
        didSet {
            try? self.refreshMetadata()
        }
    }

    public var urlString: String { return self.url.absoluteString }
    public var privateSSHKey: String? { return self.getContentsOfKeyAtPath(path: self.config.privateSSHKeyPath) }
    public var publicSSHKey: String? { return self.getContentsOfKeyAtPath(path: self.config.publicSSHKeyPath) }

    public var availabilityState: AvailabilityCheckState = .unchecked

    private(set) public var workspaceMetadata: WorkspaceMetadata?

    public init(config: ProjectConfig) throws {
        self.config = config
        try? self.refreshMetadata()
    }

    private init(original: Project, forkOriginURL: String) throws {
        self.config = original.config
        self.workspaceMetadata = try original.workspaceMetadata?.duplicateWithForkURL(forkUrlString: forkOriginURL)
    }

    public func duplicateForForkAtOriginURL(forkURL: String) throws -> Project {
        return try Project(original: self, forkOriginURL: forkURL)
    }

    public class func attemptToParseFromUrl(url: URL) throws -> WorkspaceMetadata {
        return try Project.loadWorkspaceMetadata(url: url)
    }

    private func refreshMetadata() throws {
        self.workspaceMetadata = try Project.attemptToParseFromUrl(url: self.url)
    }

    public func schemes() -> [XcodeScheme] {
        return XcodeProjectParser.sharedSchemesFromProjectOrWorkspaceUrl(url: self.url)
    }

    private class func loadWorkspaceMetadata(url: URL) throws -> WorkspaceMetadata {
        return try XcodeProjectParser.parseRepoMetadataFromProjectOrWorkspaceURL(url: url)
    }

    public func serviceRepoName() -> String? {
        guard let meta = self.workspaceMetadata else { return nil }

        let projectUrl = meta.projectURL
        let service = meta.service

        let originalStringUrl = projectUrl.absoluteString
        let stringUrl = originalStringUrl!.lowercased()

        /*
        both https and ssh repos on github have a form of:
        {https://|git@}SERVICE_URL{:|/}organization/repo.git
        here I need the organization/repo bit, which I'll do by finding "SERVICE_URL" and shifting right by one
        and scan up until ".git"
        */

        let serviceUrl = service.hostname().lowercased()
        let dotGitRange = stringUrl.range(of: ".git", options: NSString.CompareOptions.backwards, range: nil, locale: nil) ?? stringUrl.endIndex..<stringUrl.endIndex
        if let githubRange = stringUrl.range(of: serviceUrl, options: [], range: nil, locale: nil) {
            let start = stringUrl.index(githubRange.upperBound, offsetBy: 1)
            let end = dotGitRange.lowerBound

            let repoName = originalStringUrl![start ..< end]
                return String(repoName)
        }
        return nil
    }

    private func getContentsOfKeyAtPath(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        do {
            let key = try NSString(contentsOf: url, encoding: String.Encoding.ascii.rawValue)
            return key as String
        } catch {
            Log.error("Couldn't load key at url \(url) with error \(error)")
        }
        return nil
    }

}
