//
//  XcodeProjectParser.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 24/01/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

public class XcodeProjectParser {
    
    static private var sourceControlFileParsers: [SourceControlFileParser] = [
        CheckoutFileParser(),
        BlueprintFileParser(),
    ]
    
    private class func firstItemMatchingTestRecursive(url: URL, test: (_ itemUrl: URL) -> Bool) throws -> URL? {
        
        let fm = FileManager.default
        let path = url.path
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        if !exists {
            return nil
        }
        
        if isDir.boolValue == false {
            //not dir, test
            return test(url) ? url : nil
        }
        
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
        for i in contents {
            if let foundUrl = try self.firstItemMatchingTestRecursive(url: i, test: test) {
                return foundUrl
            }
        }
        return nil
    }
    
    private class func firstItemMatchingTest(url: URL, test: (_ itemUrl: URL) -> Bool) throws -> URL? {
        
        return try self.allItemsMatchingTest(url: url, test: test).first
    }

    private class func allItemsMatchingTest(url: URL, test: (_ itemUrl: URL) -> Bool) throws -> [URL] {
        
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
        
        let filtered = contents.filter(test)
        return filtered
    }
    
    private class func findCheckoutOrBlueprintUrl(projectOrWorkspaceUrl: URL) throws -> URL {
        
        if let found = try self.firstItemMatchingTestRecursive(url: projectOrWorkspaceUrl, test: { (itemUrl: URL) -> Bool in
            
            let pathExtension = itemUrl.pathExtension
            return pathExtension == "xccheckout" || pathExtension == "xcscmblueprint"
        }) {
            return found
        }
        throw XcodeDeviceParserError.with("No xccheckout or xcscmblueprint file found")
    }
    
    private class func parseCheckoutOrBlueprintFile(url: URL) throws -> WorkspaceMetadata {
        
        let pathExtension = url.pathExtension
        
        let maybeParser = self.sourceControlFileParsers.filter {
            Set($0.supportedFileExtensions()).contains(pathExtension)
        }.first
        guard let parser = maybeParser else {
            throw XcodeDeviceParserError.with("Could not find a parser for path extension \(pathExtension)")
        }
        
        let parsedWorkspace = try parser.parseFileAtUrl(url: url)
        return parsedWorkspace
    }
    
    public class func parseRepoMetadataFromProjectOrWorkspaceURL(url: URL) throws -> WorkspaceMetadata {
        
        do {
            let checkoutUrl = try self.findCheckoutOrBlueprintUrl(projectOrWorkspaceUrl: url)
            let parsed = try self.parseCheckoutOrBlueprintFile(url: checkoutUrl)
            return parsed
        } catch {
            
            //failed to find a checkout/blueprint file, attempt to parse from repo manually
            let parser = GitRepoMetadataParser()
            
            do {
                return try parser.parseFileAtUrl(url: url)
            } catch {
                //no we're definitely unable to parse workspace metadata
                throw XcodeDeviceParserError.with("Cannot find the Checkout/Blueprint file and failed to parse repository metadata directly. Please create an issue on GitHub with anonymized information about your repository. (Error \((error as NSError).localizedDescription))")
            }
        }
    }
    
    public class func sharedSchemesFromProjectOrWorkspaceUrl(url: URL) -> [XcodeScheme] {
        
        var projectUrls: [URL]
        if self.isWorkspaceUrl(url: url) {
            //first parse project urls from workspace contents
            projectUrls = self.projectUrlsFromWorkspace(url: url) ?? [URL]()
            
            //also add the workspace's url, it might own some schemes as well
            projectUrls.append(url)
            
        } else {
            //this already is a project url, take just that
            projectUrls = [url]
        }
        
        //we have the project urls, now let's parse schemes from each of them
        let schemes = projectUrls.map {
            return self.sharedSchemeUrlsFromProjectUrl(url: $0)
        }.reduce([XcodeScheme](), { (arr, newSchemes) -> [XcodeScheme] in
            return arr + newSchemes
        })
        
        return schemes
    }
    
    private class func sharedSchemeUrlsFromProjectUrl(url: URL) -> [XcodeScheme] {
        
        //the structure is
        //in a project file, if there are any shared schemes, they will be in
        //xcshareddata/xcschemes/*
        do {
            if let sharedDataFolder = try self.firstItemMatchingTest(url: url,
                test: { (itemUrl: URL) -> Bool in
                    
                    return itemUrl.lastPathComponent == "xcshareddata"
            }) {
                
                if let schemesFolder = try self.firstItemMatchingTest(url: sharedDataFolder,
                    test: { (itemUrl: URL) -> Bool in
                        
                        return itemUrl.lastPathComponent == "xcschemes"
                }) {
                    //we have the right folder, yay! just filter all files ending with xcscheme
                    let schemeUrls = try self.allItemsMatchingTest(url: schemesFolder, test: { (itemUrl: URL) -> Bool in
                        let ext = itemUrl.pathExtension
                        return ext == "xcscheme"
                    })
                    let schemes = schemeUrls.map { XcodeScheme(path: $0 as NSURL, ownerProjectOrWorkspace: url as NSURL) }
                    return schemes
                }
            }
        } catch {
            Log.error(error)
        }
        return []
    }
    
    private class func isProjectUrl(url: URL) -> Bool {
        return url.pathExtension == "xcodeproj"
    }

    private class func isWorkspaceUrl(url: URL) -> Bool {
        return url.pathExtension == "xcworkspace"
    }

    private class func projectUrlsFromWorkspace(url: URL) -> [URL]? {
        
        assert(self.isWorkspaceUrl(url: url), "Url \(url) is not a workspace url")
        
        do {
            let urls = try XcodeProjectXMLParser.parseProjectsInsideOfWorkspace(url: url)
            return urls
        } catch {
            Log.error("Couldn't load workspace at path \(url) with error \(error)")
            return nil
        }
    }
    
    private class func parseSharedSchemesFromProjectURL(url: URL) -> (schemeUrls: [URL]?, error: Error?) {
        
        return (schemeUrls: [URL](), error: nil)
    }
    
}

