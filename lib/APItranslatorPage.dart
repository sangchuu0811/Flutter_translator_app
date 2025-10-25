// 패키지 가져오기
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart'; // TTS(Text-to-Speech) 기능
import 'package:flutter/services.dart'; // 클립보드 접근 등 시스템 서비스

import 'package:translator/sttPage.dart' as sttP; // 음성 인식 서비스 모듈 (sttP 별칭 사용)
import 'dart:convert'; // JSON 인코딩/디코딩
import 'package:http/http.dart' as http; // HTTP 통신을 통한 API 요청

// TTS 재생 상태를 명확하게 관리하기 위한 열거형(Enum)
enum TtsState { playing, stopped }

// API 키와 베이스 URL을 사용하여 Google Cloud Translation API에 직접 요청 송신
const String googleApiKey = "API키 입력";
const String translationApiBaseUrl = 'translation.googleapis.com';

// '자동 감지' 기능을 위한 상수 코드 정의
const String autoDetectCode = 'auto';

// 색상 테마 정의: 녹색 계열의 세련된 디자인 테마
final ThemeData greenTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF416869), // 시드 색상
    primary: const Color(0xFF2E494A), // 주 색상: 짙은 녹청색 (앱바, 버튼 아이콘 등)
    secondary: const Color(0xFF5F9E9F), // 보조 색상: 밝은 청록색 (스왑 버튼 등)
    error: Colors.red.shade700, // 오류 색상: 마이크 사용 중 표시 등
    background: Colors.grey.shade50, // 배경색: 매우 옅은 회색
  ),
  useMaterial3: true,
);

// 언어 코드와 이름 매핑을 위한 맵 (드롭다운 초기값 용도)
final Map<String, String> _initialLanguageMap = {
  '한국어': 'ko',
  '日本語': 'ja',
  '中文(简体)': 'zh-CN',
};

// 이름 조회용으로만 사용할 전체 언어 데이터 (지원하는 모든 언어 목록)
final Map<String, String> _fullLanguageData = {
  '한국어': 'ko',
  'English': 'en',
  '日本語': 'ja',
  'Español': 'es',
  'Français': 'fr',
  '中文(简体)': 'zh-CN',
  'Deutsch': 'de',
  'Italiano': 'it',
  'Português': 'pt',
  'Pусский': 'ru',
  'العربية': 'ar',
  'Svenska': 'sv',
};

// 💡 헬퍼 함수: 코드로부터 언어 이름을 가져옵니다. (전체 맵 _fullLanguageData 사용)
String _getLanguageNameFromCode(String code) {
  if (code == autoDetectCode) return '자동 감지';

  // 맵을 순회하며 코드와 일치하는 항목의 키(이름)를 반환
  final entry = _fullLanguageData.entries.firstWhere(
        (entry) => entry.value == code,
    // 일치하는 코드가 없으면 코드를 대문자 이름으로 사용
    orElse: () => MapEntry(code.toUpperCase(), code),
  );
  return entry.key;
}

// 메인 번역기 페이지 (StatefulWidget)
class APItranslatorPage extends StatefulWidget {
  const APItranslatorPage({super.key});

  @override
  State<APItranslatorPage> createState() => APItranslatorPageState();
}

class APItranslatorPageState extends State<APItranslatorPage> {
  // ---핵심 객체 변수 ---
  final FlutterTts _flutterTts = FlutterTts(); // TTS 엔진 인스턴스
  final sttP.sttPage _sttService = sttP.sttPage(); // STT 서비스 인스턴스

  // UI 제어 및 상태 변수
  final TextEditingController _textController = TextEditingController(); // 원본 텍스트 입력
  final TextEditingController _translatedController = TextEditingController(); // 번역 결과 출력
  TtsState _ttsState = TtsState.stopped; // TTS 재생 상태
  bool _isTranslating = false; // 현재 번역 API 요청 중인지 여부

  // 마지막으로 번역을 실행한 텍스트를 저장하여 불필요한 API 호출을 방지
  String _lastTranslatedText = '';

  // --- 언어 선택 변수 ---
  // 현재 드롭다운에 표시할 언어 목록 (초기값 + 런타임에 감지된 언어 추가)
  Map<String, String> _languages = Map.from(_initialLanguageMap);

