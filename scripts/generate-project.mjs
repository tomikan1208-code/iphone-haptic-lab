import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const objects = {};
const id = label => crypto.createHash('sha256').update(`HapticLab:${label}`).digest('hex').slice(0, 24).toUpperCase();
function add(label, value) {
  const key = id(label);
  if (objects[key]) throw new Error(`Duplicate object: ${label}`);
  objects[key] = value;
  return key;
}
function serialize(value, depth = 0) {
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return /^[A-Za-z0-9_./]+$/.test(value) ? value : JSON.stringify(value);
  const indent = '\t'.repeat(depth);
  if (Array.isArray(value)) {
    return `(\n${value.map(item => `${indent}\t${serialize(item, depth + 1)},`).join('\n')}\n${indent})`;
  }
  return `{\n${Object.entries(value).map(([key, item]) => `${indent}\t${serialize(key)} = ${serialize(item, depth + 1)};`).join('\n')}\n${indent}}`;
}

const appTarget = id('target.app');
const projectID = id('project');
const appFiles = fs.readdirSync(path.join(root, 'HapticLab')).filter(file => file.endsWith('.swift')).sort();
const appReferences = appFiles.map(file => add(`ref.app.${file}`, {
  isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>'
}));
const appSources = appReferences.map((reference, index) => add(`build.app.${appFiles[index]}`, {
  isa: 'PBXBuildFile', fileRef: reference
}));
const resourceReferences = [
  add('ref.presets', { isa: 'PBXFileReference', lastKnownFileType: 'text.json', path: 'Presets.json', sourceTree: '<group>' }),
  add('ref.assets', { isa: 'PBXFileReference', lastKnownFileType: 'folder.assetcatalog', path: 'Assets.xcassets', sourceTree: '<group>' })
];
const resourceBuildFiles = resourceReferences.map((reference, index) => add(`build.resource.${index}`, {
  isa: 'PBXBuildFile', fileRef: reference
}));
const resourceGroup = add('group.resources', { isa: 'PBXGroup', children: resourceReferences, path: 'Resources', sourceTree: '<group>' });
const plistReference = add('ref.plist', { isa: 'PBXFileReference', lastKnownFileType: 'text.plist.xml', path: 'Info.plist', sourceTree: '<group>' });
const appGroup = add('group.app', { isa: 'PBXGroup', children: [...appReferences, resourceGroup, plistReference], path: 'HapticLab', sourceTree: '<group>' });

const targets = [
  { key: 'app', name: 'HapticLab', product: 'HapticLab.app', type: 'com.apple.product-type.application', fileType: 'wrapper.application', sources: appSources, resources: resourceBuildFiles },
  { key: 'tests', name: 'HapticLabTests', product: 'HapticLabTests.xctest', type: 'com.apple.product-type.bundle.unit-test', fileType: 'wrapper.cfbundle', folder: 'Tests', file: 'HapticPatternTests.swift' },
  { key: 'uitests', name: 'HapticLabUITests', product: 'HapticLabUITests.xctest', type: 'com.apple.product-type.bundle.ui-testing', fileType: 'wrapper.cfbundle', folder: 'UITests', file: 'HapticLabUITests.swift' }
];
const testGroups = [];
const products = [];
for (const target of targets) {
  if (target.folder) {
    const reference = add(`ref.${target.key}`, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: target.file, sourceTree: '<group>' });
    target.sources = [add(`build.${target.key}`, { isa: 'PBXBuildFile', fileRef: reference })];
    target.resources = [];
    testGroups.push(add(`group.${target.key}`, { isa: 'PBXGroup', children: [reference], path: target.folder, sourceTree: '<group>' }));
  }
  const product = add(`product.${target.key}`, { isa: 'PBXFileReference', explicitFileType: target.fileType, includeInIndex: 0, path: target.product, sourceTree: 'BUILT_PRODUCTS_DIR' });
  products.push(product);
  const phases = [
    add(`sources.${target.key}`, { isa: 'PBXSourcesBuildPhase', buildActionMask: 2147483647, files: target.sources, runOnlyForDeploymentPostprocessing: 0 }),
    add(`frameworks.${target.key}`, { isa: 'PBXFrameworksBuildPhase', buildActionMask: 2147483647, files: [], runOnlyForDeploymentPostprocessing: 0 }),
    add(`resources.${target.key}`, { isa: 'PBXResourcesBuildPhase', buildActionMask: 2147483647, files: target.resources, runOnlyForDeploymentPostprocessing: 0 })
  ];
  const base = {
    PRODUCT_NAME: '$(TARGET_NAME)',
    PRODUCT_BUNDLE_IDENTIFIER: `com.tomikan1208.${target.name.toLowerCase()}`,
    TARGETED_DEVICE_FAMILY: '1',
    SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator',
    SUPPORTS_MACCATALYST: 'NO',
    CODE_SIGN_STYLE: 'Automatic',
    ENABLE_USER_SCRIPT_SANDBOXING: 'YES',
    SWIFT_VERSION: '5.0',
    IPHONEOS_DEPLOYMENT_TARGET: '16.0'
  };
  if (target.key === 'app') {
    Object.assign(base, {
      INFOPLIST_FILE: 'HapticLab/Info.plist', GENERATE_INFOPLIST_FILE: 'NO',
      ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: 'AccentColor',
      ENABLE_PREVIEWS: 'YES', SWIFT_EMIT_LOC_STRINGS: 'NO'
    });
  } else {
    base.GENERATE_INFOPLIST_FILE = 'YES';
    if (target.key === 'tests') {
      base.TEST_HOST = '$(BUILT_PRODUCTS_DIR)/HapticLab.app/HapticLab';
      base.BUNDLE_LOADER = '$(TEST_HOST)';
    } else {
      base.TEST_TARGET_NAME = 'HapticLab';
    }
  }
  const configurations = ['Debug', 'Release'].map(name => add(`config.${target.key}.${name}`, {
    isa: 'XCBuildConfiguration', buildSettings: { ...base }, name
  }));
  const configList = add(`configs.${target.key}`, { isa: 'XCConfigurationList', buildConfigurations: configurations, defaultConfigurationIsVisible: 0, defaultConfigurationName: 'Release' });
  const dependencies = [];
  if (target.key !== 'app') {
    const proxy = add(`proxy.${target.key}`, { isa: 'PBXContainerItemProxy', containerPortal: projectID, proxyType: 1, remoteGlobalIDString: appTarget, remoteInfo: 'HapticLab' });
    dependencies.push(add(`dependency.${target.key}`, { isa: 'PBXTargetDependency', target: appTarget, targetProxy: proxy }));
  }
  add(`target.${target.key}`, {
    isa: 'PBXNativeTarget', buildConfigurationList: configList, buildPhases: phases, buildRules: [],
    dependencies, name: target.name, productName: target.name, productReference: product, productType: target.type
  });
}

