import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Image;

import 'package:flutter_simple_bluetooth_printer/flutter_simple_bluetooth_printer.dart';

import 'package:esc_pos_utils_plus/esc_pos_utils.dart';
import 'package:flutter/services.dart';

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
  var bluetoothManager = FlutterSimpleBluetoothPrinter.instance;
  var _isScanning = false;
  var _isConnecting = false;
  var _isBle = true;
  var _isConnected = false;
  var devices = <BluetoothDevice>[];

  StreamSubscription<BTConnectState>? _subscriptionBtStatus;
  BTConnectState _currentStatus = BTConnectState.disconnect;

  BluetoothDevice? selectedPrinter;

  int _numberOfQRCodes = 1;

  @override
  void initState() {
    super.initState();
    _discovery();

    // subscription to listen change status of bluetooth connection
    _subscriptionBtStatus = bluetoothManager.connectState.listen((status) {
      print(' ----------------- status bt $status ------------------ ');
      _currentStatus = status;
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

  @override
  void dispose() {
    _subscriptionBtStatus?.cancel();
    super.dispose();
  }

  void _scan() async {
    devices.clear();
    try {
      setState(() {
        _isScanning = true;
      });
      if (_isBle) {
        final results =
            await bluetoothManager.scan(timeout: const Duration(seconds: 20));
        devices.addAll(results);
        setState(() {});
      } else {
        final bondedDevices = await bluetoothManager.getAndroidPairedDevices();
        devices.addAll(bondedDevices);
        setState(() {});
      }
    } on BTException catch (e) {
      print(e);
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _discovery() {
    devices.clear();
    try {
      bluetoothManager.discovery().listen((device) {
        devices.add(device);
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

  void _print(int numberOfQRCodes) async {
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
          _isConnected == true;
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: _numberOfQRCodes,
                items: List.generate(10, (index) => index + 1)
                    .map((numberOfQRCodes) {
                  return DropdownMenuItem<int>(
                    value: _numberOfQRCodes,
                    child: Text('Print: $_numberOfQRCodes'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _numberOfQRCodes = newValue ?? 1;
                  });
                },
              ),
            ],
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
              child: Text('Print $_numberOfQRCodes QR Codes'),
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
                  Visibility(
                    visible: Platform.isAndroid,
                    child: SwitchListTile.adaptive(
                      contentPadding:
                          const EdgeInsets.only(bottom: 20.0, left: 20),
                      title: const Text(
                        "BLE (low energy)",
                        textAlign: TextAlign.start,
                        style: TextStyle(fontSize: 19.0),
                      ),
                      value: _isBle,
                      onChanged: (bool? value) {
                        setState(() {
                          _isBle = value ?? false;
                          _isConnected = false;
                          selectedPrinter = null;
                          _scan();
                        });
                      },
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.all(16),
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
                                            color:
                                                Colors.green) // Connected icon
                                        : const Icon(Icons.bluetooth_connected,
                                            color: Colors
                                                .red), // Disconnected icon
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
                  _isScanning
                      ? const CircularProgressIndicator()
                      : Column(
                          children: devices
                              .map(
                                (device) => ListTile(
                                  title: Text(device.name),
                                  subtitle: Text(device.address),
                                  onTap: () {
                                    // do something
                                    selectDevice(device);
                                  },
                                  trailing: OutlinedButton(
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
                                ),
                              )
                              .toList()),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _isBle ? () => _scan() : null,
          backgroundColor: _isBle ? Colors.blueAccent : Colors.grey,
          child: const Icon(Icons.bluetooth),
        ),
      ),
    );
  }
}
