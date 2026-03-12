import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/AllGraph.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';

class GraphPageDashboard extends StatefulWidget {
  const GraphPageDashboard({super.key});

  @override
  State<GraphPageDashboard> createState() => _GraphPageDashboardState();
}

class _GraphPageDashboardState extends State<GraphPageDashboard> {
  List<Map<String, dynamic>> folkBoys = [];
  List<Map<String, dynamic>> hostelers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
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
          'role': role,
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
    } catch (e) {
      print("Error fetching users: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          backgroundColor: colorProvider.color,
          title: Text(
            'Users for Graph',
            style: TextStyle(
                color: colorProvider.secondColor, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
            onPressed: () => Navigator.pop(context),
          ),
          elevation: 0,
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildUserSection("👦 FOLK Boys", folkBoys, colorProvider),
            const SizedBox(height: 24),
            _buildUserSection("🏠 Hostelers / Localites", hostelers, colorProvider),
          ],
        ),
      );
    });
  }

  Widget _buildUserSection(
      String title,
      List<Map<String, dynamic>> users,
      ColorProvider colorProvider,
      ) {
    if (users.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade300],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          /// SECTION TITLE
          Row(
            children: [
              Container(
                width: 5,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          /// USERS LIST
          ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (context, index) {

              final user = users[index];

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade100, Colors.blue.shade600],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.06),
                      blurRadius: 6,
                      offset: const Offset(0,3),
                    )
                  ],
                ),

                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AllGraph(
                            username: user['name'],
                            role: user['role'],
                          ),
                        ),
                      );
                    },

                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),

                      child: Row(
                        children: [

                          /// AVATAR
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withOpacity(.3),
                                  blurRadius: 8,
                                )
                              ],
                            ),

                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.black,
                              child: Text(
                                (user['name'] != null &&
                                    user['name'].isNotEmpty)
                                    ? user['name'][0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          /// NAME
                          Expanded(
                            child: Text(
                              user['name'],
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),

                          /// ARROW
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
