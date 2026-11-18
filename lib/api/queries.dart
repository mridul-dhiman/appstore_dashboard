import 'asc_client.dart';
import 'models.dart';
import 'screenshots.dart';

// The reads the pages make, in one place: the UI asks for "the builds", not for a URL and its query parameters.

/// Builds of an app, newest first, with their pre-release version (the 1.2.3 they belong to).
Future<ResourcePage> loadBuilds(AscClient c, String appId, {int limit = 100, String? platform}) => c.all('/v1/builds', {
  'filter[app]': appId,
  'filter[preReleaseVersion.platform]': ?platform,
  'sort': '-uploadedDate',
  'limit': '$limit',
  'include': 'preReleaseVersion',
}, 1);

/// Processed, unexpired builds that can be attached to a version on [platform].
Future<List<Resource>> loadAttachableBuilds(AscClient c, String appId, String platform) async => [
  for (final b in (await loadBuilds(c, appId, limit: 30, platform: platform)).data)
    if (b.str('processingState') == 'VALID' && b.flag('expired') != true) b,
];

/// The app's App Store versions, newest first.
Future<ResourcePage> loadVersions(AscClient c, String appId) => c.page('/v1/apps/$appId/appStoreVersions', {'limit': '20'});

Future<ResourcePage> loadAppInfos(AscClient c, String appId) => c.page('/v1/apps/$appId/appInfos', {'limit': '10'});

Future<ResourcePage> loadAppInfoLocalizations(AscClient c, String appInfoId) =>
    c.all('/v1/appInfos/$appInfoId/appInfoLocalizations', {'limit': '200'}, 2);

Future<ResourcePage> loadVersionLocalizations(AscClient c, String versionId) =>
    c.all('/v1/appStoreVersions/$versionId/appStoreVersionLocalizations', {'limit': '200'}, 2);

/// Screenshots on a version localization, in display order, with their library images.
Future<ResourcePage> loadScreenshotPlacements(AscClient c, String versionLocId) => c.all(
  '/v1/appStoreVersionLocalizations/$versionLocId/placements',
  {'filter[placementType]': screenshotPlacementType, 'include': 'image', 'sort': 'placementGroupPosition', 'limit': '200'},
);

Future<ResourcePage> loadInAppPurchases(AscClient c, String appId) => c.all('/v1/apps/$appId/inAppPurchasesV2', {'limit': '200'}, 2);

Future<ResourcePage> loadSubscriptionGroups(AscClient c, String appId) =>
    c.all('/v1/apps/$appId/subscriptionGroups', {'limit': '50', 'include': 'subscriptions'}, 1);

Future<ResourcePage> loadBuildUploadHistory(AscClient c, String appId) => c.page('/v1/apps/$appId/buildUploads', {'limit': '25'});

/// Everyone on the team (for picking internal testers).
Future<List<Resource>> loadTeamUsers(AscClient c) async => (await c.all('/v1/users', {'limit': '200'})).data;

// Signing. The certificate's own content is large and never shown, so it is left out.
Future<ResourcePage> loadCertificates(AscClient c) => c.all('/v1/certificates', {
  'limit': '200',
  'fields[certificates]': 'name,displayName,certificateType,expirationDate,serialNumber,platform',
});
Future<ResourcePage> loadBundleIds(AscClient c) => c.all('/v1/bundleIds', {'limit': '200', 'sort': 'name'});
Future<ResourcePage> loadProfiles(AscClient c) => c.all('/v1/profiles', {'limit': '200'});
Future<ResourcePage> loadDevices(AscClient c) => c.all('/v1/devices', {'limit': '200', 'sort': 'name'});

const devicePlatforms = ['IOS', 'MAC_OS'];

Future<Resource> registerDevice(AscClient c, {required String name, required String udid, required String platform}) async {
  final page = await c.post('/v1/devices', {
    'data': {
      'type': 'devices',
      'attributes': {'name': name, 'udid': udid, 'platform': platform},
    },
  });
  return page.data.first;
}

// Profile regeneration: delete and recreate with all current devices.
Future<ResourcePage> loadProfileDetail(AscClient c, String profileId) =>
    c.page('/v1/profiles/$profileId', {'include': 'bundleId,certificates,devices'});

/// A profile type Apple can create, and what it needs: which certificate types sign it, which bundle and device
/// platform it is for, and whether it lists devices at all (store and Developer ID profiles do not).
class ProfileKind {
  const ProfileKind(this.type, this.label, this.platform, this.certTypes, {this.needsDevices = false});
  final String type;
  final String label;
  final String platform;
  final Set<String> certTypes;
  final bool needsDevices;

  bool fitsBundle(String? bundlePlatform) => bundlePlatform == platform || bundlePlatform == 'UNIVERSAL';
}

