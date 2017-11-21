//
//  TriggerConfig.swift
//  BuildaKit
//
//  Created by Sylvain Fay-Chatelard on 20/11/2017.
//  Copyright © 2017 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils
import XcodeServerSDK

//HACK: move to XcodeServerSDK
extension TriggerConfig: JSONReadable, JSONWritable {
    public init(json: [String: Any]) throws {
        let phase = Phase(rawValue: json["phase"] as! Int)!
        self.phase = phase
        if let conditionsJSON = json["conditions"] as? NSDictionary, phase == .postbuild {
            //also parse conditions
            self.conditions = try TriggerConditions(json: conditionsJSON)
        } else {
            self.conditions = nil
        }

        let kind = Kind(rawValue: json["type"] as! Int)!
        self.kind = kind
        if let configurationJSON = json["emailConfiguration"] as? NSDictionary, kind == .emailNotification {
            //also parse email config
            self.emailConfiguration = try EmailConfiguration(json: configurationJSON)
        } else {
            self.emailConfiguration = nil
        }

        self.name = json["name"] as! String
        self.scriptBody = json["scriptBody"] as! String

        self.id = json["id"] as? RefType ?? Ref.new()
    }

    public func jsonify() -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["id"] = self.id
        dict["phase"] = self.phase.rawValue
        dict["type"] = self.kind.rawValue
        dict["scriptBody"] = self.scriptBody
        dict["name"] = self.name
        if let conditions = self.conditions {
            dict["conditions"] = conditions.dictionarify()
        }
        if let emailConfiguration = self.emailConfiguration {
            dict["emailConfiguration"] = emailConfiguration.dictionarify()
        }
        return dict
    }
}
