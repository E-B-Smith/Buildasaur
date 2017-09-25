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
import ReactiveSwift

open class Project {
    
    public var url: URL {
        return URL(fileURLWithPath: self._config.url, isDirectory: true)
    }
    
    public let config: MutableProperty<ProjectConfig>
    
    private var _config: ProjectConfig {
        return self.config.value
    }
    
    public var urlString: String { return self.url.absoluteString }
    public var privateSSHKey: String? { return self.getContentsOfKeyAtPath(path: self._config.privateSSHKeyPath) }
    public var publicSSHKey: String? { return self.getContentsOfKeyAtPath(path: self._config.publicSSHKeyPath) }
    
    public var availabilityState: AvailabilityCheckState = .unchecked
    
    private(set) public var workspaceMetadata: WorkspaceMetadata?
    
    public init(config: ProjectConfig) throws {
        
        self.config = MutableProperty<ProjectConfig>(config)
        self.setupBindings()
        try self.refreshMetadata()
    }
    
    private init(original: Project, forkOriginURL: String) throws {
        
        self.config = MutableProperty<ProjectConfig>(original.config.value)
        self.workspaceMetadata = try original.workspaceMetadata?.duplicateWithForkURL(forkUrlString: forkOriginURL)
    }
    
    private func setupBindings() {
        
        self.config.producer.startWithValues { [weak self] _ in
            _ = try? self?.refreshMetadata()
        }
    }
    
    public func duplicateForForkAtOriginURL(forkURL: String) throws -> Project {
        return try Project(original: self, forkOriginURL: forkURL)
    }
    
    public class func attemptToParseFromUrl(url: URL) throws -> WorkspaceMetadata {
        return try Project.loadWorkspaceMetadata(url: url)
    }

    private func refreshMetadata() throws {
        let meta = try Project.attemptToParseFromUrl(url: self.url)
        self.workspaceMetadata = meta
    }
    
    public func schemes() -> [XcodeScheme] {
        
        let schemes = XcodeProjectParser.sharedSchemesFromProjectOrWorkspaceUrl(url: self.url)
        return schemes
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
        if let githubRange = stringUrl.range(of: serviceUrl, options: [], range: nil, locale: nil){
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

