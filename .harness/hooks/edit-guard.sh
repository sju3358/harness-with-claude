#!/bin/sh
# PreToolUse(Edit|Write) 훅: 작업 브랜치와 계획 승인 게이트를 파일 편집에서 강제
# 사용법: edit-guard.sh (stdin: 도구 입력 JSON)
#   .harness/state/(승인 기록) 편집 차단
#   요구사항·PRD·API 문서·feature 산출물·소스·테스트는 작업 브랜치(feat|fix/ITD-####)에서만 편집. 통합 브랜치에서 차단
#   소스·빌드 파일·테스트는 계획 승인 기록이 있을 때만 편집

dir=$(dirname "$0")
. "$dir/lib.sh"

require_jq
input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null | tr -d '\r')
[ -n "$path" ] || exit 0

rel=$(rel_path "$path")
[ -n "$rel" ] || exit 0

case "$rel" in
  .harness/state/*) deny ".harness/state/는 사용자 승인 문구로만 기록됨 (docs/rules/workflow.md)" ;;
esac

kind=other
case "$rel" in
  src/test/*|*/src/test/*) kind=code ;;
  src/*|*/src/main/*|build.gradle|build.gradle.kts|*/build.gradle|*/build.gradle.kts|settings.gradle|settings.gradle.kts|pom.xml|*/pom.xml|gradle/*|gradlew|gradlew.bat) kind=code ;;
  docs/requirements.md|docs/prd/*|docs/api/*) kind=doc ;;
  artifacts/work/_template/*|artifacts/work/README.md) ;;
  artifacts/work/*) kind=doc ;;
esac

[ "$kind" = other ] && exit 0

branch=$(current_branch)
is_work_branch "$branch" || deny "작업 브랜치(feat|fix/ITD-####)가 아님($branch). work-start로 작업 브랜치를 만들어 전환한 뒤 작업 (docs/rules/git.md)"

if [ "$kind" = code ]; then
  [ -f "$(state_dir)/plan-approved--$(branch_key "$branch")" ] \
    || deny "계획 승인 기록 없음($branch). feature-plan으로 PLAN.md를 쓰고 사용자가 '계획 승인'을 입력해야 함 (docs/rules/workflow.md)"
fi

exit 0
