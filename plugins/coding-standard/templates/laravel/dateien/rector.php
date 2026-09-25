<?php

declare(strict_types=1);

// Rector — monatlicher Probelauf (.github/workflows/monatlich.yml, --dry-run): zeigt, was sich
// modernisieren ließe; angewendet wird nichts von selbst. Ein Vorschlag wird zum PR, wenn er
// den Code klarer macht — nicht, weil ein Werkzeug ihn kennt. Lokal: vendor/bin/rector --dry-run

use Rector\Config\RectorConfig;

return RectorConfig::configure()
    ->withPaths([
        __DIR__.'/app',
        __DIR__.'/database',
        __DIR__.'/routes',
        __DIR__.'/tests',
    ])
    ->withPhpSets()
    ->withPreparedSets(deadCode: true, codeQuality: true, typeDeclarations: true);
