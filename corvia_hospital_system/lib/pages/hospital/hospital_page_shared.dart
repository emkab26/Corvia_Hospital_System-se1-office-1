import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalAdminScope {
  final String hospitalId;
  final String hospitalName;

  const HospitalAdminScope({
    required this.hospitalId,
    required this.hospitalName,
  });

  static Future<HospitalAdminScope> load(
    SupabaseClient supabase, {
    required String fallbackName,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'You are not signed in.',
      );
    }

    Map<String, dynamic>? adminLink;

    final directResponse = await supabase
        .from('hospital_admins')
        .select(
          'hospital_id, hospitals(name)',
        )
        .eq(
          'profile_id',
          user.id,
        )
        .maybeSingle();

    if (directResponse != null) {
      adminLink =
          Map<String, dynamic>.from(
        directResponse,
      );
    }

    if (adminLink == null) {
      final profileResponse =
          await supabase
              .from('profiles')
              .select()
              .eq(
                'user_id',
                user.id,
              )
              .maybeSingle();

      final profileId =
          profileResponse?['id']
              ?.toString();

      if (profileId != null &&
          profileId.trim().isNotEmpty) {
        final linkedResponse =
            await supabase
                .from('hospital_admins')
                .select(
                  'hospital_id, hospitals(name)',
                )
                .eq(
                  'profile_id',
                  profileId,
                )
                .maybeSingle();

        if (linkedResponse != null) {
          adminLink =
              Map<String, dynamic>.from(
            linkedResponse,
          );
        }
      }
    }

    if (adminLink == null) {
      throw Exception(
        'This account is not linked to a hospital admin record.',
      );
    }

    final hospitalId =
        adminLink['hospital_id']
            ?.toString();

    if (hospitalId == null ||
        hospitalId.trim().isEmpty) {
      throw Exception(
        'No hospital is linked to this admin account.',
      );
    }

    String hospitalName =
        fallbackName;

    final hospital =
        adminLink['hospitals'];

    if (hospital is Map &&
        hospital['name'] != null &&
        hospital['name']
            .toString()
            .trim()
            .isNotEmpty) {
      hospitalName =
          hospital['name']
              .toString()
              .trim();
    }

    return HospitalAdminScope(
      hospitalId:
          hospitalId,
      hospitalName:
          hospitalName,
    );
  }
}

