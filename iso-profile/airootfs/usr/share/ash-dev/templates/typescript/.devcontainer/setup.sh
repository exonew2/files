#!/usr/bin/env bash
corepack enable
pnpm install
pnpm exec prisma generate
