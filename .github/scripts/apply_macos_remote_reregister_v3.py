from pathlib import Path

remote_path = Path('lib/services/remote_provisioning_service.dart')
provider_path = Path('lib/providers/iptv_provider.dart')

remote = remote_path.read_text()
provider = provider_path.read_text()

credential_class = '''class RemoteDeviceCredentials {
  final String code;
  final String secret;

  const RemoteDeviceCredentials({required this.code, required this.secret});
}
'''
exception_block = credential_class + '''
class RemoteDeviceCredentialsInvalidException implements Exception {
  const RemoteDeviceCredentialsInvalidException();

  @override
  String toString() => 'La vinculación de este dispositivo ya no es válida.';
}
'''
if 'class RemoteDeviceCredentialsInvalidException' not in remote:
    if credential_class not in remote:
        raise SystemExit('RemoteDeviceCredentials block not found')
    remote = remote.replace(credential_class, exception_block, 1)

load_credentials_end = '''    return RemoteDeviceCredentials(code: code, secret: secret);
  }

  Future<RemoteDeviceCredentials> ensureRegistered() async {
'''
clear_credentials_block = '''    return RemoteDeviceCredentials(code: code, secret: secret);
  }

  Future<void> clearCredentials() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceCodeKey);
    await prefs.remove(_deviceSecretKey);
  }

  Future<RemoteDeviceCredentials> ensureRegistered() async {
'''
if 'Future<void> clearCredentials()' not in remote:
    if load_credentials_end not in remote:
        raise SystemExit('ensureRegistered anchor not found')
    remote = remote.replace(load_credentials_end, clear_credentials_block, 1)

old_401 = """    if (response.statusCode == 401) {
      throw Exception('La vinculación de este dispositivo ya no es válida.');
    }
"""
new_401 = """    if (response.statusCode == 401) {
      throw const RemoteDeviceCredentialsInvalidException();
    }
"""
if old_401 in remote:
    remote = remote.replace(old_401, new_401, 1)
elif 'throw const RemoteDeviceCredentialsInvalidException();' not in remote:
    raise SystemExit('401 handling anchor not found')

remote = remote.replace("'app_version': '1.0.0+1-mac-remote-v1',", "'app_version': '1.0.0+1-mac-remote-v3',")

old_sync = '''      final credentials = await _remoteProvisioning.ensureRegistered();
      _remoteDeviceCode = credentials.code;
      notifyListeners();

      final configuration = await _remoteProvisioning.fetchConfiguration(
        credentials,
      );
      _remoteDeviceCode = configuration.deviceCode;
'''
new_sync = '''      var credentials = await _remoteProvisioning.ensureRegistered();
      _remoteDeviceCode = credentials.code;
      notifyListeners();

      RemoteProvisioningConfiguration configuration;
      try {
        configuration = await _remoteProvisioning.fetchConfiguration(
          credentials,
        );
      } on RemoteDeviceCredentialsInvalidException {
        // Si el administrador borró este dispositivo del panel, olvidamos
        // únicamente la identidad remota local y pedimos un código nuevo.
        // Un dispositivo marcado como INACTIVO devuelve 403 y NO entra acá,
        // por lo que sigue bloqueado hasta que el administrador lo reactive.
        await _remoteProvisioning.clearCredentials();
        credentials = await _remoteProvisioning.ensureRegistered();
        _remoteDeviceCode = credentials.code;
        notifyListeners();
        configuration = await _remoteProvisioning.fetchConfiguration(
          credentials,
        );
      }
      _remoteDeviceCode = configuration.deviceCode;
'''
if old_sync in provider:
    provider = provider.replace(old_sync, new_sync, 1)
elif 'on RemoteDeviceCredentialsInvalidException' not in provider:
    raise SystemExit('syncRemoteServices anchor not found')

remote_path.write_text(remote)
provider_path.write_text(provider)
print('macOS remote re-registration V3 patch applied')
