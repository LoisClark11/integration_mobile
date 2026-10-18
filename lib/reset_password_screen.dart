import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gradient_header.dart';
import 'login_screen.dart';
import 'supabase_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _saving = false;

  final TextEditingController _passwordController =
      TextEditingController();

  final TextEditingController _confirmPasswordController =
      TextEditingController();

  Future<void> _applyNewPassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in both password fields.'),
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password must be at least 6 characters.',
          ),
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // A session exists because Supabase already exchanged the code
      // in the reset link for us before this screen opened.
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: password),
      );

      // Sign out afterwards so the new password is proven by a real
      // sign in, and so no session is left hanging open.
      await SupabaseService.client.auth.signOut();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),

            title: const Column(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 48,
                  color: Color(0xFF2E7D32),
                ),

                SizedBox(height: 12),

                Text("Password Updated"),
              ],
            ),

            content: const Text(
              "Your new password has been saved. "
              "Sign in with it to continue.",
              textAlign: TextAlign.center,
            ),

            actionsAlignment: MainAxisAlignment.center,

            actions: [
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFC25E7A),
                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),

                  child: const Text("OK"),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Could not update the password: $error",
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  /// Abandons a half-finished password reset.
  ///
  /// Opening the reset link left a recovery session in memory. If the
  /// customer backs out instead of setting a password, that session has
  /// to be signed out so nothing is left hanging, and they are returned
  /// to the login screen to start over.
  Future<void> _cancelRecovery() async {
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {
      // Nothing useful to do if sign out fails; the session is in memory
      // only and dies with the process anyway.
    }

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back is a working "cancel", not a dead end. This screen can only
      // be reached through a password reset link, which leaves a recovery
      // session open; previously the back button was disabled and no back
      // arrow was shown, so if `updateUser` kept failing the customer was
      // trapped here and had to kill the app. Now back (and the arrow)
      // signs the recovery session out and returns to the login screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _cancelRecovery();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF6F2),

        body: Column(
          children: [
            GradientHeader(
              toolbarTitle: "New Password",
              headerTitle: "Choose a new password",
              subtitle: "Make sure it is easy to remember.",
              icon: Icons.lock_reset_rounded,
              showBackButton: true,
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),

                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(22),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),

                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Set your new password",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 18),

                          TextField(
                            controller:
                                _passwordController,
                            obscureText: _obscurePassword,

                            decoration:
                                InputDecoration(
                              labelText: "New Password",

                              prefixIcon: const Icon(
                                Icons.lock_outline,
                              ),

                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons
                                          .visibility_outlined
                                      : Icons
                                          .visibility_off_outlined,
                                ),

                                onPressed: () {
                                  setState(() {
                                    _obscurePassword =
                                        !_obscurePassword;
                                  });
                                },
                              ),

                              filled: true,
                              fillColor: const Color(
                                0xFFF7F9FC,
                              ),

                              border:
                                  OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                                borderSide:
                                    BorderSide.none,
                              ),

                              focusedBorder:
                                  OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                                borderSide:
                                    const BorderSide(
                                  color: Color(
                                    0xFFC25E7A,
                                  ),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller:
                                _confirmPasswordController,
                            obscureText:
                                _obscureConfirmPassword,

                            onSubmitted: (_) =>
                                _applyNewPassword(),

                            decoration:
                                InputDecoration(
                              labelText:
                                  "Confirm New Password",

                              prefixIcon: const Icon(
                                Icons.password_outlined,
                              ),

                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons
                                          .visibility_outlined
                                      : Icons
                                          .visibility_off_outlined,
                                ),

                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),

                              filled: true,
                              fillColor: const Color(
                                0xFFF7F9FC,
                              ),

                              border:
                                  OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                                borderSide:
                                    BorderSide.none,
                              ),

                              focusedBorder:
                                  OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                                borderSide:
                                    const BorderSide(
                                  color: Color(
                                    0xFFC25E7A,
                                  ),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 52,

                            child:
                                ElevatedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : _applyNewPassword,

                              icon: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons
                                          .check_circle_outline,
                                    ),

                              label: Text(
                                _saving
                                    ? "Saving..."
                                    : "Save New Password",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),

                              style:
                                  ElevatedButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color(
                                  0xFFC25E7A,
                                ),
                                foregroundColor:
                                    Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFFFCEBEF),
                                elevation: 2,

                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                    14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}