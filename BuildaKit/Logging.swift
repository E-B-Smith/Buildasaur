//
//  Logging.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 19/05/15.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

public class Logging {

    public class func setup(persistence: Persistence, alsoIntoFile: Bool) {
        Log.addLoggers([ConsoleLogger()])
        self.setupFileLogger(persistence: persistence, enable: alsoIntoFile)

        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
        let ascii =
        " ____        _ _     _\n" +
            "|  _ \\      (_) |   | |\n" +
            "| |_) |_   _ _| | __| | __ _ ___  __ _ _   _ _ __\n" +
            "|  _ <| | | | | |/ _` |/ _` / __|/ _` | | | | '__|\n" +
            "| |_) | |_| | | | (_| | (_| \\__ \\ (_| | |_| | |\n" +
        "|____/ \\__,_|_|_|\\__,_|\\__,_|___/\\__,_|\\__,_|_|\n"

        Log.untouched("*\n*\n*\n\(ascii)\nBuildasaur \(version) launched at \(NSDate()).\n*\n*\n*\n")
    }

    public class func setupFileLogger(persistence: Persistence, enable: Bool) {
        let path = persistence
            .fileURLWithName(name: "Logs", intention: .Writing, isDirectory: true)
            .appendingPathComponent("Builda.log", isDirectory: false)

        if enable && !Log.loggers.contains(where: { $0.id().hasSuffix(String(describing: FileLogger.self)) }) {
            let fileLogger = FileLogger(fileURL: path)
            fileLogger.fileSizeCap = 1024 * 1024 * 10 // 10MB
            Log.addLoggers([fileLogger])
        } else if let fileLogger = Log.loggers.first(where: { $0.id().hasSuffix(String(describing: FileLogger.self)) }),
            !enable {
            Log.removeLogger(fileLogger)
        }
    }
}
