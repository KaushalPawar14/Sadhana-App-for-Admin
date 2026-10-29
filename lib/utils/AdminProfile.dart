import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Services/HierarchyApi.dart';

/// The four admin roles (hierarchy project). Gender is implied by role: HOD,
/// Guide and Male Enabler are male; Female Enabler is female.
///
/// The role string is exactly what the backend stores on `adminUsers.role`.
enum AdminRole { hod, guide, maleEnabler, femaleEnabler }

extension AdminRoleX on AdminRole {
  String get wire => switch (this) {
        AdminRole.hod => 'HOD',
        AdminRole.guide => 'GUIDE',
        AdminRole.maleEnabler => 'MALE_ENABLER',
        AdminRole.femaleEnabler => 'FEMALE_ENABLER',
      };

  String get label => switch (this) {
        AdminRole.hod => 'HOD',
        AdminRole.guide => 'Guide',
        AdminRole.maleEnabler => 'Male Enabler',
        AdminRole.femaleEnabler => 'Female Enabler',
      };

  /// 'male' | 'female' — the gender of the students this role may own.
  String get gender => this == AdminRole.femaleEnabler ? 'female' : 'male';

  static AdminRole fromWire(String? raw) => switch (raw) {
        'HOD' => AdminRole.hod,
        'MALE_ENABLER' => AdminRole.maleEnabler,
        'FEMALE_ENABLER' => AdminRole.femaleEnabler,
        _ => AdminRole.guide,
      };
}

/// What this admin may add (mirrors `canAddRole` in functions/hierarchyCore.js;
/// the server enforces it again).
List<AdminRole> rolesThatCanBeAddedBy(AdminRole actor) => switch (actor) {
      AdminRole.hod => AdminRole.values,
      AdminRole.guide => [AdminRole.guide, AdminRole.maleEnabler],
      AdminRole.maleEnabler => [AdminRole.maleEnabler],
      AdminRole.femaleEnabler => [AdminRole.femaleEnabler],
    };

/// Whether an admin of role [actor] may remove an admin of role [target]: delete
/// rights mirror add rights (HOD any admin, Guide Guides and Male Enablers, Male
/// Enabler Male Enablers, Female Enabler Female Enablers). Mirrors `canRemoveRole`
/// in functions/hierarchyCore.js; the server enforces it again, and also refuses
/// removing yourself or the last HOD.
bool canRemoveAdminRole(AdminRole actor, AdminRole target) =>
    rolesThatCanBeAddedBy(actor).contains(target);

/// An entry of the admin list the server returns (already filtered by the
/// visibility matrix; `email` only for a HOD viewer or for yourself).
class AdminSummary {
  const AdminSummary({
    required this.id,
    required this.displayName,
    required this.role,
    required this.teamGuide,
    this.email,
    this.boardColumn,
  });

  final String id;
  final String displayName;
  final AdminRole role;
  final String teamGuide;
  final String? email;

  /// What the server did to this admin's column on the FOLK Boys board when it added or changed them: `created`, `updated`,
  /// `unchanged`, `no-board` (no board exists yet) or `failed`. Null when the answer did not say.
  final String? boardColumn;

  factory AdminSummary.fromMap(Map<String, dynamic> m) => AdminSummary(
        id: (m['id'] ?? '').toString(),
        displayName: (m['displayName'] ?? m['id'] ?? '').toString(),
        role: AdminRoleX.fromWire(m['role']?.toString()),
        teamGuide: (m['teamGuide'] ?? '').toString(),
        email: m['email']?.toString(),
        boardColumn: m['boardColumn']?.toString(),
      );
}

/// One notification type the Guide app can receive (stable key from
/// functions/routing.js). `scope` is 'student' (the "whose students" switches
/// apply) or 'general' (only the type switch applies).
class NotificationTypeInfo {
  const NotificationTypeInfo(this.key, this.label, this.scope);
  final String key;
  final String label;
  final String scope;
}

