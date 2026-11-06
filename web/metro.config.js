// Learn more https://docs.expo.dev/guides/customizing-metro
const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// pdf-lib depends on tslib. Metro resolves tslib's ESM wrapper
// (modules/index.js), whose `import tslib from '../tslib.js'` comes back
// undefined here ("Cannot destructure property '__extends' of 'tslib.default'").
// Point it at tslib's plain ES build, which exports the helpers by name.
const tslibEs6 = require.resolve('tslib/tslib.es6.js');
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName === 'tslib') return { type: 'sourceFile', filePath: tslibEs6 };
  return context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
