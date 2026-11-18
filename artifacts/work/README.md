# feature 작업 산출물

feature마다 그 feature의 작업 브랜치에 `artifacts/work/F-##/`를 만들고 `_template/`의 파일을 복사해 쓴다(`feature-plan`이 수행).

| 파일 | 작성 | 내용 |
| --- | --- | --- |
| `PLAN.md` | `feature-plan` | REQ ↔ 변경 파일 ↔ TC 매핑, 확인 필요, 계획 변경 이력 |
| `VERIFY.md` | `code-verifier`(mode=code) · `doc-code-verify` | 문서-코드 정합성 판정표, 메인 세션 재검증 |
| `API-VERIFY.md` | `code-verifier`(mode=api) · `api-verify` | API 문서-코드 엔드포인트·항목별 판정표 |
| `TEST-REPORT.md` | `test-verify` · `code-verifier`(mode=test) | 회차별 실행 범위·결과, 명세 누락, 테스트 유효성 판정 |
| `test-status.md` | `test-write`·`test-verify` | TC별 최신 상태(`PASS`·`FAIL`·`미실행`)와 마지막 전체 회귀. 재실행 범위의 기준 |
| `HANDOFF.md` | 모든 단계 | 현재 상태, 진행 위치, 다음 행동, 구현 수정 요청·PRD 변경 요청 |

- 토큰 한도로 세션이 끊겨 다른 계정으로 이어 받을 때는 같은 폴더·브랜치에서 `HANDOFF.md`부터 읽는다. 대화 내용이나 계정별 기억에 기대지 않는다.
- 산출물은 커밋에 포함하되 커밋 본문에는 쓰지 않는다.
- 코드 주석에 산출물 파일 경로를 인용하지 않는다(정리·이동될 수 있음).
