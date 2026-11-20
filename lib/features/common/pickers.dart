import 'package:flutter/material.dart';

import '../../core/constants/category_icons.dart';

class IconPickerRow extends StatelessWidget {
  const IconPickerRow({super.key, required this.selected, required this.color, required this.onChanged, this.keys});

  final String selected;
  final int color;
  final ValueChanged<String> onChanged;
  final List<String>? keys;

  @override
  Widget build(BuildContext context) {
    final options = keys ?? AppIcons.all.keys.toList();
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = options[i];
          final isSelected = key == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onChanged(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isSelected ? Color(color).withValues(alpha: 0.18) : null,
                border: Border.all(
                  color: isSelected ? Color(color) : Theme.of(context).colorScheme.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Icon(AppIcons.of(key), color: isSelected ? Color(color) : null),
            ),
          );
        },
      ),
    );
  }
}

class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({super.key, required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in AppPalette.colors)
            GestureDetector(
              onTap: () => onChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: c == selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
              ),
            ),
        ],
      );
}
