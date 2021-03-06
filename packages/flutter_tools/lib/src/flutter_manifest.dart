// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/src/globals.dart';
import 'package:json_schema/json_schema.dart';
import 'package:yaml/yaml.dart';

import 'base/file_system.dart';
import 'cache.dart';

/// A wrapper around the `flutter` section in the  `pubspec.yaml` file.
class FlutterManifest {
  FlutterManifest._();

  /// Returns null on missing or invalid manifest
  static Future<FlutterManifest> createFromPath(String path) async {
    return  _createFromYaml(await _loadFlutterManifest(path));
  }
  /// Returns null on missing or invalid manifest
  static Future<FlutterManifest> createFromString(String manifest) async {
    return _createFromYaml(loadYaml(manifest));
  }

  static Future<FlutterManifest> _createFromYaml(Object yamlDocument) async {
    final FlutterManifest pubspec = new FlutterManifest._();
    if (yamlDocument != null && !await _validate(yamlDocument))
      return null;

    pubspec._descriptor = yamlDocument ?? <String, dynamic>{};
    pubspec._flutterDescriptor = pubspec._descriptor['flutter'] ?? <String, dynamic>{};
    return pubspec;
  }

  /// A map representation of the entire `pubspec.yaml` file.
  Map<String, dynamic> _descriptor;

  /// A map representation of the `flutter` section in the `pubspec.yaml` file.
  Map<String, dynamic> _flutterDescriptor;

  bool get isEmpty => _descriptor.isEmpty;

  String get appName => _descriptor['name'] ?? '';

  bool get usesMaterialDesign {
    return _flutterDescriptor['uses-material-design'] ?? false;
  }

  List<Map<String, dynamic>> get fontsDescriptor {
   return _flutterDescriptor['fonts'] ?? const <Map<String, dynamic>>[];
  }

  List<String> get assets {
    return _flutterDescriptor['assets'] ?? const <String>[];
  }

  List<Font> _fonts;

  List<Font> get fonts {
    _fonts ??= _extractFonts();
    return _fonts;
  }

  List<Font> _extractFonts() {
    if (!_flutterDescriptor.containsKey('fonts'))
      return <Font>[];

    final List<Font> fonts = <Font>[];
    for (Map<String, dynamic> fontFamily in _flutterDescriptor['fonts']) {
      final List<Map<String, dynamic>> fontFiles = fontFamily['fonts'];
      final String familyName = fontFamily['family'];
      if (familyName == null) {
        printError('Warning: Missing family name for font.', emphasis: true);
        continue;
      }
      if (fontFiles == null) {
        printError('Warning: No fonts specified for font $familyName', emphasis: true);
        continue;
      }

      final List<FontAsset> fontAssets = <FontAsset>[];
      for (Map<String, dynamic> fontFile in fontFiles) {
        final String asset = fontFile['asset'];
        if (asset == null) {
          printError('Warning: Missing asset in fonts for $familyName', emphasis: true);
          continue;
        }

        fontAssets.add(new FontAsset(
          asset,
          weight: fontFile['weight'],
          style: fontFile['style'],
        ));
      }
      if (fontAssets.isNotEmpty)
        fonts.add(new Font(fontFamily['family'], fontAssets));
    }
    return fonts;
  }
}

class Font {
  Font(this.familyName, this.fontAssets) {
    assert(familyName != null);
    assert(fontAssets != null);
    assert(fontAssets.isNotEmpty);
  }

  final String familyName;
  final List<FontAsset> fontAssets;

  Map<String, dynamic> get descriptor {
    return <String, dynamic>{
      'family': familyName,
      'fonts': fontAssets.map((FontAsset a) => a.descriptor).toList(),
    };
  }

  @override
  String toString() => '$runtimeType(family: $familyName, assets: $fontAssets)';
}

class FontAsset {
  FontAsset(this.asset, {this.weight, this.style}) {
    assert(asset != null);
  }

  final String asset;
  final int weight;
  final String style;

  Map<String, dynamic> get descriptor {
    final Map<String, dynamic> descriptor = <String, dynamic>{};
    if (weight != null)
      descriptor['weight'] = weight;

    if (style != null)
      descriptor['style'] = style;

    descriptor['asset'] = asset;
    return descriptor;
  }

  @override
  String toString() => '$runtimeType(asset: $asset, weight; $weight, style: $style)';
}

Future<dynamic> _loadFlutterManifest(String manifestPath) async {
  if (manifestPath == null || !fs.isFileSync(manifestPath))
    return null;
  final String manifestDescriptor = await fs.file(manifestPath).readAsString();
  return loadYaml(manifestDescriptor);
}

Future<bool> _validate(Object manifest) async {
  final String schemaPath = fs.path.join(
    fs.path.absolute(Cache.flutterRoot), 'packages', 'flutter_tools', 'schema',
    'pubspec_yaml.json',
  );
  final Schema schema = await Schema.createSchemaFromUrl(fs.path.toUri(schemaPath).toString());

  final Validator validator = new Validator(schema);
  if (validator.validate(manifest)) {
    return true;
  } else {
    printStatus('Error detected in pubspec.yaml:', emphasis: true);
    printError(validator.errors.join('\n'));
    return false;
  }
}