package com.obeynotebook.universal_notebook

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth (folder locks) shows the system biometric prompt, which needs a
// FragmentActivity. With a plain FlutterActivity every authentication fails,
// so a locked folder could never be opened or unlocked again.
class MainActivity : FlutterFragmentActivity()
