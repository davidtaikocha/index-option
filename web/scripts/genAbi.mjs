import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../../out');
const abiDir = resolve(here, '../src/lib/abi');
mkdirSync(abiDir, { recursive: true });

// [artifactPath, exportName, includeBytecode]
const targets = [
  ['OptionFactory.sol/OptionFactory.json', 'optionFactory', false],
  ['OptionSeries.sol/OptionSeries.json', 'optionSeries', false],
  ['ClaimToken.sol/ClaimToken.json', 'claimToken', false],
  ['OptionPool.sol/OptionPool.json', 'optionPool', false],
  ['OptionPoolFactory.sol/OptionPoolFactory.json', 'optionPoolFactory', false]
];

for (const [path, name, withBytecode] of targets) {
  const artifact = JSON.parse(readFileSync(resolve(out, path), 'utf8'));
  let body = `export const ${name}Abi = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`;
  if (withBytecode) {
    body += `\nexport const ${name}Bytecode = ${JSON.stringify(artifact.bytecode.object)} as \`0x\${string}\`;\n`;
  }
  writeFileSync(resolve(abiDir, `${name}.ts`), body);
  console.log(`wrote src/lib/abi/${name}.ts`);
}
