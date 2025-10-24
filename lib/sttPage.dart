import 'package:flutter/material.dart';                     // ValueNotifier 사용 위한 패키지 가져오기
import 'package:speech_to_text/speech_to_text.dart' as stt; // Speech-to-Text 라이브러리를 stt 별칭으로 가져오기

// STT 기능 캡슐화 및 상태를 ValueNotifier로 외부에 알리는 서비스 클래스
class sttPage {
  // 메인 번역 UI(APItranslatorPage)에 STT 서비스 상태를 실시간으로 알리기 위한 변수들
  // ValueNotifier를 사용하여 상태 변화 시 UI 위젯이 자동으로 리빌드될 수 있도록 합니다.
  ValueNotifier<bool> isAvailable = ValueNotifier(false); // STT 서비스 사용 가능 여부
  ValueNotifier<bool> isListening = ValueNotifier(false); // 현재 음성 인식이 진행 중인지 여부

  // Speech-to-Text 라이브러리의 핵심 객체 생성
  final stt.SpeechToText _speech = stt.SpeechToText();

  // STT의 지원 언어 및 지역 목록을 저장할 리스트
  List<stt.LocaleName> _localeNames = [];

  // STT 서비스 초기화 및 마이크 권한 확인을 수행하는 비동기 함수
  Future<void> initialize(Function(String error) onError) async {
    final bool available = await _speech.initialize( // 호출 → STT 서비스 초기화 및 사용 가능 여부(권한 등) 확인
      onError: (error) { // STT 초기화 또는 리스닝 중 오류 발생 시 호출되는 콜백 함수
        if (isListening.value) { // 리스닝 중 오류가 발생했다면
          isListening.value = false; // 리스닝 상태를 즉시 false로 설정
        }
        onError(error.errorMsg); // 오류 메시지를 UI(메인 모듈)에 전달
      },
      onStatus: (status) { // 음성 인식 엔진의 상태 변화 'listening', 'notListening' 시 호출
        // 상태 변화를 ValueNotifier로 반영
        isListening.value = status == 'listening'; // 'listening' 상태일 때만 isListening.value를 true로 설정
      },
    );

    // initialize()의 최종 반환값(available)에 따라 STT 서비스의 사용 가능 상태 변수 업데이트
    isAvailable.value = available;

    if (available) { // STT 서비스 사용이 가능하다면
      // STT가 지원하는 로케일 목록을 가져와 _localeNames에 저장
      _localeNames = await _speech.locales();
    } else { // STT 서비스 사용이 불가능할 경우 디버그 메시지 출력
      debugPrint('STT 초기화 실패, STT 서비스 사용 불가!');
    }
  }

  // 음성 인식 시작 함수
  Future<void> startListening(
      String languageCode, // 사용자가 선택한 언어 코드 (예: 'ko', 'en')
      Function(String recognizedText, bool isFinalResult) onResult, // 텍스트 결과마다 호출될 콜백
      ) async {
    // 서비스 불가능하거나 지원 로케일 목록이 비어 있으면 즉시 함수 종료
    if (!isAvailable.value || _localeNames.isEmpty) {
      return;
    }

    // languageCode와 일치하는 로케일 ID를 찾기
    final sttLocaleId = _localeNames.firstWhere(
      // localeId가 전달받은 languageCode로 시작하는 첫 번째 로케일을 찾기
          (locale) => locale.localeId.startsWith(languageCode),
      // 일치하는 로케일이 없으면 목록의 첫 번째 항목을 대체하여 사용
      orElse: () => _localeNames.first,
    ).localeId;

    // Speech-to-Text 엔진을 사용하여 음성 인식 시작
    await _speech.listen(
      localeId: sttLocaleId, // 찾은 로케일 ID를 사용하여 특정 언어로 인식하도록 지정
      onResult: (r) { // 인식된 텍스트 결과가 나올 때마다 콜백 호출
        onResult(r.recognizedWords, r.finalResult);
        if (r.finalResult) { // 최종 결과(사용자가 말을 멈춤)일 때
          isListening.value = false; // 인식 끝남 상태로 변경
        }
      },
      listenFor: const Duration(seconds: 15), // 최대 15초 동안 음성 입력 대기
    );
  }

  // 음성 인식 중지 함수
  Future<void> stopListening() async {
    await _speech.stop();
    isListening.value = false; // 인식 끝남 상태로 변경
  }

  // 리소스 정리 함수 (위젯이 제거될 때 호출되어 메모리 누수 방지)
  void dispose() {
    stopListening(); // 활성화된 음성 인식 즉시 중단
    // ValueNotifier 객체의 리소스를 해제 → 외부 위젯과의 연결 해제
    isAvailable.dispose();
    isListening.dispose();
  }
}
