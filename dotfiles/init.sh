#! /bin/bash
sudo apt update
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
npm install -g @anthropic-ai/claude-code
npm i -g @openai/codex
git submodule update --init
pushd tests/wast/spec && git apply ../spec.patch && cd /workspaces/DTVM
./tools/easm2bytecode.sh tests/evm_asm/ tests/evm_asm/
git config user.name Abmcar
git config user.email abmcar@qq.com
git config push.default current
# Release test