  String _fromLanguage = autoDetectCode; // 출발 언어 (기본: 자동 감지)
  String _toLanguage = 'ja'; // 도착 언어 (기본: 일본어)
  String _detectedSourceLanguage = ''; // API 응답으로 감지된 출발 언어 코드

  // 1. 언어 코드에 해당하는 국기 이모지 문자열을 반환 함수
  String _getFlagEmoji(String langCode) {
    switch (langCode) {
      case 'ko':
        return '🇰🇷';
      case 'en':
        return '🇺🇸';
      case 'ja':
        return '🇯🇵';
      case 'es':
        return '🇪🇸';
      case 'fr':
        return '🇫🇷';
      case 'zh-CN':
        return '🇨🇳';
      case 'de':
        return '🇩🇪';
      case 'it':
        return '🇮🇹';
      case 'pt':
        return '🇧🇷'; // 포르투갈어(브라질)
      case 'ru':
        return '🇷🇺';
      case 'ar':
        return '🇸🇦'; // 아랍어(사우디아라비아)
      case 'sv':
        return '🇸🇪';
      default:
        return '🌐'; // 기타 (지구본 아이콘)
    }
  }

  // 2. --- 위젯 생명주기 메서드 ---
  @override
  void initState() {
    super.initState();
    _initTTS();
    _initSTT();

    // 텍스트 컨트롤러에 리스너를 추가하여 텍스트가 변경될 때마다 _onTextChange 호출
    // 이를 통해 사용자가 텍스트를 입력하면 자동으로 번역이 실행
    _textController.addListener(_onTextChange);

    // 번역 결과 텍스트나 STT 상태가 변경될 때마다 UI(아이콘)를 갱신하도록 설정
    _translatedController.addListener(_updateIconVisibility);
    _sttService.isListening.addListener(_updateIconVisibility);
  }

  // 텍스트 변경 시 자동 호출
  void _onTextChange() {
    // 텍스트 필드 아이콘 가시성 업데이트 (지우기/복사 버튼 등)
    _updateIconVisibility();

    final currentText = _textController.text.trim();

    // 텍스트가 비어있지 않고, 현재 번역 중이 아니며, 직전에 번역했던 내용과 다를 때만
    if (currentText.isNotEmpty && !_isTranslating && currentText != _lastTranslatedText) {
      _translate();  // 번역을 실행 → API 중복 호출 방지
    } else if (currentText.isEmpty) {
      // 텍스트가 비워지면 번역 결과, 감지된 언어, 마지막 번역 텍스트를 모두 초기화
      _clearTranslatedText();
      _detectedSourceLanguage = '';
      _lastTranslatedText = '';
    }
  }

  // 상태 변경 없이 단순히 build()를 호출하여 아이콘 등을 갱신
  void _updateIconVisibility() {
    setState(() {});
  }

  @override
  void dispose() {
    // 모든 리스너를 반드시 제거하여 메모리 누수를 방지
    _textController.removeListener(_onTextChange);
    _translatedController.removeListener(_updateIconVisibility);
    _sttService.isListening.removeListener(_updateIconVisibility);

    _textController.dispose();
    _translatedController.dispose();
    _flutterTts.stop(); // TTS 재생 중지
    _sttService.dispose(); // STT 서비스 리소스 정리
    super.dispose();
  }

  // --- STT (음성 인식) 기능 ---
  Future<void> _initSTT() async {
    await _sttService.initialize(
          (errorMsg) {
        if (mounted) {
          // 오류 발생 시 사용자에게 표시하는 코드는 제거하고, 콘솔에만 출력
          print('음성 인식 오류: $errorMsg');
        }
      },
    );
    if (!_sttService.isAvailable.value && mounted) {
      // STT 초기화 실패 시 콘솔에 출력
      print('STT 초기화 실패, STT 서비스 사용 불가!');
    }
    setState(() {}); // STT 가용 상태가 변경되면 UI 갱신 (마이크 아이콘 색상/활성화 상태 등)
  }

