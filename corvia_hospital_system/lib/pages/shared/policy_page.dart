import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PolicyPage extends StatefulWidget {
  const PolicyPage({super.key});

  @override
  State<PolicyPage> createState() => _PolicyPageState();
}

class _PolicyPageState extends State<PolicyPage> {
  List<Map<String, dynamic>> terms = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTermsAndConditions();
  }

  Future<void> _loadTermsAndConditions() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/policy.json');

      final List<dynamic> jsonData = jsonDecode(jsonString);

      setState(() {
        terms = List<Map<String, dynamic>>.from(jsonData);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Error loading terms: $e";
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(errorMessage!,
                      style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: terms.length,
                        itemBuilder: (context, index) {
                          final term = terms[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  term['heading'],
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      height: 1.6),
                                ),
                                ...List<String>.from(term['content'])
                                    .map((p) => Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            p,
                                            style: const TextStyle(
                                                fontSize: 16, height: 1.5),
                                          ),
                                        )),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text("Agree and confirm"),
                      ),
                    ),
                  ],
                ),
    );
  }
}
