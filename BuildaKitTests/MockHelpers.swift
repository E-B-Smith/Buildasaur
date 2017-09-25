//
//  MockHelpers.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 17/05/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation

class MockHelpers {
    
    class func loadSampleIntegration() -> NSMutableDictionary {
        
        let bundle = Bundle(for: MockHelpers.self)
        if let url = bundle.url(forResource: "sampleFinishedIntegration", withExtension: "json") {
            let data = try! Data(contentsOf: url)
            if let obj = try! JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? NSMutableDictionary {
                return obj
            }
        } else {
            assertionFailure("no sample integration json")
        }
        return NSMutableDictionary()
    }
    
}
