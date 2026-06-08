import daisyuiPlugin from 'daisyui';

/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class', '[data-theme="dark"]'],
  content: ['./src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Public Sans', 'sans-serif'],
        display: ['Clash Grotesk', 'sans-serif']
      },
      colors: {
        pink: { 50: '#FFC6E9', 200: '#FF6FC8', 400: '#E81899', 500: '#C8047D' },
        grey: {
          5: '#FAFAFA', 10: '#F3F3F3', 50: '#E3E3E3', 100: '#CACBCE', 200: '#ADB1B8',
          500: '#5D636F', 600: '#444A55', 700: '#2B303B', 800: '#191E28', 900: '#0B101B'
        },
        green: { 300: '#47E0A0', 800: '#00321D' },
        red: { 300: '#F15C5D', 800: '#440000' }
      }
    }
  },
  plugins: [daisyuiPlugin],
  daisyui: {
    darkTheme: 'dark',
    base: true,
    styled: true,
    utils: true,
    logs: false,
    themes: [
      {
        dark: {
          'color-scheme': 'dark',
          '--btn-text-case': 'capitalize',
          primary: '#C8047D',
          'primary-focus': '#E81899',
          'primary-content': '#F3F3F3',
          secondary: '#E81899',
          'secondary-content': '#ADB1B8',
          neutral: '#2B303B',
          'neutral-focus': '#444A55',
          'neutral-content': '#F3F3F3',
          'base-100': '#0B101B',
          'base-200': '#191E28',
          'base-300': '#2B303B',
          'base-content': '#F3F3F3',
          success: '#00321D',
          'success-content': '#47E0A0',
          error: '#440000',
          'error-content': '#F15C5D',
          warning: '#382800',
          'warning-content': '#EBB222',
          info: '#002966',
          'info-content': '#8DC4FF'
        }
      }
    ]
  }
};
