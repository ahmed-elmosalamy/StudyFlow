import 'package:flutter/material.dart';

const goalColorOptions = <Color>[
  Color(0xFF3F51B5),
  Color(0xFF009688),
  Color(0xFFF57C00),
  Color(0xFFD81B60),
  Color(0xFF43A047),
];

const goalColorLabels = <String>['Indigo', 'Teal', 'Orange', 'Pink', 'Green'];

Color goalColorForIndex(int index) {
  if (index < 0 || index >= goalColorOptions.length) {
    return goalColorOptions.first;
  }
  return goalColorOptions[index];
}
