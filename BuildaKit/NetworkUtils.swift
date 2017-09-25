//
//  NetworkUtils.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 07/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaGitServer
import BuildaUtils
import XcodeServerSDK

public class NetworkError: Error {
    static func with(_ info: String) -> Error {
        return NSError(domain: "GithubServer", code: -1, userInfo: ["info": info])
    }
}

public class NetworkUtils {
    
    public typealias VerificationCompletion = (_ success: Bool, _ error: Error?) -> ()
    
    public class func checkAvailabilityOfServiceWithProject(project: Project, completion: @escaping VerificationCompletion) {
        
        self.checkService(project: project, completion: { success, error in
            
            if !success {
                completion(false, error)
                return
            }
            
            //now test ssh keys
            let credentialValidationBlueprint = project.createSourceControlBlueprintForCredentialVerification()
            self.checkValidityOfSSHKeys(blueprint: credentialValidationBlueprint, completion: { (success, error) -> () in
                
                if success {
                    Log.verbose("Finished blueprint validation with success!")
                } else {
                    Log.verbose("Finished blueprint validation with error: \(String(describing: error))")
                }
                
                //now complete
                completion(success, error)
            })
        })
    }
    
    private class func checkService(project: Project, completion: @escaping VerificationCompletion) {
        
        let auth = project.config.value.serverAuthentication
        let service = auth!.service
        let server = SourceServerFactory().createServer(service: service, auth: auth)
        
        //check if we can get the repo and verify permissions
        guard let repoName = project.serviceRepoName() else {
            completion(false, NetworkError.with("Invalid repo name"))
            return
        }
        
        //we have a repo name
        server.getRepo(repo: repoName, completion: { (repo, error) -> () in
            
            if error != nil {
                completion(false, error)
                return
            }
            
            if let repo = repo {
                
                let permissions = repo.permissions
                let readPermission = permissions.read
                let writePermission = permissions.write
                
                //look at the permissions in the PR metadata
                if !readPermission {
                    completion(false, NetworkError.with("Missing read permission for repo"))
                } else if !writePermission {
                    completion(false, NetworkError.with("Missing write permission for repo"))
                } else {
                    //now complete
                    completion(true, nil)
                }
            } else {
                completion(false, NetworkError.with("Couldn't find repo permissions in \(service.prettyName()) response"))
            }
        })
    }
    
    public class func checkAvailabilityOfXcodeServerWithCurrentSettings(config: XcodeServerConfig, completion: @escaping (_ success: Bool, _ error: Error?) -> ()) {
        
        let xcodeServer = XcodeServerFactory.server(config)
        
        //the way we check availability is first by logging out (does nothing if not logged in) and then
        //calling getUserCanCreateBots, which, if necessary, authenticates before resolving to true or false in JSON.
        xcodeServer.logout { (success, error) -> () in
            
            if let error = error {
                completion(false, error)
                return
            }
            
            xcodeServer.getUserCanCreateBots({ (canCreateBots, error) -> () in
                
                if let error = error {
                    completion(false, error)
                    return
                }
                
                completion(canCreateBots, nil)
            })
        }
    }
    
    class func checkValidityOfSSHKeys(blueprint: SourceControlBlueprint, completion: (_ success: Bool, _ error: Error?) -> ()) {
        
        let blueprintDict = blueprint.dictionarify()
        let r = SSHKeyVerification.verifyBlueprint(blueprint: blueprintDict)
        
        //based on the return value, either succeed or fail
        if r.terminationStatus == 0 {
            completion(true, nil)
        } else {
            completion(false, NetworkError.with(r.standardError))
        }
    }
}