const profileKinds = [
  ProfileKind('IOS_APP_DEVELOPMENT', 'iOS App Development', 'IOS', {'DEVELOPMENT', 'IOS_DEVELOPMENT'}, needsDevices: true),
  ProfileKind('IOS_APP_ADHOC', 'iOS Ad Hoc', 'IOS', {'DISTRIBUTION', 'IOS_DISTRIBUTION'}, needsDevices: true),
  ProfileKind('IOS_APP_STORE', 'iOS App Store', 'IOS', {'DISTRIBUTION', 'IOS_DISTRIBUTION'}),
  ProfileKind('MAC_APP_DEVELOPMENT', 'macOS App Development', 'MAC_OS', {'DEVELOPMENT', 'MAC_APP_DEVELOPMENT'}, needsDevices: true),
  ProfileKind('MAC_APP_STORE', 'Mac App Store', 'MAC_OS', {'DISTRIBUTION', 'MAC_APP_DISTRIBUTION'}),
  ProfileKind('MAC_APP_DIRECT', 'Developer ID', 'MAC_OS', {'DEVELOPER_ID_APPLICATION', 'DEVELOPER_ID_APPLICATION_G2'}),
];

Future<void> deleteProfile(AscClient c, String profileId) => c.delete('/v1/profiles/$profileId');

Future<Resource> createProfile(
  AscClient c, {
  required String name,
  required String profileType,
  required String bundleIdResourceId,
  required List<String> certificateIds,
  required List<String> deviceIds,
}) async {
  final page = await c.post('/v1/profiles', {
    'data': {
      'type': 'profiles',
      'attributes': {'name': name, 'profileType': profileType},
      'relationships': {
        'bundleId': {
          'data': {'type': 'bundleIds', 'id': bundleIdResourceId},
        },
        'certificates': {
          'data': [
            for (final id in certificateIds) {'type': 'certificates', 'id': id},
          ],
        },
        if (deviceIds.isNotEmpty)
          'devices': {
            'data': [
              for (final id in deviceIds) {'type': 'devices', 'id': id},
            ],
          },
      },
    },
  });
  return page.data.first;
}

// Bundle ID capabilities.
Future<ResourcePage> loadBundleIdCapabilities(AscClient c, String bundleIdResourceId) =>
    c.all('/v1/bundleIds/$bundleIdResourceId/bundleIdCapabilities');

const capabilityLabels = {
  'ICLOUD': 'iCloud',
  'IN_APP_PURCHASE': 'In-App Purchase',
  'GAME_CENTER': 'Game Center',
  'PUSH_NOTIFICATIONS': 'Push Notifications',
  'WALLET': 'Wallet',
  'APPLE_PAY': 'Apple Pay',
  'MAPS': 'Maps',
  'ASSOCIATED_DOMAINS': 'Associated Domains',
  'PERSONAL_VPN': 'Personal VPN',
  'APP_GROUPS': 'App Groups',
  'HEALTHKIT': 'HealthKit',
  'HOMEKIT': 'HomeKit',
  'INTER_APP_AUDIO': 'Inter-App Audio',
  'CLASSKIT': 'ClassKit',
  'AUTOFILL_CREDENTIAL_PROVIDER': 'AutoFill Credential Provider',
  'ACCESS_WIFI_INFORMATION': 'Access WiFi Information',
  'NETWORK_EXTENSIONS': 'Network Extensions',
  'HOT_SPOT': 'Hotspot',
  'MULTIPATH': 'Multipath',
  'NFC_TAG_READING': 'NFC Tag Reading',
  'SIRIKIT': 'SiriKit',
  'USERNOTIFICATIONS_COMMUNICATION': 'Communication Notifications',
  'COREMEDIA_HLS_LOW_LATENCY': 'Low Latency HLS',
  'SYSTEM_EXTENSION_INSTALL': 'System Extension',
  'MARZIPAN': 'Mac Catalyst',
  'SIGN_IN_WITH_APPLE': 'Sign in with Apple',
  'DATA_PROTECTION': 'Data Protection',
  'FONT_INSTALLATION': 'Fonts',
};

String prettyCapability(String type) => capabilityLabels[type] ?? type.replaceAll('_', ' ').toLowerCase();

Map<String, dynamic> enableCapabilityBody(String bundleIdResourceId, String capabilityType) => {
  'data': {
    'type': 'bundleIdCapabilities',
    'attributes': {'capabilityType': capabilityType, 'settings': <dynamic>[]},
    'relationships': {
      'bundleId': {
        'data': {'type': 'bundleIds', 'id': bundleIdResourceId},
      },
    },
  },
};

Future<Resource> enableCapability(AscClient c, String bundleIdResourceId, String capabilityType) async =>
    (await c.post('/v1/bundleIdCapabilities', enableCapabilityBody(bundleIdResourceId, capabilityType))).data.first;

Future<void> disableCapability(AscClient c, String capabilityId) => c.delete('/v1/bundleIdCapabilities/$capabilityId');
