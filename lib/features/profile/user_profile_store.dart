import 'package:shared_preferences/shared_preferences.dart';

/// Public, non-sensitive profile information stored on this device.
///
/// Authentication credentials are deliberately managed separately by OIDC.
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.username,
    this.homeArea = '',
    this.bio = '',
  });

  final String displayName;
  final String username;
  final String homeArea;
  final String bio;
}

/// Local persistence for editable profile fields.
///
/// SharedPreferences is already part of España Outdoor's dependency set.
/// This store does not claim to synchronise data with a remote account.
class UserProfileStore {
  static const _displayNameKey = 'espana_outdoor.profile.display_name';
  static const _usernameKey = 'espana_outdoor.profile.username';
  static const _homeAreaKey = 'espana_outdoor.profile.home_area';
  static const _bioKey = 'espana_outdoor.profile.bio';

  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,19}$');

  Future<UserProfile?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final displayName = preferences.getString(_displayNameKey)?.trim();
    final username = preferences.getString(_usernameKey)?.trim();

    if (displayName == null ||
        displayName.isEmpty ||
        username == null ||
        username.isEmpty) {
      return null;
    }

    return UserProfile(
      displayName: displayName,
      username: username,
      homeArea: preferences.getString(_homeAreaKey) ?? '',
      bio: preferences.getString(_bioKey) ?? '',
    );
  }

  Future<void> save(UserProfile profile) async {
    final displayName = profile.displayName.trim();
    final username = profile.username.trim().toLowerCase();
    final homeArea = profile.homeArea.trim();
    final bio = profile.bio.trim();

    if (displayName.length < 2 || displayName.length > 50) {
      throw ArgumentError.value(
        profile.displayName,
        'displayName',
        'Must contain 2 to 50 characters.',
      );
    }
    if (!_usernamePattern.hasMatch(username)) {
      throw ArgumentError.value(
        profile.username,
        'username',
        'Must contain 3 to 20 lowercase letters, numbers, dots, hyphens or underscores, and start with a letter or number.',
      );
    }
    if (homeArea.length > 80) {
      throw ArgumentError.value(
        profile.homeArea,
        'homeArea',
        'Must contain at most 80 characters.',
      );
    }
    if (bio.length > 160) {
      throw ArgumentError.value(
        profile.bio,
        'bio',
        'Must contain at most 160 characters.',
      );
    }

    final preferences = await SharedPreferences.getInstance();
    final results = await Future.wait<bool>([
      preferences.setString(_displayNameKey, displayName),
      preferences.setString(_usernameKey, username),
      preferences.setString(_homeAreaKey, homeArea),
      preferences.setString(_bioKey, bio),
    ]);

    if (results.any((saved) => !saved)) {
      throw StateError('Could not save the complete profile.');
    }
  }
}
