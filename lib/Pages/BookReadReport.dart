import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';

class BookReadingScreen extends StatefulWidget {
  const BookReadingScreen({super.key});

  @override
  State<BookReadingScreen> createState() => _CheckSadhanaScreenState();
}

class _CheckSadhanaScreenState extends State<BookReadingScreen> {

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {

        return Scaffold(
          backgroundColor: colorProvider.color,

          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: colorProvider.secondColor,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(
              'Books Read',
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('booksRead')
                .snapshots(),

            builder: (context, snapshot) {

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text("Error: ${snapshot.error}"),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text("No books found."),
                );
              }

              final books = snapshot.data!.docs;

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: books.length,
                physics: const BouncingScrollPhysics(),

                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200, // max width of each card
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 180, // flexible height
                ),

                itemBuilder: (context, index) {

                  final name = books[index].id;
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : "?";

                  return InkWell(
                    borderRadius: BorderRadius.circular(20),

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentDetailScreen(student: name),
                        ),
                      );
                    },

                    child: Container(
                      padding: const EdgeInsets.all(16),

                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade300,
                            Colors.blue.shade100,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),

                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [

                          /// Avatar
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white.withOpacity(.4),
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          /// Name
                          Flexible(
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class StudentDetailScreen extends StatelessWidget {
  final String student;

  StudentDetailScreen({required this.student});

  Stream<String?> _currentBookStream() {
    return FirebaseFirestore.instance
        .collection('booksRead')
        .doc(student)
        .snapshots()
        .map((doc) => doc.data()?['currentBook']);
  }

  Stream<Map<String, List<Map<String, dynamic>>>> _booksStream() async* {

    final levels = ['level-1', 'level-2', 'level-3'];

    while (true) {

      Map<String, List<Map<String, dynamic>>> booksByLevel = {};

      for (String level in levels) {

        final snapshot = await FirebaseFirestore.instance
            .collection('booksRead')
            .doc(student)
            .collection(level)
            .get();

        List<Map<String, dynamic>> books = snapshot.docs.map((doc) {

          final data = doc.data();

          return {
            "name": data["bookName"] ?? doc.id,
            "notes": data["madeNotes"] ?? false,
            "startDate": data["startDate"] ?? "",
          };

        }).toList();

        booksByLevel[level] = books;
      }

      yield booksByLevel;

      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {

        return Scaffold(
          backgroundColor: colorProvider.color,

          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back,
                  color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              student,
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  /// CURRENT BOOK
                  StreamBuilder<String?>(
                    stream: _currentBookStream(),
                    builder: (context, snapshot) {

                      if (!snapshot.hasData) return const SizedBox();

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Colors.blueAccent, Colors.lightBlueAccent],
                          ),
                        ),
                        child: Row(
                          children: [

                            const Icon(Icons.menu_book, color: Colors.white, size: 30),

                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                                  const Text(
                                    "Currently Reading",
                                    style: TextStyle(color: Colors.white70, fontSize: 14),
                                  ),

                                  const SizedBox(height: 4),

                                  Text(
                                    snapshot.data ?? "",
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  /// BOOK LEVELS
                  StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
                    stream: _booksStream(),
                    builder: (context, snapshot) {

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final booksByLevel = snapshot.data!;

                      return Column(
                        children: booksByLevel.entries.map((entry) {

                          final levelBooks = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 18),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                width: 2,
                                color: colorProvider.secondColor,
                              ),
                              color: Colors.white,
                            ),

                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [

                                Text(
                                  entry.key.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                    letterSpacing: 1,
                                  ),
                                ),

                                const SizedBox(height: 12),

                                ...levelBooks.map((book) {

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),

                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: Colors.grey.shade100,
                                    ),

                                    child: Row(
                                      children: [

                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.blue.shade100,
                                          ),
                                          child: const Icon(
                                            Icons.menu_book,
                                            size: 18,
                                            color: Colors.blue,
                                          ),
                                        ),

                                        const SizedBox(width: 12),

                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [

                                              Text(
                                                book["name"],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),

                                              const SizedBox(height: 4),

                                              Row(
                                                children: [

                                                  const Icon(
                                                    Icons.calendar_today,
                                                    size: 12,
                                                    color: Colors.black,
                                                  ),

                                                  const SizedBox(width: 4),

                                                  Text(
                                                    book["startDate"],
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.deepPurple,
                                                    ),
                                                  ),

                                                  const SizedBox(width: 16),

                                                  Icon(
                                                    book["notes"]
                                                        ? Icons.check_circle
                                                        : Icons.cancel,
                                                    size: 14,
                                                    color: book["notes"]
                                                        ? Colors.green
                                                        : Colors.red,
                                                  ),

                                                  const SizedBox(width: 4),

                                                  Text(
                                                    book["notes"]
                                                        ? "Notes made"
                                                        : "No notes",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: book["notes"]
                                                          ? Colors.green
                                                          : Colors.red,
                                                    ),
                                                  )
                                                ],
                                              )
                                            ],
                                          ),
                                        )
                                      ],
                                    ),
                                  );

                                }).toList()
                              ],
                            ),
                          );

                        }).toList(),
                      );
                    },
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
