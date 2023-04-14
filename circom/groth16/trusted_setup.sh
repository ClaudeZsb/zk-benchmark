#!/bin/bash

if [ $# -ne 2 ]; then
  echo "./trusted_setup.sh <circom_file> <tau_rank>"
  exit 1
fi

SCRIPT=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT")
CIRCUIT=$(realpath "$1")
CIRCUIT_FILE=$(basename "$CIRCUIT")
CIRCUIT_NAME=$(basename "$CIRCUIT" | sed 's/\(.*\)\..*/\1/')
CIRCUIT_DIR=$(dirname "$CIRCUIT")
TAU_RANK=$2
TAU_DIR=${SCRIPT_DIR}"/../setup/tau"
TAU_FILE="${TAU_DIR}/powersOfTau28_hez_final_${TAU_RANK}.ptau"

if [ ! -f "$TAU_FILE" ]; then
  wget -P "$TAU_DIR" https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_${TAU_RANK}.ptau
fi

pushd "$CIRCUIT_DIR" || exit
snarkjs groth16 setup "$CIRCUIT_NAME".r1cs ${TAU_FILE} "$CIRCUIT_NAME"_0000.zkey
echo 1 | snarkjs zkey contribute "$CIRCUIT_NAME"_0000.zkey "$CIRCUIT_NAME"_0001.zkey --name='Claude' -v
snarkjs zkey export verificationkey "$CIRCUIT_NAME"_0001.zkey verification_key.json
popd || exit