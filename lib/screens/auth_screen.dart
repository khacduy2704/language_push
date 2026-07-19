import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const String _googleProvider = 'google';
  static const String _appleProvider = 'apple';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: <String>['email']);

  bool _isLoginMode = true;
  bool _isSubmitting = false;
  bool _hidePassword = true;
  String? _activeSocialProvider;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    try {
      if (_isLoginMode) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        final UserCredential credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await credential.user?.updateDisplayName(email);
        await credential.user?.reload();
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final String message;
      switch (error.code) {
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Incorrect email or password.';
          break;
        case 'email-already-in-use':
          message = 'This email is already registered.';
          break;
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        default:
          message = error.message ?? 'Authentication failed. Please try again.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  bool get _supportsAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_isSubmitting || _activeSocialProvider != null) {
      return;
    }

    setState(() => _activeSocialProvider = _googleProvider);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.message ?? 'Google sign-in failed.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Google sign-in was cancelled or failed.');
    } finally {
      if (mounted) {
        setState(() => _activeSocialProvider = null);
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (_isSubmitting || _activeSocialProvider != null) {
      return;
    }
    if (!_supportsAppleSignIn) {
      _showMessage('Apple sign-in is available on iPhone, iPad, and macOS after Apple setup.');
      return;
    }

    setState(() => _activeSocialProvider = _appleProvider);
    try {
      final String rawNonce = _generateNonce();
      final String hashedNonce = _sha256OfString(rawNonce);
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final String? identityToken = appleCredential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-identity-token',
          message: 'Apple identity token is missing.',
        );
      }

      final OAuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: identityToken,
        rawNonce: rawNonce,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final String fullName = <String?>[
        appleCredential.givenName,
        appleCredential.familyName,
      ].whereType<String>().where((String value) => value.isNotEmpty).join(' ');
      final String? fallbackName = appleCredential.email ?? userCredential.user?.email;
      final String displayName = fullName.isNotEmpty ? fullName : (fallbackName ?? '');
      if (displayName.isNotEmpty) {
        await userCredential.user?.updateDisplayName(displayName);
      }
    } on SignInWithAppleAuthorizationException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == AuthorizationErrorCode.canceled) {
        _showMessage('Apple sign-in was cancelled.');
      } else {
        _showMessage('Apple sign-in failed.');
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.message ?? 'Apple sign-in failed.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Apple sign-in failed.');
    } finally {
      if (mounted) {
        setState(() => _activeSocialProvider = null);
      }
    }
  }

  String _generateNonce([int length = 32]) {
    const String charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256OfString(String input) {
    final List<int> bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  Widget _buildSocialButton({
    required Color backgroundColor,
    required Color foregroundColor,
    required Widget leading,
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      height: 62,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 32,
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : leading,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFFEEF6FF), Color(0xFFD8E8FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Text(
                            'Push Language',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isLoginMode
                                ? 'Sign in with your username (email)'
                                : 'Create your account with username (email)',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF5A6878)),
                          ),
                          const SizedBox(height: 20),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const <ButtonSegment<bool>>[
                              ButtonSegment<bool>(value: true, label: Text('Sign In')),
                              ButtonSegment<bool>(value: false, label: Text('Sign Up')),
                            ],
                            selected: <bool>{_isLoginMode},
                            onSelectionChanged: (Set<bool> selected) {
                              setState(() => _isLoginMode = selected.first);
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Username (Email)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (String? value) {
                              final String input = value?.trim() ?? '';
                              if (input.isEmpty || !input.contains('@') || !input.contains('.')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _hidePassword,
                            textInputAction: _isLoginMode
                                ? TextInputAction.done
                                : TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() => _hidePassword = !_hidePassword);
                                },
                                icon: Icon(
                                  _hidePassword ? Icons.visibility : Icons.visibility_off,
                                ),
                              ),
                            ),
                            validator: (String? value) {
                              if (value == null || value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          if (!_isLoginMode)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _hidePassword,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.lock_reset_outlined),
                                ),
                                validator: (String? value) {
                                  if (_isLoginMode) {
                                    return null;
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(_isLoginMode ? 'Sign In' : 'Create Account'),
                            ),
                          ),
                          if (_isLoginMode) ...<Widget>[
                            const SizedBox(height: 22),
                            const Row(
                              children: <Widget>[
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'or continue with',
                                    style: TextStyle(
                                      color: Color(0xFF7B8794),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _buildSocialButton(
                              backgroundColor: const Color(0xFFFF4B3A),
                              foregroundColor: Colors.white,
                              leading: const Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              label: 'Login with Google',
                              onPressed: _activeSocialProvider == null
                                  ? _signInWithGoogle
                                  : null,
                              isLoading: _activeSocialProvider == _googleProvider,
                            ),
                            const SizedBox(height: 12),
                            _buildSocialButton(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              leading: const Icon(
                                Icons.apple,
                                size: 26,
                                color: Colors.white,
                              ),
                              label: 'Login with Apple',
                              onPressed: _activeSocialProvider == null
                                  ? _signInWithApple
                                  : null,
                              isLoading: _activeSocialProvider == _appleProvider,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