  Future<void> _startListening() async {
    if (_ttsState == TtsState.playing) await _stop(); // TTS 재생 중이면 중지

    // '자동 감지'이거나 드롭다운에 없는 언어면 'ko'를 기본값으로 사용
    final sttLang = (_fromLanguage == autoDetectCode || !_languages.containsValue(_fromLanguage))
        ? 'ko' : _fromLanguage;

    await _sttService.startListening(
      sttLang,
          (recognizedText, isFinalResult) {
        // STT 결과가 들어올 때마다 텍스트 컨트롤러를 업데이트 → _onTextChange 리스너가 호출되어 실시간 자동 번역
        _textController.text = recognizedText;
      },
    );
  }

  Future<void> _stopListening() async {
    await _sttService.stopListening();
  }

  Future<void> _toggleListening() async {
    if (_sttService.isListening.value) {
      // 현재 듣고 있는 중이면 중지
      await _stopListening();
    } else {
      // STT 사용 가능하면 시작
      if (_sttService.isAvailable.value) {
        // 음성 인식을 시작하기 전에 현재 텍스트를 _lastTranslatedText에 저장
        // → 매번 불필요한 API 번역이 시작되는 것을 방지합니다.
        _lastTranslatedText = _textController.text.trim();
        await _startListening();
      } else if (mounted) {
        // STT 불가능 시 콘솔 출력
        print('음성 인식이 불가능하여 _toggleListening 호출 실패');
      }
    }
  }

  // --- 핵심 기능 함수 ---

  // TTS 초기화 및 상태 핸들러 설정
  Future<void> _initTTS() async {
    _flutterTts.setStartHandler(() {
      setState(() => _ttsState = TtsState.playing); // 재생 시작 시 상태 업데이트
    });
    _flutterTts.setCompletionHandler(() {
      setState(() => _ttsState = TtsState.stopped); // 재생 완료 시 상태 업데이트
    });
    _flutterTts.setErrorHandler((msg) {
      setState(() => _ttsState = TtsState.stopped); // 오류 발생 시 상태 업데이트
    });
  }

  // 원본 텍스트 입력 필드 전체 초기화
  Future<void> _clearSourceText() async {
    if (_sttService.isListening.value) {
      await _sttService.stopListening(); // 음성 인식 중이면 중지
    }

    setState(() {
      _textController.clear();
      _translatedController.clear();
      _isTranslating = false;
      _detectedSourceLanguage = '';
      _lastTranslatedText = ''; // 마지막 번역 텍스트 초기화
    });
  }

  // 번역 결과 필드만 초기화
  Future<void> _clearTranslatedText() async {
    _flutterTts.stop();
    setState(() {
      _translatedController.clear();
      _ttsState = TtsState.stopped;
    });
  }

