import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:face_plugin/face_plugin.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycorvia/pages/shared/terms_and_conditions.dart';
import 'package:mycorvia/theme/app_theme.dart';

// TODO: connect storedEmbedding to Supabase - fetch the encrypted embedding
// for the current user, decrypt it, and populate storedEmbedding before compare.

class FaceRecognitionLogin extends StatefulWidget {
  const FaceRecognitionLogin({super.key});

  @override
  State<FaceRecognitionLogin> createState() => _FaceRecognitionLoginState();
}

class _FaceRecognitionLoginState extends State<FaceRecognitionLogin> {
  static const List<String> _instructions = [
    'Take the photo in a well‑lit environment. Natural light is best, but avoid harsh shadows or bright sunlight directly on your face.',
    'Stand against a plain background (like a wall) so the system focuses on your face without distractions.',
    'Position your face in the middle of the frame, with your eyes level and looking straight at the camera.',
    'Remove hats, sunglasses, or masks. Glasses are usually fine if they\'re clear, but avoid tinted or reflective lenses.',
    'Keep a relaxed, natural look. Don\'t smile too widely or frown - consistency helps recognition.',
  ];

  File? _image;
  final _picker = ImagePicker();

  List<double>? _capturedEmbedding;

  // Populated once Supabase integration is complete (see TODO above).
  List<double> _storedEmbedding = [];

  final String _encryptedEmbedding = '';
  bool? _match;

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() {
      _image = File(pickedFile.path);
    });

    final bytes = await _image!.readAsBytes();
    final faces = await FacePlugin.detectFaces(bytes);
    for (final _ in faces) {
      final embeddings = await FacePlugin.extractFeatures(bytes);
      setState(() {
        _capturedEmbedding = embeddings.first;
      });
    }

    await _decryptEmbedding();

    // Guard: if storedEmbedding is empty the Supabase fetch hasn't been
    // implemented yet - block login rather than allowing a false match.
    if (_storedEmbedding.isEmpty) {
      setState(() => _match = false);
      return;
    }

    _compareAndConfirmIdentity(_storedEmbedding, _capturedEmbedding!);
  }

  Future<void> _decryptEmbedding() async {
    if (_encryptedEmbedding.isEmpty) return;

    final key = encrypt.Key.fromUtf8('32characterslongsecretkey!!!!');
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final decryptedJson = encrypter.decrypt64(_encryptedEmbedding, iv: iv);
    final embeddingList = jsonDecode(decryptedJson) as List<dynamic>;
    setState(() {
      _storedEmbedding =
          embeddingList.map((e) => (e as num).toDouble()).toList();
    });
  }

  void _compareAndConfirmIdentity(
    List<double> storedEmbedding,
    List<double> capturedEmbedding,
  ) {
    double cosineSimilarity(List<double> a, List<double> b) {
      double dot = 0, normA = 0, normB = 0;
      for (int i = 0; i < a.length; i++) {
        dot += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
      }
      return dot / (sqrt(normA) * sqrt(normB));
    }

    final similarity = cosineSimilarity(storedEmbedding, capturedEmbedding);
    setState(() {
      _match = similarity > 0.80;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Face ID Scan')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 500,
                width: 500,
                child: _image != null
                    ? Image.file(_image!)
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: ListView.builder(
                          itemCount: _instructions.length,
                          itemBuilder: (context, index) => Text(
                            '•${_instructions[index]}',
                            style: const TextStyle(height: 1.5, fontSize: 15),
                          ),
                        ),
                      ),
              ),
              IconButton(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
              ),
              Text(
                _capturedEmbedding != null
                    ? 'Face ID captured'
                    : _image != null
                        ? 'Failed to capture Face ID - try again'
                        : '',
              ),
              Text(
                _match == true
                    ? 'Identity confirmed'
                    : _match == null
                        ? ''
                        : 'Face does not match',
              ),
              TextButton(
                onPressed: _match == true
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TermsAndConditionsPage(),
                          ),
                        )
                    : null,
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
