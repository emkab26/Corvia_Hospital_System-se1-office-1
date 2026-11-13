import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

final SupabaseClient supabase = Supabase.instance.client;

/// An administrative page for editing the available laboratory test options
/// and updating the configuration file securely stored in Supabase.
class EditRequestForm extends StatefulWidget {
  const EditRequestForm({super.key});

  @override
  State<EditRequestForm> createState() => _EditRequestFormState();
}

class _EditRequestFormState extends State<EditRequestForm> {
  final heading = TextEditingController();
  final test = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();

  List<String> headings = [];
  List<List<Map<String, dynamic>>> tests = [];

  List<List<bool>> _checkedTests = [];

  bool loading = true;
  String error = '';

  String? selectedHeadingForAdd;

  // Remove section
  String? removeHeadingName;
  int? removeTestGroupIndex;
  String? removeTest;

  @override
  void initState() {
    super.initState();
    loadList();
  }

  // Load JSON from Supabase Storage using a freshly generated signed URL.
  Future<Map<String, dynamic>> loadData() async {
    try {
      final signedUrl = await supabase.storage
          .from('Config')
          .createSignedUrl('List.json', 86400);
      final response = await http.get(Uri.parse(signedUrl));
      if (response.statusCode != 200) {
        setState(() => error = 'Failed to load JSON: ${response.statusCode}');
        return {};
      }
      return jsonDecode(response.body);
    } catch (e) {
      setState(() => error = 'Error loading JSON: $e');
      return {};
    }
  }

  // Parse JSON into lists
  Future<void> loadList() async {
    final loaded = await loadData();
    if (loaded.isEmpty) {
      setState(() => loading = false);
      return;
    }

    setState(() {
      headings = List<String>.from(loaded["headings"]);
      tests = (loaded["tests"] as List)
          .map((group) => List<Map<String, dynamic>>.from(group))
          .toList();

      _checkedTests = tests
          .map(
              (group) => List<bool>.filled(group.length, false, growable: true))
          .toList(growable: true);

      loading = false;
    });
  }

  // Add heading
  void addNewHeading() {
    if (heading.text.isEmpty) return;

    setState(() {
      headings.add(heading.text);
      tests.add([]);
      _checkedTests.add([]);
    });

    heading.clear();
  }

  // Add test
  void addNewTest() {
    if (selectedHeadingForAdd == null ||
        test.text.isEmpty ||
        description.text.isEmpty ||
        price.text.isEmpty) {
      return;
    }

    int index = headings.indexOf(selectedHeadingForAdd!);

    setState(() {
      tests[index].add({
        "name": test.text,
        "description": description.text,
        "price": int.tryParse(price.text) ?? 0,
      });
      _checkedTests[index].add(false);
    });

    test.clear();
    description.clear();
    price.clear();
  }

  // Remove heading function
  void removeHeadingByName(String headingName) {
    int index = headings.indexOf(headingName);
    if (index == -1) return;

    setState(() {
      headings.removeAt(index);
      tests.removeAt(index);
      _checkedTests.removeAt(index);

      if (removeHeadingName == headingName) removeHeadingName = null;
      if (selectedHeadingForAdd == headingName) selectedHeadingForAdd = null;
      if (removeTestGroupIndex == index) {
        removeTestGroupIndex = null;
        removeTest = null;
      }
    });
  }

  // Remove test function
  void removeTestByName(int groupIndex, String testName) {
    int testIndex = tests[groupIndex].indexWhere((t) => t['name'] == testName);
    if (testIndex == -1) return;

    setState(() {
      tests[groupIndex].removeAt(testIndex);
      _checkedTests[groupIndex].removeAt(testIndex);
      if (removeTest == testName) {
        removeTest = null;
      }

      // FIX: If this heading now has ZERO tests, reset index selection
      if (tests[groupIndex].isEmpty) {
        if (removeTestGroupIndex == groupIndex) {
          removeTestGroupIndex = null;
          removeTest = null;
        }
      }
    });
  }

  // Encode JSON
  String buildJson() {
    return jsonEncode({
      "headings": headings,
      "tests": tests,
    });
  }

