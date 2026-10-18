/// Where a student stays (`users.role`): "Stay at FOLK", "Stay at Hostel" or "Stay at Localite".
const String kRoleHostel = 'Stay at Hostel';
const String kRoleLocalite = 'Stay at Localite';

/// Hostel and Localite students file a different form (`hostel-sadhana`) that has no
/// daily-services question, so they never have daily-services data. Everyone else (FOLK
/// residents, and a student with no residence yet) does.
bool hasDailyServices(String role) {
  final r = role.trim();
  return r != kRoleHostel && r != kRoleLocalite;
}
