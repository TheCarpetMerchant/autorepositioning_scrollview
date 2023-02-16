import 'package:flutter/material.dart';

import 'package:autorepositioning_scrollview/autorepositioning_scrollview.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AutoRepositioningScrollViewController autoRepositioningController;

  @override
  void initState() {
    super.initState();
    autoRepositioningController = AutoRepositioningScrollViewController(
      initialIndex: 5,
      initialAlignment: 0.5,
      triggerInitialGoToCurrentData: true,
      onPositionUpdated: () {
        // currentIndex and currentAlignment have been updated.
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AutoRepositioningScrollViewWidget(
      controller: autoRepositioningController,
      child: Column(
        children: [
          for (int i = 0; i < 50; i++)
            Text(
                '''$i Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.'''),
        ],
      ),
    );
  }
}
