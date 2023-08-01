import 'dart:async';

import 'package:flutter/material.dart' hide Image;

import 'package:flutter_simple_bluetooth_printer/flutter_simple_bluetooth_printer.dart';

import 'package:esc_pos_utils_plus/esc_pos_utils.dart';
import 'package:flutter/services.dart';

final List<int> maxNumQr = <int>[1, 2, 3, 4, 5];

void main() {
  runApp(const MaterialApp(
    home: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterSimpleBluetoothPrinter bluetoothManager =
      FlutterSimpleBluetoothPrinter.instance;
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isConnected = false;

  List<BluetoothDevice> scannedDevices = [];
  List<BluetoothDevice> bondedDevices = [];

  StreamSubscription<BTConnectState>? _subscriptionBtStatus;

  BluetoothDevice? selectedPrinter;

  int _numberOfQRCodes = maxNumQr.first;

  @override
  void initState() {
    super.initState();
    _discovery();
    _getBondedDevices();

    // subscription to listen change status of bluetooth connection
    _subscriptionBtStatus = bluetoothManager.connectState.listen((status) {
      print(' ----------------- status bt $status ------------------ ');

      if (status == BTConnectState.connected) {
        setState(() {
          _isConnected = true;
        });
      }
      if (status == BTConnectState.disconnect ||
          status == BTConnectState.fail) {
        setState(() {
          _isConnected = false;
        });
      }
    });
  }

  Future<void> _getBondedDevices() async {
    try {
      final List<BluetoothDevice> bonded = await bluetoothManager.getAndroidPairedDevices();
      setState(() {
        bondedDevices = bonded;
      });
    } on BTException catch (e) {
      print(e);
    }
  }

  @override
  void dispose() {
    _subscriptionBtStatus?.cancel();
    super.dispose();
  }

  void _scan() async {
    scannedDevices.clear();
    try {
      setState(() {
        _isScanning = true;
      });

      final results =
          await bluetoothManager.scan(timeout: const Duration(seconds: 20));


      scannedDevices.addAll(results);


      setState(() {});
    } on BTException catch (e) {
      print(e);
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _discovery() {
    scannedDevices.clear(); // Clear scanned devices
    try {
      bluetoothManager.discovery().listen((device) {
        scannedDevices
            .add(device); // Add scanned device to the scannedDevices list
        setState(() {});
      });
    } on BTException catch (e) {
      print(e);
    }
  }

  void selectDevice(BluetoothDevice device) async {
    if (selectedPrinter != null) {
      if (device.address != selectedPrinter!.address) {
        await bluetoothManager.disconnect();
      }
    }

    selectedPrinter = device;
    setState(() {});
  }

  void _print(int howMany) async {
    if (selectedPrinter == null) return;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile, spaceBetweenRows: 0);
    List<int> bytes = [];

    //TODO Anadir texto para ticket

    for (int i = 0; i < _numberOfQRCodes; i++) {
      bytes += generator.qrcode('Buenas tardes',
          size: QRSize.Size8, cor: QRCorrection.L);
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    try {
      if (!_isConnected) return;

      final isSuccess =
          await bluetoothManager.writeRawData(Uint8List.fromList(bytes));
      if (isSuccess) {
        setState(() {
          _isConnected = true;
        });
      }
    } on BTException catch (e) {
      print(e);
    }
  }

  void openWindow() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Number of QR Codes'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<int>(
                    value: _numberOfQRCodes,
                    onChanged: (int? value) {
                      setState(() {
                        _numberOfQRCodes = value!;
                      });
                    },
                    items: maxNumQr.map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('To print: $value'),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(); // Close the dialog without printing
              },
              child: const Text('Exit'),
            ),
            TextButton(
              onPressed: () {
                _print(_numberOfQRCodes);
              },
              child: const Text('Print QR Codes'),
            ),
          ],
        );
      },
    ).then((selectedValue) {
      if (selectedValue != null) {
        setState(() {
          _numberOfQRCodes = selectedValue;
        });
      }
    });
  }

  Future<void> _connectDevice() async {
    if (selectedPrinter == null || _isConnecting) return;

    try {
      setState(() {
        _isConnecting = true; // Show CircularProgressIndicator
      });

      if (!_isScanning) await Future.delayed(const Duration(seconds: 8));

      // Attempt to connect to the device
      bool isConnected = await bluetoothManager.connect(
        address: selectedPrinter!.address,
        isBLE: selectedPrinter!.isLE,
      );

      setState(() {
        _isConnecting = false; // Hide CircularProgressIndicator
      });

      // If the connection is successful
      if (isConnected) {
        _isConnected = true;
        print(
            'Connected to the device: ${selectedPrinter!.name} (${selectedPrinter!.address})');
        // You can perform any further actions needed when connected.
      } else {
        // If the connection is refused or unsuccessful
        _isConnected = false;
        print('Connection to the device was refused or failed.');
        // You can handle this scenario based on your application's requirements.
      }
    } on Error catch (e) {
      setState(() {
        _isConnecting =
            false; // Hide CircularProgressIndicator in case of an error
      });
      print('there was an error in the connection : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasConnectedDevice = _isConnected && selectedPrinter != null;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Adag - connection page'),
        ),
        body: Center(
          child: Container(
            height: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Card(
                    margin: const EdgeInsetsDirectional.fromSTEB(16, 32, 16, 24),
                    child: selectedPrinter != null
                        ? ListTile(
                            title: Row(
                              children: [
                                Text(selectedPrinter!.name,
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 5),
                                _isConnecting
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : _isConnected
                                        ? const Icon(Icons.bluetooth_connected,
                                            color: Colors.green)
                                        : const Icon(Icons.bluetooth_connected,
                                            color: Colors.red), // Disconnected icon
                              ],
                            ),
                            subtitle: Text(
                              selectedPrinter!.address,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: OutlinedButton(
                              onPressed: hasConnectedDevice
                                  ? () async => openWindow()
                                  : null,
                              style: ButtonStyle(
                                backgroundColor:
                                    MaterialStateProperty.all<Color>(
                                        hasConnectedDevice
                                            ? Colors.blueAccent
                                            : Colors.white),
                                foregroundColor: MaterialStateProperty.all<Color>(
                                    hasConnectedDevice
                                        ? Colors.white
                                        : Colors.grey),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 20),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.print),
                                    SizedBox(width: 8),
                                    Text("Print", textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : const ListTile(
                            title: Text("No Printer Selected"),
                            subtitle: Text("Please select a printer"),
                          ),
                  ),
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16.0),
                          child: const Text(
                            'Bonded Devices',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold, // Color of the title text
                            ),
                          ),
                        ),
                        const Divider(),
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: bondedDevices.length,
                          itemBuilder: (context, index) {
                            BluetoothDevice device = bondedDevices[index];
                            return ListTile(
                              title: Text(device.name),
                              subtitle: Text(device.address),
                              onTap: () {
                                selectDevice(device);
                              },
                              trailing: OutlinedButton(
                                style: ButtonStyle(
                                  shape:MaterialStateProperty.all<RoundedRectangleBorder>(
                                      RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(18.0),
                                          side: BorderSide(color: Colors.red)
                                      )
                                  )
                                ),
                                onPressed: selectedPrinter == null ||
                                    device.name != selectedPrinter?.name
                                    ? null
                                    : () async {
                                  _connectDevice();
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 2, horizontal: 20),
                                  child: Text("connect",
                                      textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16.0),
                          child: const Text(
                            'Scanned Devices',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold, // Color of the title text
                            ),
                          ),
                        ),
                        const Divider(),
                        _isScanning ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ) :
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: scannedDevices.length,
                          itemBuilder: (context, index) {
                            BluetoothDevice device = scannedDevices[index];
                            return ListTile(
                              title: Text(device.name),
                              subtitle: Text(device.address),
                              onTap: () {
                                selectDevice(device);
                              },
                              trailing: OutlinedButton(
                                style: ButtonStyle(
                                    shape:MaterialStateProperty.all<RoundedRectangleBorder>(
                                        RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(18.0),
                                            side: BorderSide(color: Colors.red)
                                        )
                                    )
                                ),
                                onPressed: selectedPrinter == null ||
                                    device.name != selectedPrinter?.name
                                    ? null
                                    : () async {
                                  _connectDevice();
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 2, horizontal: 20),
                                  child: Text("Connect",
                                      textAlign: TextAlign.center),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: !_isScanning ? () => _scan() : null,
          backgroundColor: !_isScanning ? Colors.blueAccent : Colors.grey,
          child: const Icon(Icons.bluetooth),
        ),
      ),
    );
  }
}
