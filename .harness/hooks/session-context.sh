#!/bin/sh
# SessionStart 훅: 하네스가 최신이 아니면 한 줄 알림(모든 브랜치, harness-version.sh)
# 작업 브랜치에서 세션이 시작·재개·압축되면 인계 상태를 컨텍스트로 출력
# 토큰 한도로 다른 계정의 새 세션이 이어 받아도 대화 맥락 없이 파일만으로 이어 가기 위함
#   - artifacts/work/F-*/HANDOFF.md의 "상태"·"진행 위치"
#   - HANDOFF.md가 아직 없으면(feature-plan 전) 요구사항·PRD·API 문서의 버전·상태 줄과 마지막 PRD 검증 회차
#   - 승인 상태(approval-status.sh), 미커밋 변경
# 출력만 하고 막지 않음

dir=$(dirname "$0")
. "$dir/lib.sh"

[ -t 0 ] || cat >/dev/null

# 하네스 최신 여부(해시 비교만). 최신이면 출력 없음. 브랜치와 상관없이 확인
v=$(sh "$dir/harness-version.sh" --quiet)
[ -n "$v" ] && printf '%s\n\n' "$v"

branch=$(current_branch)
is_work_branch "$branch" || exit 0
root=$(repo_root)

echo "하네스: 작업 브랜치($branch) 세션. 이전 세션(다른 계정일 수 있음)의 인계 상태다. 대화 기억이 아니라 이 내용과 파일로 이어 간다. 이어서 작업하기 전에 확인하고, 필요하면 HANDOFF.md 전체와 PLAN.md를 읽을 것."
found=0
for f in "$root"/artifacts/work/F-*/HANDOFF.md; do
  [ -f "$f" ] || continue
  found=1
  echo
  echo "== ${f#"$root"/}"
  awk '/^## /{ p = ($0 == "## 상태" || $0 == "## 진행 위치") } p' "$f"
done

if [ "$found" = 0 ]; then
  echo
  echo "== 문서 단계 (HANDOFF.md 없음: feature-plan 전)"
  for f in docs/requirements.md docs/prd/00-overview.md docs/api/README.md; do
    [ -f "$root/$f" ] || continue
    printf '%s: %s\n' "$f" "$(grep -E '^- (버전|상태):' "$root/$f" | tr -d '\r' | sed 's/^- //' | tr '\n' ' ' | sed 's/ *$//')"
  done
  ls "$root"/docs/prd/features/F-*.md >/dev/null 2>&1 \
    && echo "feature 명세: $(cd "$root" && ls docs/prd/features/F-*.md | tr '\n' ' ' | sed 's/ *$//')"
  v="$root/docs/verification/prd-verify.md"
  if [ -f "$v" ]; then
    last=$(tr -d '\r' < "$v" | awk '/^## 회차/{ h = $0; r = ""; c = "(결론 없음: 중단된 회차일 수 있음)" } /^- 범위:/{ r = $0 } /^### 결론:/{ c = $0 } END { if (h) print h " | " r " | " c }')
    echo "마지막 PRD 검증 회차: ${last:-없음}"
  fi
fi

echo
echo "== 승인 상태 (sh .harness/hooks/approval-status.sh)"
sh "$dir/approval-status.sh" | tail -n +2

echo
echo "== 미커밋 변경 (git status --short)"
git -C "$root" status --short | head -n 40
exit 0
