//
//  Persistence.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 07/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

public class PersistenceFactory {
    
    public class func migrationPersistenceWithReadingFolder(read: URL) -> Persistence {
        
        let name = read.lastPathComponent
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        let tmp = URL(fileURLWithPath: path, isDirectory: true)
        let fileManager = FileManager.default
        return Persistence(readingFolder: read, writingFolder: tmp, fileManager: fileManager)
    }
    
    public class func createStandardPersistence() -> Persistence {
        
        let folderName = "Buildasaur"
//        let folderName = "Buildasaur-Debug"

        let fileManager = FileManager.default
        guard let applicationSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first else {
                preconditionFailure("Couldn't access Builda's persistence folder, aborting")
        }
        let buildaRoot = applicationSupport
            .appendingPathComponent(folderName, isDirectory: true)
        
        let persistence = Persistence(readingFolder: buildaRoot, writingFolder: buildaRoot, fileManager: fileManager)
        return persistence
    }
}

public class Persistence {
    
    public let readingFolder: URL
    public let writingFolder: URL
    public let fileManager: FileManager
    
    public init(readingFolder: URL, writingFolder: URL, fileManager: FileManager) {
        
        self.readingFolder = readingFolder
        self.writingFolder = writingFolder
        self.fileManager = fileManager
        self.ensureFoldersExist()
    }
    
    private func ensureFoldersExist() {
        
        self.createFolderIfNotExists(url: self.readingFolder)
        self.createFolderIfNotExists(url: self.writingFolder)
    }
    
    public func deleteFile(name: String) {
        let itemUrl = self.fileURLWithName(name: name, intention: .Writing, isDirectory: false)
        self.delete(url: itemUrl)
    }
    
    public func deleteFolder(name: String) {
        let itemUrl = self.fileURLWithName(name: name, intention: .Writing, isDirectory: true)
        self.delete(url: itemUrl)
    }
    
    private func delete(url: URL) {
        do {
            try self.fileManager.removeItem(at: url)
        } catch {
            Log.error(error)
        }
    }
    
    func saveData(name: String, item: AnyObject) {
        
        let itemUrl = self.fileURLWithName(name: name, intention: .Writing, isDirectory: false)
        let json = item
        do {
            try self.saveJSONToUrl(json: json, url: itemUrl)
        } catch {
            assert(false, "Failed to save \(name), \(error)")
        }
    }
    
    func saveDictionary(name: String, item: NSDictionary) {
        self.saveData(name: name, item: item)
    }
    
    //crashes when I use [JSONWritable] instead of NSArray :(
    func saveArray(name: String, items: NSArray) {
        self.saveData(name: name, item: items)
    }
    
    func saveArrayIntoFolder<T>(folderName: String, items: [T], itemFileName: (_ item: T) -> String, serialize: (_ item: T) -> NSDictionary) {
        
        let folderUrl = self.fileURLWithName(name: folderName, intention: .Writing, isDirectory: true)
        items.forEach { (item: T) -> () in
            
            let json = serialize(item)
            let name = itemFileName(item)
            let url = folderUrl.appendingPathComponent("\(name).json")
            do {
                try self.saveJSONToUrl(json: json, url: url)
            } catch {
                assert(false, "Failed to save a \(folderName), \(error)")
            }
        }
    }
    
    func saveArrayIntoFolder<T: JSONWritable>(folderName: String, items: [T], itemFileName: (_ item: T) -> String) {
        
        self.saveArrayIntoFolder(folderName: folderName, items: items, itemFileName: itemFileName) {
            $0.jsonify() as NSDictionary
        }
    }
    
    func loadDictionaryFromFile<T>(name: String) -> T? {
        return self.loadDataFromFile(name: name, process: { (json) -> T? in
            
            guard let contents = json as? T else { return nil }
            return contents
        })
    }
    
    func loadArrayFromFile<T: JSONReadable>(name: String) -> [T]? {
        
        return self.loadArrayFromFile(name: name) { try T(json: $0 as! [String : Any]) }
    }
    
    func loadArrayFromFile<T>(name: String, convert: (_ json: NSDictionary) throws -> T?) -> [T]? {
        
        return self.loadDataFromFile(name: name, process: { (json) -> [T]? in
            
            guard let json = json as? [NSDictionary] else { return nil }
            
            let allItems = json.map { (item) -> T? in
                do { return try convert(item) } catch { return nil }
            }
            let parsedItems = allItems.filter { $0 != nil }.map { $0! }
            if parsedItems.count != allItems.count {
                Log.error("Some \(name) failed to parse, will be ignored.")
                //maybe show a popup?
            }
            return parsedItems
        })
    }
    
