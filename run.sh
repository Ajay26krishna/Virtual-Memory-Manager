#!/usr/bin/env bash
set -euo pipefail

# ============================================
# CONFIG
# ============================================
EXEC="./tester"
INPUT_DIR="sample_input"
EXPECTED_DIR="sample_output"
OUT_DIR="output"

mkdir -p "$OUT_DIR"

# ============================================
# Policy selection: 1 = FIFO, 2 = Third Chance
# ============================================
ALL_POLICY_ARGS=("1" "2")
ALL_POLICY_NAMES=("FIFO" "Third")

SELECTED_POLICY_ARGS=()
SELECTED_POLICY_NAMES=()
COMBINED_SUFFIX="both"

case "${1-}" in
  "")
    SELECTED_POLICY_ARGS=("${ALL_POLICY_ARGS[@]}")
    SELECTED_POLICY_NAMES=("${ALL_POLICY_NAMES[@]}")
    COMBINED_SUFFIX="both"
    ;;
  "1")
    SELECTED_POLICY_ARGS=("1")
    SELECTED_POLICY_NAMES=("FIFO")
    COMBINED_SUFFIX="1"
    ;;
  "2")
    SELECTED_POLICY_ARGS=("2")
    SELECTED_POLICY_NAMES=("Third")
    COMBINED_SUFFIX="2"
    ;;
  *)
    echo "Usage: $0 [1|2]"
    echo "  (no arg)  Run both FIFO and Third Chance"
    echo "  1         Run FIFO only"
    echo "  2         Run Third Chance only"
    exit 2
    ;;
esac

COMBINED_REPORT="${OUT_DIR}/combined_policy_${COMBINED_SUFFIX}.txt"

# ============================================
# Helper: normalize output (ignore CR, trailing spaces, trailing blank lines)
# ============================================
normalize() {
  tr -d '\r' | awk '
    { sub(/[ \t]+$/, "", $0); lines[NR]=$0 }
    END {
      last=NR
      while (last>0 && lines[last]=="") last--
      for (i=1;i<=last;i++) print lines[i]
    }'
}

policy_selected() {
  local p="$1"
  for q in "${SELECTED_POLICY_ARGS[@]}"; do
    [[ "$q" == "$p" ]] && return 0
  done
  return 1
}

# ============================================
# Build (if Makefile present)
# ============================================
if [[ -f Makefile ]]; then
  echo "[build] Running make..."
  make -s
fi

# Validate dirs
[[ -d "$INPUT_DIR" ]]    || { echo "Missing $INPUT_DIR"; exit 1; }
[[ -d "$EXPECTED_DIR" ]] || { echo "Missing $EXPECTED_DIR"; exit 1; }

