#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project deterministically (Python 3)."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'FieldForge.xcodeproj'
PROJECT.mkdir(exist_ok=True)
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value):
    return json.dumps(str(value), ensure_ascii=False)
objects = []
def obj(name, content):
    objects.append(f'{uid(name)} = {{ {content} }};')
    return uid(name)
def refs(names):
    return '(' + ', '.join(uid(n) for n in names) + ',)'
app_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'FieldForge').rglob('*.swift'))
unit_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'Tests').glob('*.swift'))
ui_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'UITests').glob('*.swift'))
resources = ['FieldForge/Resources/PrivacyInfo.xcprivacy', 'FieldForge/Resources/Assets.xcassets']
obj('signingConfig', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = \"Config/Signing.xcconfig\"; sourceTree = SOURCE_ROOT;')
for p in app_sources + unit_sources + ui_sources + resources:
    kind = 'sourcecode.swift' if p.endswith('.swift') else 'folder.assetcatalog' if p.endswith('.xcassets') else 'text.xml'
    obj(p, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(p)}; sourceTree = SOURCE_ROOT;')
    obj('build:' + p, f'isa = PBXBuildFile; fileRef = {uid(p)};')
obj('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "FieldForge/Resources/Info.plist"; sourceTree = SOURCE_ROOT;')
for name, ext, kind in [('FieldForge', 'app', 'wrapper.application'), ('FieldForgeTests', 'xctest', 'wrapper.cfbundle'), ('FieldForgeUITests', 'xctest', 'wrapper.cfbundle')]:
    obj('product:' + name, f'isa = PBXFileReference; explicitFileType = {kind}; includeInIndex = 0; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
obj('appGroup', f'isa = PBXGroup; name = FieldForge; children = {refs(app_sources + resources + ["plist"])}; sourceTree = "<group>";')
obj('testGroup', f'isa = PBXGroup; name = Tests; children = {refs(unit_sources + ui_sources)}; sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; name = Products; children = {refs(["product:FieldForge", "product:FieldForgeTests", "product:FieldForgeUITests"])}; sourceTree = "<group>";')
obj('rootGroup', f'isa = PBXGroup; children = {refs(["appGroup", "testGroup", "products", "signingConfig"])}; sourceTree = "<group>";')
for target, sources in [('FieldForge', app_sources), ('FieldForgeTests', unit_sources), ('FieldForgeUITests', ui_sources)]:
    obj(target + ':sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(["build:" + p for p in sources])}; runOnlyForDeploymentPostprocessing = 0;')
    obj(target + ':frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj(target + ':resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(["build:" + p for p in resources]) if target == "FieldForge" else "()"}; runOnlyForDeploymentPostprocessing = 0;')
    if target != 'FieldForge':
        obj(target + ':proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("FieldForge")}; remoteInfo = FieldForge;')
        obj(target + ':dependency', f'isa = PBXTargetDependency; target = {uid("FieldForge")}; targetProxy = {uid(target + ":proxy")};')
    product_type = 'application' if target == 'FieldForge' else 'bundle.unit-test' if target == 'FieldForgeTests' else 'bundle.ui-testing'
    obj(target, f'isa = PBXNativeTarget; buildConfigurationList = {uid(target + ":configs")}; buildPhases = {refs([target + ":sources", target + ":frameworks", target + ":resources"])}; buildRules = (); dependencies = {refs([target + ":dependency"]) if target != "FieldForge" else "()"}; name = {target}; productName = {target}; productReference = {uid("product:" + target)}; productType = "com.apple.product-type.{product_type}";')
    for config in ['Debug', 'Release']:
        settings = {
            'CODE_SIGN_STYLE': 'Automatic', 'DEVELOPMENT_TEAM': '', 'PRODUCT_NAME': '$(TARGET_NAME)',
            'PRODUCT_BUNDLE_IDENTIFIER': 'com.tinuvael.' + target,
            'SWIFT_VERSION': '5.0', 'TARGETED_DEVICE_FAMILY': '1',
            'GENERATE_INFOPLIST_FILE': 'YES' if target != 'FieldForge' else 'NO',
            'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
        }
        if target == 'FieldForge':
            del settings['DEVELOPMENT_TEAM']
            settings.update({'INFOPLIST_FILE': 'FieldForge/Resources/Info.plist', 'MARKETING_VERSION': '0.1.0',
                'CURRENT_PROJECT_VERSION': '1', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
                'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
                'ENABLE_PREVIEWS': 'YES', 'SWIFT_EMIT_LOC_STRINGS': 'YES'})
        elif target == 'FieldForgeTests':
            settings.update({'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/FieldForge.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FieldForge',
                'BUNDLE_LOADER': '$(TEST_HOST)'})
        else:
            settings.update({'TEST_TARGET_NAME': 'FieldForge'})
        base_config = f'baseConfigurationReference = {uid("signingConfig")}; ' if target == 'FieldForge' else ''
        obj(target + ':' + config, f'isa = XCBuildConfiguration; name = {config}; {base_config}buildSettings = {{ ' + ' '.join(f'{k} = {q(v)};' for k, v in settings.items()) + ' };')
    obj(target + ':configs', f'isa = XCConfigurationList; buildConfigurations = {refs([target + ":Debug", target + ":Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
for config in ['Debug', 'Release']:
    settings = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'CLANG_ENABLE_MODULES': 'YES',
        'CLANG_ENABLE_OBJC_ARC': 'YES', 'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES',
        'GCC_WARN_UNINITIALIZED_AUTOS': 'YES_AGGRESSIVE', 'GCC_WARN_UNUSED_VARIABLE': 'YES',
        'GCC_WARN_UNUSED_FUNCTION': 'YES', 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O',
        'SWIFT_COMPILATION_MODE': 'singlefile' if config == 'Debug' else 'wholemodule',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if config == 'Debug' else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY': 'YES' if config == 'Debug' else 'NO',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG $(inherited)' if config == 'Debug' else '$(inherited)',
        'ONLY_ACTIVE_ARCH': 'YES' if config == 'Debug' else 'NO', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator'}
    obj('project:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ ' + ' '.join(f'{k} = {q(v)};' for k, v in settings.items()) + ' };')
obj('project:configs', f'isa = XCConfigurationList; buildConfigurations = {refs(["project:Debug", "project:Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2660; TargetAttributes = {{ {uid("FieldForge")} = {{ CreatedOnToolsVersion = 26.6; }}; }}; }}; buildConfigurationList = {uid("project:configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru, en, Base); mainGroup = {uid("rootGroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {refs(["FieldForge", "FieldForgeTests", "FieldForgeUITests"])};')
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')
scheme_dir = PROJECT / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def build_ref(name):
    ext = 'app' if name == 'FieldForge' else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name)}" BuildableName="{name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:FieldForge.xcodeproj"/>'
scheme = '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="2660" version="1.3">\n'
scheme += '<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>'
scheme += '<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">' + build_ref('FieldForge') + '</BuildActionEntry></BuildActionEntries></BuildAction>'
scheme += '<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'
for t in ['FieldForgeTests', 'FieldForgeUITests']:
    scheme += '<TestableReference skipped="NO" parallelizable="NO">' + build_ref(t) + '</TestableReference>'
scheme += '</Testables></TestAction>'
scheme += '<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">' + build_ref('FieldForge') + '</BuildableProductRunnable></LaunchAction>'
scheme += '<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">' + build_ref('FieldForge') + '</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n'
(scheme_dir / 'FieldForge.xcscheme').write_text(scheme)
print(f'Generated project: {len(app_sources)} app sources, {len(unit_sources)} unit test files, {len(ui_sources)} UI test files')
