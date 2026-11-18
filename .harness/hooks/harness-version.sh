#!/bin/sh
# 설치된 하네스가 최신인지 해시만 비교해 알림(읽기 전용, 막지 않음)
# 사용법: sh .harness/hooks/harness-version.sh [--quiet]
#   --quiet: 최신이거나 .harness/version이 없으면 아무것도 출력하지 않음(SessionStart 훅용)
# 구버전이면 harness-update 스킬 "0. 업데이트 시점 판단"대로 처리

dir=$(dirname "$0")
. "$dir/lib.sh"

state=$(harness_version_state)
case "$state" in
  '')
    [ "${1:-}" = --quiet ] || echo "하네스 버전: 확인 대상 아님(.harness/version 없음)" ;;
  최신)
    [ "${1:-}" = --quiet ] || echo "하네스 버전: 최신 ($(cut -c1-7 < "$(repo_root)/.harness/version"))" ;;
  확인불가)
    echo "하네스 버전: 확인 불가(원본 저장소 응답 없음). 이번에는 넘어가고 다음 세션에서 다시 확인" ;;
  *)
    set -- $state
    echo "하네스 버전: 구버전 (설치 $(printf '%s' "$2" | cut -c1-7), 최신 $(printf '%s' "$3" | cut -c1-7)). harness-update 스킬 '0. 업데이트 시점 판단'대로 확인 후 업데이트할 것" ;;
esac
exit 0