class HospitalDataTools {
  static List<Map<String, dynamic>> rows(
    dynamic data,
  ) {
    if (data is! List) {
      return [];
    }

    return data
        .whereType<Map>()
        .map(
          (row) =>
              Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  static bool isPlaceholderName(
    dynamic value,
  ) {
    if (value == null) {
      return true;
    }

    final name =
        value
            .toString()
            .trim()
            .toLowerCase();

    if (name.isEmpty) {
      return true;
    }

    const placeholders = [
      'corvia patient',
      'patient',
      'unknown patient',
      'qr scanned patient',
      'patient profile not linked',
      'doctor profile not linked',
      'unlinked record',
      'unknown record',
      'assigned doctor',
      'no patient linked',
    ];

    return placeholders.contains(
      name,
    );
  }

  static Future<
      Map<String, Map<String, dynamic>>>
      loadProfiles(
    SupabaseClient supabase,
    Iterable<Map<String, dynamic>>
        records,
  ) async {
    final keys = <String>{};
    final emails = <String>{};

    for (final record in records) {
      for (final field in [
        'profile_id',
        'user_id',
        'profileId',
        'userId',
      ]) {
        final value =
            record[field]
                ?.toString()
                .trim();

        if (value != null &&
            value.isNotEmpty) {
          keys.add(
            value,
          );
        }
      }

      final email =
          record['email']
              ?.toString()
              .trim()
              .toLowerCase();

      if (email != null &&
          email.isNotEmpty) {
        emails.add(
          email,
        );
      }
    }

    final profiles =
        <String,
            Map<String, dynamic>>{};

    void registerProfile(
      Map<String, dynamic> row,
    ) {
      final id =
          row['id']
              ?.toString()
              .trim();

      final userId =
          row['user_id']
              ?.toString()
              .trim();

      final email =
          row['email']
              ?.toString()
              .trim()
              .toLowerCase();

      if (id != null &&
          id.isNotEmpty) {
        profiles[id] =
            row;
      }

      if (userId != null &&
          userId.isNotEmpty) {
        profiles[userId] =
            row;
      }

      if (email != null &&
          email.isNotEmpty) {
        profiles[
                'email:$email'] =
            row;
      }
    }

    Future<void> loadByColumn(
      String column,
      List<String> values,
    ) async {
      if (values.isEmpty) {
        return;
      }

      try {
        /*
         * Do not explicitly request optional fields such as
         * full_name, last_name or phone_number.
         *
         * select() lets Supabase return the actual columns
         * available on the current Corvia profiles schema.
         */
        final data =
            await supabase
                .from('profiles')
                .select()
                .inFilter(
                  column,
                  values,
                );

        for (final row in rows(
          data,
        )) {
          registerProfile(
            row,
          );
        }
      } catch (error) {
        debugPrint(
          'Could not load profiles by $column: $error',
        );
      }
    }

    await loadByColumn(
      'id',
      keys.toList(),
    );

    await loadByColumn(
      'user_id',
      keys.toList(),
    );

    await loadByColumn(
      'email',
      emails.toList(),
    );

    return profiles;
  }

  static Map<String, dynamic>?
      profileFor(
    Map<String, dynamic> record,
    Map<String,
            Map<String, dynamic>>
        profiles,
  ) {
    for (final field in [
      'profile_id',
      'user_id',
      'profileId',
      'userId',
    ]) {
      final key =
          record[field]
              ?.toString()
              .trim();

      if (key != null &&
          key.isNotEmpty &&
          profiles.containsKey(
            key,
          )) {
        return profiles[key];
      }
    }

    final email =
        record['email']
            ?.toString()
            .trim()
            .toLowerCase();

    if (email != null &&
        email.isNotEmpty &&
        profiles.containsKey(
          'email:$email',
        )) {
      return profiles[
          'email:$email'];
    }

    return null;
  }

  static String personName(
    Map<String, dynamic> record,
    Map<String,
            Map<String, dynamic>>
        profiles, {
    String fallback = 'Unlinked record',
    String prefix = '',
  }) {
    /*
     * First use the linked profile when available.
     */
    final profile =
        profileFor(
      record,
      profiles,
    );

    if (profile != null) {
      final profileName =
          _readFullName(
        profile,
      );

      if (profileName.isNotEmpty &&
          !isPlaceholderName(
            profileName,
          )) {
        return _withPrefix(
          profileName,
          prefix,
        );
      }
    }

    /*
     * Then check the source record itself.
     */
    final recordName =
        _readFullName(
      record,
    );

    if (recordName.isNotEmpty &&
        !isPlaceholderName(
          recordName,
        )) {
      return _withPrefix(
        recordName,
        prefix,
      );
    }

    /*
     * A patient number identifies the person without showing an email
     * address as if it were their name.
     */
    final patientNumber =
        (record['patient_number'] ??
                profile?['patient_number'])
            ?.toString()
            .trim();

    if (patientNumber != null &&
        patientNumber.isNotEmpty) {
      return _withPrefix(
        'Patient $patientNumber',
        prefix,
      );
    }

    /*
     * Email is preferable to a generic placeholder.
     */
    final email =
        record['email']
            ?.toString()
            .trim();

    if (email != null &&
        email.isNotEmpty) {
      return _withPrefix(
        email,
        prefix,
      );
    }

    /*
     * Do not display:
     *
     * Patient profile not linked
     * Corvia Patient
     * Unknown patient
     *
     * when we have an ID that can identify the record.
     */
    final rawId =
        record['patient_id'] ??
            record['profile_id'] ??
            record['user_id'] ??
            record['id'];

    final recordId =
        rawId
                ?.toString()
                .trim() ??
            '';

    if (recordId.isNotEmpty) {
      final shortId =
          recordId.length > 8
              ? recordId.substring(
                  0,
                  8,
                )
              : recordId;

      return _withPrefix(
        'Patient ${shortId.toUpperCase()}',
        prefix,
      );
    }

    if (!isPlaceholderName(
      fallback,
    )) {
      return _withPrefix(
        fallback,
        prefix,
      );
    }

    return _withPrefix(
      'Unlinked patient',
      prefix,
    );
  }

  static String phone(
    Map<String, dynamic> record,
    Map<String,
            Map<String, dynamic>>
        profiles, {
    String fallback = 'No phone linked',
  }) {
    final profile =
        profileFor(
      record,
      profiles,
    );

    final value =
        record['phone'] ??
            record['phone_number'] ??
            record['contact_number'] ??
            record['mobile_number'] ??
            profile?['phone'] ??
            profile?['phone_number'] ??
            profile?['contact_number'] ??
            profile?['mobile_number'];

    if (value != null &&
        value
            .toString()
            .trim()
            .isNotEmpty) {
      return value
          .toString()
          .trim();
    }

    return fallback;
  }

  static String email(
    Map<String, dynamic> record,
    Map<String,
            Map<String, dynamic>>
        profiles, {
    String fallback = 'No email linked',
  }) {
    final profile =
        profileFor(
      record,
      profiles,
    );

    final value =
        record['email'] ??
            profile?['email'];

    if (value != null &&
        value
            .toString()
            .trim()
            .isNotEmpty) {
      return value
          .toString()
          .trim();
    }

    return fallback;
  }

  static String _readFullName(
    Map<String, dynamic> row,
  ) {
    /*
     * These are Map lookups only.
     * They are not SQL column requests.
     */
    final directName =
        row['full_name'] ??
            row['display_name'] ??
            row['patient_name'] ??
            row['doctor_name'] ??
            row['name'];

    if (directName != null &&
        directName
            .toString()
            .trim()
            .isNotEmpty) {
      return directName
          .toString()
          .trim();
    }

    final firstName =
        row['first_name']
                ?.toString()
                .trim() ??
            row['firstname']
                ?.toString()
                .trim() ??
            row['given_name']
                ?.toString()
                .trim() ??
            '';

    final surname =
        row['surname']
                ?.toString()
                .trim() ??
            row['last_name']
                ?.toString()
                .trim() ??
            row['lastname']
                ?.toString()
                .trim() ??
            row['family_name']
                ?.toString()
                .trim() ??
            '';

    return '$firstName $surname'
        .trim();
  }

  static String _withPrefix(
    String value,
    String prefix,
  ) {
    if (prefix.trim().isEmpty) {
      return value;
    }

    if (value
        .toLowerCase()
        .startsWith(
          prefix.toLowerCase(),
        )) {
      return value;
    }

    return '$prefix $value';
  }
}

class HospitalStatItem {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const HospitalStatItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class HospitalStatGrid
    extends StatelessWidget {
  const HospitalStatGrid({
    super.key,
    required this.items,
  });

  final List<HospitalStatItem>
      items;

  @override
  Widget build(
    BuildContext context,
  ) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        int columns = 2;

        if (constraints.maxWidth >=
            1100) {
          columns = 4;
        } else if (constraints.maxWidth <
            520) {
          columns = 1;
        }

        return GridView.builder(
          shrinkWrap:
              true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              items.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                columns,
            crossAxisSpacing:
                14,
            mainAxisSpacing:
                14,

            /*
             * Increased from 195.
             *
             * The previous height caused the Emergency
             * dashboard cards to overflow by ~8 pixels.
             */
            mainAxisExtent:
                215,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final item =
                items[index];

            return Container(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              decoration:
                  BoxDecoration(
                color:
                    context.cBgSecondary,
                borderRadius:
                    BorderRadius.circular(
                  20,
                ),
                border:
                    Border.all(
                  color:
                      context.cDivider,
                ),
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    height:
                        42,
                    width:
                        42,
                    decoration:
                        BoxDecoration(
                      color:
                          item.color.withValues(
                        alpha:
                            0.12,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    child:
                        Icon(
                      item.icon,
                      color:
                          item.color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.value,
                    maxLines:
                        1,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        TextStyle(
                      color:
                          context.cTextPrimary,
                      fontSize:
                          25,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  const SizedBox(
                    height:
                        3,
                  ),
                  Text(
                    item.title,
                    maxLines:
                        1,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        TextStyle(
                      color:
                          context.cTextPrimary,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  const SizedBox(
                    height:
                        3,
                  ),
                  Text(
                    item.subtitle,
                    maxLines:
                        2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        TextStyle(
                      color:
                          context.cTextSecondary,
                      fontSize:
                          12,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class HospitalPageHeader
    extends StatelessWidget {
  const HospitalPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRefresh;

  @override
  Widget build(
    BuildContext context,
  ) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final compact =
            constraints.maxWidth <
                650;

        final text =
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style:
                  TextStyle(
                color:
                    context.cTextPrimary,
                fontSize:
                    27,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
            const SizedBox(
              height:
                  5,
            ),
            Text(
              subtitle,
              style:
                  TextStyle(
                color:
                    context.cTextSecondary,
                fontSize:
                    14,
              ),
            ),
          ],
        );

        final refresh =
            OutlinedButton.icon(
          onPressed:
              onRefresh,
          icon:
              const Icon(
            Icons.refresh_rounded,
          ),
          label:
              const Text(
            'Refresh',
          ),
          style:
              OutlinedButton.styleFrom(
            foregroundColor:
                context.cAccentReadable,
            side:
                BorderSide(
              color:
                  context.cDivider,
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              text,
              const SizedBox(
                height:
                    14,
              ),
              refresh,
            ],
          );
        }

        return Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Expanded(
              child:
                  text,
            ),
            const SizedBox(
              width:
                  16,
            ),
            refresh,
          ],
        );
      },
    );
  }
}

class HospitalPanel
    extends StatelessWidget {
  const HospitalPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        20,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border:
            Border.all(
          color:
              context.cDivider,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final compact =
                  constraints.maxWidth <
                      520;

              final headingContent =
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        TextStyle(
                      color:
                          context.cTextPrimary,
                      fontSize:
                          18,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  if (subtitle !=
                      null) ...[
                    const SizedBox(
                      height:
                          4,
                    ),
                    Text(
                      subtitle!,
                      style:
                          TextStyle(
                        color:
                            context.cTextSecondary,
                        fontSize:
                            13,
                      ),
                    ),
                  ],
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          color:
                              context.cAccentReadable,
                        ),
                        const SizedBox(
                          width:
                              10,
                        ),
                        Expanded(
                          child:
                              headingContent,
                        ),
                      ],
                    ),
                    if (action !=
                        null) ...[
                      const SizedBox(
                        height:
                            10,
                      ),
                      Align(
                        alignment:
                            Alignment.centerRight,
                        child:
                            action!,
                      ),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    color:
                        context.cAccentReadable,
                  ),
                  const SizedBox(
                    width:
                        10,
                  ),
                  Expanded(
                    child:
                        headingContent,
                  ),
                  if (action !=
                      null) ...[
                    const SizedBox(
                      width:
                          12,
                    ),
                    action!,
                  ],
                ],
              );
            },
          ),
          const SizedBox(
            height:
                18,
          ),
          child,
        ],
      ),
    );
  }
}

