library autorepositioning_scrollview;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Allows [AutoRepositioningScrollViewWidget]'s child to keep/restore its precise position.
///
/// Simply wrap a widget with [AutoRepositioningScrollViewWidget] and it will keep its exact position
/// relative to the actual content of the widget tree and not just the ScrollController's position.
/// This is done by analysing the element tree on scroll events, and re-positioning the ScrollController
/// when orientation changes. Re-positioning can also be triggered manually by calling [goToCurrentData].
class AutoRepositioningScrollViewController {
  AutoRepositioningScrollViewController({
    int? initialIndex,
    double? initialAlignment,
    this.ignoredKeys = const [],
    this.onlyChildrenOf,
    this.onPositionUpdated,
    this.triggerInitialGoToCurrentData = false,
    this.debounceDuration = const Duration(milliseconds: 300),
  }) {
    _scrollViewKey = GlobalKey();
    currentIndex = initialIndex ?? currentIndex;
    currentAlignment = initialAlignment ?? currentAlignment;
  }

  /// Used to get the SingleChildScrollView's context and thus access to the RenderObjects.
  late GlobalKey _scrollViewKey;

  /// Current position in the flattened widget tree.
  int currentIndex = -1;

  /// How far after the top of the [currentIndex] widget we have scrolled.
  double currentAlignment = 0;

  /// Temporary holder of data created from context.visitChildElements.
  final List<_VisitData> _datas = [];

  /// Current ScrollController.
  ScrollController scrollController = ScrollController();

  /// Debouncer for when to register a new position.
  Timer? _scrollTimer;

  /// Time to wait before registering a new position after the last scroll event.
  final Duration debounceDuration;

  /// Used to know when to re-position the [scrollController].
  Orientation? _currentOrientation;

  /// Keys of widgets that should be ignored by the positioning calculations.
  /// Typically used to ignored top or bottom widgets (ie a subtitle could not exist).
  /// Passing null as a value will lead to only widgets with a key being calculated on.
  final List<Key> ignoredKeys;

  /// If not null, [ignoredKeys] is ignored and only children of [onlyChildrenOf] will be calculated on.
  final Key? onlyChildrenOf;

  /// Called when [currentIndex] and [currentAlignment] are updated.
  final void Function()? onPositionUpdated;

  /// If true, [goToCurrentData] will be called after the first frame is drawn.
  final bool triggerInitialGoToCurrentData;

  /// When a scroll is triggered by [goToCurrentData], a scroll event is raised.
  /// We should ignore this call to prevent useless calculations (and potential incorrect values).
  bool _ignoreNextScroll = false;

  /// Whether to record the text contained by a RenderObject or not.
  bool _recordText = false;

  /// Initializes a new ScrollController.
  void _setScrollController() {
    scrollController.removeListener(_onScrollNotification);
    scrollController.dispose();
    scrollController = ScrollController();
    scrollController.addListener(_onScrollNotification);
  }

