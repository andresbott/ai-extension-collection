#!/usr/bin/env bash
set -euo pipefail

has_make_target() {
  local target="$1"
  [[ -f Makefile ]] && awk -v target="$target" '
    $0 ~ "^" target "[[:space:]]*:" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' Makefile
}

run_command() {
  local display="$1"
  shift
  printf 'command=%s\n' "$display"
  "$@"
}

requested="${1:-}"
requested_kind=auto
case "$requested" in
  check=*) requested_kind=check; requested="${requested#check=}" ;;
  target=*) requested_kind=target; requested="${requested#target=}" ;;
esac

if [[ -n "$requested" ]]; then
  if [[ "$requested_kind" == target ]] || { [[ "$requested_kind" == auto ]] && has_make_target "$requested"; }; then
    display="make $requested"
    command=(make "$requested")
  else
    display="$requested"
    command=(bash -lc "$requested")
  fi
  if run_command "$display" "${command[@]}"; then
    printf 'state=pass\n'
    exit 0
  else
    status=$?
    printf 'state=fail\n'
    exit "$status"
  fi
fi

if has_make_target verify; then
  if run_command 'make verify' make verify; then
    printf 'state=pass\n'
    exit 0
  else
    status=$?
    printf 'state=fail\n'
    exit "$status"
  fi
fi

make_checks=()
for target in test lint vet check; do
  if has_make_target "$target"; then
    make_checks+=("$target")
  fi
done

if ((${#make_checks[@]})); then
  for target in "${make_checks[@]}"; do
    if run_command "make $target" make "$target"; then
      :
    else
      status=$?
      printf 'state=fail\n'
      exit "$status"
    fi
  done
  printf 'state=pass\n'
  exit 0
fi

npm_checks=()
if [[ -f package.json ]] && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  for script in test lint vet check; do
    if node -e 'const p=require("./package.json"); process.exit(p.scripts && Object.hasOwn(p.scripts, process.argv[1]) ? 0 : 1)' "$script"; then
      npm_checks+=("$script")
    fi
  done
fi

if ((${#npm_checks[@]})); then
  for script in "${npm_checks[@]}"; do
    if [[ "$script" == test ]]; then
      display='npm test'
      command=(npm test)
    else
      display="npm run $script"
      command=(npm run "$script")
    fi
    if run_command "$display" "${command[@]}"; then
      :
    else
      status=$?
      printf 'state=fail\n'
      exit "$status"
    fi
  done
  printf 'state=pass\n'
  exit 0
fi

if [[ -f go.mod ]] && command -v go >/dev/null 2>&1; then
  for check in test vet; do
    if run_command "go $check ./..." go "$check" ./...; then
      :
    else
      status=$?
      printf 'state=fail\n'
      exit "$status"
    fi
  done
  printf 'state=pass\n'
  exit 0
fi

if [[ -f pom.xml ]]; then
  maven=()
  if [[ -x ./mvnw ]]; then
    maven=(./mvnw)
  elif command -v mvn >/dev/null 2>&1; then
    maven=(mvn)
  fi
  if ((${#maven[@]})); then
    if run_command "${maven[0]} -B verify" "${maven[@]}" -B verify; then
      printf 'state=pass\n'
      exit 0
    else
      status=$?
      printf 'state=fail\n'
      exit "$status"
    fi
  fi
fi

printf 'state=skip\n'
printf 'report=no verification checks discovered\n'
