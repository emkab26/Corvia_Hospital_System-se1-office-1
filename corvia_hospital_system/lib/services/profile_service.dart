import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_update_model.dart';
import '../utils/error_messages.dart';

class ProfileUpdateResult {
  const ProfileUpdateResult._({required this.isSuccess, this.errorMessage});

  const ProfileUpdateResult.success() : this._(isSuccess: true);

  const ProfileUpdateResult.failure(String message)
      : this._(isSuccess: false, errorMessage: message);

  final bool isSuccess;
  final String? errorMessage;
}

class ProfileService {
  const ProfileService();

  Future<ProfileUpdateResult> updateProfile(ProfileUpdateModel model) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        return const ProfileUpdateResult.failure(
          'Your session has expired. Please sign in and try again.',
        );
      }

      // profiles is keyed by user_id, which holds the auth uid. profiles.id is
      // a separate uuid that never equals it, so matching on id updates nothing
      // and still reports success.
      await Supabase.instance.client
          .from('profiles')
          .update(model.toJson())
          .eq('user_id', user.id);

      return const ProfileUpdateResult.success();
    } catch (e) {
      return ProfileUpdateResult.failure(
        friendlyErrorMessage(e, whatFailed: "We couldn't save your changes."),
      );
    }
  }
}
