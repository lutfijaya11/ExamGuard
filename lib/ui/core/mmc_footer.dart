import 'package:flutter/material.dart';

class MmcDevFooter extends StatelessWidget {
  const MmcDevFooter({
    super.key,
    this.padding = const EdgeInsets.only(top: 14, bottom: 4),
  });

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/mmc_logo.png',
              width: 20,
              height: 20,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFF5B21B6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.code_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                fontFamily: 'Roboto',
              ),
              children: [
                TextSpan(text: 'Craft with '),
                TextSpan(
                  text: '❤',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                  ),
                ),
                TextSpan(text: ' By Micromedia Dev'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
