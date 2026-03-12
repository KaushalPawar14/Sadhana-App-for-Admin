import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/Home/Calendar.dart';
import 'package:folk_guide_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool isLoading = true;
  bool isDeleting = false;

  List<Map<String, dynamic>> folkBoys = [];
  List<Map<String, dynamic>> hostelers = [];

  final Map<String, bool> dateSavedCache = {};

  bool selectionMode = false;
  final Set<String> selectedUserIds = {};
  final Set<String> selectedUserNames = {};

  @override
  void initState() {
    super.initState();
  }

  Future<void> _fetchUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();

      final List<Map<String, dynamic>> fetchedFolkBoys = [];
      final List<Map<String, dynamic>> fetchedHostelers = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final role = data['role'] ?? '';

        final user = {
          'id': doc.id,
          'name': data['name'] ?? 'Unknown',
          'role' : role
        };

        if (role == 'Stay at FOLK') {
          fetchedFolkBoys.add(user);
        } else if (role == 'Stay at Hostel') {
          fetchedHostelers.add(user);
        }
      }

      setState(() {
        folkBoys = fetchedFolkBoys;
        hostelers = fetchedHostelers;
        isLoading = false;
      });

      _preloadDateSaved([...fetchedFolkBoys, ...fetchedHostelers]);
    } catch (e) {
      setState(() => isLoading = false);
      print("Error fetching users: $e");
    }
  }

  Future<void> _preloadDateSaved(List<Map<String, dynamic>> users) async {
    final currentDate = DateFormat('dd-MM-yyyy').format(DateTime.now());

    final futures = users.map((user) async {
      final username = user['name'];
      final role = user['role'] ?? '';

      if (!dateSavedCache.containsKey(username)) {
        try {
          final collectionName =
          role == 'Stay at Hostel' ? 'hostel-sadhana' : 'sadhana-reports';

          final docSnap = await FirebaseFirestore.instance
              .collection(collectionName)
              .doc(username)
              .collection('dates')
              .doc(currentDate)
              .get();

          dateSavedCache[username] = docSnap.exists;
        } catch (e) {
          print("Error preloading dateSaved for $username: $e");
          dateSavedCache[username] = false;
        }
      }
    }).toList();

    await Future.wait(futures);

    if (mounted) setState(() {});
  }

  void _toggleSelection({required String userId, required String userName}) {
    setState(() {
      if (selectedUserIds.contains(userId)) {
        selectedUserIds.remove(userId);
        selectedUserNames.remove(userName);
      } else {
        selectedUserIds.add(userId);
        selectedUserNames.add(userName);
      }

      if (selectedUserIds.isEmpty) selectionMode = false;
    });
  }

  void _enterSelectionMode({required String userId, required String userName}) {
    setState(() {
      selectionMode = true;
      selectedUserIds.add(userId);
      selectedUserNames.add(userName);
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      selectionMode = false;
      selectedUserIds.clear();
      selectedUserNames.clear();
    });
  }

  Future<void> _deleteSelectedUsers() async   {
    if (selectedUserIds.isEmpty) return;

    final count = selectedUserIds.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Delete $count selected user(s)? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isDeleting = true);

    final batchFutures = selectedUserIds.map((uid) async {
      // Fetch the user directly from Firestore
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!doc.exists) {
        print("Warning: User with id $uid does not exist. Skipping deletion.");
        return; // or continue if inside a loop
      }

      final username = doc['name'] ?? 'Unknown';
      final role = doc['role'] ?? '';

      final refs = [
        FirebaseFirestore.instance.collection('users').doc(uid),
        FirebaseFirestore.instance.collection('scorecard').doc(username),
        FirebaseFirestore.instance.collection('sadhana-reports').doc(username),
        FirebaseFirestore.instance.collection('notification').doc(username),
        FirebaseFirestore.instance.collection('competition').doc(username),
        FirebaseFirestore.instance.collection('hostel-sadhana').doc(username),
      ];

      await Future.wait(refs.map((ref) => ref.delete()));
    }).toList();

    try {
      await Future.wait(batchFutures);
      await _fetchUsers(); // refresh lists
      _cancelSelectionMode();

      showSnackbar(
        context,
        "Participants deleted successfully",
        Colors.deepOrange,
        Icons.delete_forever,
      );
    } catch (e) {
      print("Error deleting users: $e");
      showSnackbar(
        context,
        "Error deleting some users",
        Colors.red,
        Icons.error,
      );
    }

    setState(() => isDeleting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Stack(
        children: [
          Scaffold(
            backgroundColor: colorProvider.color,
            appBar: selectionMode
                ? _buildSelectionAppBar(colorProvider)
                : _buildNormalAppBar(colorProvider),
            body: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                final List<Map<String, dynamic>> folkBoys = [];
                final List<Map<String, dynamic>> hostelers = [];

                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final role = data['role'] ?? '';
                  final user = {
                    'id': doc.id,
                    'name': data['name'] ?? 'Unknown',
                    'role': role,
                  };

                  if (role == 'Stay at FOLK') {
                    folkBoys.add(user);
                  } else if (role == 'Stay at Hostel') {
                    hostelers.add(user);
                  }
                }

                // Preload dateSavedCache for today
                _preloadDateSaved([...folkBoys, ...hostelers]);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildUserSection("👦 FOLK Boys", folkBoys, colorProvider),
                    const SizedBox(height: 24),
                    _buildUserSection("🏠 Hostelers / Localites", hostelers, colorProvider),
                  ],
                );
              },
            ),
          ),
          if (isDeleting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      );
    });
  }

  AppBar _buildNormalAppBar(ColorProvider colorProvider) {
    return AppBar(
      elevation: 0,
      backgroundColor: colorProvider.color,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'User Dashboard',
        style: TextStyle(color: colorProvider.secondColor, fontWeight: FontWeight.bold, fontSize: 20),
      ),
      centerTitle: true,
    );
  }

  AppBar _buildSelectionAppBar(ColorProvider colorProvider) {
    final selectedCount = selectedUserIds.length;
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.red.shade700,
      leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _cancelSelectionMode),
      title: Text('$selectedCount selected', style: const TextStyle(color: Colors.white)),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.white),
          onPressed: selectedUserIds.isEmpty ? null : _deleteSelectedUsers,
        ),
      ],
    );
  }

  Widget _buildUserSection(String title, List<Map<String, dynamic>> users, ColorProvider colorProvider) {
    if (users.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(
            title,
            style: TextStyle(
              color: colorProvider.secondColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final username = (user['name'] ?? '').toString().trim();
            final isDateSaved = dateSavedCache[user['name']] ?? false;
            final isSelected = selectedUserIds.contains(user['id']);

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.grey.shade300],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (selectionMode) {
                    _toggleSelection(userId: user['id'], userName: user['name']);
                    return;
                  }

                  final username = user['name'];
                  final role = user['role'] ?? '';

                  // Preload the CalendarPage data in the background
                  final datesFuture = FirebaseFirestore.instance
                      .collection(role == 'Stay at Hostel' ? 'hostel-sadhana' : 'sadhana-reports')
                      .doc(username)
                      .collection('dates')
                      .get();

                  // Push the page immediately
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          CalendarPage(username: username, role: role),
                      transitionDuration: const Duration(milliseconds: 150), // very fast fade
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                    ),
                  );

                  // Optionally, in CalendarPage initState you can await datesFuture
                  // so the data loads faster when the page opens.
                },
                onLongPress: () => _enterSelectionMode(userId: user['id'], userName: user['name']),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blue.shade700,
                        child: Text(
                          username.isNotEmpty ? username[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          user['name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(scale: animation, child: child),
                          ),
                          child: selectionMode
                              ? Checkbox(
                            key: ValueKey('checkbox_${user['id']}'),
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(userId: user['id'], userName: user['name']),
                            checkColor: Colors.white,
                            activeColor: Colors.deepOrange.shade400,
                          )
                              : Icon(
                            isDateSaved ? Icons.check_circle : Icons.cancel,
                            key: ValueKey('status_${user['id']}'),
                            color: isDateSaved ? Colors.green : Colors.redAccent,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
