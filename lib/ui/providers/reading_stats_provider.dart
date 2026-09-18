import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something worth telling the reader right now: a new rank, a finished book.
///
/// Separate from `ReaderState.statusMessage`, which is the small status line
/// under the controls. A new rank deserves a SnackBar, once, and then to go
/// away; the screen shows it and sets this back to null.
final readingMilestoneProvider = StateProvider<String?>((ref) => null);
