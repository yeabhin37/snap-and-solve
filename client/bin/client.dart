import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

// 서버 주소를 상수로 만들어 관리하면 편리합니다.
final serverUrl = 'http://127.0.0.1:8000';

// 프로그램의 시작점
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    printUsage();
    return;
  }

  final command = arguments[0];
  final args = arguments.sublist(1);

  // 입력된 명령어에 따라 각각의 함수를 호출합니다.
  switch (command) {
    case 'register':
      if (args.length < 1) return print('사용법: register <사용자이름>');
      await postToServer('/register', {'username': args[0]});
      break;
    case 'add-folder':
      if (args.length < 2) return print('사용법: add-folder <사용자이름> <폴더명>');
      await postToServer('/create-folder', {
        'username': args[0],
        'folder_name': args[1],
      });
      break;
    case 'preview':
      if (args.length < 2) return print('사용법: preview <사용자이름> <이미지경로>');
      await handleOcrPreview(args[0], args[1]);
      break;
    case 'confirm':
      if (args.length < 4)
        return print('사용법: confirm <사용자이름> <임시ID> <폴더명> <정답>');
      await postToServer('/ocr/confirm', {
        'username': args[0],
        'temp_id': args[1],
        'folder_name': args[2],
        'correct_answer': args[3],
      });
      break;
    case 'folders':
      if (args.length < 1) return print('사용법: folders <사용자이름>');
      await postToServer('/folders', {'username': args[0]});
      break;
    case 'problems':
      if (args.length < 2) return print('사용법: problems <사용자이름> <폴더명>');
      await postToServer('/problems', {
        'username': args[0],
        'folder_name': args[1],
      });
      break;
    case 'solve':
      if (args.length < 2) return print('사용법: solve <문제ID> <제출할답>');
      await postToServer('/solve', {
        'problem_id': args[0],
        'user_answer': args[1],
      });
      break;
    // --- [디버깅용] 새로운 명령어 케이스 추가 ---
    case 'debug-ocr':
      if (args.length < 2) return print('사용법: debug-ocr <사용자이름> <이미지경로>');
      await handleOcrDebug(args[0], args[1]);
      break;
    default:
      print('알 수 없는 명령어입니다: $command');
      printUsage();
  }
}

Future<void> handleOcrPreview(String username, String imagePath) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    print('오류: 파일을 찾을 수 없습니다: $imagePath');
    return;
  }
  final base64Image = base64Encode(await file.readAsBytes());
  final dataUri = 'data:image/jpeg;base64,$base64Image';

  final url = Uri.parse('$serverUrl/ocr/preview');
  final headers = {'Content-Type': 'application/json'};
  final body = jsonEncode({'username': username, 'image_data': dataUri});

  print('\n[요청] /ocr/preview');

  try {
    final response = await http.post(url, headers: headers, body: body);

    print('--- 서버 응답 ---');
    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);

      // 서버 응답에서 "previews" 라는 키로 문제 목록(List)을 가져옵니다.
      final previews = responseBody['previews'] as List;

      if (previews.isEmpty) {
        print("이미지에서 문제를 찾을 수 없습니다.");
      } else {
        // [핵심 변경 1] 사람이 읽기 좋은 요약 정보를 먼저 출력합니다.
        print("총 ${previews.length}개의 문제를 감지했습니다. 저장할 문제의 temp_id를 사용하세요.");

        // [핵심 변경 2] 각 문제를 순회하면서 개별적으로 예쁜 JSON으로 출력합니다.
        for (var i = 0; i < previews.length; i++) {
          print("\n======= 감지된 문제 ${i + 1} =======");
          final problemJson = previews[i]; // 이것은 Dart의 Map 객체입니다.

          // 이 Map 객체를 다시 들여쓰기가 적용된 JSON 문자열로 변환합니다.
          final prettyJsonString = JsonEncoder.withIndent(
            '  ',
          ).convert(problemJson);
          print(prettyJsonString);
          print("==============================");
        }
      }
    } else {
      // 에러가 발생한 경우, 기존 방식대로 에러 내용을 출력합니다.
      print('오류가 발생했습니다 (코드: ${response.statusCode})');
      print('오류 내용: ${response.body}');
    }
    print('------------------');
  } catch (e) {
    print('--- 통신 오류 ---');
    print('서버에 연결할 수 없습니다. 서버가 켜져 있는지 확인해주세요.');
    print('오류 상세: $e');
    print('------------------');
  }
}

