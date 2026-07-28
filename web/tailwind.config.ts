import type { Config } from 'tailwindcss';

/// Lifted verbatim from app/lib/core/theme/tokens.dart. These are the same
/// values the Android app renders, so the two surfaces cannot drift apart —
/// if a colour changes, it changes in both places or neither.
export default {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        canvas: '#f7f5f0',
        backdrop: '#e9e6df',
        surface: '#ffffff',
        ink: { DEFAULT: '#1b2430', strong: '#1c2534', muted: '#5b6472', faint: '#8a92a0' },
        teal: { DEFAULT: '#0d9488', deep: '#0d7d74', tint: '#eaf6f4' },
        violet: { DEFAULT: '#8659c9', tint: '#f1eafb' },
        blue: { DEFAULT: '#2f5fa8', tint: '#eaf0fa' },
        amber: { DEFAULT: '#b45309', tint: '#fdf3e7' },
        danger: { DEFAULT: '#c2410c', tint: '#fdeee8' },
        border: { DEFAULT: 'rgba(27,36,48,.08)', strong: 'rgba(27,36,48,.12)' },
      },
      fontFamily: {
        // Newsreader for the wordmark, job titles and screen titles; IBM Plex
        // Sans for everything else. Same split as the app.
        serif: ['Newsreader', 'Georgia', 'serif'],
        sans: ['"IBM Plex Sans"', 'system-ui', 'sans-serif'],
      },
      borderRadius: { card: '16px', 'card-lg': '20px', field: '10px', button: '13px' },
    },
  },
  plugins: [],
} satisfies Config;
