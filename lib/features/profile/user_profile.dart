/// Shared public profile returned by the España Outdoor profile API.
///
/// The account identity and password are managed by Keycloak, never by this
/// model. The API associates this profile with the authenticated OIDC subject.
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
