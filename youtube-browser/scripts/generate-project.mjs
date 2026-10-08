import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const objects = {};
const id = label => crypto.createHash('sha256').update(`ResonWeb:${label}`).digest('hex').slice(0, 24).toUpperCase();
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
const youtubePackage = add('package.youtube', {
  isa: 'XCRemoteSwiftPackageReference', repositoryURL: 'https://github.com/alexeichhorn/YouTubeKit.git',
  requirement: { kind: 'revision', revision: 'e5b7d0396ce12bf3444f0d209e8436c83373b7af' }
});
const youtubeProduct = add('product.youtube', {
  isa: 'XCSwiftPackageProductDependency', package: youtubePackage, productName: 'YouTubeKit'
});
const youtubeFramework = add('build.youtube', { isa: 'PBXBuildFile', productRef: youtubeProduct });
const sharedFiles = [
  'HapticPattern.swift', 'HapticAHAP.swift', 'MusicModels.swift', 'MusicLibrary.swift',
  'MusicAnalyzer.swift', 'MusicPCMDecoder.swift', 'MusicPrecisionAnalysis.swift', 'MusicComposer.swift',
  'MusicHapticRenderer.swift', 'YouTubeAudioSource.swift', 'YouTubeAudioDownload.swift', 'PCAnalysis.swift',
  'Theme.swift', 'MusicVibrationSettings.swift', 'MusicPreparationView.swift', 'MusicMessage.swift',
  'MusicAnalysisDeletionView.swift'
];
const sharedReferences = sharedFiles.map(file => {
  if (!fs.existsSync(path.join(root, '../haptic-lab/HapticLab', file))) throw new Error(`Missing shared source: ${file}`);
  return add(`ref.shared.${file}`, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>' });
});
const sharedSources = sharedReferences.map((reference, i) => add(`build.shared.${sharedFiles[i]}`, { isa: 'PBXBuildFile', fileRef: reference }));
const sharedGroup = add('group.shared', { isa: 'PBXGroup', children: sharedReferences, name: 'Shared Reson haptics', path: '../haptic-lab/HapticLab', sourceTree: '<group>' });
const appFiles = fs.readdirSync(path.join(root, 'ResonWeb')).filter(file => file.endsWith('.swift')).sort();
const appReferences = appFiles.map(file => add(`ref.app.${file}`, {
  isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>'
}));
const appSources = appReferences.map((reference, index) => add(`build.app.${appFiles[index]}`, {
  isa: 'PBXBuildFile', fileRef: reference
}));
appSources.push(...sharedSources);
const resourceReferences = [
  add('ref.browser-video', { isa: 'PBXFileReference', lastKnownFileType: 'video.mpeg-4', path: '.build/BrowserFixture.mp4', sourceTree: 'SOURCE_ROOT' }),
  add('ref.playback-script', { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.javascript', path: 'PlaybackObservation.js', sourceTree: '<group>' }),
  add('ref.youtube-license', { isa: 'PBXFileReference', lastKnownFileType: 'text', path: '../haptic-lab/HapticLab/Resources/YouTubeKit-LICENSE.txt', sourceTree: 'SOURCE_ROOT' }),
  add('ref.assets', { isa: 'PBXFileReference', lastKnownFileType: 'folder.assetcatalog', path: 'Assets.xcassets', sourceTree: '<group>' })
];
const resourceBuildFiles = resourceReferences.map((reference, index) => add(`build.resource.${index}`, {
  isa: 'PBXBuildFile', fileRef: reference
}));
const resourceGroup = add('group.resources', { isa: 'PBXGroup', children: resourceReferences, path: 'Resources', sourceTree: '<group>' });
const plistReference = add('ref.plist', { isa: 'PBXFileReference', lastKnownFileType: 'text.plist.xml', path: 'Info.plist', sourceTree: '<group>' });
const appGroup = add('group.app', { isa: 'PBXGroup', children: [...appReferences, resourceGroup, plistReference], path: 'ResonWeb', sourceTree: '<group>' });

const targets = [
  { key: 'app', name: 'ResonWeb', product: 'ResonWeb.app', type: 'com.apple.product-type.application', fileType: 'wrapper.application', sources: appSources, resources: resourceBuildFiles },
  { key: 'tests', name: 'ResonWebTests', product: 'ResonWebTests.xctest', type: 'com.apple.product-type.bundle.unit-test', fileType: 'wrapper.cfbundle', folder: 'Tests' },
  { key: 'uitests', name: 'ResonWebUITests', product: 'ResonWebUITests.xctest', type: 'com.apple.product-type.bundle.ui-testing', fileType: 'wrapper.cfbundle', folder: 'UITests', file: 'ResonWebUITests.swift' }
];
const testGroups = [];
const products = [];
for (const target of targets) {
  if (target.folder) {
    const files = fs.readdirSync(path.join(root, target.folder)).filter(file => file.endsWith('.swift')).sort();
    const references = files.map(file => add(`ref.${target.key}.${file}`, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>' }));
    target.sources = references.map((reference, i) => add(`build.${target.key}.${files[i]}`, { isa: 'PBXBuildFile', fileRef: reference }));
    target.resources = [];
    testGroups.push(add(`group.${target.key}`, { isa: 'PBXGroup', children: references, path: target.folder, sourceTree: '<group>' }));
  }
  const product = add(`product.${target.key}`, { isa: 'PBXFileReference', explicitFileType: target.fileType, includeInIndex: 0, path: target.product, sourceTree: 'BUILT_PRODUCTS_DIR' });
  products.push(product);
  const phases = [
    add(`sources.${target.key}`, { isa: 'PBXSourcesBuildPhase', buildActionMask: 2147483647, files: target.sources, runOnlyForDeploymentPostprocessing: 0 }),
    add(`frameworks.${target.key}`, { isa: 'PBXFrameworksBuildPhase', buildActionMask: 2147483647, files: target.key === 'app' ? [youtubeFramework] : [], runOnlyForDeploymentPostprocessing: 0 }),
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
      INFOPLIST_FILE: 'ResonWeb/Info.plist', GENERATE_INFOPLIST_FILE: 'NO',
      ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: 'AccentColor',
      ENABLE_PREVIEWS: 'YES', SWIFT_EMIT_LOC_STRINGS: 'NO'
    });
  } else {
    base.GENERATE_INFOPLIST_FILE = 'YES';
    if (target.key === 'tests') {
      base.TEST_HOST = '$(BUILT_PRODUCTS_DIR)/ResonWeb.app/ResonWeb';
      base.BUNDLE_LOADER = '$(TEST_HOST)';
    } else {
      base.TEST_TARGET_NAME = 'ResonWeb';
    }
  }
  const configurations = ['Debug', 'Release'].map(name => add(`config.${target.key}.${name}`, {
    isa: 'XCBuildConfiguration', buildSettings: { ...base }, name
  }));
  const configList = add(`configs.${target.key}`, { isa: 'XCConfigurationList', buildConfigurations: configurations, defaultConfigurationIsVisible: 0, defaultConfigurationName: 'Release' });
  const dependencies = [];
  if (target.key !== 'app') {
    const proxy = add(`proxy.${target.key}`, { isa: 'PBXContainerItemProxy', containerPortal: projectID, proxyType: 1, remoteGlobalIDString: appTarget, remoteInfo: 'ResonWeb' });
    dependencies.push(add(`dependency.${target.key}`, { isa: 'PBXTargetDependency', target: appTarget, targetProxy: proxy }));
  }
  add(`target.${target.key}`, {
    isa: 'PBXNativeTarget', buildConfigurationList: configList, buildPhases: phases, buildRules: [],
    dependencies, packageProductDependencies: target.key === 'app' ? [youtubeProduct] : [],
    name: target.name, productName: target.name, productReference: product, productType: target.type
  });
}

const productGroup = add('group.products', { isa: 'PBXGroup', children: products, name: 'Products', sourceTree: '<group>' });
const mainGroup = add('group.main', { isa: 'PBXGroup', children: [appGroup, sharedGroup, ...testGroups, productGroup], sourceTree: '<group>' });
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
  targets: targets.map(target => id(`target.${target.key}`)), packageReferences: [youtubePackage]
});
const project = { archiveVersion: 1, classes: {}, objectVersion: 56, objects, rootObject: projectID };
const projectDir = path.join(root, 'ResonWeb.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata', 'xcschemes'), { recursive: true });
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), `// !$*UTF8*$!\n${serialize(project)}\n`);

const reference = target => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(`target.${target.key}`)}" BuildableName="${target.product}" BlueprintName="${target.name}" ReferencedContainer="container:ResonWeb.xcodeproj"/>`;
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
fs.writeFileSync(path.join(projectDir, 'xcshareddata', 'xcschemes', 'ResonWeb.xcscheme'), scheme);
console.log(`Generated Xcode project: ${appFiles.length} app sources, unit tests, UI tests.`);
