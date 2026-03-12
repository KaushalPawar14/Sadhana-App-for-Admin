import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import 'Profile.dart';

class BoysProfilePage extends StatelessWidget {
  const BoysProfilePage({super.key});

  Widget buildUserGrid(List<Map<String, dynamic>> users, ColorProvider colorProvider) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {

        final user = users[index];
        final name = user['name'];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BoyProfileDetailsPage(
                  userId: user['id'],
                ),
              ),
            );
          },

          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.blue.shade500],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),

              border: Border.all(
                color: Colors.black.withOpacity(.3),
              ),

              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
                  blurRadius: 8,
                  offset: const Offset(0,4),
                )
              ],
            ),

            child: Row(
              children: [

                /// Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.black,
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                /// Name
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget sectionCard({
    required String title,
    required Widget child,
    required ColorProvider colorProvider,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade100, Colors.blue.shade50],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0,5),
          )
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              Container(
                width: 6,
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          child
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {

        return Scaffold(

          backgroundColor: colorProvider.color,

          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,

            title: Text(
              "Boys Profiles",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),

            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),

            builder: (context, snapshot) {

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData) {
                return const Center(child: Text("No users found"));
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
                  'role': role
                };

                if (role == 'Stay at FOLK') {
                  folkBoys.add(user);
                } else if (role == 'Stay at Hostel') {
                  hostelers.add(user);
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(18),

                child: Column(
                  children: [

                    /// FOLK SECTION
                    sectionCard(
                      title: "FOLK Boys 👦",
                      child: buildUserGrid(folkBoys, colorProvider),
                      colorProvider: colorProvider,
                    ),

                    /// HOSTEL SECTION
                    sectionCard(
                      title: "Hostelers 🏠",
                      child: buildUserGrid(hostelers, colorProvider),
                      colorProvider: colorProvider,
                    ),

                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}