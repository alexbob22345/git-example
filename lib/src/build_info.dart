/// Date shown by the Kernel button.
///
/// The release script passes `--dart-define=BUILD_DATE=YYYY-MM-DD`.
const String kBuildDate = String.fromEnvironment(
  'BUILD_DATE',
  defaultValue: '2026-11-15',
);

const String kAppName = 'Change GUI';
const String kCredit = 'Created by Bored Programmer';
