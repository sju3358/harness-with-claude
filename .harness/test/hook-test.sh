#!/bin/sh
# 하네스 훅 자동 검사. setup.sh로 만든 샌드박스에서만 실행 (사용자 승인 문구 입력을 흉내 내 .harness/state/를 직접 바꾸기 때문)
# 사용법 (샌드박스 루트에서): sh .harness/test/hook-test.sh
# 각 훅에 도구 입력 JSON을 넣어 통과(0)·차단(2)을 확인하고, 끝나면 시작 전 승인 기록으로 되돌리고 처음 브랜치로 돌아감
# 실패가 하나라도 있으면 exit 1

set -u
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "git 저장소에서 실행"; exit 2; }
cd "$root" || exit 2
[ -f "$(git rev-parse --git-dir)/harness-sandbox" ] \
  || { echo "샌드박스가 아님. 하네스 저장소에서 sh .harness/test/setup.sh <폴더>로 만든 뒤 그 폴더에서 실행"; exit 2; }
[ -z "$(git status --porcelain)" ] || { echo "미커밋 변경이 있음. 브랜치를 바꾸며 검사하므로 깨끗한 상태에서 실행"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq 필요"; exit 2; }

H=.harness/hooks
S=.harness/state
start_branch=$(git rev-parse --abbrev-ref HEAD)
pass=0
fail=0

check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    echo "PASS  $1"
  else
    fail=$((fail + 1))
    echo "FAIL  $1 (기대 $2, 실제 $3)"
  fi
}

# 파일 편집 훅 입력 → 종료 코드. 두 번째 인자는 훅 인자(이전 버전 settings.json의 `claude` 인자 호환 확인용)
edit() {
  jq -nc --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p}}' | sh "$H/edit-guard.sh" ${2:-} >/dev/null 2>&1
  echo $?
}

bash_hook() {
  jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' | sh "$H/$1.sh" >/dev/null 2>&1
  echo $?
}

# 사용자 프롬프트 입력 흉내
say() {
  jq -nc --arg p "$1" '{prompt:$p}' | sh "$H/record-approval.sh" >/dev/null 2>&1
}

exists() {
  [ -f "$S/$1" ] && echo 있음 || echo 없음
}

reset_state() {
  rm -f "$S"/prd-approved "$S"/plan-approved--* "$S"/git-approved "$S"/adopt-approved "$S"/harness-off
}

