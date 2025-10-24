import 'package:flutter/material.dart';
import 'package:translator/APItranslatorPage.dart'; // 메인 번역 기능이 구현된 위젯 파일 가져오기


void main() => runApp(const MyApp());               // Flutter 앱의 메인 진입점 함수


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '나만의 번역기',
      debugShowCheckedModeBanner: false,            // 화면 오른쪽 상단의 디버그 배너 숨김

      theme: ThemeData(                             // 앱의 디자인 테마 설정
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade50,
      ),

      home: const APItranslatorPage(),              // 앱이 시작 시 표시되는 첫 화면을 'APItranslatorPage'로 지정
    );
  }
}