  // 번역 수행 함수
  Future<void> _translate() async {
    final String sourceText = _textController.text.trim();
    if (sourceText.isEmpty || _isTranslating) {
      _translatedController.clear();
      return;
    }

    // API 요청 중임을 표시하고 중복 호출 방지
    if (_isTranslating) return;
    setState(() => _isTranslating = true);

    // _lastTranslatedText를 현재 텍스트로 업데이트하여 중복 호출 방지 로직 적용
    _lastTranslatedText = sourceText;

    // 출발 언어와 도착 언어가 같을 경우 API 호출을 생략
    final bool isSameLanguage = (_fromLanguage != autoDetectCode && _fromLanguage == _toLanguage);

    if (isSameLanguage) {
      // API 호출 없이 원본 텍스트를 번역 결과에 복사하고 종료
      setState(() {
        _translatedController.text = sourceText;
        _detectedSourceLanguage = _fromLanguage;
        _isTranslating = false;
      });
      return;
    }

    // Google Cloud Translation API 요청 URL 구성
    final uri = Uri.https(
      translationApiBaseUrl,
      '/language/translate/v2', // v2 API
      {'key': googleApiKey}, // API 키를 쿼리 매개변수로 포함
    );

    // API 요청 본문(Body) 구성
    final Map<String, dynamic> bodyMap = {
      'q': sourceText, // 번역할 텍스트
      'target': _toLanguage, // 도착 언어
      'format': 'text',
    };

    // 출발 언어가 '자동 감지'가 아니면 요청 본문에 명시적으로 포함
    if (_fromLanguage != autoDetectCode) {
      bodyMap['source'] = _fromLanguage;
    }

    try {
      // HTTP POST 요청 실행
      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(bodyMap), // JSON 본문을 인코딩하여 전송
      );

      if (response.statusCode == 200) {
        // 성공적인 응답 처리
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final translationData = jsonResponse['data']['translations'][0];

        final String translatedText = translationData['translatedText'];
        // API에서 감지된 출발 언어 코드 추출
        final String detectedLang = translationData['detectedSourceLanguage'] ?? autoDetectCode;

        setState(() {
          _translatedController.text = translatedText;
          _detectedSourceLanguage = detectedLang;

          // 출발 언어가 '자동 감지'로 설정되어 있고, 실제로 언어가 감지된 경우
          if (_fromLanguage == autoDetectCode && detectedLang != autoDetectCode) {
            final newLanguageName = _getLanguageNameFromCode(detectedLang);

            // 감지된 언어를 드롭다운 목록에 추가
            if (!_languages.containsValue(detectedLang)) {
              _languages[newLanguageName] = detectedLang;
            }

            // UI의 출발 언어를 감지된 언어로 업데이트
            _fromLanguage = detectedLang;
          }
        });
      } else {
        // API 오류 응답 처리
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        final errorMessage = errorBody['error']['message'] ?? '알 수 없는 API 오류';

        if (mounted) {
          // 오류 메시지를 사용자에게 스낵바로 표시
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('번역 API 오류 (${response.statusCode}): $errorMessage')),
          );
        }
      }
    } catch (e) {
      // 네트워크 또는 기타 예외 처리
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('번역 요청 중 네트워크 오류가 발생했습니다: $e')));
      }
    } finally {
      // 번역 완료 후 로딩 상태 해제
      setState(() => _isTranslating = false);
    }
  }

  // TTS를 사용하여 번역 결과를 음성으로 재생
  Future<void> _speak() async {
    if (_translatedController.text.isNotEmpty) {
      // 도착 언어 코드를 사용하여 TTS 언어 설정
      await _flutterTts.setLanguage(_toLanguage);
      await _flutterTts.setSpeechRate(0.5); // 재생 속도 설정
      await _flutterTts.speak(_translatedController.text);
    }
  }

  // TTS 재생 중지
  Future<void> _stop() async {
    await _flutterTts.stop();
  }

  // 클립보드로 텍스트 복사
  Future<void> _copyToClipboard(String text) async {
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('텍스트가 클립보드에 복사되었습니다.')),
        );
      }
    }
  }


  // 언어 교환 로직: 출발 언어와 도착 언어, 그리고 텍스트 내용을 교환
  void _swapLanguages() {
    _stop();
    if (_sttService.isListening.value) _stopListening(); // STT 중지

    setState(() {
      // 언어 코드 교환
      final tempLang = _fromLanguage;
      _fromLanguage = _toLanguage;
      _toLanguage = tempLang;

      // 텍스트 내용 교환
      final tempText = _textController.text;
      _textController.text = _translatedController.text;
      _translatedController.text = tempText;

      _detectedSourceLanguage = '';
      // 스왑 후 즉시 새로운 번역을 실행하기 위해 _lastTranslatedText 초기화
      _lastTranslatedText = '';
    });

    _translate(); // 교환된 텍스트로 즉시 번역 실행
  }

  // --- UI 컴포넌트 빌더 ---

  // [Widget] 드롭다운 버튼 자체를 만드는 헬퍼 함수
  Widget _buildDropdownButton(String value, ValueChanged<String?> onChanged, ThemeData theme, {required bool isSource}) {

    // 출발지 드롭다운은 '자동 감지' 옵션을 포함
    Map<String, String> dropdownItems = isSource ? {'자동 감지': autoDetectCode, ..._languages} : _languages;

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
        items: dropdownItems.entries.map((entry) {
          final itemFlag = _getFlagEmoji(entry.value);
          final displayKey = entry.key;

          return DropdownMenuItem<String>(
            value: entry.value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(itemFlag, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5), // 간격 유지
                Text(displayKey, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 11.0)),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged, // 언어 변경 시 호출되는 콜백
        // 선택된 항목이 드롭다운 버튼 자체에 표시되는 방식 정의
        selectedItemBuilder: (context) {
          return dropdownItems.entries.map((entry) {
            if (entry.value == value) {
              final itemFlag = _getFlagEmoji(entry.value);
              final displayKey = entry.key;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(itemFlag, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 5), // 간격 유지
                    Text(displayKey, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 11.0)),
                  ],
                ),
              );
            }
            return Container();
          }).toList();
        },
      ),
    );
  }

  // [Widget] 언어 선택 및 교환 기능 카드
  Widget _buildLanguageSelectionCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.4), width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // 1. 출발 언어 드롭다운 (자동 감지 옵션 포함)
            Expanded(
              child: _buildDropdownButton(
                _fromLanguage,
                    (val) {
                  if (val != null) {
                    if (val == _toLanguage) {
                      _swapLanguages(); // 출발지와 도착지 언어가 같으면 교환
                    } else {
                      // 출발 언어 변경 후 번역 실행
                      setState(() {
                        _fromLanguage = val;
                      });
                      _translate();
                    }
                  }
                },
                theme,
                isSource: true,
              ),
            ),

            // 2. 언어 교환 버튼
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 28),
                onPressed: _swapLanguages,
                tooltip: '언어 교환',
              ),
            ),
            const SizedBox(width: 8),

            // 3. 도착 언어 드롭다운
            Expanded(
              child: _buildDropdownButton(
                _toLanguage,
                    (val) {
                  if (val != null) {
                    if (val == _fromLanguage) {
                      _swapLanguages(); // 도착지와 출발지 언어가 같으면 교환
                    } else {
                      // 도착 언어 변경 후 번역 실행
                      setState(() {
                        _toLanguage = val;
                      });
                      _translate();
                    }
                  }
                },
                theme,
                isSource: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [Widget] 상단 컨트롤 바 (언어 선택 + 기능 아이콘)을 포함하는 컨테이너
  Widget _buildTopControlBar(ThemeData theme) {
    return Column(
      children: [
        _buildLanguageSelectionCard(theme),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildVoiceButton(theme), // 음성 인식 버튼
              _buildTranslateButton(theme), // 번역 실행 버튼/로딩 인디케이터
            ],
          ),
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  // [Widget] 음성 인식 버튼 (마이크 / 중지)
  Widget _buildVoiceButton(ThemeData theme) {
    final bool isListening = _sttService.isListening.value;
    // 듣는 중일 때는 에러 색상(빨간색)으로 강조
    final iconColor = isListening ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: iconColor.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(
          isListening ? Icons.stop : Icons.mic,
          color: iconColor,
          size: 30,
        ),
        onPressed: _toggleListening, // 음성 인식 시작/중지 토글
        tooltip: isListening ? '음성 입력 중지' : '음성으로 입력하기',
      ),
    );
  }

  // [Widget] 번역 실행 버튼 (수동 호출/로딩 표시)
  Widget _buildTranslateButton(ThemeData theme) {
    // 번역 중이거나 STT가 활성화되어 있으면 '사용 중' 상태로 간주
    final bool isBusy = _isTranslating || _sttService.isListening.value;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IconButton(
        icon: isBusy
            ? SizedBox( // 사용 중일 경우 로딩 인디케이터 표시
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              color: theme.colorScheme.primary, strokeWidth: 3),
        )
            : Icon( // 사용 가능할 경우 번역 아이콘 표시
          Icons.translate,
          color: theme.colorScheme.primary,
          size: 30,
        ),
        // 자동 번역이 기본이나, 로딩 중이 아닐 때 수동으로 번역 호출 가능
        onPressed: isBusy ? null : _translate,
        tooltip: '번역 실행',
      ),
    );
  }

  // [Widget] 텍스트 입력/출력 필드를 공통으로 생성하는 함수
  Widget _buildTextField({
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    bool readOnly = false,
    Widget? suffixIcon,
  }) {
    // 감지된 언어를 '원본 텍스트' 필드 상단에 표시할지 결정하는 플래그
    // 조건: 원본 텍스트 필드, 감지된 언어가 비어있지 않고, 수동 설정 언어와 감지된 언어가 일치할 때
    final bool showDetected = label == '원본 텍스트' &&
        _detectedSourceLanguage.isNotEmpty &&
        _detectedSourceLanguage != autoDetectCode &&
        _fromLanguage != autoDetectCode && // 출발 언어가 수동 설정된 경우에만 (자동 감지 상태에서는 이미 드롭다운에 표시되므로)
        _fromLanguage == _detectedSourceLanguage;

    String detectedName = '';
    if (showDetected) {
      detectedName = _getLanguageNameFromCode(_detectedSourceLanguage);
    }

    // 힌트 텍스트 로직 (현재 상태에 따라 변경)
    String hint = readOnly
        ? (_isTranslating ? '번역하고 있습니다 ..' : '번역 결과가 여기에 표시됩니다.')
        : (_sttService.isListening.value ? '듣고 있습니다 ..' : '음성 인식 또는 입력하세요.');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withOpacity(0.4),
          width: 1.5,),),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 15, top: 15),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      fontSize: 16,
                    ),
                  ),
                ),
                // 감지된 언어 표시 영역
                if (showDetected)
                  Expanded(
                    child: Text(
                      ' ($detectedName감지)',
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        color: theme.colorScheme.primary.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.clip,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                border: InputBorder.none, // 기본 밑줄 제거
                contentPadding: const EdgeInsets.only(left: 15),
                suffixIcon: suffixIcon, // 우측 하단 아이콘들 (복사/지우기/TTS)
              ),
              maxLines: null, // 여러 줄 입력 가능
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }


  // --- UI 구성 ---
  @override
  Widget build(BuildContext context) {
    final theme = greenTheme;

    return MaterialApp(
      title: '간단 언어 번역기',
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('번역기'),
          backgroundColor: theme.colorScheme.primary,
          elevation: 1,
          titleTextStyle: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(
            color: theme.colorScheme.onPrimary,
          ),
        ),
        // 키보드가 올라올 때 화면이 리사이즈되는 것을 방지 (텍스트 필드가 찌그러지는 현상 방지)
        resizeToAvoidBottomInset: false,

        backgroundColor: theme.colorScheme.background,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 60.0), // 하단 패딩을 여유 있게 설정
          child: Column(
            children: [
              // [UI Block 1] 상단 컨트롤 바 (언어 선택 + 기능 아이콘)
              _buildTopControlBar(theme),
              const SizedBox(height: 16),

              // [UI Block 2] 원본 텍스트 입력 필드
              Expanded(
                child: _buildTextField(
                  theme: theme,
                  controller: _textController,
                  label: '원본 텍스트',
                  // 텍스트가 있을 때만 복사/지우기 아이콘 표시
                  suffixIcon: _textController.text.isNotEmpty
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.copy, color: theme.colorScheme.primary),
                              onPressed: () => _copyToClipboard(_textController.text),
                              tooltip: '원본 텍스트 복사',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: theme.colorScheme.primary),
                              onPressed: _clearSourceText,
                              tooltip: '원본 텍스트 지우기',
                            ),
                          ],
                        ),
                      )
                    ],
                  )
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // [UI Block 3] 번역 결과 출력 필드
              Expanded(
                child: _buildTextField(
                  theme: theme,
                  controller: _translatedController,
                  label: '번역된 텍스트',
                  readOnly: true, // 읽기 전용
                  // 번역 결과가 있을 때만 TTS/복사/지우기 아이콘 표시
                  suffixIcon: _translatedController.text.isNotEmpty
                      ? Row(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          children: [
                            // TTS 버튼 (재생/중지)
                            IconButton(
                              icon: Icon(
                                _ttsState == TtsState.playing
                                    ? Icons.stop_circle
                                    : Icons.volume_up,
                                color: theme.colorScheme.primary,
                              ),
                              onPressed: _ttsState == TtsState.playing ? _stop : _speak,
                              tooltip: '음성 듣기/중지',
                            ),
                            // 복사 버튼
                            IconButton(
                              icon: Icon(
                                Icons.copy,
                                color: theme.colorScheme.primary,
                              ),
                              onPressed: () => _copyToClipboard(_translatedController.text),
                              tooltip: '번역 결과 복사',
                            ),
                            // 지우기 버튼
                            IconButton(
                              icon: Icon(Icons.delete, color: theme.colorScheme.primary),
                              onPressed: _clearTranslatedText,
                              tooltip: '번역 결과 지우기',
                            ),
                          ],
                        ),
                      )
                    ],
                  )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
