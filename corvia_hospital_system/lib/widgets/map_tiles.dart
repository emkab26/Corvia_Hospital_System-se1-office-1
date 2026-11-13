import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/env.dart';

const _osmUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgentPackageName = 'com.corvia.mycorvia';

/// Base tile layer shared by every in-app map.
///
/// MapTiler is the primary source when a key is configured, with the public
/// OpenStreetMap tiles as a fallback in two ways: at config time when no key is
/// set, and per-tile via [TileLayer.fallbackUrl] when an individual MapTiler
/// request fails. Without a key the map runs entirely on OpenStreetMap.
TileLayer mapTileLayer() {
  final key = Env.mapTilerKey;
  if (key == null) {
    return TileLayer(
      urlTemplate: _osmUrlTemplate,
      userAgentPackageName: _userAgentPackageName,
    );
  }
  return TileLayer(
    urlTemplate:
        'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$key',
    fallbackUrl: _osmUrlTemplate,
    userAgentPackageName: _userAgentPackageName,
  );
}

/// Attribution overlay matching [mapTileLayer]. Credits both providers when a
/// MapTiler key is active, since tiles may come from either at runtime.
Widget mapAttribution() {
  final source = Env.mapTilerKey == null
      ? 'OpenStreetMap contributors'
      : 'MapTiler, OpenStreetMap contributors';
  return SimpleAttributionWidget(source: Text(source));
}