/// The signed-in admin, as the server sees them.
class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.displayName,
    required this.role,
    required this.teamGuide,
    required this.email,
    required this.groupPrefs,
    required this.typePrefs,
    required this.notificationTypes,
    required this.admins,
  });

  final String id;
  final String displayName;
  final AdminRole role;
  final String teamGuide;
  final String email;

  /// `notificationPrefs.groups` — keys "own", "unassigned", "admin:<id>".
  final Map<String, bool> groupPrefs;

  /// `notificationPrefs.types` — keys from [notificationTypes].
  final Map<String, bool> typePrefs;
  final List<NotificationTypeInfo> notificationTypes;

  /// Admins this viewer may see (server-filtered), including yourself.
  final List<AdminSummary> admins;

  bool get isHod => role == AdminRole.hod;
  bool get isGuide => role == AdminRole.guide;
  bool get isMaleEnabler => role == AdminRole.maleEnabler;
  bool get isFemaleEnabler => role == AdminRole.femaleEnabler;

  /// Gender of the students this admin may own / claim.
  String get gender => role.gender;

  /// The Male Enablers on this Guide's team.
  List<AdminSummary> get myMaleEnablers => admins
      .where((a) => a.role == AdminRole.maleEnabler && a.teamGuide == id)
      .toList();

  /// Every admin whose students may be shown as a column / switch for this
  /// viewer (the admin list already follows the visibility matrix).
  AdminSummary? adminById(String id) {
    for (final a in admins) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// A Guide's per-Male-Enabler switches default OFF; everything else ON.
  bool groupOn(String key) {
    final v = groupPrefs[key];
    if (v != null) return v;
    return !(isGuide && key.startsWith('admin:'));
  }

  bool typeOn(String key) => typePrefs[key] ?? true;

  AdminProfile withPrefs({
    Map<String, bool>? groups,
    Map<String, bool>? types,
  }) =>
      AdminProfile(
        id: id,
        displayName: displayName,
        role: role,
        teamGuide: teamGuide,
        email: email,
        groupPrefs: groups ?? groupPrefs,
        typePrefs: types ?? typePrefs,
        notificationTypes: notificationTypes,
        admins: admins,
      );

  static Map<String, bool> _boolMap(Object? raw) {
    final out = <String, bool>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is bool) out[k.toString()] = v;
      });
    }
    return out;
  }

  /// The same shape the server's `getAdminProfile` answers with ([AdminProfile.fromMap] reads
  /// it back), so the profile can be cached on this device.
  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'role': role.wire,
        'teamGuide': teamGuide,
        'email': email,
        'notificationPrefs': {'groups': groupPrefs, 'types': typePrefs},
        'notificationTypes': [
          for (final t in notificationTypes) {'key': t.key, 'label': t.label, 'scope': t.scope},
        ],
        'admins': [
          for (final a in admins)
            {
              'id': a.id,
              'displayName': a.displayName,
              'role': a.role.wire,
              'teamGuide': a.teamGuide,
              if (a.email != null) 'email': a.email,
            },
        ],
      };

  factory AdminProfile.fromMap(Map<String, dynamic> m) {
    final prefs = m['notificationPrefs'];
    final types = <NotificationTypeInfo>[
      for (final t in (m['notificationTypes'] as List? ?? const []))
        if (t is Map)
          NotificationTypeInfo(
            (t['key'] ?? '').toString(),
            (t['label'] ?? '').toString(),
            (t['scope'] ?? 'student').toString(),
          ),
    ];
    return AdminProfile(
      id: (m['id'] ?? '').toString(),
      displayName: (m['displayName'] ?? m['id'] ?? '').toString(),
      role: AdminRoleX.fromWire(m['role']?.toString()),
      teamGuide: (m['teamGuide'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
      groupPrefs: _boolMap(prefs is Map ? prefs['groups'] : null),
      typePrefs: _boolMap(prefs is Map ? prefs['types'] : null),
      notificationTypes: types,
      admins: [
        for (final a in (m['admins'] as List? ?? const []))
          if (a is Map) AdminSummary.fromMap(Map<String, dynamic>.from(a)),
      ],
    );
  }
}

/// Holds the signed-in admin's profile for the whole app (a Provider, plus a
/// static [current] for code that has no BuildContext — query helpers, services).
///
/// Loaded once after sign-in via the `getAdminProfile` callable; screens never
/// read `adminUsers` themselves. `isHod` etc. replace every old
/// `guide == kHodGuideId` check (several HODs are possible; no id is special).
/// What [AdminProfileProvider.revalidate] found when it asked the server again.
enum ProfileRefresh {
  /// The same profile.
  unchanged,

  /// Something that does not change what the app shows structurally (preferences, the admin
  /// list, a display name): the provider already holds the new one and has notified.
  updated,

  /// The id, role or team changed: who sees what is different, so the shell must be rebuilt.
  restructured,

  /// The server says this account is no longer a registered admin: sign out.
  removed,

  /// The server could not be reached: keep what we have.
  offline,
}

class AdminProfileProvider extends ChangeNotifier {
  AdminProfileProvider._();
  static final AdminProfileProvider instance = AdminProfileProvider._();

  /// The last profile the server gave this device (role, display name, team, preferences, the
  /// admins this viewer may see), kept so the app can open at once on the next launch. It is
  /// only ever used for a signed-in user whose email matches it, is refreshed from the server in
  /// the background on every launch, and is deleted on sign-out. The server enforces every
  /// permission again on every read and write; this is only what the screens were built from.
  static const String cacheKey = 'admin_profile_cache_v1';

  /// The cached profile for [email] (case-insensitive), or null.
  Future<AdminProfile?> readCache(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = AdminProfile.fromMap(Map<String, dynamic>.from(decoded));
      if (profile.id.isEmpty || profile.email.trim().toLowerCase() != email.trim().toLowerCase()) {
        return null;
      }
      return profile;
    } catch (_) {
      return null; // a damaged cache is no cache: the normal (slower) path runs
    }
  }

  Future<void> _writeCache(AdminProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(profile.toMap()));
    } catch (_) {}
  }

  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
    } catch (_) {}
  }

  /// Makes [profile] (from the cache) the current one without asking the server.
  void restore(AdminProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  /// Asks the server again (in the background, after the app is showing) and reports what
  /// changed; the cache and the current profile follow the answer.
  Future<ProfileRefresh> revalidate({HierarchyApi? api}) async {
    final before = _profile;
    final AdminProfile? fetched;
    try {
      fetched = await (api ?? HierarchyApi.instance).getAdminProfile();
    } catch (_) {
      return ProfileRefresh.offline;
    }
    if (fetched == null) return ProfileRefresh.removed;
    _profile = fetched;
    await _writeCache(fetched);
    notifyListeners();
    if (before == null ||
        before.id != fetched.id ||
        before.role != fetched.role ||
        before.teamGuide != fetched.teamGuide) {
      return ProfileRefresh.restructured;
    }
    return jsonEncode(before.toMap()) == jsonEncode(fetched.toMap())
        ? ProfileRefresh.unchanged
        : ProfileRefresh.updated;
  }

  AdminProfile? _profile;
  AdminProfile? get profile => _profile;

  /// The loaded profile, or null before sign-in completes.
  static AdminProfile? get current => instance._profile;

  /// The loaded profile; throws if a screen is built before sign-in finished
  /// (the splash and the sign-in page always await [load] first).
  static AdminProfile require() {
    final p = instance._profile;
    if (p == null) {
      throw StateError('Admin profile not loaded yet');
    }
    return p;
  }

  /// Whether the signed-in admin is a HOD. False while nothing is loaded.
  static bool get viewerIsHod => instance._profile?.isHod ?? false;

  /// Installs a profile directly (tests).
  @visibleForTesting
  void debugSet(AdminProfile? p) {
    _profile = p;
    notifyListeners();
  }

  /// Fetches the profile. Returns null when this account is not a registered
  /// admin (the caller then signs out and shows "not registered").
  Future<AdminProfile?> load({HierarchyApi? api}) async {
    final fetched = await (api ?? HierarchyApi.instance).getAdminProfile();
    _profile = fetched;
    if (fetched != null) {
      await _writeCache(fetched);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_guide', fetched.id);
      } catch (_) {}
    }
    notifyListeners();
    return fetched;
  }

  /// Re-reads the profile (after adding/removing an admin, changing prefs...).
  Future<void> refresh({HierarchyApi? api}) async {
    try {
      final fetched = await (api ?? HierarchyApi.instance).getAdminProfile();
      if (fetched != null) {
        _profile = fetched;
        notifyListeners();
      }
    } catch (_) {
      // keep the profile we have
    }
  }

  void applyPrefs({Map<String, bool>? groups, Map<String, bool>? types}) {
    final p = _profile;
    if (p == null) return;
    _profile = p.withPrefs(groups: groups, types: types);
    notifyListeners();
  }

  void clear() {
    _profile = null;
    clearCache();
    notifyListeners();
  }
}
