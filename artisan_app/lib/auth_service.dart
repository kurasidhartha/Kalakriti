import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';

import 'notification_service.dart';

class AuthService2 {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static const String _webClientId =
      '1088239052613-f09o82tbrc5lanc3chirohd796nbd8ed.apps.googleusercontent.com';

  static final GoogleSignIn _google = kIsWeb
      ? GoogleSignIn(scopes: ['email', 'profile'], clientId: _webClientId)
      : GoogleSignIn(
          scopes: ['email', 'profile'],
          serverClientId: _webClientId,
        );

  /// Sign in with Google + register FCM token afterward.
  static Future<User?> signInWithGoogle() async {
    try {
      final gUser = await _google.signIn();
      if (gUser == null) return null;

      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);
      final user = result.user;

      if (user != null) {
        // Create profile doc if new user
        final doc = await _db.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await _db.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'email': user.email,
            'displayName':
                user.displayName ?? user.email?.split('@').first ?? '',
            'photoUrl': user.photoURL,
            'bio': '',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // 🔔 Register FCM token NOW that user is signed in
        await NotificationService.registerToken();
      }
      return user;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return null;
    }
  }

  /// Send password reset email (kept for potential future use)
  static Future<String?> sendPasswordReset(String email) async {
    if (email.trim().isEmpty) {
      return 'Enter your email first.';
    }
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No account exists with this email.';
        case 'invalid-email':
          return 'Invalid email address.';
        default:
          return e.message ?? 'Failed to send reset email.';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Sign out of both Google and Firebase.
  static Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
  }
}