import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import 'language.dart';
import 'device.dart';

/// Validators for device-related form fields.
/// Extracted from Device class to reduce file size.

String? Function(String?) deviceNameValidator(
  BuildContext context,
  List<Device> devices,
) {
  return (String? value) {
    if (value == null || value.isEmpty) {
      return context.formatString(AppLocale.deviceNameEmptyHint, []);
    }
    for (final element in devices) {
      if (element.targetDeviceName == value) {
        return context.formatString(AppLocale.deviceNameRepeatHint, []);
      }
    }
    return null;
  };
}

String? Function(String?) portValidator(BuildContext context) {
  return (String? value) {
    if (value == null || value.isEmpty) {
      return context.formatString(AppLocale.cannotBeEmpty, ['Port']);
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
      return context.formatString(AppLocale.mustBeNumber, ['Port']);
    }
    final int port = int.parse(value);
    if (port < 0 || port > 65535) {
      return context.formatString(AppLocale.invalidPort, []);
    }
    return null;
  };
}

String? Function(String?) ipValidator(BuildContext context, bool autoSelect) {
  return (String? value) {
    if (autoSelect) {
      return null;
    }
    if (value == null || value.isEmpty) {
      return context.formatString(AppLocale.cannotBeEmpty, ['IP']);
    }
    return null;
  };
}

String? Function(String?) secretKeyValidator(BuildContext context) {
  return (String? value) {
    if (value == null || value.isEmpty) {
      return context.formatString(AppLocale.cannotBeEmpty, ['SecretKey']);
    }
    return null;
  };
}

String? Function(String?) filePickerPackageNameValidator(BuildContext context) {
  return (String? value) {
    return null;
  };
}

String? Function(String?) certificateAuthorityValidator(BuildContext context) {
  return (String? value) {
    if (value == null || value.isEmpty) {
      return context.formatString(AppLocale.cannotBeEmpty, ['Certificate']);
    }
    return null;
  };
}
