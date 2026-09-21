import 'package:flutter/material.dart';

/// Body-part renders and original standard-icon marks for activity categories.
class BodyPartIllustration extends StatelessWidget {
  const BodyPartIllustration({super.key, required this.category});
  final String category;
  static const assets = {
    '胸': 'chest',
    '背中': 'back',
    '肩': 'shoulders',
    '腕': 'arms',
    '脚': 'legs',
    '腹': 'abs',
  };
  @override
  Widget build(BuildContext context) {
    final label = category == '腹' ? '腹筋' : category;
    final asset = assets[category];
    return Semantics(
      label: '$labelの部位イラスト',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.expand(
          key: Key('bodyPartIllustration$category'),
          child: category == '有酸素' || category == 'HYROX'
              ? _ActivityCategoryMark(isHyrox: category == 'HYROX')
              : asset == null
              ? const Icon(
                  Icons.monitor_heart_outlined,
                  size: 46,
                  color: Color(0xFFD4162A),
                )
              : Image.asset(
                  'assets/category_muscles/$asset.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      ),
    );
  }
}

class _ActivityCategoryMark extends StatelessWidget {
  const _ActivityCategoryMark({required this.isHyrox});

  final bool isHyrox;

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 80,
        height: 88,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 4,
              child: Icon(
                isHyrox
                    ? Icons.fitness_center_rounded
                    : Icons.directions_run_rounded,
                size: 62,
                color: const Color(0xFFD4162A),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Icon(
                isHyrox
                    ? Icons.directions_run_rounded
                    : Icons.monitor_heart_outlined,
                size: 30,
                color: const Color(0xFF263238),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class BodyPartCategoryCard extends StatelessWidget {
  const BodyPartCategoryCard({
    super.key,
    required this.category,
    required this.label,
    required this.count,
    required this.onTap,
  });
  final String category;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: true,
      label: '$label、$count種目',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: Key('exerciseCategory$category'),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final imageWidth = (constraints.maxWidth * .34).clamp(84.0, 128.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: imageWidth,
                    height: 104,
                    child: BodyPartIllustration(category: category),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101820),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '$count種目',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF666D68),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF263238),
                    size: 24,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