const productGroup = add('group.products', { isa: 'PBXGroup', children: products, name: 'Products', sourceTree: '<group>' });
const mainGroup = add('group.main', { isa: 'PBXGroup', children: [appGroup, ...testGroups, productGroup], sourceTree: '<group>' });
const projectConfigurations = ['Debug', 'Release'].map(name => add(`config.project.${name}`, {
  isa: 'XCBuildConfiguration', name,
  buildSettings: {
    CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES', SDKROOT: 'iphoneos',
    IPHONEOS_DEPLOYMENT_TARGET: '16.0', SWIFT_VERSION: '5.0',
    SWIFT_OPTIMIZATION_LEVEL: name === 'Debug' ? '-Onone' : '-O',
    SWIFT_COMPILATION_MODE: name === 'Debug' ? 'singlefile' : 'wholemodule',
    SWIFT_ACTIVE_COMPILATION_CONDITIONS: name === 'Debug' ? 'DEBUG $(inherited)' : '$(inherited)',
    DEBUG_INFORMATION_FORMAT: name === 'Debug' ? 'dwarf' : 'dwarf-with-dsym',
    ENABLE_TESTABILITY: name === 'Debug' ? 'YES' : 'NO'
  }
}));
const projectConfigurationList = add('configs.project', { isa: 'XCConfigurationList', buildConfigurations: projectConfigurations, defaultConfigurationIsVisible: 0, defaultConfigurationName: 'Release' });
const targetAttributes = Object.fromEntries(targets.map(target => [id(`target.${target.key}`), {
  CreatedOnToolsVersion: '16.0', ...(target.key !== 'app' ? { TestTargetID: appTarget } : {})
}]));
add('project', {
  isa: 'PBXProject', attributes: { BuildIndependentTargetsInParallel: 'YES', LastUpgradeCheck: '1600', TargetAttributes: targetAttributes },
  buildConfigurationList: projectConfigurationList, compatibilityVersion: 'Xcode 14.0',
  developmentRegion: 'ja', hasScannedForEncodings: 0, knownRegions: ['ja', 'en', 'Base'],
  mainGroup, productRefGroup: productGroup, projectDirPath: '', projectRoot: '',
  targets: targets.map(target => id(`target.${target.key}`))
});
const project = { archiveVersion: 1, classes: {}, objectVersion: 56, objects, rootObject: projectID };
const projectDir = path.join(root, 'HapticLab.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata', 'xcschemes'), { recursive: true });
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), `// !$*UTF8*$!\n${serialize(project)}\n`);

const reference = target => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(`target.${target.key}`)}" BuildableName="${target.product}" BlueprintName="${target.name}" ReferencedContainer="container:HapticLab.xcodeproj"/>`;
const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    ${targets.map(target => `<BuildActionEntry buildForTesting="YES" buildForRunning="${target.key === 'app' ? 'YES' : 'NO'}" buildForProfiling="${target.key === 'app' ? 'YES' : 'NO'}" buildForArchiving="${target.key === 'app' ? 'YES' : 'NO'}" buildForAnalyzing="YES">${reference(target)}</BuildActionEntry>`).join('\n    ')}
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>${targets.slice(1).map(target => `<TestableReference skipped="NO" parallelizable="NO">${reference(target)}</TestableReference>`).join('')}</Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${reference(targets[0])}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${reference(targets[0])}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
`;
fs.writeFileSync(path.join(projectDir, 'xcshareddata', 'xcschemes', 'HapticLab.xcscheme'), scheme);
console.log(`Generated Xcode project: ${appFiles.length} app sources, unit tests, UI tests.`);

