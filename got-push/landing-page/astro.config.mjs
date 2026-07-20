import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://ash.sh',
  base: '/',
  output: 'static',
  build: { format: 'file' },
  vite: { plugins: [tailwindcss()] },
  integrations: [
    sitemap({
      filter: (page) => !page.includes('/404'),
      customPages: [
        'https://ash.sh/',
        'https://ash.sh/download',
        'https://ash.sh/verify',
        'https://ash.sh/docs/quickstart',
        'https://ash.sh/docs/gpu-passthrough',
        'https://ash.sh/docs/persistence',
        'https://ash.sh/docs/updates',
        'https://ash.sh/docs/comparison',
        'https://ash.sh/docs/verification',
      ],
      serialize(item) {
        if (item.url === 'https://ash.sh/') {
          item.priority = 1.0;
          item.changefreq = 'weekly';
        } else if (item.url.includes('/docs/')) {
          item.priority = 0.8;
          item.changefreq = 'monthly';
        } else {
          item.priority = 0.9;
          item.changefreq = 'weekly';
        }
        return item;
      },
    }),
  ],
});
