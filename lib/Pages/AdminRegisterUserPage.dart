import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/utils/Snackbar.dart';
import 'package:provider/provider.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../utils/StudentNameGuard.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../utils/GuideDb.dart';

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

  // Hierarchy: a Female Enabler can only add females, a Guide / Male Enabler
  // only males; a HOD chooses (default male).
  late String _gender = AdminProfileProvider.require().gender;
  bool get _genderLocked => !AdminProfileProvider.viewerIsHod;

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
      // Unreachable dead code (its only caller, an "Add Hostelers" tile,
      // was removed — kept per this project's convention). Fixed
      // defensively in case it is ever resurrected: unique/normalized
      // names task — StudentNameGuard.dart is the ONE shared
      // implementation every account-creation path uses.
      final name = normalizeStudentName(nameController.text);
      if (await isStudentNameTaken(name)) {
        setState(() => isLoading = false);
        showSnackbar(context, kNameTakenMessage, Colors.red, Icons.error);
        return;
      }

      final profile = AdminProfileProvider.require();
      UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      String uid = userCredential.user!.uid;

      // `name` is written exactly ONCE, right here, at account creation.
      // Do NOT add a way to edit it later — see StudentNameGuard.dart for
      // why every name-keyed collection depends on it never changing after
      // this point.
      await GuideDb.instance.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': emailController.text.trim(),
        'role': 'Stay at Hostel',
        'gender': _gender,
        // Owner = the creating admin; a HOD-created female stays unassigned
        // (only a Female Enabler may own a female student). `teamGuide` is
        // stamped by the server.
        'guideId': (_gender == 'female' && !profile.isFemaleEnabler)
            ? ''
            : profile.id,
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
          context, e.message ?? "Something went wrong", context.g.danger, Icons.error);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return GuideScaffold(
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
                    SizedBox(height: height * 0.02),

                    // Gender
                    Row(
                      children: [
                        Text("Gender",
                            style: TextStyle(color: colorProvider.secondColor)),
                        for (final g in const ['male', 'female'])
                          Expanded(
                            child: RadioListTile<String>(
                              value: g,
                              groupValue: _gender,
                              onChanged: _genderLocked
                                  ? null
                                  : (v) => setState(() => _gender = v!),
                              title: Text(g == 'male' ? 'Male' : 'Female',
                                  style: TextStyle(
                                      color: colorProvider.secondColor)),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: height * 0.02),

                    // Button
                    AnimatedContainer(
                      duration: Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: isLoading
                          ? CircularProgressIndicator(color: context.g.warning)
                          : ElevatedButton(
                        onPressed: registerUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.g.brass,
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
