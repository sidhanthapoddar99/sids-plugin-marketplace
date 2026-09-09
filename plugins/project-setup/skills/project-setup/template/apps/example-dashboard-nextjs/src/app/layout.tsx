// Root layout: <html>, <body>, providers. import "@scope/ui/globals.css" — the one style import.
// Next.js owns routing through app/: this folder replaces routes/ and main.tsx from the Vite shape. Everything
// else (layout/, modules/, components/, lib/) is the same tree with the same meaning.
// suppressHydrationWarning on <html>: the inline theme script sets [data-theme] before hydration.
