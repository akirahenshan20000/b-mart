import 'package:flutter/material.dart';

class BrandBottomNavigation extends StatelessWidget {
  const BrandBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    this.dark = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<BrandNavItem> items;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    assert(items.length == 5);
    final background = dark
        ? const [Color(0xFF0A1119), Color(0xFF101D29)]
        : const [Colors.white, Color(0xFFFFF6F7)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: background),
        border: Border(top: BorderSide(color: dark ? const Color(0xFF273542) : const Color(0xFFF0DDE0))),
        boxShadow: const [BoxShadow(color: Color(0x220F1018), blurRadius: 22, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final active = selectedIndex == index;
              final primary = index == 2;
              final foreground = dark ? Colors.white : const Color(0xFF65707E);
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: active,
                  label: item.label,
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: primary ? 76 : 62,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (primary)
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFFF3650), Color(0xFFE60023), Color(0xFFA90820)],
                                ),
                                border: Border.all(color: dark ? const Color(0xFF101D29) : Colors.white, width: 4),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [BoxShadow(color: Color(0x55B30920), blurRadius: 15, offset: Offset(0, 6))],
                              ),
                              child: Icon(active ? item.activeIcon : item.icon, color: Colors.white, size: 26),
                            )
                          else
                            Container(
                              width: 42,
                              height: 34,
                              decoration: BoxDecoration(
                                color: active ? (dark ? const Color(0xFF3B1822) : const Color(0xFFFFE9EC)) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                active ? item.activeIcon : item.icon,
                                color: active ? const Color(0xFFD20A2E) : foreground,
                                size: 23,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primary ? (dark ? Colors.white : const Color(0xFFA40D25))
                                  : active ? const Color(0xFFD20A2E) : foreground,
                              fontSize: 10,
                              fontWeight: active || primary ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class BrandNavItem {
  const BrandNavItem(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
