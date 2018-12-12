#!/usr/bin/env bash
set -Eeuo pipefail

exec grpc_cli "$@"