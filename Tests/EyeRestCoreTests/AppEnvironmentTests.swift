import Foundation
import Testing
@testable import EyeRestCore

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func isInApplications(_ path: String) -> Bool {
        AppEnvironment.isInApplicationsFolder(URL(fileURLWithPath: path), home: home)
    }

    @Test func applicationsFoldersQualify() {
        #expect(isInApplications("/Applications/EyeRest.app"))
        #expect(isInApplications("/Applications/Utilities/EyeRest.app"))
        #expect(isInApplications("/Users/someone/Applications/EyeRest.app"))
    }

    @Test func otherLocationsDoNotQualify() {
        #expect(!isInApplications("/Users/someone/Downloads/EyeRest.app"))
        #expect(!isInApplications("/Users/other/Applications/EyeRest.app"))
        #expect(!isInApplications("/ApplicationsBackup/EyeRest.app"))
        #expect(!isInApplications("/Applications"))
        #expect(!isInApplications("/Applications/../tmp/EyeRest.app"))
        #expect(!isInApplications("/private/var/folders/xy/T/AppTranslocation/1234/d/EyeRest.app"))
    }
}
