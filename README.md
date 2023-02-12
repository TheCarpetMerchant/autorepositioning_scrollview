A widget that will keep its exact position in the scrollview when tilting the device.
The position is kept in reference to the widget tree, which means that no matter how your widgets change between portrait and landscape, the scrollview will stay on the same widget.
If such a widget is Text, it will snap to the line in order to fully show the content of the text instead.

## Features
- Keep the scroll position relative to the widget tree when the orientation of the device changes.
- Snaps to the current line of text when such a change occurs in order to fully show the current line.
- The position can be restore using *initialIndex* and *initialAlignment*.
- Control how often is the current position registered in order not to affect performance.
- Blacklist/whitelist widgets from being considered by the automatic repositioning.
- Manually go to a certain position.
- Manually go to a certain instance of text in the widget tree.
- 