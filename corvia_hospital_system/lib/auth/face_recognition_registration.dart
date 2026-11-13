import 'dart:io';
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:face_plugin/face_plugin.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycorvia/theme/app_theme.dart';

// TODO: once embedding is encrypted, save the JSON payload (embedding_encrypted,
// iv, key_id) to Supabase for the current user instead of writing to a local file.

class FaceRecognitionRegister extends StatefulWidget {
  const FaceRecognitionRegister({super.key});

  @override
  State<FaceRecognitionRegister> createState() =>
      _FaceRecognitionRegisterState();
}

class _FaceRecognitionRegisterState extends State<FaceRecognitionRegister> {
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
  }

  Future<void> _encryptAndSaveEmbedding() async {
    if (_capturedEmbedding == null) return;

    final embeddingJson = jsonEncode(_capturedEmbedding);
    final key = encrypt.Key.fromUtf8('12345678909876543212345678909876');
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(embeddingJson, iv: iv);

    // TODO: replace local file write with Supabase upsert
    final payload = {
      'embedding_encrypted': encrypted.base64,
      'iv': iv.base64,
      'key_id': key.base64,
    };
    final file = File('filePath');
    await file.writeAsString(jsonEncode(payload));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Face ID Registration')),
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
              TextButton(
                onPressed: _capturedEmbedding != null
                    ? _encryptAndSaveEmbedding
                    : null,
                child: const Text('Submit Face ID'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
