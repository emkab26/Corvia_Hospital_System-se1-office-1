
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VitalSignsSimulatorPage extends StatefulWidget {
  const VitalSignsSimulatorPage({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<VitalSignsSimulatorPage> createState() =>
      _VitalSignsSimulatorPageState();
}

class _VitalSignsSimulatorPageState
    extends State<VitalSignsSimulatorPage> {

  Timer? _timer;
  final Random _random = Random();

  bool _isRunning = true;
  bool _isEmergency = false;
  bool _wasInAlert = false;

  // Simulated vital signs
  int heartRate = 75;
  int oxygen = 98;
  double temperature = 36.8;
  int systolic = 120;
  int diastolic = 80;

  // Adjustable safety thresholds
  double heartRateLimit = 120;
  double oxygenLimit = 92;
  double temperatureLimit = 38;
  double bloodPressureLimit = 140;

  // Data used by the charts
  List<double> heartRateHistory = [];
  List<double> oxygenHistory = [];

  @override
  void initState() {
    super.initState();

    heartRateHistory = List.filled(20, 75.0);
    oxygenHistory = List.filled(20, 98.0);

    _startSimulation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Start changing the readings every second
  void _startSimulation() {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        _generateReadings();
      },
    );

    setState(() {
      _isRunning = true;
    });
  }

  // Generate new simulated readings
  void _generateReadings() {
    if (!mounted) return;

    if (_isEmergency) {
      heartRate = 145 + _random.nextInt(21);
      oxygen = 82 + _random.nextInt(8);
      temperature = 39.0 + _random.nextDouble();
      systolic = 160 + _random.nextInt(21);
      diastolic = 95 + _random.nextInt(16);
    } else {
      heartRate = 68 + _random.nextInt(19);
      oxygen = 96 + _random.nextInt(4);
      temperature = 36.4 + _random.nextDouble() * 0.8;
      systolic = 110 + _random.nextInt(16);
      diastolic = 70 + _random.nextInt(16);
    }

    // Keep only the latest 30 chart readings
    heartRateHistory.add(heartRate.toDouble());
    oxygenHistory.add(oxygen.toDouble());

    if (heartRateHistory.length > 30) {
      heartRateHistory.removeAt(0);
      oxygenHistory.removeAt(0);
    }

    final hasWarning = _warnings.isNotEmpty;

    
  }

  // Check whether any reading is outside its safety limit
  List<String> get _warnings {
    List<String> warnings = [];

    if (heartRate > heartRateLimit) {
      warnings.add('High heart rate detected!');
    }

    if (oxygen < oxygenLimit) {
      warnings.add('Low oxygen level detected!');
    }

    if (temperature > temperatureLimit) {
      warnings.add('High temperature detected!');
    }

    if (systolic > bloodPressureLimit) {
      warnings.add('High blood pressure detected!');
    }

    return warnings;
  }


  // Change between normal and emergency mode
  void _changeMode(bool emergency) {
    setState(() {
      _isEmergency = emergency;
      _wasInAlert = false;
    });

    _generateReadings();
  }

  // Configure safety thresholds
  void _showThresholdSettings() {
    double newHeartRate = heartRateLimit;
    double newOxygen = oxygenLimit;
    double newTemperature = temperatureLimit;
    double newBloodPressure = bloodPressureLimit;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              title: const Text('Safety Thresholds'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Maximum heart rate: ${newHeartRate.round()} bpm'),
                    Slider(
                      value: newHeartRate,
                      min: 90,
                      max: 180,
                      divisions: 90,
                      onChanged: (value) {
                        updateDialog(() {
                          newHeartRate = value;
                        });
                      },
                    ),

                    Text('Minimum oxygen: ${newOxygen.round()}%'),
                    Slider(
                      value: newOxygen,
                      min: 80,
                      max: 98,
                      divisions: 18,
                      onChanged: (value) {
                        updateDialog(() {
                          newOxygen = value;
                        });
                      },
                    ),

                    Text('Maximum temperature: ${newTemperature.toStringAsFixed(1)} °C'),
                    Slider(
                      value: newTemperature,
                      min: 37,
                      max: 41,
                      divisions: 40,
                      onChanged: (value) {
                        updateDialog(() {
                          newTemperature = value;
                        });
                      },
                    ),

                    Text('Maximum systolic BP: ${newBloodPressure.round()} mmHg'),
                    Slider(
                      value: newBloodPressure,
                      min: 120,
                      max: 200,
                      divisions: 80,
                      onChanged: (value) {
                        updateDialog(() {
                          newBloodPressure = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      heartRateLimit = newHeartRate;
                      oxygenLimit = newOxygen;
                      temperatureLimit = newTemperature;
                      bloodPressureLimit = newBloodPressure;
                    });

                    Navigator.pop(dialogContext);
                    _generateReadings();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final warnings = _warnings;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Vital Signs Simulator'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // Mode selection
          const Text(
            'Simulation Mode',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_isEmergency
                        ? Colors.green
                        : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _changeMode(false),
                  child: const Text('Normal Mode'),
                ),
              ),

              const SizedBox(width: 10),

            ],
          ),

          const SizedBox(height: 20),

          // Simulation status
          Card(
            child: ListTile(
              leading: Icon(
                _isRunning
                    ? Icons.play_circle
                    : Icons.pause_circle,
                color: _isRunning ? Colors.green : Colors.orange,
                size: 35,
              ),
              title: Text(
                _isRunning ? 'Simulation Running' : 'Simulation Paused',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _isEmergency
                    ? 'Emergency scenario'
                    : 'Normal scenario',
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Warning messages
          if (warnings.isNotEmpty)
            Card(
              color: Colors.red.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'SAFETY WARNING',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          warning,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: Colors.green.shade100,
              child: const ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text(
                  'No threshold warnings',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Vital signs heading
          const Text(
            'Current Vital Signs',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          // Heart rate and oxygen
          Row(
            children: [
              Expanded(
                child: _vitalCard(
                  'Heart Rate',
                  '$heartRate',
                  'BPM',
                  Icons.favorite,
                  Colors.red,
                  heartRate > heartRateLimit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _vitalCard(
                  'Oxygen',
                  '$oxygen',
                  '%',
                  Icons.air,
                  Colors.blue,
                  oxygen < oxygenLimit,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Temperature and blood pressure
          Row(
            children: [
              Expanded(
                child: _vitalCard(
                  'Temperature',
                  temperature.toStringAsFixed(1),
                  '°C',
                  Icons.thermostat,
                  Colors.orange,
                  temperature > temperatureLimit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _vitalCard(
                  'Blood Pressure',
                  '$systolic/$diastolic',
                  'mmHg',
                  Icons.monitor_heart,
                  Colors.purple,
                  systolic > bloodPressureLimit,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Heart rate chart
          const Text(
            'Heart Rate Chart',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          _chartCard(
            heartRateHistory,
            Colors.red,
            40,
            190,
          ),

          const SizedBox(height: 20),

          // Oxygen chart
          const Text(
            'Oxygen Level Chart',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          _chartCard(
            oxygenHistory,
            Colors.blue,
            75,
            100,
          ),

          const SizedBox(height: 24),

          // Control buttons
          const Text(
            'Simulation Controls',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          
          const SizedBox(height: 10),

          OutlinedButton.icon(
            onPressed: _showThresholdSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Configure Safety Thresholds'),
          ),

          const SizedBox(height: 20),

          const Text(
            'Educational simulation only. These readings are generated '
            'randomly and must not be used for actual patient diagnosis '
            'or treatment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // Reusable card for displaying a vital sign
  Widget _vitalCard(
    String title,
    String value,
    String unit,
    IconData icon,
    Color color,
    bool warning,
  ) {
    return Card(
      color: warning ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: warning ? Colors.red : color,
              size: 28,
            ),

            const SizedBox(height: 10),

            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              value,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: warning ? Colors.red : color,
              ),
            ),

            Text(
              unit,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Display a simple real-time line chart
  Widget _chartCard(
    List<double> values,
    Color color,
    double minimum,
    double maximum,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: VitalChartPainter(
              values: values,
              lineColor: color,
              minimum: minimum,
              maximum: maximum,
            ),
          ),
        ),
      ),
    );
  }
}

// Draws the chart using the latest simulated readings
class VitalChartPainter extends CustomPainter {
  VitalChartPainter({
    required this.values,
    required this.lineColor,
    required this.minimum,
    required this.maximum,
  });

  final List<double> values;
  final Color lineColor;
  final double minimum;
  final double maximum;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Draw horizontal chart lines
    for (int i = 0; i < 4; i++) {
      double y = size.height * i / 3;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (values.length < 2) return;

    final path = Path();

    for (int i = 0; i < values.length; i++) {
      double x = size.width * i / (values.length - 1);

      double normalized =
          (values[i] - minimum) / (maximum - minimum);

      normalized = normalized.clamp(0.0, 1.0);

      double y = size.height -
          (normalized * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant VitalChartPainter oldDelegate) {
    return true;
  }
}
