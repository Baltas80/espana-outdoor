import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:espana_outdoors/features/profile/user_profile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns null when no profile has been saved', () async {
    final store = UserProfileStore();

    expect(await store.load(), isNull);
  });

  test('saves and restores profile fields with normalised values', () async {
    final store = UserProfileStore();

    await store.save(
      const UserProfile(
        displayName: '  Alex Senderista  ',
        username: 'Alex_Outdoor',
        homeArea: '  Córdoba  ',
        bio: '  Me gusta caminar.  ',
      ),
    );

    final profile = await store.load();

    expect(profile, isNotNull);
    expect(profile!.displayName, 'Alex Senderista');
    expect(profile.username, 'alex_outdoor');
    expect(profile.homeArea, 'Córdoba');
    expect(profile.bio, 'Me gusta caminar.');
  });

  test('rejects an invalid public username', () async {
    final store = UserProfileStore();

    await expectLater(
      store.save(
        const UserProfile(
          displayName: 'Alex',
          username: 'a!',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects profile text longer than the supported limit', () async {
    final store = UserProfileStore();

    await expectLater(
      store.save(
        UserProfile(
          displayName: 'Alex',
          username: 'alex_1',
          bio: 'a' * 161,
        ),
      ),
      throwsArgumentError,
    );
  });
}
