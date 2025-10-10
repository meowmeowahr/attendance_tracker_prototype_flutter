import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class DeveloperOptionsPage extends StatefulWidget {
  DeveloperOptionsPage({super.key, required this.settingsManager, required this.logger});

  final SettingsManager settingsManager;
  final Logger logger;

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Options'),
      ),
      body: ListView.builder(itemCount: widget.settingsManager.developerOptions.length + 1, itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            tileColor: Theme.of(context).colorScheme.errorContainer,
            leading: Icon(Icons.info, color: Theme.of(context).colorScheme.error,),
            title: Text('Warning'),
            subtitle: Text('Changing these settings may cause unexpected behavior. Proceed with caution! A restart may be required for changes to take effect.'),
          );
        }
        index--;
        return ListTile(
          minTileHeight: 64,
          leading: Icon(Icons.settings),
          title: Text(widget.settingsManager.developerOptions.keys.elementAt(index)),
          trailing: switch (widget.settingsManager.developerOptions.values.elementAt(index)) {
            double => SizedBox(
              width: 180,
              child: TextFormField(
                initialValue: widget.settingsManager.getValue<double>(widget.settingsManager.developerOptions.keys.elementAt(index)).toString(),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final doubleValue = double.tryParse(value);
                  if (doubleValue != null) {
                    setState(() {
                      widget.settingsManager.setValue(widget.settingsManager.developerOptions.keys.elementAt(index), doubleValue);
                    });
                  }
                },
              ),
            ),
            int => SizedBox(
              width: 180,
              child: TextFormField(
                initialValue: widget.settingsManager.getValue<int>(widget.settingsManager.developerOptions.keys.elementAt(index)).toString(),
                keyboardType: TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final doubleValue = int.tryParse(value);
                  if (doubleValue != null) {
                    setState(() {
                      widget.settingsManager.setValue(widget.settingsManager.developerOptions.keys.elementAt(index), doubleValue);
                    });
                  }
                },
              ),
            ),
            String => SizedBox(
              width: 180,
              child: TextFormField(
                initialValue: widget.settingsManager.getValue<String>(widget.settingsManager.developerOptions.keys.elementAt(index)),
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                    setState(() {
                      widget.settingsManager.setValue(widget.settingsManager.developerOptions.keys.elementAt(index), value);
                    });
                },
              ),
            ),
            DataFormat => SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: widget.settingsManager.getValue<String>(widget.settingsManager.developerOptions.keys.elementAt(index)),
                items: DataFormat.values.map((format) {
                  return DropdownMenuItem<String>(
                    value: format.toString().split('.').last,
                    child: Text(format.toString().split('.').last),
                  );
                }).toList(),
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    widget.settingsManager.setValue(widget.settingsManager.developerOptions.keys.elementAt(index), value);
                  });
                },
              ),
            ),
            Type() => throw UnimplementedError("Type ${widget.settingsManager.developerOptions.values.elementAt(index)} is not a supported DevOpt"),
          },
        );
      }),
    );
  }
}
