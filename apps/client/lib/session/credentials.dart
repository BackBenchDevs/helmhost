import '../session_helpers.dart';
import '../storage/credential_store.dart';

/// Session memory wins over permanent vault; entry vault wins over profile vault.
Future<String?> resolvePassword({
  required ICredentialStore store,
  required String entryId,
  String? sessionPassword,
  String? profileId,
}) async {
  if (sessionPassword != null && sessionPassword.isNotEmpty) {
    return sessionPassword;
  }
  final entryPwd = await store.readPassword(entryId);
  if (entryPwd != null && entryPwd.isNotEmpty) return entryPwd;
  if (profileId != null && profileId.isNotEmpty) {
    final groupPwd = await store.readPassword(profileVaultKey(profileId));
    if (groupPwd != null && groupPwd.isNotEmpty) return groupPwd;
  }
  return null;
}

/// Entry username wins over profile `default_username` (group shared account).
String? resolveUsername({
  String? entryUsername,
  String? profileDefaultUsername,
}) {
  if (entryUsername != null && entryUsername.trim().isNotEmpty) {
    return entryUsername.trim();
  }
  if (profileDefaultUsername != null &&
      profileDefaultUsername.trim().isNotEmpty) {
    return profileDefaultUsername.trim();
  }
  return null;
}

bool isAuthError(Object e) {
  final msg = e is StateError ? e.message : e.toString();
  return parseAuthNeed(msg) != AuthNeed.none;
}

String authErrorLabel(Object e) {
  final need = parseAuthNeed(e is StateError ? e.message : e.toString());
  return switch (need) {
    AuthNeed.usernamePassword => 'Username and password required',
    AuthNeed.password => 'Password required',
    AuthNeed.none => e.toString(),
  };
}

/// Persist or clear vault passwords without wiping on ordinary connects.
///
/// - [savePassword] true + non-empty [password] → write
/// - [clearPassword] true → delete (editor unchecked “Save password”)
/// - otherwise → no-op (preserve existing vault entry)
Future<void> persistEntryCredentials(
  ICredentialStore store,
  String entryId, {
  String? password,
  required bool savePassword,
  bool clearPassword = false,
}) async {
  if (savePassword && password != null && password.isNotEmpty) {
    await store.writePassword(entryId, password);
  } else if (clearPassword) {
    await store.deletePassword(entryId);
  }
}

/// Persist shared group password under `profile:{id}`.
Future<void> persistProfileCredentials(
  ICredentialStore store,
  String profileId, {
  String? password,
  required bool savePassword,
  bool clearPassword = false,
}) async {
  final key = profileVaultKey(profileId);
  if (savePassword && password != null && password.isNotEmpty) {
    await store.writePassword(key, password);
  } else if (clearPassword) {
    await store.deletePassword(key);
  }
}

/// Write group shared Unix username onto the profile JSON (not the vault).
void upsertProfileDefaultUsername({
  required void Function(Map<String, dynamic> profile) profileUpsert,
  required ConnectionProfileCard profile,
  required String username,
}) {
  final u = username.trim();
  if (u.isEmpty) return;
  if ((profile.defaultUsername ?? '').trim() == u) return;
  profileUpsert(profile.copyWith(defaultUsername: u).toJson());
}

ConnectionProfileCard? findProfileById(
  Iterable<ConnectionProfileCard> profiles,
  String? profileId,
) {
  if (profileId == null || profileId.isEmpty) return null;
  for (final p in profiles) {
    if (p.id == profileId) return p;
  }
  return null;
}