class HospitalSearchBox
    extends StatelessWidget {
  const HospitalSearchBox({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController
      controller;

  final String hint;

  final ValueChanged<String>
      onChanged;

  @override
  Widget build(
    BuildContext context,
  ) {
    return ValueListenableBuilder<
        TextEditingValue>(
      valueListenable:
          controller,
      builder: (
        context,
        value,
        child,
      ) {
        return TextField(
          controller:
              controller,
          onChanged:
              onChanged,
          decoration:
              InputDecoration(
            hintText:
                hint,
            prefixIcon:
                Icon(
              Icons.search_rounded,
              color:
                  context.cAccentReadable,
            ),
            suffixIcon:
                value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip:
                            'Clear search',
                        onPressed:
                            () {
                          controller.clear();
                          onChanged(
                            '',
                          );
                        },
                        icon:
                            const Icon(
                          Icons.clear_rounded,
                        ),
                      ),
            filled:
                true,
            fillColor:
                context.cBgPrimary,
            border:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  BorderSide(
                color:
                    context.cDivider,
              ),
            ),
            enabledBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  BorderSide(
                color:
                    context.cDivider,
              ),
            ),
            focusedBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  BorderSide(
                color:
                    context.cAccentReadable,
                width:
                    1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}

class HospitalStatusPill
    extends StatelessWidget {
  const HospitalStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      constraints:
          const BoxConstraints(
        maxWidth:
            220,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal:
            10,
        vertical:
            6,
      ),
      decoration:
          BoxDecoration(
        color:
            color.withValues(
          alpha:
              0.10,
        ),
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha:
                0.22,
          ),
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size:
                  13,
              color:
                  color,
            ),
            const SizedBox(
              width:
                  5,
            ),
          ],
          Flexible(
            child:
                Text(
              label,
              maxLines:
                  1,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  TextStyle(
                color:
                    color,
                fontSize:
                    11,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HospitalEmptyState
    extends StatelessWidget {
  const HospitalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        36,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgPrimary,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border:
            Border.all(
          color:
              context.cDivider,
        ),
      ),
      child:
          Column(
        children: [
          Icon(
            icon,
            size:
                40,
            color:
                context.cAccentReadable,
          ),
          const SizedBox(
            height:
                12,
          ),
          Text(
            title,
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  context.cTextPrimary,
              fontWeight:
                  FontWeight.w900,
              fontSize:
                  16,
            ),
          ),
          const SizedBox(
            height:
                6,
          ),
          Text(
            message,
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
              fontSize:
                  13,
            ),
          ),
        ],
      ),
    );
  }
}