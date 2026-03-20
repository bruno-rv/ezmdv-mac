import * as esbuild from 'esbuild';

await esbuild.build({
  entryPoints: ['editor-src.js'],
  bundle: true,
  format: 'iife',
  outfile: '../Sources/EzmdvApp/Resources/editor.js',
  minify: true,
  sourcemap: false,
  target: ['safari16'],
});

console.log('✅ editor.js bundled to Sources/EzmdvApp/Resources/editor.js');
