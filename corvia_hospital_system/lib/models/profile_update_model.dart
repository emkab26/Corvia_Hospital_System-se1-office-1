/// The subset of `profiles` a user may edit about themselves. Everything else
/// on that table is set during registration or by staff, not from this form.
class ProfileUpdateModel {
  const ProfileUpdateModel({
    required this.address,
    required this.phoneNumber,
  });

  final String address;
  final String phoneNumber;

  Map<String, dynamic> toJson() => {
        'address': address,
        'phone_number': phoneNumber,
      };
}
