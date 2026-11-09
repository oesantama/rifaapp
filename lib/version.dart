/// Release version of the app. Updated by scripts/release.sh together with pubspec.yaml,
/// backend/package.json and CHANGELOG.md — do not edit by hand.
const String appVersion = '3.4.8';

/// Identificador único de cada compilación de la web (lo pone scripts/build-web.sh). Si el servidor tiene otro,
/// el usuario recibe el aviso de nueva versión aunque el número de versión no haya cambiado.
const String appBuild = String.fromEnvironment('BUILD_ID');