  // Upload JSON to Supabase
  Future<void> uploadJson() async {
    // NOTE: do NOT log session tokens or anon key prefixes here, even in
    // debug - earlier versions of this file did, which is a credential leak
    // waiting to happen. If you need to debug auth, attach a debugger
    // instead of writing tokens to logs.
    try {
      final bytes = utf8.encode(buildJson());

      const bucket = 'Config';
      const filePath = 'List.json';

      await supabase.storage.from(bucket).remove([filePath]);

      await supabase.storage.from(bucket).uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/json'),
          );
    } catch (e) {
      debugPrint("Upload failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error.isNotEmpty) {
      return Scaffold(
        body: Center(child: Text(error)),
      );
    }

    return Scaffold(
        appBar: AppBar(
          title: const Text("Tests form"),
        ),
        body: SingleChildScrollView(
            child: DefaultTextStyle(
          style: TextStyle(
            color: CorviaColors.textPrimary,
          ),
          child: Container(
            decoration: BoxDecoration(gradient: context.cBgGradient),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT PANEL - ADD
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            controller: heading,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'New Heading',
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: addNewHeading,
                            child: const Text("Add Heading"),
                          ),
                          const SizedBox(height: 8),

                          // Select heading for test
                          DropdownButtonFormField<String>(
                            initialValue: selectedHeadingForAdd,
                            style: TextStyle(color: CorviaColors.textPrimary),
                            dropdownColor: Colors.black,
                            items: headings
                                .map((h) => DropdownMenuItem<String>(
                                      value: h,
                                      child: Text(h),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => selectedHeadingForAdd = v),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: "Select Heading for Test",
                            ),
                          ),

                          const SizedBox(height: 8),
                          TextField(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            controller: test,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Test Name',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            controller: description,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Description',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            controller: price,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Price',
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: addNewTest,
                            child: const Text("Add Test"),
                          ),
                        ],
                      ),
                    ),

                    // RIGHT PANEL - REMOVE
                    Expanded(
                      child: Column(
                        children: [
                          // Remove heading dropdown
                          DropdownButtonFormField<String>(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            dropdownColor: Colors.black,
                            initialValue: removeHeadingName,
                            items: headings
                                .map((h) => DropdownMenuItem<String>(
                                      value: h,
                                      child: Text(h),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => removeHeadingName = v),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: "Remove Heading",
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: removeHeadingName == null
                                ? null
                                : () => removeHeadingByName(removeHeadingName!),
                            child: const Text("Remove Heading"),
                          ),
                          const SizedBox(height: 8),

                          // Select heading for test removal
                          DropdownButtonFormField<int>(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            dropdownColor: Colors.black,
                            initialValue: removeTestGroupIndex,
                            items: List.generate(headings.length, (i) {
                              return DropdownMenuItem<int>(
                                value: i,
                                child: Text(headings[i]),
                              );
                            }),
                            onChanged: (v) {
                              setState(() {
                                removeTestGroupIndex = v;
                                removeTest = null;
                              });
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: "Select Heading for Test",
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Select test to remove
                          DropdownButtonFormField<String>(
                            style: TextStyle(color: CorviaColors.textPrimary),
                            dropdownColor: Colors.black,
                            initialValue: removeTest,
                            items: (removeTestGroupIndex == null)
                                ? []
                                : tests[removeTestGroupIndex!]
                                    .map((t) => DropdownMenuItem<String>(
                                          value: t['name'],
                                          child: Text(t['name']),
                                        ))
                                    .toList(),
                            onChanged: (v) => setState(() => removeTest = v),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: "Remove Test",
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: (removeTest != null &&
                                    removeTestGroupIndex != null)
                                ? () => removeTestByName(
                                      removeTestGroupIndex!,
                                      removeTest!,
                                    )
                                : null,
                            child: const Text("Remove Test"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                FilledButton(
                  onPressed: () {
                    uploadJson();
                  },
                  child: const Text("Save List"),
                ),

                // DISPLAY LIST
                for (int i = 0; i < tests.length; i++) ...[
                  Text(
                    headings[i],
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int j = 0; j < tests[i].length; j++)
                    CheckboxListTile(
                      title: Text(
                        '${tests[i][j]['name']} '
                        '${tests[i][j]['description']} '
                        'R${tests[i][j]['price']}',
                        style: TextStyle(color: CorviaColors.textPrimary),
                      ),
                      value: _checkedTests[i][j],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _checkedTests[i][j] = v);
                      },
                    ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        )));
  }
}
