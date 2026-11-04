import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Custom UI copy is handled by LocalizationService. Material/Cupertino controls
// need their own delegates for calendars, text selection and accessibility.
const kUiControlDelegates = GlobalMaterialLocalizations.delegates;
const kUiControlLocales = [Locale('en'), Locale('ru')];

Locale uiControlLocale(String language) =>
    RegExp(r'^ru(?:[-_].*)?$', caseSensitive: false).hasMatch(language.trim())
    ? const Locale('ru')
    : const Locale('en');
