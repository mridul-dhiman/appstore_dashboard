import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:appstore_dashboard/services/vault.dart';
import 'package:appstore_dashboard/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';
import 'support/fake_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('vault', () {
    test('what this app wrote reads back; anything else is marked unreadable, not empty', () {
      final ok = parseVault('{"accounts":[{"keyId":"K","issuerId":"I","privateKeyPem":"P"}],"activeId":"I:K"}');
      expect(ok.unreadable, isFalse);
      expect(ok.active!.keyId, 'K');
      expect(parseVault('not json').unreadable, isTrue);
      expect(parseVault('{"accounts":"nope"}').unreadable, isTrue);
    });

    test('an unreadable save sends you to setup with an explanation, and nothing is written over it', () async {
      final h = StateHarness((_) => null, vault: const VaultData(unreadable: true));
      await h.state.unlock();
      expect(h.state.phase, Phase.setup);
      expect(h.state.message, contains(Vault.backupKey));
      expect(h.vault.writes, 0);
    });

    test('connecting a key afterwards clears the warning', () async {
      final h = StateHarness((r) => json({'data': [{'type': 'apps', 'id': 'A1', 'attributes': {'name': 'App'}}]}), vault: const VaultData(unreadable: true));
      await h.state.unlock();
      await h.state.connect(testCreds);
      expect(h.state.message, isNull);
      expect(h.state.phase, Phase.ready);
    });
  });

  group('keychain failures', () {
    test('a keychain read error after unlocking leaves the app locked with the reason, not spinning', () async {
      final h = StateHarness((_) => null);
      h.vault.failRead = Exception('errSecInteractionNotAllowed');
      await h.state.unlock();
      expect(h.state.phase, Phase.locked);
      expect(h.state.unlocking, isFalse);
      expect(h.state.message, contains('errSecInteractionNotAllowed'));
    });

    test('a key that cannot be saved is not shown as connected', () async {
      final h = StateHarness((r) => json({'data': []}), vault: const VaultData());
      await h.state.unlock();
      h.vault.failWrite = Exception('keychain full');
      await expectLater(h.state.connect(testCreds), throwsA(isA<Exception>()));
      expect(h.state.phase, Phase.setup);
      expect(h.state.accounts, isEmpty);
    });

    test('switching clients waits for the save and reports a failure', () async {
      const other = Credentials(keyId: 'OTHERKEY12', issuerId: '00000000-0000-0000-0000-000000000000', privateKeyPem: testKeyPem);
      final h = StateHarness((_) => null, vault: VaultData(accounts: const [testCreds, other], activeId: testCreds.id));
      await h.state.unlock();
      h.vault.failWrite = Exception('nope');
      await expectLater(h.state.switchTo(other.id), throwsA(isA<Exception>()));
    });
  });
}
