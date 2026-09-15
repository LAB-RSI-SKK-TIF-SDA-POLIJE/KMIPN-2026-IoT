import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] untuk digunakan dengan Firebase initialization.
/// Generated oleh command: `flutterfire configure`
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the "flutterfire configure" command.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the "flutterfire configure" command.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    appId: '1:123456789:web:abcdefghijklmnopqrst',
    messagingSenderId: '123456789',
    projectId: 'saferise-alert-system',
    authDomain: 'saferise-alert-system.firebaseapp.com',
    storageBucket: 'saferise-alert-system.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    appId: '1:123456789:android:abcdefghijklmnopqrst',
    messagingSenderId: '123456789',
    projectId: 'saferise-alert-system',
    storageBucket: 'saferise-alert-system.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    appId: '1:123456789:ios:abcdefghijklmnopqrst',
    messagingSenderId: '123456789',
    projectId: 'saferise-alert-system',
    storageBucket: 'saferise-alert-system.appspot.com',
    iosBundleId: 'com.example.saferisMobileapps',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    appId: '1:123456789:macos:abcdefghijklmnopqrst',
    messagingSenderId: '123456789',
    projectId: 'saferise-alert-system',
    storageBucket: 'saferise-alert-system.appspot.com',
    iosBundleId: 'com.example.saferisMobileapps',
  );
}
