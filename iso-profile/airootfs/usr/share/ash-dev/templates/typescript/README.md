# {{project_name}}

TypeScript project scaffolded by `ash-new`.

## Stack
- **Framework:** Next.js 14
- **API:** tRPC
- **ORM:** Prisma
- **Testing:** Vitest
- **Package:** pnpm

## Quick Start
```bash
pnpm install
pnpm dev       # Start dev server
pnpm test      # Run tests
pnpm build     # Production build
```

## Project Structure
```
src/
  app/
    page.tsx
    layout.tsx
  server/
    trpc/
      router.ts
      context.ts
    db/
      schema.prisma
  components/
tests/
```

## AI Agent Instructions
- Use `pnpm` (not npm/yarn)
- TypeScript strict mode enabled
- tRPC for type-safe APIs
- Prisma for database access
- Vitest for testing
