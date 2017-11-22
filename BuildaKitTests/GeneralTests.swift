//
//  GeneralTests.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/4/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import XCTest
@testable import BuildaKit

class GeneralTests: XCTestCase {

    func testXcodeWorkspaceParsing() {

        let projectUrl = URL(fileURLWithPath: MockProject().config.url, isDirectory: true)
        let projects = try? XcodeProjectXMLParser.parseProjectsInsideOfWorkspace(url: projectUrl)
        XCTAssert(projects != nil)
        XCTAssert(projects?.count ?? 0 > 0)
    }

}