// 서버에 POST 요청을 보내는 공통 함수
Future<void> postToServer(String path, Map<String, dynamic> body) async {
  final url = Uri.parse('$serverUrl$path');
  final headers = {'Content-Type': 'application/json'};

  print('\n[요청] $path'); // 어떤 요청을 보내는지 명확히 보여줍니다.

  try {
    // http.post를 사용하여 서버에 요청을 보내고 응답을 기다립니다.
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(body), // Map을 JSON 문자열로 변환합니다.
    );
    handleResponse(response);
  } catch (e) {
    print('--- 통신 오류 ---');
    print('서버에 연결할 수 없습니다. 서버가 켜져 있는지 확인해주세요.');
    print('오류 상세: $e');
    print('------------------');
  }
}

// 서버로부터 받은 응답을 처리하는 공통 함수
void handleResponse(http.Response response) {
  print('--- 서버 응답 ---');
  if (response.statusCode >= 200 && response.statusCode < 300) {
    // 성공적인 응답 (2xx 코드)
    final responseBody = jsonDecode(response.body);
    // 사람이 보기 좋게 예쁘게 출력합니다. (들여쓰기 적용)
    final prettyJson = JsonEncoder.withIndent('  ').convert(responseBody);
    print(prettyJson);
  } else {
    // 에러 응답 (4xx, 5xx 코드)
    print('오류가 발생했습니다 (코드: ${response.statusCode})');
    print('오류 내용: ${response.body}');
  }
  print('------------------');
}

// --- [디버깅용] 새로운 핸들러 함수 추가 ---
Future<void> handleOcrDebug(String username, String imagePath) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    print('오류: 파일을 찾을 수 없습니다: $imagePath');
    return;
  }
  final base64Image = base64Encode(await file.readAsBytes());
  final dataUri = 'data:image/jpeg;base64,$base64Image';

  // 새로 만든 /ocr/debug API를 호출합니다.
  await postToServer('/ocr/debug', {
    'username': username,
    'image_data': dataUri,
  });
}

// 프로그램 사용법을 안내하는 함수
void printUsage() {
  print('''

==================================================
  나만의 맞춤형 디지털 학습지, 찍고풀고 (CLI 버전)
==================================================

사용법: dart run . <명령어> [옵션]

명령어:
  register <사용자이름>
    - 새로운 사용자를 등록합니다.
    - 예: dart run . register yebeen

  add-folder <사용자이름> <폴더명>
    - 문제 없이 새 폴더를 생성
    - 예: dart run . add-folder "수학 오답노트" 

  preview <사용자이름> <이미지 경로>
    - 이미지를 스캔하여 OCR 결과를 미리 봅니다. (임시 ID 발급)
    - 예: dart run . preview yebeen ../my_problem.jpg

  confirm <사용자이름> <임시ID> <폴더명> <정답>
    - 미리보기 결과를 확인하고 문제집에 최종 저장합니다.
    - 예: dart run . confirm yebeen <임시ID> "수학 오답노트" 2

  folders <사용자이름>
    - 해당 사용자의 모든 폴더 목록을 봅니다.
    - 예: dart run . folders yebeen

  problems <사용자이름> <폴더명>
    - 해당 폴더에 저장된 모든 문제 목록을 봅니다.
    - 예: dart run . problems yebeen "수학 오답노트"

  solve <문제ID> <제출할 답>
    - 저장된 문제를 풉니다.
    - 예: dart run . solve <문제ID> 2

  debug-ocr <사용자이름> <이미지>
    - [디버깅용] 파싱 없이 순수한 OCR 결과 텍스트만 확인
''');
}
