
import 'package:flutter/material.dart';

class TriageTrainingGamePage extends StatefulWidget {
  const TriageTrainingGamePage({super.key});

  @override
  State<TriageTrainingGamePage> createState() =>
      _TriageTrainingGamePageState();
}

class _TriageTrainingGamePageState
    extends State<TriageTrainingGamePage> {
  int currentQuestion = 0;
  int score = 0;
  String? feedback;
  bool answered = false;

  final List<Map<String, dynamic>> questions = [
    {
      'patient': 'Patient 1',
      'description': 'A patient has a small cut on their finger.',
      'symptoms': 'Minor bleeding. Patient is alert and breathing normally.',
      'answer': 'Low',
      'explanation': 'Minor injuries are usually low priority.'
    },
    {
      'patient': 'Patient 2',
      'description': 'A patient has a high fever and feels very weak.',
      'symptoms': 'High temperature, dizziness and weakness.',
      'answer': 'Medium',
      'explanation': 'The patient needs medical attention but is stable.'
    },
    {
      'patient': 'Patient 3',
      'description': 'A patient is struggling to breathe.',
      'symptoms': 'Severe breathing difficulty and chest pain.',
      'answer': 'High',
      'explanation': 'Breathing difficulty is an emergency.'
    },
  ];

  void checkAnswer(String answer) {
    if (answered) return;

    setState(() {
      answered = true;

      if (answer == questions[currentQuestion]['answer']) {
        score++;
        feedback = 'Correct! ${questions[currentQuestion]['explanation']}';
      } else {
        feedback =
            'Incorrect. ${questions[currentQuestion]['explanation']}';
      }
    });
  }

  void nextQuestion() {
    setState(() {
      if (currentQuestion < questions.length - 1) {
        currentQuestion++;
        feedback = null;
        answered = false;
      } else {
        currentQuestion = questions.length;
      }
    });
  }

  void restartGame() {
    setState(() {
      currentQuestion = 0;
      score = 0;
      feedback = null;
      answered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (currentQuestion == questions.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Triage Training Game')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, size: 70, color: Colors.orange),
              const SizedBox(height: 20),
              const Text(
                'Game Complete!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              Text(
                'Your score: $score / ${questions.length}',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: restartGame,
                child: const Text('Play Again'),
              ),
            ],
          ),
        ),
      );
    }

    final question = questions[currentQuestion];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Triage Training Game'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Question ${currentQuestion + 1} of ${questions.length}',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Score: $score',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 25),

            Text(
              question['patient'],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),

            Text(
              question['description'],
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),

            Text(
              'Symptoms: ${question['symptoms']}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 30),

            const Text(
              'Choose the patient priority:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            ElevatedButton(
              onPressed: answered ? null : () => checkAnswer('Low'),
              child: const Text('Low Priority'),
            ),
            ElevatedButton(
              onPressed: answered ? null : () => checkAnswer('Medium'),
              child: const Text('Medium Priority'),
            ),
            ElevatedButton(
              onPressed: answered ? null : () => checkAnswer('High'),
              child: const Text('High Priority'),
            ),

            const SizedBox(height: 20),

            if (feedback != null)
              Text(
                feedback!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const Spacer(),

            if (answered)
              ElevatedButton(
                onPressed: nextQuestion,
                child: Text(
                  currentQuestion == questions.length - 1
                      ? 'Finish Game'
                      : 'Next Patient',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
