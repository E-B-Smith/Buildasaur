//
//  XcodeDeviceParser.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 30/06/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaUtils

public class XcodeDeviceParserError: Error {
    static func with(_ info: String) -> Error {
        return NSError(domain: "GithubServer", code: -1, userInfo: ["info": info])
    }
}

public class XcodeDeviceParser {
    
    public enum DeviceType: String {
        case iPhoneOS = "iphoneos"
        case macOSX = "macosx"
        case watchOS = "watchos"
        case tvOS = "appletvos"
        
        public func toPlatformType() -> DevicePlatform.PlatformType {
            switch self {
            case .iPhoneOS:
                return .iOS
            case .macOSX:
                return .OSX
            case .watchOS:
                return .watchOS
            case .tvOS:
                return .tvOS
            }
        }
    }
    
    public class func parseDeviceTypeFromProjectUrlAndScheme(projectUrl: URL, scheme: XcodeScheme) throws -> DeviceType {
        
        let typeString = try self.parseTargetTypeFromSchemeAndProjectAtUrl(scheme: scheme, projectFolderUrl: projectUrl)
        guard let deviceType = DeviceType(rawValue: typeString) else {
            throw XcodeDeviceParserError.with("Unrecognized type: \(typeString)")
        }
        return deviceType
    }
    
    private class func parseTargetTypeFromSchemeAndProjectAtUrl(scheme: XcodeScheme, projectFolderUrl: URL) throws -> String {
        
        let ownerArgs = try { () throws -> String in
            
            let ownerUrl = scheme.ownerProjectOrWorkspace.path!
            switch (scheme.ownerProjectOrWorkspace.lastPathComponent! as NSString).pathExtension {
                case "xcworkspace":
                return "-workspace \"\(ownerUrl)\""
                case "xcodeproj":
                return "-project \"\(ownerUrl)\""
            default: throw XcodeDeviceParserError.with("Unrecognized project/workspace path \(ownerUrl)")
            }
            }()
        
        let folder = projectFolderUrl.deletingLastPathComponent().path
        let schemeName = scheme.name
        
        let script = "cd \"\(folder)\"; xcodebuild \(ownerArgs) -scheme \"\(schemeName)\" -showBuildSettings 2>/dev/null | egrep '^\\s*PLATFORM_NAME' | cut -d = -f 2 | uniq | xargs echo"
        let res = Script.runTemporaryScript(script)
        if res.terminationStatus == 0 {
            let deviceType = res.standardOutput.stripTrailingNewline()
            return deviceType
        }
        throw XcodeDeviceParserError.with("Termination status: \(res.terminationStatus), output: \(res.standardOutput), error: \(res.standardError)")
    }
}
