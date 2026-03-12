import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/ColorProvider.dart';

class Graphicalanalysis extends StatefulWidget {
  const Graphicalanalysis({super.key});

  @override
  State<Graphicalanalysis> createState() => _GraphicalanalysisState();
}

class _GraphicalanalysisState extends State<Graphicalanalysis> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child){
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: Center(
          child: Container(
            color: colorProvider.color,
            height: 300,
            width: 300,
            child: MyBarChart(),
          ),
        ),
      );
    });
  }
}

class MyBarChart extends StatelessWidget {
  const MyBarChart({super.key});

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        barTouchData: barTouchData,
        titlesData: titlesData,
        borderData: borderData,
        barGroups: barGroups,
        gridData: FlGridData(show: true),
        alignment: BarChartAlignment.spaceAround,
        maxY: 20
      )
    );
  }
}

BarTouchData get barTouchData => BarTouchData(
  enabled: false,
  touchTooltipData: BarTouchTooltipData(
    tooltipPadding: EdgeInsets.zero,
    tooltipMargin: 8,
    getTooltipItem: (
        BarChartGroupData group,
        int groupIndex,
        BarChartRodData rod,
        int rodIndex,
    ){
      return BarTooltipItem(
        rod.toY.toString(),
        const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)
      );
    }
  )
);

Widget getTitles(double value, TitleMeta meta){
  final style = TextStyle(
    color: Colors.blueAccent,
    fontWeight: FontWeight.bold,
    fontSize: 14
  );
  String text;
  switch(value.toInt()){
    case 0 :
      text = 'Mn';
      break;
    case 1 :
      text = 'Tu';
      break;
    case 2 :
      text = 'Wd';
      break;
    case 3 :
      text = 'Th';
      break;
    case 4 :
      text = 'Fr';
      break;
    case 5 :
      text = 'St';
      break;
    case 6 :
      text = 'Sn';
      break;
    default :
      text = '';
      break;
  }
  return SideTitleWidget(child: Text(text, style: style,), meta: meta);
}

FlTitlesData get titlesData => FlTitlesData(
  show: true,
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 30,
      getTitlesWidget: getTitles,
    )
  ),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
  topTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
  rightTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false)
  )
);

FlBorderData get borderData => FlBorderData(
  show: false
);

LinearGradient get _barGradient => LinearGradient(colors:
    [
      Colors.blueAccent,
      Colors.redAccent
    ],
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
);

List<BarChartGroupData> get barGroups =>[
  BarChartGroupData(x: 0,
    barRods: [
      BarChartRodData(toY: 8, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 1,
    barRods: [
      BarChartRodData(toY: 10, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 2,
    barRods: [
      BarChartRodData(toY: 15, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 3,
    barRods: [
      BarChartRodData(toY: 8, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 4,
    barRods: [
      BarChartRodData(toY: 16, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 5,
    barRods: [
      BarChartRodData(toY: 5, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 6,
    barRods: [
      BarChartRodData(toY: 8, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 7,
    barRods: [
      BarChartRodData(toY: 5, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),
  BarChartGroupData(x: 8,
    barRods: [
      BarChartRodData(toY: 8, gradient: _barGradient)
    ],
    showingTooltipIndicators: [0],
  ),

];


class BarChartSample extends StatefulWidget {
  const BarChartSample({super.key});

  @override
  State<BarChartSample> createState() => _BarChartSampleState();
}

class _BarChartSampleState extends State<BarChartSample> {
  @override
  Widget build(BuildContext context) {
    return const AspectRatio(aspectRatio: 1.6, child: MyBarChart(),);
  }
}

