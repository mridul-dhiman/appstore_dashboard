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
Future<ResourcePage> loadProfiles(AscClient c) =>
    c.all('/v1/profiles', {'limit': '200', 'fields[profiles]': 'name,profileType,profileState,expirationDate,createdDate'});
Future<ResourcePage> loadDevices(AscClient c) => c.all('/v1/devices', {'limit': '200', 'sort': 'name'});
