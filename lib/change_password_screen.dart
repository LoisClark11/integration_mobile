import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gradient_header.dart';
import 'supabase_service.dart';
import 'session.dart';

/// Lets a signed in user change their password by proving they know
/// the current one first.
///
/// This is the counterpart to the forgot password flow: that one is
/// for locked out users, this one is for users who are already in.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  final TextEditingController _currentPasswordController =
      TextEditingController();

  final TextEditingController _newPasswordController =
      TextEditingController();

  final TextEditingController _confirmPasswordController =
      TextEditingController();

  /// Confirms the account owner really is the current password
  /// holder by signing in with it.
  ///
  /// Supabase never exposes password hashes to the client, so the
  /// only way to verify the old password is to attempt a real sign in.
  /// A wrong password throws and leaves the existing session alone.
  Future<void> _verifyCurrentPassword(String email) async {
    await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: _currentPasswordController.text,
    );
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all password fields.'),
        ),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'New password must be at least 6 characters.',
          ),
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New passwords do not match.'),
        ),
      );
      return;
    }

    if (newPassword == currentPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your new password must be different '
            'from the current one.',
          ),
        ),
      );
      return;
    }

    final email = AppSession.email;

    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not read your account email. '
            'Please sign out and back in.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _verifyCurrentPassword(email);

      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully.'),
          backgroundColor: Color(0xFFC25E7A),
        ),
      );

      Navigator.pop(context);
    } on AuthException catch (error) {
      if (!mounted) return;

      final message = error.message;

      final isWrongPassword = message.contains(
            'Invalid login credentials',
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isWrongPassword
                ? 'Your current password is incorrect.'
                : message,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not change your password: $error',
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

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onSubmitted: isLast ? (_) => _changePassword() : null,

        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),

          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),

            onPressed: onToggle,
          ),

          filled: true,
          fillColor: const Color(0xFFF7F9FC),

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),

          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFC25E7A),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),

      body: Column(
        children: [
          GradientHeader(
            toolbarTitle: "Security",
            headerTitle: "Change Password",
            subtitle: "Confirm your current password first.",
            icon: Icons.password_rounded,
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
                      borderRadius: BorderRadius.circular(22),

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
                          "Update your password",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          "Signed in as ${AppSession.email ?? "your account"}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 18),

                        _buildPasswordField(
                          controller:
                              _currentPasswordController,
                          label: "Current Password",
                          obscure: _obscureCurrent,
                          onToggle: () {
                            setState(() {
                              _obscureCurrent =
                                  !_obscureCurrent;
                            });
                          },
                        ),

                        _buildPasswordField(
                          controller: _newPasswordController,
                          label: "New Password",
                          obscure: _obscureNew,
                          onToggle: () {
                            setState(() {
                              _obscureNew = !_obscureNew;
                            });
                          },
                        ),

                        _buildPasswordField(
                          controller:
                              _confirmPasswordController,
                          label: "Confirm New Password",
                          obscure: _obscureConfirm,
                          onToggle: () {
                            setState(() {
                              _obscureConfirm =
                                  !_obscureConfirm;
                            });
                          },
                          isLast: true,
                        ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 52,

                          child: ElevatedButton.icon(
                            onPressed: _saving
                                ? null
                                : _changePassword,

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
                                    Icons.lock_reset_rounded,
                                  ),

                            label: Text(
                              _saving
                                  ? "Updating..."
                                  : "Update Password",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            style:
                                ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFC25E7A),
                              foregroundColor: Colors.white,
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

                        const SizedBox(height: 14),

                        Container(
                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(
                            color: const Color(0xFFFCEBEF),
                            borderRadius:
                                BorderRadius.circular(12),
                          ),

                          child: const Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: Color(0xFFC25E7A),
                              ),

                              SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  "Use at least 6 characters. "
                                  "You will stay signed in after "
                                  "changing it.",
                                  style: TextStyle(
                                    color: Color(0xFFC25E7A),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
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
    );
  }
}