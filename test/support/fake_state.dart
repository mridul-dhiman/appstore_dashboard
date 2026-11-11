import 'dart:convert';

import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:appstore_dashboard/services/device_lock.dart';
import 'package:appstore_dashboard/services/vault.dart';
import 'package:appstore_dashboard/state/app_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_asc.dart';

/// Keeps the saved clients in memory instead of the keychain.
class MemoryVault extends Vault {
  MemoryVault([this.data = const VaultData()]);
  VaultData data;
  int writes = 0;
  Object? failRead;
  Object? failWrite;

  @override
  bool get persistent => true;

  @override
  Future<VaultData> read() async {
    if (failRead != null) throw failRead!;
    return data;
  }

  @override
  Future<void> write(VaultData d) async {
    if (failWrite != null) throw failWrite!;
    writes++;
    data = d;
  }
}

class FakeLock extends DeviceLock {
  FakeLock([this.result = UnlockResult.unlocked]);
  UnlockResult result;

  @override
  bool get supported => true;

  @override
  Future<UnlockResult> unlock({String reason = ''}) async => result;
}

/// A mock HTTP client that, like the real one, refuses to work once closed.
class ClosableClient extends http.BaseClient {
  ClosableClient(this._inner);
  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closed) throw http.ClientException('Client is already closed.', request.url);
    return _inner.send(request);
  }

  @override
  void close() => closed = true;
}

const testCreds = Credentials(keyId: 'TESTKEY123', issuerId: '00000000-0000-0000-0000-000000000000', privateKeyPem: testKeyPem, name: 'Test');

/// An [AppState] whose clients answer from [responder]. Every request is recorded in [log].
class StateHarness {
  StateHarness(Responder responder, {VaultData? vault, UnlockResult unlock = UnlockResult.unlocked})
      : vault = MemoryVault(vault ?? const VaultData(accounts: [testCreds], activeId: '00000000-0000-0000-0000-000000000000:TESTKEY123')),
        lock = FakeLock(unlock) {
    state = AppState(
      lock: lock,
      vault: this.vault,
      httpClient: () {
        final c = ClosableClient(MockClient((req) async {
          Map<String, dynamic>? body;
          if (req.body.isNotEmpty) body = (jsonDecode(req.body) as Map).cast<String, dynamic>();
          final rec = Recorded(req.method, req.url.path + (req.url.hasQuery ? '?${req.url.query}' : ''), body);
          log.add(rec);
          return responder(rec) ?? http.Response(jsonEncode({'errors': [{'title': 'Unexpected', 'detail': rec.toString()}]}), 500);
        }));
        clients.add(c);
        return c;
      },
    );
  }

  final MemoryVault vault;
  final FakeLock lock;
  late final AppState state;
  final log = <Recorded>[];
  final clients = <ClosableClient>[];
}