    func loadArrayOfDictionariesFromFile(name: String) -> [NSDictionary]? {
        return self.loadArrayFromFile(name: name, convert: { $0 })
    }
    
    func loadArrayOfDictionariesFromFolder(folderName: String) -> [NSDictionary]? {
        return self.loadArrayFromFolder(folderName: folderName) { $0 }
    }
    
    func loadArrayFromFolder<T: JSONReadable>(folderName: String) -> [T]? {
        return self.loadArrayFromFolder(folderName: folderName) {
            try T(json: $0 as! [String : Any])
        }
    }
    
    func loadArrayFromFolder<T>(folderName: String, parse: @escaping (NSDictionary) throws -> T) -> [T]? {
        let folderUrl = self.fileURLWithName(name: folderName, intention: .Reading, isDirectory: true)
        return self.filesInFolder(folderUrl: folderUrl)?.map { (url: URL) -> T? in
            
            do {
                let json = try self.loadJSONFromUrl(url: url)
                if let json = json as? NSDictionary {
                    let template = try parse(json)
                    return template
                }
            } catch {
                Log.error("Couldn't parse \(folderName) at url \(url), error \(error)")
            }
            return nil
            }.filter { $0 != nil }.map { $0! }
    }
    
    func loadDataFromFile<T>(name: String, process: (_ json: Any?) -> T?) -> T? {
        let url = self.fileURLWithName(name: name, intention: .Reading, isDirectory: false)
        do {
            let json = try self.loadJSONFromUrl(url: url)
            guard let contents = process(json) else { return nil }
            return contents
        } catch {
            //file not found
            if (error as NSError).code != 260 {
                Log.error("Failed to read \(name), error \(error). Will be ignored. Please don't play with the persistence :(")
            }
            return nil
        }
    }
    
    public func loadJSONFromUrl(url: URL) throws -> Any? {
        
        let data = try Data(contentsOf: url, options: [])
        return try JSONSerialization.jsonObject(with: data, options: [])
    }
    
    public func saveJSONToUrl(json: Any, url: URL) throws {

        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try data.write(to: url, options: Data.WritingOptions.atomicWrite)
    }
    
    public func fileURLWithName(name: String, intention: PersistenceIntention, isDirectory: Bool) -> URL {
        
        let root = self.folderForIntention(intention: intention)
        let url = root.appendingPathComponent(name, isDirectory: isDirectory)
        if isDirectory && intention == .Writing {
            self.createFolderIfNotExists(url: url)
        }
        return url
    }
    
    public func copyFileToWriteLocation(name: String, isDirectory: Bool) {
        
        let url = self.fileURLWithName(name: name, intention: .Reading, isDirectory: isDirectory)
        let writeUrl = self.fileURLWithName(name: name, intention: .WritingNoCreateFolder, isDirectory: isDirectory)
        
        _ = try? self.fileManager.copyItem(at: url, to: writeUrl)
    }
    
    public func copyFileToFolder(fileName: String, folder: String) {
        
        let url = self.fileURLWithName(name: fileName, intention: .Reading, isDirectory: false)
        let writeUrl = self
            .fileURLWithName(name: folder, intention: .Writing, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        
        _ = try? self.fileManager.copyItem(at: url, to: writeUrl)
    }
    
    public func createFolderIfNotExists(url: URL) {
        
        let fm = self.fileManager
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError("Failed to create a folder in Builda's Application Support folder \(url), error \(error)")
        }
    }
    
    public enum PersistenceIntention {
        case Reading
        case Writing
        case WritingNoCreateFolder
    }
    
    func folderForIntention(intention: PersistenceIntention) -> URL {
        switch intention {
        case .Reading:
            return self.readingFolder
        case .Writing, .WritingNoCreateFolder:
            return self.writingFolder
        }
    }
    
    public func filesInFolder(folderUrl: URL) -> [URL]? {
        
        do {
            let contents = try self.fileManager.contentsOfDirectory(at: folderUrl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            return contents
        } catch {
            if (error as NSError).code != 260 { //ignore not found errors
                Log.error("Couldn't read folder \(folderUrl), error \(error)")
            }
            return nil
        }
    }
    
}
