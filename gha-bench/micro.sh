#!/usr/bin/env bash
# Microbenchmark: npm ci cold and warm, a CPU loop and small-file IO.
ms() { echo $(( $(date +%s%N) / 1000000 )); }
t() { local s=$(ms); "$@" >/dev/null 2>&1; echo $(( $(ms) - s )); }
echo "nproc=$(nproc) model=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"
echo "registry=$(npm config get registry)"
SRC=$(cd "$(dirname "$0")" && pwd)
for d in "$PWD/t1" "$HOME/t2" /dev/shm/t3; do
  mkdir -p $d; cp $SRC/package*.json $d/
  cold=$(cd $d && rm -rf node_modules ~/.npm && t npm ci --ignore-scripts)
  warm=$(cd $d && rm -rf node_modules && t npm ci --ignore-scripts)
  echo "$d [$(df -P $d | tail -1 | awk '{print $1" "$6}')]: npm ci cold ${cold} ms, warm-cache ${warm} ms"
done
s=$(ms); node -e 'let x=0;for(let i=0;i<3e8;i++)x+=i%7;console.log(x)' >/dev/null; echo "cpu loop: $(( $(ms) - s )) ms"
for d in "$PWD" "$HOME" /dev/shm; do s=$(ms); mkdir -p $d/f && (cd $d/f && for i in $(seq 3000); do echo x > f$i; done); rm -rf $d/f; echo "3000 small files in $d: $(( $(ms) - s )) ms"; done
