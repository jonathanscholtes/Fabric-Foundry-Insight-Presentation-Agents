module.exports = {
  root: true,
  env: { browser: true, es2020: true },
  extends: [
    'react-app',
    'react-app/jest',
  ],
  plugins: ['react-refresh'],
  rules: {
    'no-unused-vars': 'warn',
    'react/jsx-runtime': 'off',
    'react-refresh/only-export-components': [
      'warn',
      { allowConstantExport: true },
    ],
  },
};