  void _onScrollNotification() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(debounceDuration, _onScroll);
  }

  /// Called with debouncing on scroll events by [scrollController].
  /// Triggers [onPositionUpdated].
  void _onScroll() {
    if (_ignoreNextScroll) {
      _ignoreNextScroll = false;
      return;
    }
    _setCurrentData();
    onPositionUpdated?.call();
  }

  /// Analysis the current element tree to extract [currentIndex] and [currentAlignment].
  void _setCurrentData() {
    if (!scrollController.hasClients) return;
    if (_scrollViewKey.currentContext == null) return;
    _visit();
    if (_datas.isEmpty) return;
    // Find the element with the revealOffset closest to 0
    currentIndex = -1;
    currentAlignment = 0;
    for (int i = 0; i < _datas.length; i++) {
      if (scrollController.offset < _datas[i].revealOffset) {
        currentIndex = i - 1;
        break;
      }
    }
    // Calculate how far along this object we have scrolled
    if (currentIndex >= 0) {
      double pixelsAlong =
          scrollController.offset - _datas[currentIndex].revealOffset;
      currentAlignment = pixelsAlong / _datas[currentIndex].size;
    }
    _datas.clear();
  }

  /// Positions the [scrollController] according to [currentIndex] and [currentAlignment].
  void goToCurrentData() {
    if (!scrollController.hasClients) return;
    if (_scrollViewKey.currentContext == null) return;
    if (currentIndex == -1) return;
    // Get all children and find out the positioning of the child we want ot go to.
    _visit();
    if (_datas.isEmpty) {
      _ignoreNextScroll = true;
      scrollController.jumpTo(0);
      return;
    }
    if (_datas.length < currentIndex) currentIndex = _datas.length - 1;
    var data = _datas[currentIndex];
    var goingTo = data.revealOffset + (data.size * currentAlignment);
    // If this is a text widget, "snap" to the top of the current line.
    if (data.textHeight > 0) {
      double offsetFromReveal = goingTo - data.textRevealOffset;
      // If we have ignored widgets we could be on them so bypass this treatment
      if (offsetFromReveal > 0) {
        // We take how much we scrolled into the current line, and remove that.
        if (offsetFromReveal < data.textHeight) {
          goingTo -= offsetFromReveal;
        } else {
          double before = offsetFromReveal % data.textHeight;
          double after = offsetFromReveal - before;
          if (before < after) {
            goingTo -= before;
          } else {
            // If we reached the end of the text, snap to the line above anyway
            if (goingTo + after >= data.textSize + data.textRevealOffset) {
              goingTo -= before;
            } else {
              goingTo += after;
            }
          }
        }
      }
    }
    _ignoreNextScroll = true;
    scrollController.jumpTo(goingTo);
  }

  /// Creates the data necessary to calculate the current position in the element tree.
  /// This data will be held in [_datas].
  void _visit() {
    _datas.clear();

    // If we're working on a specific key, we need to find that widget first.
    if (onlyChildrenOf != null) {
      _scrollViewKey.currentContext
          ?.findByKey(onlyChildrenOf!)
          ?.visitChildElements(_visiting);
    } else {
      _scrollViewKey.currentContext?.visitChildElements(_visiting);
    }

    // Sort on the revealOffset to make sure they are in order.
    _datas.sort((a, b) => a.revealOffset.compareTo(b.revealOffset));
  }

  /// Recursive method for Element.visitChildElements().
  /// Actually extracts the data we need from the element tree.
  void _visiting(Element element) {
    // Only take the elements we want to calculate on
    if (onlyChildrenOf == null) {
      if (ignoredKeys.contains(element.widget.key)) return;
    }

    // We only want the "bottom" children, so we do not register those that have children.
    if (element.hasChildren) {
      element.visitChildElements(_visiting);
    } else if (element.renderObject != null && element.size != null) {
      RenderAbstractViewport? viewport =
          RenderAbstractViewport.of(element.renderObject);

      // If we are text, we want to position ourselves to show a full line,
      // so we need some more data.
      double textSize = 0;
      double textHeight = 0;
      double textRevealOffset = 0;
      String text = '';
      if (element.renderObject is RenderParagraph) {
        textHeight = (element.renderObject! as RenderParagraph)
                .getFullHeightForCaret(const TextPosition(offset: 0)) ??
            0;
        textSize = element.size?.height ?? 0;
        // Get the revealOffset to the actual text
        textRevealOffset =
            viewport.getOffsetToReveal(element.renderObject!, 0).offset;

        if (_recordText) {
          text = (element.renderObject! as RenderParagraph).text.toPlainText();
        }
      }

      // Go back up to the "main" parent. ie, if we have a Column(Padding(Text)), we are now on the Text.
      // We need to go back up to the Padding in order to have the widget's full width.
      BuildContext? parent = element;
      while (!parent!.hasMultipleChildren) {
        var newParent = parent.parent;
        if (newParent == null) break;
        if (newParent.hasMultipleChildren) break;
        parent = newParent;
      }

      try {
        // If one of those is null, or no parent renderer exists, we don't need it.
        _datas.add(
          _VisitData(
            text: text,
            size: parent.size!.height,
            textHeight: textHeight,
            textSize: textSize,
            textRevealOffset: textRevealOffset,
            revealOffset: viewport
                .getOffsetToReveal((parent as Element).renderObject!, 0)
                .offset,
          ),
        );
      } catch (_) {}
    }
  }

  /// Positions the ScrollView to make the [text] number [instance] appears at the top of the screen.
  /// TODO : Once Longcatislong has exposed TextLayout, this can probably made better.
  void goToTextInstance(String text, int instance) {
    _recordText = true;
    _visit();

    // Visit all Text widgets and find which one holds our text.
    // Once we have it set it as our current position and scroll there.
    int numberFound = 0;
    for (int i = 0; i < _datas.length; i++) {
      numberFound +=
          RegExp(text, caseSensitive: false).allMatches(_datas[i].text).length;
      if (numberFound >= instance) {
        currentIndex = i;
        currentAlignment = 0;
        goToCurrentData();
        break;
      }
    }

    _recordText = false;
    _datas.clear();
  }
}

