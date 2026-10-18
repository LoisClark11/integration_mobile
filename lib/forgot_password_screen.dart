import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gradient_header.dart';
import 'supabase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  bool _sending = false;

  final TextEditingController _emailController =
      TextEditingController();

  bool _looksLikeEmail(String value) {
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(value);
  }

  /// Shows the same confirmation no matter what Supabase replies.
  ///
  /// Reporting "no account with that email" would let anyone discover
  /// which addresses are registered, so the outcome is deliberately
  /// identical either way.
  Future<void> _showConfirmation(String email) async {
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
                Icons.mark_email_read_rounded,
                size: 48,
                color: Color(0xFFC25E7A),
              ),

              SizedBox(height: 12),

              Text("Check your email"),
            ],
          ),

          content: Text(
            "If an account exists for $email, "
            "a password reset link is on its way.\n\n"
            "Open the link on this device to choose "
            "a new password.",
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
                  backgroundColor: const Color(0xFFC25E7A),
                  foregroundColor: Colors.white,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                child: const Text("OK"),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> sendResetLink() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address.'),
        ),
      );
      return;
    }

    if (!_looksLikeEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      // Supabase emails a link, not a new password. Opening that link
      // on this device opens ResetPasswordScreen.
      await SupabaseService.client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseService.deepLinkRedirect,
      );

      if (!mounted) return;

      await _showConfirmation(email);
    } on AuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not send the reset link: $error"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),

      body: Column(
        children: [
          GradientHeader(
            toolbarTitle: "Reset Password",
            headerTitle: "Forgot your password?",
            subtitle:
                "We'll email you a link to choose a new one.",
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
                      borderRadius: BorderRadius.circular(22),

                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.05),
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
                          "Reset your password",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          "Enter the email address you signed up "
                          "with and we'll send instructions to reset "
                          "your password.",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 18),

                        TextField(
                          controller: _emailController,

                          keyboardType:
                              TextInputType.emailAddress,

                          onSubmitted: (_) => sendResetLink(),

                          decoration: InputDecoration(
                            labelText: "Email",
                            prefixIcon: const Icon(
                              Icons.alternate_email,
                            ),

                            filled: true,
                            fillColor:
                                const Color(0xFFF7F9FC),

                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),

                            focusedBorder:
                                OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFC25E7A),
                                width: 2,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 52,

                          child: ElevatedButton.icon(
                            onPressed: _sending
                                ? null
                                : sendResetLink,

                            icon: _sending
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
                                    Icons.send_rounded,
                                  ),

                            label: Text(
                              _sending
                                  ? "Sending..."
                                  : "Send Reset Link",
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

                        const SizedBox(height: 16),

                        Container(
                          padding: const EdgeInsets.all(12),

                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
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
                                color: Color(0xFF8D6E00),
                              ),

                              SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  "Open the reset link on this same "
                                  "device. For security, Supabase "
                                  "will not recognise the link "
                                  "elsewhere.",
                                  style: TextStyle(
                                    color: Color(0xFF8D6E00),
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