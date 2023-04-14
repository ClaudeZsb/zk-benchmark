#!/bin/bash

if [ $# -lt 3 ]; then
  echo "./test_groth.sh <circom_file> <tau_rank> <input_file> <rapid_snark_prover>"
  exit 1
fi

set -e
SCRIPT=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT")
CIRCUIT=$(realpath "$1")
CIRCUIT_FILE=$(basename "$CIRCUIT")
CIRCUIT_NAME=$(basename "$CIRCUIT" | sed 's/\(.*\)\..*/\1/')
CIRCUIT_DIR=$(dirname "$CIRCUIT")
TAU_RANK=$2
echo "tau rank $TAU_RANK"
TAU_DIR="$SCRIPT_DIR"/../setup/tau
TAU_FILE="${TAU_DIR}/powersOfTau28_hez_final_${TAU_RANK}.ptau"
# TAU=$(realpath "$2")
# TAU_DIR=$(dirname "$TAU")
INPUT=$(realpath "$3")
if [ -z "$4" ]; then
  RAPID_SNARK_PROVER=''
else
  RAPID_SNARK_PROVER=$(realpath "$4")
fi
echo "rapid_snark_prover:" $RAPID_SNARK_PROVER
echo "circuit_name:" $CIRCUIT_NAME

TIME=(/usr/bin/time -f "mem %M\ntime %e\ncpu %P")

export NODE_OPTIONS=--max_old_space_size=327680
sysctl -w vm.max_map_count=655300

function compile() {
  pushd "$CIRCUIT_DIR"
  echo circom "$CIRCUIT_FILE" --r1cs --sym --c
  circom "$CIRCUIT_FILE" --r1cs --sym --c
  cd "$CIRCUIT_NAME"_cpp
  make
  popd
}

function setup() {
  if [ ! -f "$TAU_FILE" ]; then
    pushd "$TAU_DIR"
    echo "download $TAU_FILE"
    wget -P "$TAU_DIR" https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_${TAU_RANK}.ptau
    popd
  fi
  echo "${TIME[@]}" "$SCRIPT_DIR"/trusted_setup.sh "$CIRCUIT" "$TAU_RANK"
  "${TIME[@]}" "$SCRIPT_DIR"/trusted_setup.sh "$CIRCUIT" "$TAU_RANK"
# snarkjs groth16 setup sha256_test.r1cs ${TAU_FILE} sha256_test_0000.zkey
# echo 1 | snarkjs zkey contribute sha256_test_0000.zkey sha256_test_0001.zkey --name='Celer' -v
# snarkjs zkey export verificationkey sha256_test_0001.zkey verification_key.json
  prove_key_size=$(ls -lh "$CIRCUIT_DIR"/"$CIRCUIT_NAME"_0001.zkey | awk '{print $5}')
  verify_key_size=$(ls -lh "$CIRCUIT_DIR"/verification_key.json | awk '{print $5}')
  echo "Prove key size: $prove_key_size"
  echo "Verify key size: $verify_key_size"
}

function generateWtns() {
  pushd "$CIRCUIT_DIR"
  echo "${TIME[@]}" "$CIRCUIT_NAME"_cpp/"$CIRCUIT_NAME" "$INPUT" witness.wtns
  "${TIME[@]}" "$CIRCUIT_NAME"_cpp/"$CIRCUIT_NAME" "$INPUT" witness.wtns
  #"${TIME[@]}" node "$CIRCUIT_NAME"_js/generate_witness.js "$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm "$INPUT" witness.wtns
  popd
}

avg_time() {
    #
    # usage: avg_time n command ...
    #
    n=$1; shift
    (($# > 0)) || return                   # bail if no command given
    echo "$@"
    for ((i = 0; i < n; i++)); do
        "${TIME[@]}" "$@" 2>&1
    done | awk '
        /mem/ { mem = mem + $2; nm++ }
        /time/ { time = time + $2; nt++ }
        /cpu/  { cpu  = cpu  + substr($2,1,length($2)-1); nc++}
        END    {
                 if (nm>0) printf("mem %f\n", mem/nm);
                 if (nt>0) printf("time %f\n", time/nt);
                 if (nc>0) printf("cpu %f\n",  cpu/nc)
               }'
}

function normalProve() {
  pushd "$CIRCUIT_DIR"
  avg_time 10 snarkjs groth16 prove "$CIRCUIT_NAME"_0001.zkey witness.wtns proof.json public.json
#  "${TIME[@]}" snarkjs groth16 prove "$CIRCUIT_NAME"_0001.zkey witness.wtns proof.json public.json
  proof_size=$(ls -lh proof.json | awk '{print $5}')
  echo "Proof size: $proof_size"
  popd
}

function verify() {
  pushd "$CIRCUIT_DIR"
  avg_time 10 snarkjs groth16 verify verification_key.json public.json proof.json
#  "${TIME[@]}" snarkjs groth16 verify verification_key.json public.json proof.json
  popd
}

function rapidProveAndVerify() {
  if [ "$RAPID_SNARK_PROVER" != "" ]; then
    pushd "$CIRCUIT_DIR"
    avg_time 10 "$RAPID_SNARK_PROVER" "$CIRCUIT_NAME"_0001.zkey witness.wtns proof.json public.json
    #  "${TIME[@]}" "$RAPID_SNARK_PROVER" "$CIRCUIT_NAME"_0001.zkey witness.wtns proof.json public.json
    proof_size=$(ls -lh proof.json | awk '{print $5}')
    echo "Proof size: $proof_size"
    popd

    verify
  fi
}

echo "========== Step1: compile circom  =========="
compile

echo "========== Step2: setup =========="
setup

echo "========== Step3: generate witness  =========="
generateWtns

echo "========== Step4: prove  =========="
normalProve

echo "========== Step5: verify  =========="
verify

echo "========== Step6: rapid prove & verify  =========="
rapidProveAndVerify