/// See [AutoRepositioningScrollViewController].
/// Should only be used with vertical scrolling and full-width widgets.
class AutoRepositioningScrollViewWidget extends StatefulWidget {
  const AutoRepositioningScrollViewWidget({
    required this.controller,
    required this.child,
    super.key,
  });

  final AutoRepositioningScrollViewController controller;
  final Widget child;

  @override
  State<AutoRepositioningScrollViewWidget> createState() =>
      _AutoRepositioningScrollViewWidgetState();
}

class _AutoRepositioningScrollViewWidgetState
    extends State<AutoRepositioningScrollViewWidget>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    widget.controller._setScrollController();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller.triggerInitialGoToCurrentData) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        widget.controller.goToCurrentData();
      });
    }
  }

  @override
  Future<void> didChangeMetrics() async {
    // Get the orientation from calculation MediaQuery return last value used by Flutter so it isn't correct for our use.
    final newOrientation =
        WidgetsBinding.instance.window.physicalSize.aspectRatio > 1
            ? Orientation.landscape
            : Orientation.portrait;

    // Changing orientation calls didChangeMetrics twice, once before and once after.
    // Since Flutter rebuilds in between, prevent the update of the memorized variables.
    if (widget.controller._currentOrientation == newOrientation) {
      // Memorise current position right away.
      widget.controller._setCurrentData();
      return;
    }

    // Save new values
    widget.controller._currentOrientation = newOrientation;

    // Repositioning at the next frame
    SchedulerBinding.instance
        .addPostFrameCallback((_) => widget.controller.goToCurrentData());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: widget.controller._scrollViewKey,
      controller: widget.controller.scrollController,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Holds data about an element of the element tree.
class _VisitData {
  _VisitData({
    this.text = '',
    this.revealOffset = 0,
    this.size = 0,
    this.textHeight = 0,
    this.textRevealOffset = 0,
    this.textSize = 0,
  });

  double revealOffset = 0;
  double size = 0;
  double textSize = 0;
  double textHeight = 0;
  double textRevealOffset = 0;
  String text = '';

  @override
  String toString() => '$text\n$revealOffset\n';
}

/// Utilities for [BuildContext] but mainly used for operations on [Element]s.
class _BuildContextFinder {
  _BuildContextFinder(BuildContext element, [this.key]) {
    if (key != null) {
      if (element.widget.key == key) {
        foundElement = element;
      }
    }
    // Get the information we want about our children.
    element.visitChildElements(visit);
    // Get the information we want about our parent.
    element.visitAncestorElements(getParent);
  }

  final Key? key;
  int numberOfChildren = 0;
  BuildContext? foundElement;
  BuildContext? parent;

  bool get hasChildren => numberOfChildren > 0;

  /// Handles the creation of [numberOfChildren] and [foundElement].
  void visit(Element element) {
    numberOfChildren++;
    if (key != null && foundElement == null) {
      if (element.widget.key == key) {
        foundElement = element;
        return;
      } else {
        element.visitChildElements(visit);
      }
    }
  }

  /// Sets [parent].
  bool getParent(BuildContext element) {
    parent = element;
    return false;
  }
}

/// Shorthand for [BuildContext] utilities.
extension _BuildContextUtilities on BuildContext {
  bool get hasChildren => _BuildContextFinder(this).hasChildren;
  bool get hasMultipleChildren => _BuildContextFinder(this).numberOfChildren > 1;
  BuildContext? findByKey(Key key) =>
      _BuildContextFinder(this, key).foundElement;
  BuildContext? get parent => _BuildContextFinder(this).parent;
}
