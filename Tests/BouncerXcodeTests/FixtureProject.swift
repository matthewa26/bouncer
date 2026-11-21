#if canImport(XcodeProj)
import Foundation
import PathKit
import XcodeProj

/// Builds a minimal Xcode project on disk: native targets with a sources and a frameworks phase each, and
/// Debug and Release configurations at the project and target levels.
enum FixtureProject {
    static func make(
        in directory: URL, targets: [(name: String, type: PBXProductType)], projectSettings: BuildSettings = [:]
    ) throws -> URL {
        var objects: [PBXObject] = []
        let projectConfigurations = configurationList(projectSettings, into: &objects)
        let nativeTargets = targets.map { target(named: $0.name, type: $0.type, into: &objects) }
        let mainGroup = PBXGroup(children: [], sourceTree: .group)
        objects.append(mainGroup)
        let project = PBXProject(
            name: "Fixture", buildConfigurationList: projectConfigurations, compatibilityVersion: "Xcode 14.0",
            preferredProjectObjectVersion: nil, minimizedProjectReferenceProxies: nil, mainGroup: mainGroup,
            targets: nativeTargets
        )
        objects.append(project)
        let pbxproj = PBXProj(rootObject: project, objectVersion: 56, objects: objects)
        let url = directory.appendingPathComponent("Fixture.xcodeproj")
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj).write(path: Path(url.path))
        return url
    }

    private static func target(named name: String, type: PBXProductType, into objects: inout [PBXObject]) -> PBXNativeTarget {
        let sources = PBXSourcesBuildPhase()
        let frameworks = PBXFrameworksBuildPhase()
        let configurations = configurationList(["PRODUCT_NAME": .string("$(TARGET_NAME)")], into: &objects)
        let target = PBXNativeTarget(
            name: name, buildConfigurationList: configurations, buildPhases: [frameworks, sources], productType: type
        )
        objects += [sources, frameworks, target]
        return target
    }

    private static func configurationList(_ settings: BuildSettings, into objects: inout [PBXObject]) -> XCConfigurationList {
        let debug = XCBuildConfiguration(name: "Debug", buildSettings: settings)
        let release = XCBuildConfiguration(name: "Release", buildSettings: settings)
        let list = XCConfigurationList(buildConfigurations: [debug, release], defaultConfigurationName: "Release")
        objects += [debug, release, list]
        return list
    }
}
#endif
