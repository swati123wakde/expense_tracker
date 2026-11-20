/// Holds the signed-in user's id so repositories can stamp `user_id` on new
/// records without depending on the auth layer.
class CurrentUser {
  String? id;

  bool get isSignedIn => id != null;
}
