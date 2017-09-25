//
//  Availability.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/6/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result
import BuildaUtils
import XcodeServerSDK

public class AvailabilityChecker {
    
    public static func xcodeServerAvailability() -> Action<XcodeServerConfig, AvailabilityCheckState, NoError> {
        return Action {
            (input: XcodeServerConfig) -> SignalProducer<AvailabilityCheckState, NoError> in
            
            return SignalProducer {
                sink, _ in
                
                sink.send(value: .checking)
                
                NetworkUtils.checkAvailabilityOfXcodeServerWithCurrentSettings(config: input, completion: { (success, error) -> () in
                    OperationQueue.main.addOperation {
                        if success {
                            sink.send(value: .succeeded)
                        } else {
                            sink.send(value: .failed(error))
                        }
                        sink.sendCompleted()
                    }
                })
            }
        }
    }
    
    public static func projectAvailability() -> Action<ProjectConfig, AvailabilityCheckState, NoError> {
        return Action {
            (input: ProjectConfig) -> SignalProducer<AvailabilityCheckState, NoError> in
            
            return SignalProducer { sink, _ in
                
                sink.send(value: .checking)
                
                var project: Project!
                do {
                    project = try Project(config: input)
                } catch {
                    sink.send(value: .failed(error))
                    return
                }
                
                NetworkUtils.checkAvailabilityOfServiceWithProject(project: project, completion: { (success, error) -> () in
                    
                    OperationQueue.main.addOperation {
                        
                        if success {
                            sink.send(value: .succeeded)
                        } else {
                            sink.send(value: .failed(error))
                        }
                        sink.sendCompleted()
                    }
                })
            }
        }
    }
}
