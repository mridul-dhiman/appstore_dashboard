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
}
