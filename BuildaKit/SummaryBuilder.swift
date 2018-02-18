//
//  SummaryCreator.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/15/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import XcodeServerSDK
import BuildaUtils
import BuildaGitServer

class SummaryBuilder {

    var statusCreator: BuildStatusCreator!
    var lines: [String] = []
    let resultString: String
    var linkBuilder: (Integration) -> [String: String]? = { _ in [:] }

    init() {
        self.resultString = "*Result*: "
    }

    // MARK: high level

    func buildPassing(integration: Integration) -> StatusAndComment {

        let linkToIntegration = self.linkBuilder(integration)
        self.addBaseCommentFromIntegration(integration: integration)

        let status = self.createStatus(state: .Success, description: "Build passed!", targetUrl: linkToIntegration)

        let buildResultSummary = integration.buildResultSummary!
        switch integration.result {
        case .Succeeded?:
            self.appendTestsPassed(buildResultSummary: buildResultSummary)
        case .Warnings?, .AnalyzerWarnings?:

            switch (buildResultSummary.warningCount, buildResultSummary.analyzerWarningCount) {
            case (_, 0):
                self.appendWarnings(buildResultSummary: buildResultSummary)
            case (0, _):
                self.appendAnalyzerWarnings(buildResultSummary: buildResultSummary)
            default:
                self.appendWarningsAndAnalyzerWarnings(buildResultSummary: buildResultSummary)
            }

        default: break
        }

        //and code coverage
        self.appendCodeCoverage(buildResultSummary: buildResultSummary)

        return self.buildWithStatus(status: status, integration: integration, links: linkToIntegration)
    }

    func buildFailingTests(integration: Integration) -> StatusAndComment {

        let linkToIntegration = self.linkBuilder(integration)

        self.addBaseCommentFromIntegration(integration: integration)

        let status = self.createStatus(state: .Failure, description: "Build failed tests!", targetUrl: linkToIntegration)
        let buildResultSummary = integration.buildResultSummary!
        self.appendTestFailure(buildResultSummary: buildResultSummary)
        return self.buildWithStatus(status: status, integration: integration, links: linkToIntegration)
    }

    func buildErrorredIntegration(integration: Integration) -> StatusAndComment {

        let linkToIntegration = self.linkBuilder(integration)
        self.addBaseCommentFromIntegration(integration: integration)

        let status = self.createStatus(state: .Error, description: "Build error!", targetUrl: linkToIntegration)

        self.appendErrors(integration: integration)
        return self.buildWithStatus(status: status, integration: integration, links: linkToIntegration)
    }

    func buildCanceledIntegration(integration: Integration) -> StatusAndComment {

        let linkToIntegration = self.linkBuilder(integration)

        self.addBaseCommentFromIntegration(integration: integration)

        let status = self.createStatus(state: .Error, description: "Build canceled!", targetUrl: linkToIntegration)

        self.appendCancel()
        return self.buildWithStatus(status: status, integration: integration, links: linkToIntegration)
    }

    func buildEmptyIntegration() -> StatusAndComment {

        let status = self.createStatus(state: .NoState, description: nil, targetUrl: nil)
        return self.buildWithStatus(status: status)
    }

    // MARK: utils

    private func createStatus(state: BuildState, description: String?, targetUrl: [String: String]?) -> StatusType {

        let status = self.statusCreator.createStatusFromState(state: state, description: description, targetUrl: targetUrl)
        return status
    }

    func addBaseCommentFromIntegration(integration: Integration) {

        var integrationText = "Integration \(integration.number)"
        if let link = self.linkBuilder(integration)?["https"] {
            //linkify
            integrationText = "[\(integrationText)](\(link))"
        }

        self.lines.append("Result of \(integrationText)")
        self.lines.append("---")

        if let duration = self.formattedDurationOfIntegration(integration: integration) {
            self.lines.append("*Duration*: " + duration)
        }
    }

    func appendTestsPassed(buildResultSummary: BuildResultSummary) {

        let testsCount = buildResultSummary.testsCount
        let testSection = testsCount > 0 ? "All \(testsCount) " + "test".pluralizeStringIfNecessary(testsCount) + " passed. " : ""
        self.lines.append(self.resultString + "**Perfect build!** \(testSection):+1:")
    }

    func appendWarnings(buildResultSummary: BuildResultSummary) {

        let warningCount = buildResultSummary.warningCount
        let testsCount = buildResultSummary.testsCount
        self.lines.append(self.resultString + "All \(testsCount) tests passed with **\(warningCount) " + "warning".pluralizeStringIfNecessary(warningCount) + "**.")
    }

    func appendAnalyzerWarnings(buildResultSummary: BuildResultSummary) {

        let analyzerWarningCount = buildResultSummary.analyzerWarningCount
        let testsCount = buildResultSummary.testsCount
        self.lines.append(self.resultString + "All \(testsCount) tests passed with **\(analyzerWarningCount) " + "analyzer warning".pluralizeStringIfNecessary(analyzerWarningCount) + "**.")
    }

    func appendWarningsAndAnalyzerWarnings(buildResultSummary: BuildResultSummary) {

        let warningCount = buildResultSummary.warningCount
        let analyzerWarningCount = buildResultSummary.analyzerWarningCount
        let testsCount = buildResultSummary.testsCount
        self.lines.append(self.resultString + "All \(testsCount) tests passed with **\(warningCount) " + "warning".pluralizeStringIfNecessary(warningCount) + "** and **\(analyzerWarningCount) " + "analyzer warning".pluralizeStringIfNecessary(analyzerWarningCount) + "**.")
    }

    func appendCodeCoverage(buildResultSummary: BuildResultSummary) {

        let codeCoveragePercentage = buildResultSummary.codeCoveragePercentage
        if codeCoveragePercentage > 0 {
            self.lines.append("*Test Coverage*: \(codeCoveragePercentage)%")
        }
    }

    func appendTestFailure(buildResultSummary: BuildResultSummary) {

        let testFailureCount = buildResultSummary.testFailureCount
        let testsCount = buildResultSummary.testsCount
        self.lines.append(self.resultString + "**Build failed \(testFailureCount) " + "test".pluralizeStringIfNecessary(testFailureCount) + "** out of \(testsCount)")
    }

    func appendErrors(integration: Integration) {

        let errorCount: Int = integration.buildResultSummary?.errorCount ?? -1
        self.lines.append(self.resultString + "**\(errorCount) " + "error".pluralizeStringIfNecessary(errorCount) + ", failing state: \(integration.result!.rawValue)**")
    }

    func appendCancel() {

        //TODO: find out who canceled it and add it to the comment?
        self.lines.append("Build was **manually canceled**.")
    }

    func buildWithStatus(status: StatusType, integration: Integration? = nil, links: [String: String]? = nil) -> StatusAndComment {

        let comment: String?
        if lines.isEmpty {
            comment = nil
        } else {
            comment = lines.joined(separator: "\n")
        }
        return StatusAndComment(status: status, comment: comment, integration: integration, links: links)
    }
}

extension SummaryBuilder {

    func formattedDurationOfIntegration(integration: Integration) -> String? {

        if let seconds = integration.duration {

            let result = TimeUtils.secondsToNaturalTime(Int(seconds))
            return result

        } else {
            Log.error("No duration provided in integration \(integration)")
            return "[NOT PROVIDED]"
        }
    }
}
