//
//  Availability.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/6/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK

public class AvailabilityChecker {
    public static func xcodeServerAvailability(config: XcodeServerConfig, onUpdate: @escaping (_ state: AvailabilityCheckState) -> Void) {
        onUpdate(.checking)

        NetworkUtils.checkAvailabilityOfXcodeServerWithCurrentSettings(config: config) { (success, error) -> Void in
            OperationQueue.main.addOperation {
                if success {
                    onUpdate(.succeeded)
                } else {
                    onUpdate(.failed(error))
                }
            }
        }
    }

    public static func projectAvailability(config: ProjectConfig, onUpdate: @escaping (_ state: AvailabilityCheckState) -> Void) {
        onUpdate(.checking)

        var project: Project!
        do {
            project = try Project(config: config)
        } catch {
            onUpdate(.failed(error))
            return
        }

        NetworkUtils.checkAvailabilityOfServiceWithProject(project: project) { (success, error) -> Void in
            OperationQueue.main.addOperation {
                if success {
                    onUpdate(.succeeded)
                } else {
                    onUpdate(.failed(error))
                }
            }
        }
    }
}