# Collect expected files
mapfile -t EXPECTED_FILES < <(find "$EXPECTED_DIR" -maxdepth 1 -type f -name 'result-*' | sort -V)
if (( ${#EXPECTED_FILES[@]} == 0 )); then
  echo "No expected files in $EXPECTED_DIR/result-*"
  exit 1
fi

# ============================================
# Init counters and header
# ============================================
declare -i total_cases=0
declare -i total_correct=0
declare -A policy_total
declare -A policy_correct

for idx in "${!SELECTED_POLICY_ARGS[@]}"; do
  p="${SELECTED_POLICY_ARGS[$idx]}"
  policy_total["$p"]=0
  policy_correct["$p"]=0
done

: > "$COMBINED_REPORT"

{
  echo "========================================"
  echo "Running tests using      : $EXEC"
  echo "Inputs from              : $INPUT_DIR"
  echo "Expected from            : $EXPECTED_DIR (result-<policy>-<frames>-<input_*>)"
  echo "Program outputs stored in: $OUT_DIR"
  echo "Policies                 : ${SELECTED_POLICY_NAMES[*]}"
  echo "Combined report          : $COMBINED_REPORT"
  echo "========================================"
  echo
} >> "$COMBINED_REPORT"

# ============================================
# Main loop: iterate over expected files
# ============================================
for expected in "${EXPECTED_FILES[@]}"; do
  base_fn="$(basename "$expected")"      # e.g. result-1-1-input_1

  # Strip optional .txt (if they ever add it)
  base_noext="${base_fn%.txt}"

  # base_noext = result-<policy>-<frames>-<input_name>
  rest="${base_noext#result-}"
  IFS='-' read -r -a parts <<< "$rest"

  if (( ${#parts[@]} < 3 )); then
    echo "Skipping unexpected filename: $base_fn" >&2
    continue
  fi

  policy="${parts[0]}"
  frames="${parts[1]}"
  input_name="${rest#${policy}-${frames}-}"   # everything after policy-frames-

  # Skip if this policy is not selected
  if ! policy_selected "$policy"; then
    continue
  fi

  input_file="${INPUT_DIR}/${input_name}"
  actual="${OUT_DIR}/result-${policy}-${frames}-${input_name}"

  policy_label="?"
  case "$policy" in
    1) policy_label="FIFO" ;;
    2) policy_label="Third" ;;
  esac

  # Header for this test
  {
    echo "===== BEGIN ${input_name} (policy ${policy} - ${policy_label}, frames=${frames}) ====="
    echo "Input : ${input_file}"
    echo "Actual: ${actual}"
    echo "Expect: ${expected}"
  } >> "$COMBINED_REPORT"

  # Ensure input + expected exist
  if [[ ! -f "$input_file" ]]; then
    {
      echo "[RESULT] ? Missing input file: ${input_file}"
      echo "===== END ${input_name} (policy ${policy}) ====="
      echo
    } >> "$COMBINED_REPORT"
    continue
  fi
  if [[ ! -f "$expected" ]]; then
    {
      echo "[RESULT] ? Missing expected file: ${expected}"
      echo "===== END ${input_name} (policy ${policy}) ====="
      echo
    } >> "$COMBINED_REPORT"
    continue
  fi

  # Run tester (overwrites actual output)
  if ! "$EXEC" "$policy" "$frames" "$input_file" > /dev/null 2>&1; then
    # still try to compare, but note failure
    echo "[WARN] tester returned non-zero for ${input_name}, policy ${policy}, frames=${frames}" >> "$COMBINED_REPORT"
  fi

  (( policy_total["$policy"] += 1 ))
  (( total_cases += 1 ))

  if [[ ! -f "$actual" ]]; then
    {
      echo "[RESULT] ? tester did not produce output: ${actual}"
      echo "===== END ${input_name} (policy ${policy}) ====="
      echo
    } >> "$COMBINED_REPORT"
    continue
  fi

  # Compare (normalized) without saving extra files
  diff_output=$(
    diff -u \
      <(normalize < "$expected") \
      <(normalize < "$actual") \
    || true
  )

  if [[ -z "$diff_output" ]]; then
    (( policy_correct["$policy"] += 1 ))
    (( total_correct += 1 ))
    {
      echo "[RESULT] ? MATCH"
    } >> "$COMBINED_REPORT"
  else
    {
      echo "[RESULT] ? MISMATCH"
      echo
      echo "--- Diff ---"
      echo "$diff_output"
    } >> "$COMBINED_REPORT"
  fi

  {
    echo "===== END ${input_name} (policy ${policy}) ====="
    echo
  } >> "$COMBINED_REPORT"

done

# ============================================
# Final scores
# ============================================
{
  echo "========================================"
  echo "Scores:"
  for idx in "${!SELECTED_POLICY_ARGS[@]}"; do
    p="${SELECTED_POLICY_ARGS[$idx]}"
    policy_name="${SELECTED_POLICY_NAMES[$idx]}"
    printf "  %-8s %3d/%-3d  correct\n" "${policy_name}:" "${policy_correct[$p]}" "${policy_total[$p]}"
  done
  echo "----------------------------------------"
  printf "  Overall  %3d/%-3d  correct\n" "$total_correct" "$total_cases"
  echo "========================================"
} | tee -a "$COMBINED_REPORT"
