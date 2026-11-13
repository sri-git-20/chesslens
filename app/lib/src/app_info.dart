/// Static facts about the app shown in Settings and used by bug reports.
library;

const String appName = 'ChessLens';

/// Keep in step with `version:` in pubspec.yaml.
const String appVersion = '0.1.0';

/// Set by CI with `--dart-define=BUILD_NUMBER=<run number>`.
const String buildNumber =
    String.fromEnvironment('BUILD_NUMBER', defaultValue: 'dev');

const String sourceUrl = 'https://github.com/sri-git-20/chesslens';

const String bugReportEmail = 'proxify1@gmail.com';

const String legalese =
    'Copyright (C) 2026 ChessLens contributors.\n'
    'ChessLens is free software under the GNU General Public License v3.';
