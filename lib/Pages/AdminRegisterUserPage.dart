import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/utils/Snackbar.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';

class AdminRegisterUserPage extends StatefulWidget {
  const AdminRegisterUserPage({super.key});

  @override
  State<AdminRegisterUserPage> createState() => _AdminRegisterUserPageState();
}

class _AdminRegisterUserPageState extends State<AdminRegisterUserPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool _isPasswordVisible = false;
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    // Fade-in effect for smooth transition
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  Future<void> registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      String uid = userCredential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'role': 'Stay at Hostel',
        'createdAt': Timestamp.now(),
        'createdBy': 'admin',
      });

      try {
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.signInAnonymously(); // restore admin
      } catch (_) {}

      showSnackbar(context, "User Registered Successfully!", Colors.green,
          Icons.check_circle);

      nameController.clear();
      emailController.clear();
      passwordController.clear();
    } on FirebaseAuthException catch (e) {
      showSnackbar(
          context, e.message ?? "Something went wrong", Colors.red, Icons.error);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          backgroundColor: colorProvider.color,
          title: AnimatedDefaultTextStyle(
            duration: Duration(milliseconds: 400),
            style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
                fontSize: 22),
            child: Text("Register New User"),
          ),
        ),
        body: AnimatedOpacity(
          duration: Duration(milliseconds: 600),
          opacity: _opacity,
          curve: Curves.easeIn,
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: width * 0.05, vertical: height * 0.03),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Name
                    TextFormField(
                      controller: nameController,
                      style: TextStyle(color: colorProvider.secondColor),
                      decoration: InputDecoration(
                        label: Text(
                          "Name",
                          style: TextStyle(color: colorProvider.secondColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Enter Name";
                        if (!RegExp(r'^[A-Z]').hasMatch(value.trim()))
                          return "First letter must be capital";
                        return null;
                      },
                    ),
                    SizedBox(height: height * 0.02),

                    // Email
                    TextFormField(
                      controller: emailController,
                      style: TextStyle(color: colorProvider.secondColor),
                      decoration: InputDecoration(
                        label: Text(
                          "Email",
                          style: TextStyle(color: colorProvider.secondColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Enter Email";
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value)) return "Enter valid email";
                        return null;
                      },
                    ),
                    SizedBox(height: height * 0.02),

                    // Password
                    TextFormField(
                      controller: passwordController,
                      style: TextStyle(color: colorProvider.secondColor),
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        label: Text(
                          "Password",
                          style: TextStyle(color: colorProvider.secondColor),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: colorProvider.secondColor,
                          ),
                          onPressed: () => setState(
                                  () => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Enter Password";
                        if (value.length < 8)
                          return "Minimum 8 characters required";
                        if (!RegExp(r'[A-Z]').hasMatch(value))
                          return "Must contain at least one capital letter";
                        return null;
                      },
                    ),
                    SizedBox(height: height * 0.04),

                    // Button
                    AnimatedContainer(
                      duration: Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: isLoading
                          ? CircularProgressIndicator(color: Colors.orange.shade300)
                          : ElevatedButton(
                        onPressed: registerUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: EdgeInsets.symmetric(
                              horizontal: width * 0.1,
                              vertical: height * 0.02),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          "Create User",
                          style: TextStyle(
                              color: colorProvider.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
