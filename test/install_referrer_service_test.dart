import 'package:debatly/services/install_referrer_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Install attribution is a one-shot, unrepeatable read (the Play referrer
/// expires 90 days after install), so the service's delivery contract is what
/// these tests pin down: fetch at most once per launch with a bounded retry
/// budget, cache the payload, and re-send it every launch until one insert is
/// confirmed — never losing the referrer to a flaky first launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReferrerDetails details(String? referrer) =>
      ReferrerDetails(referrer, 1700000100, 1700000200, 0, 0, '1.0.7', false);

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  group('parseUtm', () {
    test('extracts the standard utm parameters and ignores the rest', () {
      final utm = InstallReferrerService.parseUtm(
        'utm_source=tiktok&utm_medium=cpc&utm_campaign=launch'
        '&utm_content=video1&gclid=abc123',
      );
      expect(utm, {
        'utm_source': 'tiktok',
        'utm_medium': 'cpc',
        'utm_campaign': 'launch',
        'utm_content': 'video1',
      });
    });

    test('decodes a referrer that arrived url-encoded one level too deep', () {
      final utm = InstallReferrerService.parseUtm(
        'utm_source%3Dtiktok%26utm_medium%3Dcpc',
      );
      expect(utm, {'utm_source': 'tiktok', 'utm_medium': 'cpc'});
    });

    test('never throws on garbage, null, or empty input', () {
      expect(InstallReferrerService.parseUtm(null), isEmpty);
      expect(InstallReferrerService.parseUtm(''), isEmpty);
      expect(InstallReferrerService.parseUtm('not a query string %%%'), isEmpty);
      expect(InstallReferrerService.parseUtm('organic'), isEmpty);
    });
  });

  group('propertiesFrom', () {
    test('maps details to lean event properties', () {
      final props = InstallReferrerService.propertiesFrom(
        details('utm_source=newsletter&utm_campaign=summer'),
      );
      expect(props['status'], 'ok');
      expect(props['referrer'], 'utm_source=newsletter&utm_campaign=summer');
      expect(props['utm_source'], 'newsletter');
      expect(props['utm_campaign'], 'summer');
      expect(props['referrer_click_ts'], 1700000100);
      expect(props['install_begin_ts'], 1700000200);
      expect(props['install_version'], '1.0.7');
      // False is the overwhelmingly common case — omitted to keep rows lean.
      expect(props.containsKey('google_play_instant'), isFalse);
    });

    test('omits the referrer key entirely when Play returned none', () {
      final props = InstallReferrerService.propertiesFrom(details(null));
      expect(props['status'], 'ok');
      expect(props.containsKey('referrer'), isFalse);
      expect(props.containsKey('utm_source'), isFalse);
    });
  });

  group('reportIfNeeded', () {
    test('happy path: fetches once, sends, and never runs again', () async {
      final prefs = await freshPrefs();
      var fetches = 0;
      final sentEvents = <(String, Map<String, Object?>)>[];

      Future<void> run({required bool sendSucceeds}) =>
          InstallReferrerService.reportIfNeeded(
            prefs,
            fetch: () async {
              fetches++;
              return details('utm_source=tiktok&utm_medium=cpc');
            },
            send: (event, props) async {
              sentEvents.add((event, props));
              return sendSucceeds;
            },
          );

      await run(sendSucceeds: true);
      expect(fetches, 1);
      expect(sentEvents, hasLength(1));
      expect(sentEvents.single.$1, 'install_attributed');
      expect(sentEvents.single.$2['utm_source'], 'tiktok');
      expect(prefs.getBool(kReferrerLoggedPrefKey), isTrue);
      expect(prefs.getString(kReferrerPayloadPrefKey), isNull);

      // Once delivered, later launches are a complete no-op.
      await run(sendSucceeds: true);
      expect(fetches, 1);
      expect(sentEvents, hasLength(1));
    });

    test(
      'failed send caches the payload; the retry re-sends WITHOUT re-fetching',
      () async {
        final prefs = await freshPrefs();
        var fetches = 0;
        var sends = 0;

        await InstallReferrerService.reportIfNeeded(
          prefs,
          fetch: () async {
            fetches++;
            return details('utm_source=tiktok');
          },
          send: (_, _) async {
            sends++;
            return false; // offline first launch
          },
        );
        expect(fetches, 1);
        expect(prefs.getBool(kReferrerLoggedPrefKey), isNull);
        expect(prefs.getString(kReferrerPayloadPrefKey), isNotNull);

        // Next launch: the referrer must NOT be read again (Google says read
        // once; it may also have expired) — the cached payload is what ships.
        Map<String, Object?>? delivered;
        await InstallReferrerService.reportIfNeeded(
          prefs,
          fetch: () async => fail('must not re-fetch a cached referrer'),
          send: (_, props) async {
            sends++;
            delivered = props;
            return true;
          },
        );
        expect(fetches, 1);
        expect(sends, 2);
        expect(delivered?['utm_source'], 'tiktok');
        expect(prefs.getBool(kReferrerLoggedPrefKey), isTrue);
      },
    );

    test(
      'fetch failures retry across launches, then record status=unavailable',
      () async {
        final prefs = await freshPrefs();
        final sentEvents = <Map<String, Object?>>[];

        Future<void> run() => InstallReferrerService.reportIfNeeded(
          prefs,
          fetch: () async => throw Exception('SERVICE_UNAVAILABLE'),
          send: (_, props) async {
            sentEvents.add(props);
            return true;
          },
        );

        // Launches 1 and 2: burn attempts silently, nothing sent yet.
        await run();
        await run();
        expect(sentEvents, isEmpty);
        expect(prefs.getInt(kReferrerAttemptsPrefKey), 2);

        // Launch 3 (== kMaxFetchAttempts): give up and log the install as
        // unattributable so it still gets its one funnel row.
        await run();
        expect(sentEvents, hasLength(1));
        expect(sentEvents.single['status'], 'unavailable');
        expect(sentEvents.single['error'], contains('SERVICE_UNAVAILABLE'));
        expect(prefs.getBool(kReferrerLoggedPrefKey), isTrue);
      },
    );

    test('skips entirely on non-Android platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final prefs = await freshPrefs();
      await InstallReferrerService.reportIfNeeded(
        prefs,
        fetch: () async => fail('must not touch the referrer API off-Android'),
        send: (_, _) async => fail('nothing to send off-Android'),
      );
      // No attempts burned either — iOS must not eat the Android retry budget
      // (irrelevant per-device, but keeps the invariant honest).
      expect(prefs.getInt(kReferrerAttemptsPrefKey), isNull);
    });
  });
}
