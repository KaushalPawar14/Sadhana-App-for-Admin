import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';  // For formatting the date

class ScoreScreen extends StatefulWidget {
  final String username;  // Receive the username
  final DateTime selectedDate;  // Receive the selected date

  // Constructor to accept both username and selectedDate parameters
  ScoreScreen({required this.username, required this.selectedDate});

  @override
  _ScoreScreenState createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  // Format the selected date to 'dd-MM-yyyy' format
  String formattedDate = '';

  @override
  void initState() {
    super.initState();
    // Format the selected date into 'dd-MM-yyyy'
    formattedDate = DateFormat('dd-MM-yyyy').format(widget.selectedDate);
  }

  // Function to fetch the report data for the selected date from Firestore
  Future<Map<String, dynamic>?> _fetchTodaysData() async {
    try {
      // Fetch the document from 'sadhana-reports' collection based on the username
      final userDocSnapshot = await FirebaseFirestore.instance
          .collection('sadhana-reports')
          .doc(widget.username)  // Use the passed username
          .collection('dates')
          .doc(formattedDate)  // Search for the selected date document
          .get();

      // Check if the document exists
      if (userDocSnapshot.exists) {
        return userDocSnapshot.data();  // Return the data of the selected date
      } else {
        return null;  // If no data for the selected date
      }
    } catch (e) {
      print("Error fetching data: $e");
      return null;
    }
  }

  // Function to determine the unit for each field
  String _getUnitForField(String field, dynamic fieldValue) {
    if (field.toLowerCase().contains('classhearing') || field.toLowerCase().contains('dailyservices')) {
      return ' points';  // For classHearing and dailyservices fields
    }

    if (field.toLowerCase().contains('chantrounds')) {
      return ' rounds';  // For chantRounds field
    }

    if (field.toLowerCase().contains('bookreading')) {
      return ' mins';  // For bookReading field
    }

    return '';  // Default unit (if none of the above fields match)
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: colorProvider.secondColor,
            ),
            onPressed: () {
              // Perform any action when the icon is pressed, e.g., navigate back
              Navigator.pop(context);
            },
          ),
          backgroundColor: colorProvider.color,
          title: Text('${widget.username}',style: TextStyle(color: colorProvider.secondColor),), // Display the username
        ),
        body: FutureBuilder<
            Map<String, dynamic>?>( // Use FutureBuilder to display data
          future: _fetchTodaysData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}',style: TextStyle(color: colorProvider.secondColor)));
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return Center(child: Text('No data found for $formattedDate.',style: TextStyle(color: colorProvider.secondColor)));
            }

            final data = snapshot.data!;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Displaying different fields from the fetched report
                  Text(
                    'Details for ${widget.username} on $formattedDate:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorProvider.secondColor),
                  ),
                  SizedBox(height: 20),
                  // Loop through the fields in the fetched data
                  for (var key in data.keys)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            key, // Field name
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600, color: colorProvider.secondColor),
                          ),
                          Text(
                            '${data[key].toString()}${_getUnitForField(
                                key, data[key])}', // Field value + unit
                            style: TextStyle(fontSize: 16, color: colorProvider.secondColor),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    });
  }
}
