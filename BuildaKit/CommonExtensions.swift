//
//  CommonExtensions.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 17/02/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation

public func firstNonNil<T>(objects: [T?]) -> T? {
    for i in objects {
        if let i = i {
            return i
        }
    }
    return nil
}

extension Set {
    
    public func filterSet(includeElement: (Element) -> Bool) -> Set<Element> {
        return Set(self.filter(includeElement))
    }
}

extension Array {
    
    public func indexOfFirstObjectPassingTest(test: (Element) -> Bool) -> Array<Element>.Index? {
        
        for (idx, obj) in self.enumerated() {
            if test(obj) {
                return idx
            }
        }
        return nil
    }
    
    public func firstObjectPassingTest(test: (Element) -> Bool) -> Element? {
        for item in self {
            if test(item) {
                return item
            }
        }
        return nil
    }
}

extension Array {
    
    public func mapVoidAsync(transformAsync: @escaping (_ item: Element, _ itemCompletion: @escaping () -> ()) -> (), completion: @escaping () -> ()) {
        self.mapAsync(transformAsync: transformAsync as! ((Element, (Void) -> ()) -> ()), completion: { (_) -> () in
            completion()
        })
    }
    
    public func mapAsync<U>(transformAsync: (_ item: Element, _ itemCompletion: (U) -> ()) -> (), completion: @escaping ([U]) -> ()) {
        
        let group = DispatchGroup()
        var returnedValueMap = [Int: U]()
        
        for (index, element) in self.enumerated() {
            group.enter()
            transformAsync(element, {
                (returned: U) -> () in
                returnedValueMap[index] = returned
                group.leave()
            })
        }
        
        group.notify(queue: DispatchQueue.main) {
            
            //we have all the returned values in a map, put it back into an array of Us
            var returnedValues = [U]()
            for i in 0 ..< returnedValueMap.count {
                returnedValues.append(returnedValueMap[i]!)
            }
            completion(returnedValues)
        }
    }
}

extension Array {
    
    //dictionarify an array for fast lookup by a specific key
    public func toDictionary(key: (Element) -> String) -> [String: Element] {
        
        var dict = [String: Element]()
        for i in self {
            dict[key(i)] = i
        }
        return dict
    }
}

public enum NSDictionaryParseError: Error {
    case missingValueForKey(key: String)
    case wrongTypeOfValueForKey(key: String, value: AnyObject)
}

extension NSDictionary {
    
    public func get<T>(key: String) throws -> T {
        
        guard let value = self[key] else {
            throw NSDictionaryParseError.missingValueForKey(key: key)
        }
        
        guard let typedValue = value as? T else {
            throw NSDictionaryParseError.wrongTypeOfValueForKey(key: key, value: value as AnyObject)
        }
        return typedValue
    }
    
    public func getOptionally<T>(key: String) throws -> T? {
        
        guard let value = self[key] else {
            return nil
        }
        
        guard let typedValue = value as? T else {
            throw NSDictionaryParseError.wrongTypeOfValueForKey(key: key, value: value as AnyObject)
        }
        return typedValue
    }
}

extension Dictionary {
    
    public mutating func merge<S: Sequence> (other: S) where S.Iterator.Element == (Key,Value) {
        for (key, value) in other {
            self[key] = value
        }
    }
}

extension Array {
    
    public func dictionarifyWithKey(key: (_ item: Element) -> String) -> [String: Element] {
        var dict = [String: Element]()
        self.forEach { dict[key($0)] = $0 }
        return dict
    }
}

extension String {
    
    //returns nil if string is empty
    public func nonEmpty() -> String? {
        return self.isEmpty ? nil : self
    }
}

public func delayClosure(delay: Double, closure: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: closure)
}