bak=$(mktemp -d)
cp -p "$S"/* "$bak"/ 2>/dev/null
cleanup() {
  reset_state
  cp -p "$bak"/* "$S"/ 2>/dev/null
  rm -rf "$bak"
  git restore docs/requirements.md 2>/dev/null
  git restore docs/verification 2>/dev/null || rm -rf docs/verification
  git restore .harness/version 2>/dev/null
  git switch -q "$start_branch" 2>/dev/null
  git branch -q -d feat/ITD-9099 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$S"
reset_state

# 하네스 버전 비교 대상을 샌드박스 로컬 원격으로 바꾸고, 설치 버전을 그 main과 맞춰 둠(다른 검사에 버전 알림이 섞이지 않게)
export HARNESS_UPSTREAM="$(git remote get-url origin)"
git rev-parse origin/main > .harness/version

echo "== 하네스 버전 확인 (해시 비교)"
check "버전 같으면 --quiet 출력 없음" "" "$(sh "$H/harness-version.sh" --quiet)"
case "$(sh "$H/harness-version.sh")" in "하네스 버전: 최신"*) r=0 ;; *) r=1 ;; esac
check "버전 같으면 최신 표시" 0 $r
printf '0000000000000000000000000000000000000000\n' > .harness/version
case "$(sh "$H/harness-version.sh" --quiet)" in *"구버전 (설치 0000000, 최신 "*"harness-update"*) r=0 ;; *) r=1 ;; esac
check "버전 다르면 구버전 알림과 harness-update 안내" 0 $r
case "$(sh "$H/session-context.sh" </dev/null)" in "하네스 버전: 구버전"*) r=0 ;; *) r=1 ;; esac
check "session-context: main에서도 구버전 알림" 0 $r
case "$(HARNESS_UPSTREAM="$root/.git/no-such-repo" sh "$H/harness-version.sh" --quiet)" in *"확인 불가"*) r=0 ;; *) r=1 ;; esac
check "원본 저장소 응답 없으면 확인 불가(막지 않음)" 0 $r
mv .harness/version .harness/version.bak
check ".harness/version 없으면(하네스 원본 저장소) 출력 없음" "" "$(sh "$H/harness-version.sh" --quiet)"
mv .harness/version.bak .harness/version
check "harness-version 실행은 approval-gate 허용" 0 "$(bash_hook approval-gate 'sh .harness/hooks/harness-version.sh')"
git rev-parse origin/main > .harness/version

echo "== 통합 브랜치(main)"
git switch -q main
check "main: 요구사항 편집 차단" 2 "$(edit docs/requirements.md)"
check "main: PRD 편집 차단(절대 경로)" 2 "$(edit "$root/docs/prd/00-overview.md")"
check "main: 소스 편집 차단" 2 "$(edit src/main/java/demo/DemoApplication.java)"
check "main: 테스트 편집 차단" 2 "$(edit src/test/java/demo/DemoTest.java)"
check "main: feature 산출물(HANDOFF) 편집 차단" 2 "$(edit artifacts/work/F-01/HANDOFF.md)"
check "main: 규칙 밖 파일(README 등) 편집 허용" 0 "$(edit notes.md)"
check "main: git commit 차단(보호 브랜치)" 2 "$(bash_hook approval-gate 'git commit -m x')"
say "계획 승인"
check "main: '계획 승인' 기록 안 됨" 없음 "$(exists plan-approved--main)"

echo "== 작업 브랜치(feat/ITD-9001)"
git switch -q feat/ITD-9001
key=plan-approved--feat_ITD-9001
check "feat: 요구사항 편집 허용" 0 "$(edit docs/requirements.md)"
check "feat: API 문서 편집 허용" 0 "$(edit docs/api/README.md)"
check "feat: PLAN.md 편집 허용" 0 "$(edit artifacts/work/F-01/PLAN.md)"
check "feat: HANDOFF.md 편집 허용" 0 "$(edit artifacts/work/F-01/HANDOFF.md)"
check "feat: VERIFY.md 편집 허용" 0 "$(edit artifacts/work/F-01/VERIFY.md)"
check "feat: 추적표 편집 허용" 0 "$(edit docs/traceability.md)"
check "feat: 계획 승인 전 소스 편집 차단" 2 "$(edit src/main/java/demo/DemoApplication.java)"
check "feat: 계획 승인 전 빌드 파일 편집 차단" 2 "$(edit build.gradle)"
check "feat: 계획 승인 전 테스트 편집 차단" 2 "$(edit src/test/java/demo/DemoTest.java)"
check "feat: 계획 승인 전 멀티모듈 테스트 편집 차단" 2 "$(edit api/src/test/java/demo/DemoTest.java)"
check "승인 기록 파일 편집 차단" 2 "$(edit .harness/state/$key)"
check "승인 기록 셸 생성 차단" 2 "$(bash_hook approval-gate "touch .harness/state/$key")"

echo "== 승인 문구"
say "계획 승인 전에 뭐 해야 해?"
check "문장 속 '계획 승인'은 기록 안 됨" 없음 "$(exists "$key")"
say "계획 승인"
check "'계획 승인' 기록" 있음 "$(exists "$key")"
check "계획 승인 후 소스 편집 허용" 0 "$(edit src/main/java/demo/DemoApplication.java)"
check "계획 승인 후 빌드 파일 편집 허용" 0 "$(edit build.gradle)"
check "계획 승인 후 테스트 편집 허용" 0 "$(edit src/test/java/demo/DemoTest.java)"
check "이전 버전 훅 인자(claude)로도 같은 판정" 0 "$(edit src/test/java/demo/DemoTest.java claude)"
say "Claude 테스터"
check "폐지된 'Claude 테스터' 문구는 아무것도 기록하지 않음" 없음 "$(exists claude-tester)"

check "커밋 승인 전 git commit 차단" 2 "$(bash_hook approval-gate 'git commit -m x')"
check "푸시 승인 전 git push 차단" 2 "$(bash_hook approval-gate 'git push')"
say "커밋 승인"
check "커밋 승인 후 git commit 허용" 0 "$(bash_hook approval-gate 'git commit -m x')"
check "커밋 승인만으로 git push 차단" 2 "$(bash_hook approval-gate 'git push')"
say "커밋 푸시 승인"
check "커밋 푸시 승인 후 git push 허용" 0 "$(bash_hook approval-gate 'git push -u origin HEAD')"
check "작업 브랜치 git switch·merge 허용(approval-gate)" 0 "$(bash_hook approval-gate 'git switch -c feat/ITD-9002 && git merge main')"

# PRD 검증 회차 기록 흉내: 회차 번호, 범위, 문서 해시, 결론(빈 값이면 결론 줄 없음 = 중단된 회차)
verify_round() {
  mkdir -p docs/verification
  printf '## 회차 %s (2026-01-01)\n- 범위: %s\n- 문서 해시: %s\n\n' "$1" "$2" "$3" >> docs/verification/prd-verify.md
  [ -z "$4" ] || printf '### 결론: %s\n\n' "$4" >> docs/verification/prd-verify.md
}
prd_ok() {
  sh "$H/prd-check.sh" >/dev/null 2>&1
  echo $?
}
hash=$(sh "$H/prd-hash.sh")
say "PRD 승인"
check "전체 검증 회차 없으면 'PRD 승인' 기록 안 됨" 1 "$(prd_ok)"
verify_round 1 전체 "$hash" "수정 후 재검증"
verify_round 2 "영향 (직전 회차 1)" "$hash" "영향 범위 통과"
say "PRD 승인"
check "영향 회차만 통과하면 'PRD 승인' 기록 안 됨" 1 "$(prd_ok)"
verify_round 3 전체 0000 "승인 가능"
say "PRD 승인"
check "전체 회차 이후 문서가 바뀌면 'PRD 승인' 기록 안 됨" 1 "$(prd_ok)"
verify_round 4 전체 "$hash" ""
say "PRD 승인"
check "결론 줄 없는(중단된) 전체 회차로는 'PRD 승인' 기록 안 됨" 1 "$(prd_ok)"
verify_round 5 전체 "$hash" "승인 가능"
say "PRD 승인"
check "'PRD 승인' 후 prd-check 유효" 0 "$(prd_ok)"
printf '\n변경\n' >> docs/requirements.md
sh "$H/prd-check.sh" >/dev/null 2>&1
check "요구사항 변경 후 prd-check 무효" 1 $?
git restore docs/requirements.md
sh "$H/prd-check.sh" >/dev/null 2>&1
check "되돌리면 prd-check 다시 유효" 0 $?
rm -rf docs/verification

say "승인 취소"
check "'승인 취소'로 계획 승인 삭제" 없음 "$(exists "$key")"
check "'승인 취소'로 커밋·푸시 승인 삭제" 없음 "$(exists git-approved)"
check "승인 취소 후 테스트 편집 다시 차단" 2 "$(edit src/test/java/demo/DemoTest.java)"

echo "== git 안전"
check "git reset --hard 차단" 2 "$(bash_hook git-safety-guard 'git reset --hard')"
check "git clean -fd 차단" 2 "$(bash_hook git-safety-guard 'git clean -fd')"
check "git branch -D 차단" 2 "$(bash_hook git-safety-guard 'git branch -D feat/ITD-9001')"
check "git checkout -- . 차단" 2 "$(bash_hook git-safety-guard 'git checkout -- .')"
check "git push --force 차단" 2 "$(bash_hook git-safety-guard 'git push --force')"
check "bare git stash 차단" 2 "$(bash_hook git-safety-guard 'git stash')"
check "git stash pop 차단" 2 "$(bash_hook git-safety-guard 'git stash pop')"
check "pkill 차단" 2 "$(bash_hook git-safety-guard 'pkill java')"
check "git status 허용" 0 "$(bash_hook git-safety-guard 'git status')"
check "git switch -c 허용" 0 "$(bash_hook git-safety-guard 'git switch -c feat/ITD-9002')"
check "따옴표 안의 금지 명령 문자열은 명령으로 보지 않음" 0 "$(bash_hook git-safety-guard "git status && echo 'git reset --hard'")"

echo "== 승인 기록 보호와 상태 확인"
check "승인 기록 읽기 명령(ls) 차단" 2 "$(bash_hook approval-gate 'ls .harness/state')"
check "cat으로 시작해 뒤에서 지우는 명령 차단" 2 "$(bash_hook approval-gate "cat README.md; rm .harness/state/$key")"
check "PowerShell 역슬래시 경로 차단" 2 "$(bash_hook approval-gate 'Get-Content .harness\state\git-approved')"
check "상태 스크립트 실행은 허용" 0 "$(bash_hook approval-gate 'sh .harness/hooks/approval-status.sh')"
say "커밋 푸시 승인"
out=$(sh "$H/approval-status.sh")
case "$out" in *"커밋·푸시 승인: 커밋 푸시 (남은 시간"*) r=0 ;; *) r=1 ;; esac
check "approval-status: 커밋·푸시 승인과 남은 시간 표시" 0 $r
case "$out" in *"테스트·검증 담당"*) r=1 ;; *) r=0 ;; esac
check "approval-status: 담당 구분(Codex·테스터) 표시 없음" 0 $r
say "계획 승인"
case "$(sh "$H/approval-status.sh")" in *"계획 승인: 있음"*) r=0 ;; *) r=1 ;; esac
check "approval-status: 계획 승인 있음 표시" 0 $r
say "승인 취소"
case "$(sh "$H/approval-status.sh")" in *"계획 승인: 없음"*"커밋·푸시 승인: 없음"*) r=0 ;; *) r=1 ;; esac
check "approval-status: 승인 취소 후 없음 표시" 0 $r

echo "== Git 훅"
msg=$(mktemp)
printf 'feat/ITD-9001 제목\n\n- 내용\n' > "$msg"
sh .githooks/commit-msg "$msg" >/dev/null 2>&1
check "commit-msg: 브랜치와 같은 ITD 제목 허용" 0 $?
printf 'feat/ITD-9999 제목\n' > "$msg"
sh .githooks/commit-msg "$msg" >/dev/null 2>&1
check "commit-msg: 다른 티켓 제목 차단" 1 $?
printf '주문 API 추가\n' > "$msg"
sh .githooks/commit-msg "$msg" >/dev/null 2>&1
check "commit-msg: 형식 없는 제목 차단" 1 $?
rm -f "$msg"
printf 'refs/heads/main 0 refs/heads/main 0\n' | sh .githooks/pre-push origin x >/dev/null 2>&1
check "pre-push: main push 차단" 1 $?
printf 'refs/heads/feat/ITD-9001 0 refs/heads/feat/ITD-9001 0\n' | sh .githooks/pre-push origin x >/dev/null 2>&1
check "pre-push: 작업 브랜치 push 허용" 0 $?

echo "== 세션 인계 (계정 전환)"
say "계획 승인"
out=$(jq -nc '{session_id:"account-2-session"}' | sh "$H/session-context.sh" 2>/dev/null)
case "$out" in *"artifacts/work/F-01/HANDOFF.md"*"## 상태"*"## 진행 위치"*) r=0 ;; *) r=1 ;; esac
check "session-context: 작업 브랜치에서 HANDOFF 상태·진행 위치 출력" 0 $r
case "$out" in *"## 읽을 순서"*) r=1 ;; *) r=0 ;; esac
check "session-context: HANDOFF의 다른 절은 출력하지 않음" 0 $r
case "$out" in *"== 승인 상태"*"계획 승인: 있음"*) r=0 ;; *) r=1 ;; esac
check "session-context: 다른 세션 ID에서도 이전 승인 상태 출력" 0 $r
case "$out" in *"== 미커밋 변경"*) r=0 ;; *) r=1 ;; esac
check "session-context: 미커밋 변경 절 출력" 0 $r
say "승인 취소"
git switch -q -c feat/ITD-9099 main
out=$(sh "$H/session-context.sh" </dev/null 2>/dev/null)
case "$out" in *"HANDOFF.md 없음"*"docs/requirements.md: 버전: v0.1 상태: 작성 중"*"docs/prd/00-overview.md:"*) r=0 ;; *) r=1 ;; esac
check "session-context: HANDOFF 전이면 문서 버전·상태 출력" 0 $r
verify_round 1 전체 "$hash" ""
out=$(sh "$H/session-context.sh" </dev/null 2>/dev/null)
case "$out" in *"마지막 PRD 검증 회차: ## 회차 1"*"결론 없음"*) r=0 ;; *) r=1 ;; esac
check "session-context: 결론 없는(중단된) PRD 검증 회차 표시" 0 $r
rm -rf docs/verification
git switch -q main
out=$(sh "$H/session-context.sh" </dev/null 2>/dev/null)
check "session-context: main에서는 출력 없음" "" "$out"
git branch -q -d feat/ITD-9099
git switch -q feat/ITD-9001

echo "== 하네스 OFF/ON"
say "하네스 OFF"
check "OFF 중 계획 승인 없이 소스 편집 통과" 0 "$(edit src/main/java/demo/DemoApplication.java)"
case "$(sh "$H/approval-status.sh")" in *"하네스: OFF"*) r=0 ;; *) r=1 ;; esac
check "approval-status: OFF 중에도 OFF 상태 표시" 0 $r
say "하네스 ON"
check "ON 후 계획 승인 없는 소스 편집 다시 차단" 2 "$(edit src/main/java/demo/DemoApplication.java)"

echo
echo "결과: 통과 $pass, 실패 $fail"
[ "$fail" = 0 ]
