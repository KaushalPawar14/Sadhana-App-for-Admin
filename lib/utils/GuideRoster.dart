/// Admin-name and email validation helpers.
///
/// The roster itself, the signed-in admin's identity and every admin change now
/// come from the server (`getAdminProfile`, `listAdmins`, `addAdmin`,
/// `updateAdmin`, `removeAdmin` — see `Services/HierarchyApi.dart`); the app never
/// reads or writes `adminUsers` directly, and no admin id (not even the original
/// HOD's) is special.
library;

/// Rules for a NEW admin name (the permanent admin id): same as the server's.
/// Returns an error message, or null when the name is acceptable.
String? validateNewGuideName(String raw, List<String> existing) {
  final name = raw.trim();

  if (name.isEmpty) return "Enter a name";
  if (name.length > 24) return "Keep it under 24 characters";

  // Firestore document ids cannot contain these.
  if (name.contains('/') || name.contains('.')) {
    return "No slashes or dots";
  }

  final lower = name.toLowerCase();
  if (existing.any((e) => e.toLowerCase() == lower)) {
    return "$name already exists";
  }

  return null;
}

/// Lowercased, trimmed — the server compares admin emails this way.
String normalizeAdminEmail(String email) => email.trim().toLowerCase();

/// Same shape as the Student app's own registration email check.
final RegExp kAdminEmailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
